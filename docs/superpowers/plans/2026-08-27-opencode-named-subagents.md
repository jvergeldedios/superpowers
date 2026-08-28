# OpenCode Named Subagents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Register three named OpenCode subagents (`superpowers-implementer`, `superpowers-reviewer`, `superpowers-explorer`) from the superpowers plugin so their default models can be tuned per role in `opencode.json`.

**Architecture:** Extend the plugin's existing `config` hook in `.opencode/plugins/superpowers.js` to inject thin subagent definitions (user config wins field-by-field, `disable` respected), and rewrite the bootstrap's subagent tool-mapping line to route dispatches by role with `general` as fallback. Skills are untouched. Docs updated in `.opencode/INSTALL.md` and `docs/README.opencode.md`.

**Tech Stack:** Plain ESM JavaScript (plugin), Bash + Node `.mjs` tests (existing `tests/opencode/` harness), Markdown docs.

**Spec:** `docs/superpowers/specs/2026-08-27-opencode-named-subagents-design.md`

**Working context for the implementer:**

- OpenCode's `task` tool dispatches subagents by name via its `subagent_type` parameter; it has NO per-dispatch model parameter. Named agents registered in config are the only way to set subagent models on OpenCode.
- The plugin's `config` hook receives the fully merged config (user `opencode.json` already applied) and mutates it in place. Mutations are visible to later lazy consumers — this is the same mechanism the plugin already uses to register skills.
- `tests/opencode/setup.sh` builds an isolated test environment: copies the repo's plugin and skills into a temp `$OPENCODE_CONFIG_DIR`, symlinks the plugin where OpenCode reads it, and exports `$SUPERPOWERS_PLUGIN_FILE`, `$SUPERPOWERS_SKILLS_DIR`, `$TEST_HOME`, and `cleanup_test_env`.
- `tests/opencode/run-tests.sh` runs `tests` (no OpenCode needed) by default and `integration_tests` (real `opencode run` model calls) only with `--integration`.
- Repo conventions: plugin file uses single quotes, 2-space indent, ESM named export `SuperpowersPlugin`. Commit messages follow `type(scope): summary`.

---

### Task 1: Register named subagents via the config hook (unit-tested, TDD)

**Files:**
- Create: `tests/opencode/test-named-agents-merge.mjs`
- Create: `tests/opencode/test-named-agents-merge.sh`
- Modify: `tests/opencode/run-tests.sh` (add unit test to the `tests` array)
- Modify: `.opencode/plugins/superpowers.js` (add `SUBAGENTS` constant + config-hook injection)

- [ ] **Step 1: Write the failing unit test**

Create `tests/opencode/test-named-agents-merge.mjs` with exactly this content:

