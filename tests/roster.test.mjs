// Offline verification for the roster MVP (single source of truth + token policy).
//
// The roster (dsh-home/roster/team-lead.yml) drives the team-lead preset,
// the headless role patch, the AGENTS.md policy block and settings.yaml effort.
// These tests prove: clean tree passes --check, drift is caught with a line
// number, --write is idempotent + backups preserved, and the generated YAML is
// structurally correct.
//
// Run from dsh-workbench/:
//   ../../.toolchain/node-v22.23.2-darwin-arm64/bin/node tests/roster.test.mjs

import { cpSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const workbench = path.resolve(here, '..')
const require = createRequire(path.join(workbench, 'deepseek-harness', 'package.json'))
const yaml = require('js-yaml')

// The preset/patch files are entry lists; `!!js` scalars are part of the
// harness dialect (see deepseek-harness/vendor/include/src/index.ts).
const JsExpr = new yaml.Type('tag:yaml.org,2002:js', {
  kind: 'scalar',
  resolve: (data) => typeof data === 'string',
  construct: (data) => ({ __jsExpr: data }),
})
const SCHEMA = yaml.JSON_SCHEMA.extend(JsExpr)
const load = (text) => yaml.load(text, { schema: SCHEMA })

const RENDER = path.join(workbench, 'scripts', 'render-team.mjs')
const HOME = path.join(workbench, 'dsh-home')
const PRESET_REL = path.join('dsh-home', '.agent-presets', 'team-lead', 'agent.cordis.yml')
const PATCH_REL = path.join('dsh-home', 'team-roles.patch.yml')
const AGENTS_REL = path.join('dsh-home', 'AGENTS.md')
const SETTINGS_REL = path.join('dsh-home', 'settings.yaml')
const MCP_REL = path.join('dsh-home', 'profiles', 'web', 'mcp.patch.yml')

const run = (...args) => spawnSync(process.execPath, [RENDER, ...args], { encoding: 'utf8' })

const failures = []
const check = (ok, label, detail) => {
  if (ok) console.log('PASS  ' + label)
  else { failures.push(label + (detail ? ' — ' + detail : '')); console.log('FAIL  ' + label + (detail ? ' — ' + detail : '')) }
}

// ── 1. real tree: --print and --check ───────────────────────────────────────

const printed = run('--print')
check(printed.status === 0, '--print 退出码 0', printed.stderr.trim())
check(printed.stdout.includes('delegate_coder') && printed.stdout.includes('delegate_reviewer'), '--print 列出两个委派工具')
check(printed.stdout.includes('effort=low') && printed.stdout.includes('effort=high'), '--print 显示 coder=low / reviewer=high')
check(printed.stdout.includes('l3-and-risky'), '--print 显示复核口径')

const checked = run('--check')
check(checked.status === 0, '干净树 --check 退出码 0', (checked.stdout + checked.stderr).trim())

// ── 2. temp copy: drift detection, schema rejection, idempotent write ───────

const tmp = mkdtempSync(path.join(os.tmpdir(), 'dsh-roster-'))
cpSync(HOME, path.join(tmp, 'dsh-home'), { recursive: true })

// The real tree may carry backups from an earlier --write; start the copy clean
// so the backup assertions below observe only this test's first write.
const stripBackups = (dir) => {
  for (const dirent of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, dirent.name)
    try {
      if (dirent.isSymbolicLink()) continue
      if (dirent.isDirectory()) stripBackups(full)
      else if (dirent.name.endsWith('.roster-bak')) rmSync(full)
    } catch { /* the pnpm store holds disappearing entries; not our target */ }
  }
}
stripBackups(path.join(tmp, 'dsh-home'))

const injected = '\n# DRIFT-INJECTED-BY-TEST\n'
const patchPath = path.join(tmp, PATCH_REL)
writeFileSync(patchPath, readFileSync(patchPath, 'utf8') + injected)

const drifted = run('--check', '--root', tmp)
const driftOut = drifted.stdout + drifted.stderr
check(drifted.status === 1, '注入漂移后 --check 退出码 1')
check(/team-roles\.patch\.yml:\d+/.test(driftOut), '--check 指认漂移文件与行号', driftOut.trim().split('\n')[1] || '')

const bogusPath = path.join(tmp, 'dsh-home', 'roster', 'team-lead.yml')
writeFileSync(bogusPath, readFileSync(bogusPath, 'utf8') + '\nbogus: 1\n')
const bogus = run('--check', '--root', tmp)
check(bogus.status === 1, 'roster 未知字段导致校验退出码 1')
check((bogus.stdout + bogus.stderr).includes('bogus'), '报错信息点名未知字段 bogus', (bogus.stdout + bogus.stderr).trim())
writeFileSync(bogusPath, readFileSync(bogusPath, 'utf8').replace('\nbogus: 1\n', ''))

const files = [PRESET_REL, PATCH_REL, AGENTS_REL, SETTINGS_REL]
const snapshot = () => files.map((f) => readFileSync(path.join(tmp, f), 'utf8'))

const firstWrite = run('--write', '--root', tmp)
check(firstWrite.status === 0, '--write 退出码 0', (firstWrite.stdout + firstWrite.stderr).trim())
const afterFirst = snapshot()
check(existsSync(patchPath + '.roster-bak'), '首次写入留下 .roster-bak 备份')
check(readFileSync(patchPath + '.roster-bak', 'utf8').includes('DRIFT-INJECTED-BY-TEST'), '备份保留改动前内容')

const secondWrite = run('--write', '--root', tmp)
check(secondWrite.status === 0 && secondWrite.stdout.includes('0 个文件更新'), '第二次 --write 无文件更新（幂等）', secondWrite.stdout.trim())
check(JSON.stringify(afterFirst) === JSON.stringify(snapshot()), '两次 --write 输出字节一致')

