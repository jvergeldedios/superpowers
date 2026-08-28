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