```js
import { pathToFileURL } from 'url';

const [, , pluginPath] = process.argv;

if (!pluginPath) {
  console.error('Usage: node test-named-agents-merge.mjs PLUGIN_PATH');
  process.exit(2);
}

const mod = await import(pathToFileURL(pluginPath).href);
const plugin = await mod.SuperpowersPlugin({ client: {}, directory: '.' });
const configHook = plugin.config;

const NAMED_AGENTS = ['superpowers-implementer', 'superpowers-reviewer', 'superpowers-explorer'];
const failures = [];

// Scenario 1: empty config registers all three named subagents, thin, edit-deny guards
const empty = {};
await configHook(empty);
for (const name of NAMED_AGENTS) {
  const agent = empty.agent?.[name];
  if (!agent) {
    failures.push(`expected ${name} to be registered on empty config`);
    continue;
  }
  if (agent.mode !== 'subagent') {
    failures.push(`expected ${name} mode "subagent", got ${JSON.stringify(agent.mode)}`);
  }
  if ('model' in agent) {
    failures.push(`expected ${name} to leave model unset, got ${JSON.stringify(agent.model)}`);
  }
}
for (const name of ['superpowers-reviewer', 'superpowers-explorer']) {
  if (empty.agent?.[name]?.permission?.edit !== 'deny') {
    failures.push(`expected ${name} to deny edit`);
  }
}
if (empty.agent?.['superpowers-implementer']?.permission?.edit === 'deny') {
  failures.push('expected superpowers-implementer to keep edit rights');
}

// Scenario 2: user config wins field-by-field, plugin defaults fill the gaps
const user = {
  agent: {
    'superpowers-reviewer': { model: 'test-provider/test-model', description: 'mine' },
  },
};
await configHook(user);
const reviewer = user.agent['superpowers-reviewer'];
if (reviewer.model !== 'test-provider/test-model') {
  failures.push(`expected user model override preserved, got ${JSON.stringify(reviewer.model)}`);
}
if (reviewer.description !== 'mine') {
  failures.push(`expected user description preserved, got ${JSON.stringify(reviewer.description)}`);
}
if (reviewer.mode !== 'subagent') {
  failures.push(`expected plugin defaults to fill mode, got ${JSON.stringify(reviewer.mode)}`);
}
if (reviewer.permission?.edit !== 'deny') {
  failures.push('expected plugin defaults to fill edit deny');
}

// Scenario 3: a user-disabled agent is left disabled
const disabled = {
  agent: {
    'superpowers-explorer': { disable: true },
  },
};
await configHook(disabled);
if (disabled.agent['superpowers-explorer']?.disable !== true) {
  failures.push('expected disabled agent to remain disabled');
}

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL: ${failure}`);
  process.exit(1);
}
console.log('OK: named subagent registration and merge semantics');
```

Create `tests/opencode/test-named-agents-merge.sh` with exactly this content (same wrapper pattern as `test-bootstrap-caching.sh`):

```bash
#!/usr/bin/env bash
# Test: Named subagent registration and merge semantics
# Verifies the plugin's config hook registers the superpowers-* subagents,
# preserves user overrides field-by-field, and respects disabled agents.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Test: Named Subagent Registration ==="

source "$SCRIPT_DIR/setup.sh"
trap cleanup_test_env EXIT

node "$SCRIPT_DIR/test-named-agents-merge.mjs" "$SUPERPOWERS_PLUGIN_FILE"
echo "  [PASS] Named subagents registered, user overrides win, disabled agents respected"

echo ""
echo "=== All named subagent registration tests passed ==="
```

- [ ] **Step 2: Wire the test into the unit suite**

In `tests/opencode/run-tests.sh`, change the `tests` array (around line 61) from:

```bash
tests=(
    "test-plugin-loading.sh"
    "test-bootstrap-caching.sh"
)
```

to:

```bash
tests=(
    "test-plugin-loading.sh"
    "test-bootstrap-caching.sh"
    "test-named-agents-merge.sh"
)
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash tests/opencode/run-tests.sh --test test-named-agents-merge.sh`
Expected: FAIL with `FAIL: expected superpowers-implementer to be registered on empty config` (and the same for reviewer and explorer), then `STATUS: FAILED`.

- [ ] **Step 4: Implement the SUBAGENTS constant and config-hook injection**

In `.opencode/plugins/superpowers.js`, insert immediately after the closing brace of the `normalizePath` function (after line 47) and before the `// Module-level cache for bootstrap content.` comment:

```js
// Named subagents registered into every OpenCode session. Thin registry
// entries only: role identity plus permission guards. Dispatch prompt
// content still comes from the skills' dispatch templates. Model is left
// unset so each agent inherits the session default until the user sets one
// per-agent in opencode.json. See
// docs/superpowers/specs/2026-08-27-opencode-named-subagents-design.md
const SUBAGENTS = {
  'superpowers-implementer': {
    mode: 'subagent',
    description: 'Implementation agent for superpowers skills. Executes a filled implementer or fix dispatch template: writes code, runs tests, commits.',
  },
  'superpowers-reviewer': {
    mode: 'subagent',
    description: 'Review agent for superpowers skills. Reviews filled reviewer dispatch templates (task review, re-review, final/spec/plan review) against their requirements and reports findings; never edits code.',
    permission: { edit: 'deny' },
  },
  'superpowers-explorer': {
    mode: 'subagent',
    description: 'Read-only exploration agent for superpowers skills. Searches the codebase and answers research questions; reports findings without modifying anything.',
    permission: { edit: 'deny' },
  },
};
```

Then replace the entire `config` hook (lines 107-113):