const recheck = run('--check', '--root', tmp)
check(recheck.status === 0, '重写后 --check 退出码 0', (recheck.stdout + recheck.stderr).trim())

// ── 3. generated YAML structure ─────────────────────────────────────────────

// Entry lists nest: `insert` adds rows, `group: true` entries carry children
// under `config`. Walk both to reach every entry the preset mounts.
const collect = (nodes) => (nodes ?? []).flatMap((node) => [
  ...(node && typeof node === 'object' ? [node] : []),
  ...collect(Array.isArray(node?.insert) ? node.insert : undefined),
  ...collect(Array.isArray(node?.config) ? node.config : undefined),
])

const preset = load(readFileSync(path.join(tmp, PRESET_REL), 'utf8'))
const entries = collect(preset)
const subagent = (toolName) => entries.find((e) => e?.config?.toolName === toolName)

const coder = subagent('delegate_coder')
const reviewer = subagent('delegate_reviewer')
check(Boolean(coder) && Boolean(reviewer), '预设含 delegate_coder / delegate_reviewer 两个委派工具')

const EXPECTED_DENY = ['web_search', 'web_fetch', 'subagent', 'subagent_fork', 'subagent_codex', 'subagent_claude_code', 'delegate_coder', 'delegate_reviewer']
const denyOf = (entry) => entry?.config?.toolFilter?.deny ?? []
check(EXPECTED_DENY.every((t) => denyOf(coder).includes(t)) && denyOf(coder).length === EXPECTED_DENY.length,
  'coder deny 列表完整', JSON.stringify(denyOf(coder)))
check(['write', 'edit', ...EXPECTED_DENY].every((t) => denyOf(reviewer).includes(t)) && denyOf(reviewer).length === EXPECTED_DENY.length + 2,
  'reviewer 额外 deny write/edit（只读复核）', JSON.stringify(denyOf(reviewer)))
check(coder?.config?.agentOptions?.reasoningEffort === 'low' && reviewer?.config?.agentOptions?.reasoningEffort === 'high',
  'coder=low / reviewer=high 档位写入预设')
check(coder?.config?.agentOptions?.maxTokens === 32768 && reviewer?.config?.agentOptions?.maxTokens === 32768, '两个角色预算 32768')
check(coder?.config?.maxDepth === 1 && reviewer?.config?.maxDepth === 1, '两个角色 maxDepth=1')
check(coder?.config?.backgroundMode === 'one-shot' && reviewer?.config?.backgroundMode === 'one-shot', '两个角色 one-shot')

const compaction = entries.find((e) => e?.config?.some?.((c) => c?.id === 'compaction-basic'))
const basic = compaction?.config?.find((c) => c?.id === 'compaction-basic')
check(basic?.config?.thresholdRatio === 0.2 && basic?.config?.retainTokens === 20000, '压缩策略 0.2 / 20000', JSON.stringify(basic?.config))
const pruner = compaction?.config?.find((c) => c?.id === 'tool-result-pruner')
check(pruner?.config?.thresholdChars === 4096 && pruner?.config?.headChars === 2048 && pruner?.config?.tailChars === 512,
  '剪枝策略 4096 / 2048 / 512', JSON.stringify(pruner?.config))

const patch = load(readFileSync(path.join(tmp, PATCH_REL), 'utf8'))
const patchEntries = (patch ?? []).flatMap((node) => (Array.isArray(node?.insert) ? node.insert : []))
check(Boolean(patchEntries.find((e) => e?.config?.toolName === 'delegate_coder')) && Boolean(patchEntries.find((e) => e?.config?.toolName === 'delegate_reviewer')),
  'team-roles.patch.yml 含两个委派工具且可解析')

// ── 4. policy coherence across files ────────────────────────────────────────

const roster = load(readFileSync(path.join(tmp, 'dsh-home', 'roster', 'team-lead.yml'), 'utf8'))
const settings = load(readFileSync(path.join(tmp, SETTINGS_REL), 'utf8'))
check(settings?.['agent-default-model']?.reasoningEffort === roster.model.leadEffort,
  'settings.yaml 档位跟随 roster.leadEffort', `${settings?.['agent-default-model']?.reasoningEffort} vs ${roster.model.leadEffort}`)
check(settings?.['agent-default-model']?.provider === roster.model.provider && settings?.['agent-default-model']?.model === roster.model.model,
  'settings.yaml 默认模型与 roster 一致')

const agents = readFileSync(path.join(tmp, AGENTS_REL), 'utf8')
check(agents.includes('l3-and-risky') && !agents.includes('All coding tasks must be reviewed'),
  'AGENTS.md 复核口径 = 仅 L3 / 有风险')

const presetText = readFileSync(path.join(tmp, PRESET_REL), 'utf8')
check(presetText.includes('REVIEW POLICY from AGENTS.md'), '预设 persona 指向 AGENTS.md 复核口径')

const mcp = load(readFileSync(path.join(tmp, MCP_REL), 'utf8'))
const mcpEntries = (mcp ?? []).flatMap((node) => (Array.isArray(node?.insert) ? node.insert : []))
check(!mcpEntries.some((e) => e?.id === 'mcp-github'), 'GitHub MCP 默认关闭')
check(mcpEntries.some((e) => e?.id === 'mcp-filesystem') && mcpEntries.some((e) => e?.id === 'mcp-world-store'),
  'filesystem / world_store MCP 保留')

rmSync(tmp, { recursive: true, force: true })

if (failures.length) {
  console.log('\n' + failures.length + ' 项未通过')
  process.exitCode = 1
} else {
  console.log('\nRoster MVP 校验全部通过')
}
