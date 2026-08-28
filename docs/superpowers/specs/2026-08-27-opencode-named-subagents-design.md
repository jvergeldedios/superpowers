# OpenCode Named Subagents Design

**Date:** 2026-08-27
**Status:** Approved (fork-local; not intended for upstream PR)

## Goal

Give Superpowers' OpenCode integration three named subagents — implementation,
review, and exploration — so their default models can be tuned per role in
`opencode.json`. OpenCode's `task` tool accepts no per-dispatch model
parameter, so named agents are the only mechanism for controlling subagent
models on this harness.

## Background

Skills are harness-neutral: reviewer, implementer, and explorer dispatches all
say `Subagent (general-purpose):` and the OpenCode-specific translation lives
in the plugin's bootstrap tool-mapping block (`.opencode/plugins/superpowers.js`)
and its docs. Today every dispatch routes to `subagent_type: "general"`, which
always inherits the session model.

The plugin already mutates merged config in its `config` hook (this is how
skills get registered, and the same lazy-config mechanism was verified
empirically on OpenCode 1.18.23: a `config`-hook-injected agent is registered
and dispatchable by name via `task` with `subagent_type`).

## Design

### Agent definitions

The plugin registers three thin subagents from a new `SUBAGENTS` constant:

| Name | Extra fields | Role |
|------|-------------|------|
| `superpowers-implementer` | — | Executes task briefs: writes code, runs tests, commits |
| `superpowers-reviewer` | `permission: { edit: "deny" }` | Reviews diffs/specs/plans, reports findings, never edits |
| `superpowers-explorer` | `permission: { edit: "deny" }` | Codebase exploration and research, read-only |

All three are `mode: "subagent"` with no `model` field, so they inherit the
session default until the user overrides it. Agents are thin by design: no
baked-in prompts. The skills' prompt templates
(`implementer-prompt.md`, `task-reviewer-prompt.md`, `code-reviewer.md`, …)
remain the single source of truth and are filled into each dispatch as today.
This keeps behavior identical across harnesses and avoids prompt drift.

Merge semantics — user config wins field-by-field:

```js
config.agent = config.agent || {};
for (const [name, defaults] of Object.entries(SUBAGENTS)) {
  if (config.agent[name]?.disable) continue;   // user disabled it: respect that
  config.agent[name] = { ...defaults, ...config.agent[name] };
}
```

Tuning is then plain OpenCode config, global or per-project:

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

### Tool-mapping update

The bootstrap's subagent line becomes role-based, kept compact because it is
injected into every session's first user message:

> `Subagent (general-purpose):` → `task` with `subagent_type` by role —
> implementation/fix work → `superpowers-implementer`; reviews →
> `superpowers-reviewer`; exploration/research → `superpowers-explorer`;
> anything else or named agent unavailable → `general`

The `general` fallback preserves skill functionality on OpenCode versions
where hook injection no-ops.

### Out-of-the-box behavior change

Routing only (same model as before) plus read-only guards on reviewer and
explorer. No skill files change. Nothing breaks when the user has not set any
overrides.

### Docs

- `.opencode/INSTALL.md`: tool-mapping bullet gains the role-based routing; a
  short "Tuning subagent models" section shows the `opencode.json` example.
- `docs/README.opencode.md`: the same, in fuller form.

### Tests

Wired into `tests/opencode/run-tests.sh`:

1. **Unit** (`test-named-agents-merge.mjs`, no model calls): imports the
   plugin, calls the `config` hook against three configs — empty (all three
   injected), user `model` override (override preserved), `disable: true`
   (agent skipped).
2. **Integration** (`test-named-agents.sh`, following `test-tools.sh`'s
   isolated-env `opencode run` pattern): dispatches a trivial task to
   `superpowers-explorer` and asserts the subagent answers, proving
   registration and dispatch-by-name end to end.

## Known limitations (documented, not worked around)

- OpenCode's `task` tool takes no per-dispatch model, so SDD's "escalate to a
  more capable model on fix rounds 4–5" cannot be expressed per-dispatch. The
  controller uses the role's configured model and, when it would have
  escalated, records that in the ledger instead.
- Model granularity is per-role (three knobs), not per-task. This is the
  intended scope.
- If a future OpenCode version stops honoring `config`-hook agent injection,
  dispatches fall back to `general`; skills keep working but lose tunability.

## Non-goals

- No changes to skill content (harness-neutral by design; skill edits require
  evaluation evidence).
- No fat agents with baked-in prompts.
- No per-capability agent tiers (e.g., `superpowers-implementer-capable`) —
  YAGNI; revisit only if per-role granularity proves insufficient in real SDD
  sessions.