```js
    config: async (config) => {
      config.skills = config.skills || {};
      config.skills.paths = config.skills.paths || [];
      if (!config.skills.paths.includes(superpowersSkillsDir)) {
        config.skills.paths.push(superpowersSkillsDir);
      }
    },
```

with:

```js
    config: async (config) => {
      config.skills = config.skills || {};
      config.skills.paths = config.skills.paths || [];
      if (!config.skills.paths.includes(superpowersSkillsDir)) {
        config.skills.paths.push(superpowersSkillsDir);
      }

      config.agent = config.agent || {};
      for (const [name, defaults] of Object.entries(SUBAGENTS)) {
        if (config.agent[name]?.disable) continue;
        config.agent[name] = { ...defaults, ...config.agent[name] };
      }
    },
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/opencode/run-tests.sh --test test-named-agents-merge.sh`
Expected: PASS, `OK: named subagent registration and merge semantics`, `STATUS: PASSED`.

- [ ] **Step 6: Commit**

```bash
git add tests/opencode/test-named-agents-merge.mjs tests/opencode/test-named-agents-merge.sh tests/opencode/run-tests.sh .opencode/plugins/superpowers.js
git commit -m "feat(opencode): register named subagents via config hook"
```

---

### Task 2: Route subagent dispatches by role in the bootstrap mapping (TDD)

The bootstrap's tool-mapping line currently teaches `subagent_type: "general"` for every dispatch. Change it to role-based routing. `tests/opencode/test-bootstrap-caching.mjs` asserts the OLD mapping text (line 49), so the test is updated first.

**Files:**
- Modify: `tests/opencode/test-bootstrap-caching.mjs` (update assertions)
- Modify: `.opencode/plugins/superpowers.js` (replace `toolMapping` subagent line)

- [ ] **Step 1: Update the failing bootstrap test assertions**

In `tests/opencode/test-bootstrap-caching.mjs`, replace line 49:

```js
  mapsSubagentToTask: bootstrapText(firstOutput).includes('`task` with `subagent_type: "general"`'),
```

with:

```js
  mapsSubagentRoles: ['superpowers-implementer', 'superpowers-reviewer', 'superpowers-explorer']
    .every((name) => bootstrapText(firstOutput).includes(name)),
  mapsGeneralFallback: bootstrapText(firstOutput).includes('`general`'),
```

Then in `assertPresentBootstrap`, replace:

```js
  if (!result.mapsSubagentToTask) {
    failures.push('expected OpenCode bootstrap to map general-purpose subagents to task with subagent_type');
  }
```

with:

```js
  if (!result.mapsSubagentRoles) {
    failures.push('expected OpenCode bootstrap to route subagent dispatches to the named superpowers agents');
  }
  if (!result.mapsGeneralFallback) {
    failures.push('expected OpenCode bootstrap to keep general as the fallback subagent');
  }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/opencode/run-tests.sh --test test-bootstrap-caching.sh`
Expected: FAIL with `FAIL: expected OpenCode bootstrap to route subagent dispatches to the named superpowers agents`.

- [ ] **Step 3: Update the toolMapping in the plugin**

In `.opencode/plugins/superpowers.js`, replace the `toolMapping` template literal (lines 76-87):

```js
    const toolMapping = `**Tool Mapping for OpenCode:**
When skills request actions, substitute OpenCode equivalents:
- Create or update todos → \`todowrite\`
- \`Subagent (general-purpose):\` → \`task\` with \`subagent_type: "general"\`
- Invoke a skill → OpenCode's native \`skill\` tool
- Read files → \`read\`
- Create, edit, or delete files → \`apply_patch\`
- Run shell commands → \`bash\`
- Search files → \`grep\`, \`glob\`
- Fetch a URL → \`webfetch\`

Use OpenCode's native \`skill\` tool to list and load skills.`;
```

with:

```js
    const toolMapping = `**Tool Mapping for OpenCode:**
When skills request actions, substitute OpenCode equivalents:
- Create or update todos → \`todowrite\`
- \`Subagent (general-purpose):\` → \`task\` with \`subagent_type\` chosen by role:
  implementation/fix work → \`superpowers-implementer\`
  reviews → \`superpowers-reviewer\`
  exploration/research → \`superpowers-explorer\`
  anything else, or if a named agent is unavailable → \`general\`
- Invoke a skill → OpenCode's native \`skill\` tool
- Read files → \`read\`
- Create, edit, or delete files → \`apply_patch\`
- Run shell commands → \`bash\`
- Search files → \`grep\`, \`glob\`
- Fetch a URL → \`webfetch\`

Use OpenCode's native \`skill\` tool to list and load skills.`;
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/opencode/run-tests.sh --test test-bootstrap-caching.sh`
Expected: PASS, `=== All bootstrap caching tests passed ===`.

- [ ] **Step 5: Commit**

```bash
git add tests/opencode/test-bootstrap-caching.mjs .opencode/plugins/superpowers.js
git commit -m "feat(opencode): route subagent dispatches by role in bootstrap mapping"
```

---

### Task 3: Integration test — dispatch to a named agent end-to-end

Proves the whole chain with a real OpenCode session: plugin loads, config hook registers agents, `task` tool accepts `subagent_type: "superpowers-explorer"`, and the subagent answers. (Its red state is already covered by Task 1's unit test, which fails before the config-hook injection exists; the implementer, reviewer, and explorer share the same registration code path, so one dispatch test suffices.)

**Files:**
- Create: `tests/opencode/test-named-agents.sh`
- Modify: `tests/opencode/run-tests.sh` (add to `integration_tests` array and `--help` listing)

- [ ] **Step 1: Write the integration test**

Create `tests/opencode/test-named-agents.sh` with exactly this content (follows `test-tools.sh` patterns):

```bash
#!/usr/bin/env bash
# Test: Named subagent dispatch
# Verifies the plugin registers the superpowers-* named subagents and that
# OpenCode's task tool can dispatch to them by name.
# NOTE: Requires OpenCode to be installed and configured.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCODE_TEST_TIMEOUT_SECONDS="${OPENCODE_TEST_TIMEOUT_SECONDS:-120}"

echo "=== Test: Named Subagent Dispatch ==="

source "$SCRIPT_DIR/setup.sh"
trap cleanup_test_env EXIT

# Check if opencode is available
if ! command -v opencode &> /dev/null; then
    echo "  [SKIP] OpenCode not installed - skipping integration test"
    echo "  To run this test, install OpenCode: https://opencode.ai"
    exit 0
fi

run_opencode() {
    local result_var="$1"
    local dir="$2"
    local prompt="$3"
    local command_output
    local exit_code

    set +e
    command_output=$(cd "$dir" && timeout "${OPENCODE_TEST_TIMEOUT_SECONDS}s" opencode run --print-logs --format json "$prompt" 2>&1)
    exit_code=$?
    set -e

    if [ $exit_code -eq 124 ]; then
        echo "  [FAIL] OpenCode timed out after ${OPENCODE_TEST_TIMEOUT_SECONDS}s"
        exit 1
    fi

    if [ $exit_code -ne 0 ]; then
        echo "  [FAIL] OpenCode returned non-zero exit code: $exit_code"
        echo "  Output was:"
        awk 'NR <= 80 { print }' <<<"$command_output"
        exit 1
    fi

    printf -v "$result_var" '%s' "$command_output"
}

assert_contains() {
    local output="$1"
    local needle="$2"
    local message="$3"

    if [[ "$output" == *"$needle"* ]]; then
        echo "  [PASS] $message"
    else
        echo "  [FAIL] $message"
        echo "  Expected to find: $needle"
        echo "  Output was:"
        awk 'NR <= 80 { print }' <<<"$output"
        exit 1
    fi
}

echo "Test 1: Dispatching to the named explorer subagent..."
run_opencode output "$TEST_HOME/test-project" "Call the task tool with subagent_type \"superpowers-explorer\" and prompt \"Reply with exactly: EXPLORER_MARKER_24680\". Then print the marker."
assert_contains "$output" '"subagent_type":"superpowers-explorer"' "task tool dispatched to superpowers-explorer"
assert_contains "$output" "EXPLORER_MARKER_24680" "named explorer subagent executed and reported"

echo ""
echo "=== All named subagent dispatch tests passed ==="
```

- [ ] **Step 2: Wire the test into the integration suite**

In `tests/opencode/run-tests.sh`, change the `integration_tests` array (around line 67) from:

```bash
integration_tests=(
    "test-tools.sh"
    "test-priority.sh"
)
```

to:

```bash
integration_tests=(
    "test-tools.sh"
    "test-priority.sh"
    "test-named-agents.sh"
)
```

and in the `--help` text (around lines 45-49), change:

```
echo "  test-plugin-loading.sh  Verify plugin installation and structure"
echo "  test-bootstrap-caching.sh  Verify bootstrap content caching"
echo "  test-tools.sh           Test use_skill and find_skills tools (integration)"
echo "  test-priority.sh        Test skill priority resolution (integration)"
```

to:

```
echo "  test-plugin-loading.sh  Verify plugin installation and structure"
echo "  test-bootstrap-caching.sh  Verify bootstrap content caching"
echo "  test-named-agents-merge.sh  Verify named subagent registration and merge semantics"
echo "  test-tools.sh           Test use_skill and find_skills tools (integration)"
echo "  test-priority.sh        Test skill priority resolution (integration)"
echo "  test-named-agents.sh    Test named subagent dispatch (integration)"
```

- [ ] **Step 3: Run the integration test**

Run: `bash tests/opencode/run-tests.sh --test test-named-agents.sh`
Expected: PASS — `[PASS] task tool dispatched to superpowers-explorer`, `[PASS] named explorer subagent executed and reported`. (Requires opencode installed and a configured model; may take up to 120s.)

- [ ] **Step 4: Commit**

```bash
git add tests/opencode/test-named-agents.sh tests/opencode/run-tests.sh
git commit -m "test(opencode): verify named subagent dispatch end-to-end"
```

---

### Task 4: Document named subagents and model tuning

**Files:**
- Modify: `.opencode/INSTALL.md` (Tool mapping section + new Tuning section)
- Modify: `docs/README.opencode.md` (How It Works list, Tool Mapping section + new Tuning section)

- [ ] **Step 1: Update `.opencode/INSTALL.md`**

Replace the subagent bullet in the "Tool mapping" section (line 104):

```markdown
- `Subagent (general-purpose):` template → `task` tool with `subagent_type: "general"` (or `"explore"` for codebase exploration)
```

with:

```markdown
- `Subagent (general-purpose):` template → `task` tool with `subagent_type` chosen by role: implementation/fix work → `superpowers-implementer`; reviews → `superpowers-reviewer`; exploration/research → `superpowers-explorer`; anything else, or if a named agent is unavailable → `general`
```

Then insert a new section between the "Tool mapping" section and `## Getting Help` (before line 112):

```markdown
## Tuning subagent models

The plugin registers three named subagents — `superpowers-implementer`,
`superpowers-reviewer`, and `superpowers-explorer`. OpenCode's `task` tool
has no per-dispatch model setting, so set a default model per role in your
`opencode.json` (project or global):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "agent": {
    "superpowers-implementer": { "model": "openai/gpt-5-codex" },
    "superpowers-reviewer": { "model": "anthropic/claude-opus-4-6" },
    "superpowers-explorer": { "model": "anthropic/claude-haiku-4-5" }
  }
}
```

The model IDs above are examples — use any model available to your OpenCode.
Agents with no `model` set inherit the session default. Your `agent` entries
override the plugin's defaults field-by-field, so you can also change
permissions or descriptions; `"disable": true` removes an agent entirely
(dispatches then fall back to `general`). Restart OpenCode after editing
`opencode.json` — config is not hot-reloaded.
```

- [ ] **Step 2: Update `docs/README.opencode.md`**

In the "How It Works" section (lines 100-103), change:

```markdown
The plugin does two things:

1. **Injects bootstrap context** via the `experimental.chat.messages.transform` hook, adding superpowers awareness to every conversation.
2. **Registers the skills directory** via the `config` hook, so OpenCode discovers all superpowers skills without symlinks or manual config.
```

to:

```markdown
The plugin does three things:

1. **Injects bootstrap context** via the `experimental.chat.messages.transform` hook, adding superpowers awareness to every conversation.
2. **Registers the skills directory** via the `config` hook, so OpenCode discovers all superpowers skills without symlinks or manual config.
3. **Registers three named subagents** — `superpowers-implementer`, `superpowers-reviewer`, and `superpowers-explorer` — via the `config` hook, so dispatches can be tuned per role in `opencode.json`.
```

Replace the subagent bullet in "Tool Mapping" (line 110):

```markdown
- `Subagent (general-purpose):` template → OpenCode's `task` tool with `subagent_type: "general"` (or `"explore"` for codebase exploration)
```

with:

```markdown
- `Subagent (general-purpose):` template → OpenCode's `task` tool with `subagent_type` chosen by role: implementation/fix work → `superpowers-implementer`; reviews → `superpowers-reviewer`; exploration/research → `superpowers-explorer`; anything else, or if a named agent is unavailable → `general`
```

Then insert a new subsection between the "(Verified against the installed OpenCode CLI's tool inventory.)" line and `## Troubleshooting`:

```markdown
### Tuning subagent models

OpenCode's `task` tool has no per-dispatch model setting. To control subagent
models, set a default model per named agent in your `opencode.json` (project
or global):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "agent": {
    "superpowers-implementer": { "model": "openai/gpt-5-codex" },
    "superpowers-reviewer": { "model": "anthropic/claude-opus-4-6" },
    "superpowers-explorer": { "model": "anthropic/claude-haiku-4-5" }
  }
}
```

The model IDs above are examples — use any model available to your OpenCode.
Agents with no `model` set inherit the session default. Your `agent` entries
override the plugin's defaults field-by-field; `"disable": true` removes an
agent entirely (dispatches then fall back to `general`). Restart OpenCode
after editing `opencode.json` — config is not hot-reloaded.

Note: because model granularity is per role, the SDD skill's "escalate to a
more capable model on fix rounds 4-5" guidance cannot be expressed
per-dispatch on OpenCode. The controller uses the role's configured model and
records in the ledger when it would have escalated.
```

- [ ] **Step 3: Commit**

```bash
git add .opencode/INSTALL.md docs/README.opencode.md
git commit -m "docs(opencode): document named subagents and model tuning"
```

---

### Task 5: Full-suite verification

- [ ] **Step 1: Run the full unit suite**

Run: `bash tests/opencode/run-tests.sh`
Expected: `Passed: 3` (test-plugin-loading.sh, test-bootstrap-caching.sh, test-named-agents-merge.sh), `Failed: 0`, `STATUS: PASSED`.

- [ ] **Step 2: Run the full integration suite**

Run: `bash tests/opencode/run-tests.sh --integration`
Expected: `Passed: 5`, `Failed: 0`, `STATUS: PASSED` (includes the three model-calling tests; may take several minutes).

- [ ] **Step 3: Verify in-repo dev environment**

Run from the repo root (the plugin auto-loads from `.opencode/plugins/` here):

```bash
timeout 120 opencode run --format json "Call the task tool with subagent_type 'superpowers-explorer' and prompt 'Reply with exactly: REPO_EXPLORER_OK'. Then print the marker." 2>&1 | grep -c "REPO_EXPLORER_OK"
```

Expected: output ends with `1`.

- [ ] **Step 4: Report results**

Report the unit and integration suite summaries and the in-repo check result to your human partner.

---

## Self-Review Notes

- **Spec coverage:** agent definitions + merge semantics (Task 1), tool-mapping update with general fallback (Task 2), integration test proving registration and dispatch (Task 3), both doc files (Task 4), full verification (Task 5). All spec sections map to tasks.
- **Known limitation documented, not worked around:** per-role model granularity and the fix-round escalation note live in Task 4's docs, matching the spec's "Known limitations" section.
- **Type/name consistency:** agent names are `superpowers-implementer`, `superpowers-reviewer`, `superpowers-explorer` everywhere (plugin constant, tests, docs). Assertion key `mapsSubagentRoles`/`mapsGeneralFallback` defined in Task 2 Step 1 and consumed in the same step's `assertPresentBootstrap`.
