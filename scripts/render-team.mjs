#!/usr/bin/env node
/**
 * Render the team roster (dsh-home/roster/team-lead.yml) into the files that
 * actually run: the team-lead preset's generated regions, the headless role
 * patch, the AGENTS.md policy block, and the default model effort.
 *
 * One source of truth, deterministic output, no dependencies beyond the
 * harness's own js-yaml. Default run is a dry-run preview; `--write` applies;
 * `--check` fails (exit 1) when any generated file drifts from the roster.
 */

import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const workbench = path.resolve(here, '..')
const require = createRequire(path.join(workbench, 'deepseek-harness', 'package.json'))
const { load } = require('js-yaml')

const ROSTER_REL = 'dsh-home/roster/team-lead.yml'
const PRESET_REL = 'dsh-home/.agent-presets/team-lead/agent.cordis.yml'
const PATCH_REL = 'dsh-home/team-roles.patch.yml'
const AGENTS_REL = 'dsh-home/AGENTS.md'
const SETTINGS_REL = 'dsh-home/settings.yaml'

const argv = process.argv.slice(2)
const mode = argv.includes('--write') ? 'write' : argv.includes('--check') ? 'check' : argv.includes('--print') ? 'print' : 'preview'
const rootIndex = argv.indexOf('--root')
const root = rootIndex === -1 ? workbench : path.resolve(argv[rootIndex + 1])
const rel = (p) => path.join(root, p)

const problems = []
const fail = (message) => { problems.push(message) }

// ── roster loading and validation ───────────────────────────────────────────

const isPlainObject = (value) => typeof value === 'object' && value !== null && !Array.isArray(value)

function expectKeys(value, allowed, at) {
  if (!isPlainObject(value)) { fail(`${at} 必须是映射`); return }
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) fail(`${at} 含未知字段 "${key}"（允许：${allowed.join(', ')}）`)
  }
}

const EFFORT_ALWAYS_ALLOWED = ['off']
const POLICIES = {
  'l3-and-risky': [
    '`l3-and-risky`: call `delegate_reviewer` only for L3 tasks or risky/irreversible',
    'changes. L1 answers directly; L2 calls `delegate_coder` once and the Lead checks',
    'its report. If the result looks wrong, escalate and verify.',
  ],
  always: [
    '`always`: call `delegate_reviewer` before reporting any coding task done.',
  ],
  never: [
    '`never`: do not call `delegate_reviewer`; the Lead verifies the Coder report.',
  ],
}

// The global tool names this deployment's runtime actually registers. A deny
// entry the runtime cannot resolve makes `tools.restrict()` throw while the
// subagent tool is being built — the delegation fails with a tool error before
// any child session exists, which reads like a hang from the outside. The list
// is the verbatim `known global tools:` echo from that error (Web profile with
// the filesystem + world_store MCP servers mounted); `mcp__`-prefixed names are
// checked only by prefix because MCP servers come and go with the profile.
const KNOWN_TOOLS = new Set([
  'ask_user_question', 'bash', 'create_goal', 'delegate_coder', 'delegate_reviewer', 'edit',
  'exit_plan_mode', 'get_goal', 'glob', 'grep', 'interrupt_agent', 'job_kill', 'job_list',
  'job_output', 'list_agents', 'ralph', 'read', 'read_image', 'send_message', 'skill',
  'subagent_codex', 'subagent_fork', 'todo_write', 'update_goal', 'web_fetch', 'web_search',
  'workflow', 'write',
])

function settingsEfforts(settingsText, provider, model) {
  const parsed = load(settingsText)
  const entry = parsed?.['llm-pi-ai']?.providers?.[provider]?.models?.find((m) => m.id === model)
  const efforts = entry?.reasoningEfforts
  return isPlainObject(efforts) ? Object.keys(efforts) : undefined
}

function validate(roster, settingsText) {
  expectKeys(roster, ['version', 'preset', 'model', 'context', 'review', 'roles'], 'roster')
  if (roster.version !== 1) fail('roster.version 必须为 1')
  expectKeys(roster.preset, ['id', 'name'], 'roster.preset')
  expectKeys(roster.model, ['provider', 'model', 'leadEffort'], 'roster.model')
  expectKeys(roster.context, ['compaction', 'pruning'], 'roster.context')
  expectKeys(roster.context?.compaction, ['thresholdRatio', 'retainTokens'], 'roster.context.compaction')
  expectKeys(roster.context?.pruning, ['thresholdChars', 'headChars', 'tailChars'], 'roster.context.pruning')
  expectKeys(roster.review, ['policy'], 'roster.review')
  if (!POLICIES[roster.review?.policy]) fail(`roster.review.policy 必须是 ${Object.keys(POLICIES).join(' / ')}`)

  const c = roster.context?.compaction ?? {}
  if (!(c.thresholdRatio > 0 && c.thresholdRatio <= 1)) fail('compaction.thresholdRatio 必须在 (0, 1]')
  if (!Number.isInteger(c.retainTokens) || c.retainTokens < 1000) fail('compaction.retainTokens 必须是 ≥1000 的整数')
  const p = roster.context?.pruning ?? {}
  for (const key of ['thresholdChars', 'headChars', 'tailChars']) {
    if (!Number.isInteger(p[key]) || p[key] < 128) fail(`pruning.${key} 必须是 ≥128 的整数`)
  }
  if (p.headChars + p.tailChars > p.thresholdChars) fail('pruning: headChars + tailChars 不能超过 thresholdChars')

  const declared = settingsEfforts(settingsText, roster.model?.provider, roster.model?.model)
  if (declared === undefined) fail(`settings.yaml 里找不到 ${roster.model?.provider}/${roster.model?.model} 的 reasoningEfforts`)
  const allowedEfforts = [...(declared ?? []), ...EFFORT_ALWAYS_ALLOWED]
  const checkEffort = (effort, at) => {
    if (!allowedEfforts.includes(effort)) fail(`${at} 档位 "${effort}" 未在该模型声明（可用：${declared?.join(', ') ?? '未知'}）`)
  }
  checkEffort(roster.model?.leadEffort, 'roster.model.leadEffort')

  if (!Array.isArray(roster.roles) || roster.roles.length === 0) fail('roster.roles 至少要有一个角色')
  const seen = new Set()
  for (const role of roster.roles ?? []) {
    const at = `roster.roles[${role?.id ?? '?'}]`
    expectKeys(role, ['id', 'toolName', 'title', 'purpose', 'effort', 'maxTokens', 'maxDepth', 'backgroundMode', 'toolDeny', 'report', 'persona'], at)
    if (!/^[a-z][a-z0-9_]*$/.test(role.id ?? '')) fail(`${at}.id 必须是小写 snake_case`)
    if (!/^[a-z][a-z0-9_]*$/.test(role.toolName ?? '')) fail(`${at}.toolName 必须是小写 snake_case`)
    if (seen.has(role.toolName)) fail(`${at}.toolName 与其它角色重复`)
    seen.add(role.toolName)
    checkEffort(role.effort, `${at}.effort`)
    if (!Number.isInteger(role.maxTokens) || role.maxTokens < 1024) fail(`${at}.maxTokens 必须是 ≥1024 的整数`)
    if (!Number.isInteger(role.maxDepth) || role.maxDepth < 1) fail(`${at}.maxDepth 必须是 ≥1 的整数`)
    if (!['one-shot', 'continuable'].includes(role.backgroundMode)) fail(`${at}.backgroundMode 必须是 one-shot / continuable`)
    if (!Array.isArray(role.toolDeny) || role.toolDeny.some((t) => typeof t !== 'string')) fail(`${at}.toolDeny 必须是字符串数组`)
    for (const name of Array.isArray(role.toolDeny) ? role.toolDeny : []) {
      if (typeof name !== 'string' || name.startsWith('mcp__')) continue
      if (!KNOWN_TOOLS.has(name)) {
        fail(`${at}.toolDeny 含运行时没有的工具名 "${name}"（委派会以 tools.restrict() 报错告终；`
          + `可用：${[...KNOWN_TOOLS].join(', ')}）`)
      }
    }
    if (!Array.isArray(role.report) || role.report.length === 0) fail(`${at}.report 至少要有一项`)
    if (typeof role.persona !== 'string' || role.persona.trim() === '') fail(`${at}.persona 不能为空`)
  }
}

// ── region helpers ──────────────────────────────────────────────────────────

const markerEnd = (comment, kind) => (comment === '<!--'
  ? `<!-- <<< generated: ${kind} <<< -->`
  : `${comment} <<< generated: ${kind} <<<`)

function regionBody(text, kind, comment = '#') {
  const start = `${comment} >>> generated: ${kind} (${ROSTER_REL}) >>>`
  const end = markerEnd(comment, kind)
  const lines = text.split('\n')
  const from = lines.findIndex((line) => line.trim() === (comment === '#' ? start : start))
  if (from === -1) return undefined
  const to = lines.findIndex((line, index) => index > from && line.replace(/^\s*/, '') === end.replace(/^\s*/, ''))
  if (to === -1) return undefined
  return { from, to, body: lines.slice(from + 1, to).join('\n') }
}

function applyRegion(text, kind, rendered, comment = '#') {
  const start = `${comment} >>> generated: ${kind} (${ROSTER_REL}) >>>`
  const end = markerEnd(comment, kind)
  const found = regionBody(text, kind, comment)
  if (found) {
    const lines = text.split('\n')
    const head = lines.slice(0, found.from + 1)
    const tail = lines.slice(found.to)
    return [...head, ...rendered.split('\n'), ...tail].join('\n')
  }
  fail(`无法定位 ${kind} 生成区（既没有标记，也没有可迁移的旧文本）`)
  return text
}

function replaceSpan(text, startLine, endLine, replacement) {
  const lines = text.split('\n')
  const from = lines.indexOf(startLine)
  if (from === -1) return undefined
  const to = lines.indexOf(endLine, from)
  if (to === -1) return undefined
  return [...lines.slice(0, from), ...replacement.split('\n'), ...lines.slice(to + 1)].join('\n')
}

// ── rendering ───────────────────────────────────────────────────────────────

const yq = (value) => {
  if (typeof value === 'number' || typeof value === 'boolean') return String(value)
  return /^[A-Za-z0-9_.@-]+$/.test(value) ? value : `'${String(value).replace(/'/g, "''")}'`
}

function renderDenyList(names, indent) {
  const inline = `[${names.join(', ')}]`
  if (inline.length <= 90) return [`${indent}deny: ${inline}`]
  return [`${indent}deny:`, ...names.map((name) => `${indent}  - ${yq(name)}`)]
}

function renderRole(role, roster, indent) {
  const report = `Return a short report covering exactly: ${role.report.join('; ')}.`
  const personaLines = [...role.persona.replace(/\n+$/, '').split('\n'), '', report]
  const pad = `${indent}      `
  return [
    `${indent}- id: delegate-${role.id.replace(/_/g, '-')}`,
    `${indent}  name: '@deepseek-ai/dsh-tool-subagent'`,
    `${indent}  config:`,
    `${indent}    provider: spawn`,
    `${indent}    toolName: ${yq(role.toolName)}`,
    `${indent}    backgroundMode: ${yq(role.backgroundMode)}`,
    `${indent}    maxDepth: ${role.maxDepth}`,
    `${indent}    agentOptions:`,
    `${indent}      provider: ${yq(roster.model.provider)}`,
    `${indent}      model: ${yq(roster.model.model)}`,
    `${indent}      reasoningEffort: ${yq(role.effort)}`,
    `${indent}      maxTokens: ${role.maxTokens}`,
    `${indent}    toolFilter:`,
    ...renderDenyList(role.toolDeny, `${indent}      `),
    `${indent}    persona: |`,
    ...personaLines.map((line) => (line === '' ? '' : `${pad}${line}`.replace(/\s+$/, ''))),
  ].join('\n')
}

function renderRolesRegion(roster) {
  const header = '    # ── Fixed teammates (generated; edit dsh-home/roster/team-lead.yml) ──'
  const roles = roster.roles.map((role) => renderRole(role, roster, '    '))
  return [header, ...roles].join('\n\n')
}

function renderTokenPolicyRegion(roster) {
  const { compaction, pruning } = roster.context
  return [
    '- id: compaction',
    '  name: cordis:group',
    '  group: true',
    '  isolate:',
    '    compaction: true',
    '    toolResultPruner: true',
    '  config:',
    '    - id: compaction-basic',
    "      name: '@deepseek-ai/dsh-compaction-basic'",
    '      config:',
    `        thresholdRatio: ${compaction.thresholdRatio}`,
    `        retainTokens: ${compaction.retainTokens}`,
    '',
    '    - id: command-compact',
    "      name: '@deepseek-ai/dsh-command-compact'",
    '',
    '    - id: tool-result-pruner',
    "      name: '@deepseek-ai/dsh-compaction-tool-result-pruner'",
    '      config:',
    `        thresholdChars: ${pruning.thresholdChars}`,
    `        headChars: ${pruning.headChars}`,
    `        tailChars: ${pruning.tailChars}`,
  ].join('\n')
}

function renderPatchFile(roster) {
  const roles = roster.roles.map((role) => renderRole(role, roster, '    '))
  return [
    '# Lightweight team roles — all roles run IN-PROCESS via the spawn backend.',
    `# GENERATED from ${ROSTER_REL} — do not edit by hand.`,
    '# Regenerate: node dsh-workbench/scripts/render-team.mjs --write',
    '',
    '- id: tool-subagent',
    '  config:',
    '    provider: spawn',
    '    toolName: subagent',
    '    backgroundMode: one-shot',
    '',
    '- insert:',
    ...roles,
    '',
  ].join('\n')
}

function renderAgentsBlock(roster) {
  const policyLines = POLICIES[roster.review.policy]
  const rows = roster.roles.map((role) => `| ${role.title} | \`${role.toolName}\` | ${role.effort} | ${role.toolDeny.join(', ')} |`)
  return [
    '## Roles and review policy (generated)',
    '',
    '| Role | Tool | Model effort | Denied tools |',
    '| --- | --- | --- | --- |',
    ...rows,
    '',
    '**Review policy**',
    '',
    ...policyLines,
    '',
    'Keep delegation one-shot: wait for each result instead of leaving background',
    'children running.',
    '',
    `Roster: \`${ROSTER_REL}\` · regenerate: \`node dsh-workbench/scripts/render-team.mjs --write\``,
  ].join('\n')
}

function renderSettings(text, roster) {
  const lines = text.split('\n')
  const at = lines.indexOf('agent-default-model:')
  if (at === -1) return undefined
  for (let index = at + 1; index < lines.length; index++) {
    if (/^\S/.test(lines[index])) break
    if (/^  reasoningEffort: /.test(lines[index])) {
      lines[index] = `  reasoningEffort: ${roster.model.leadEffort}`
      return lines.join('\n')
    }
  }
  return undefined
}

// ── first-run migration of the hand-written blocks ──────────────────────────

const LEGACY_PRESET_COMPACTION = { start: '- id: compaction', end: '        tailChars: 1024' }
const LEGACY_PRESET_ROLES = {
  indent: '    ',
  start: '    # ── Fixed three-role teammates (in-process spawn, flat, role persona) ──',
  end: '          and a precise list of any issues with where they are.',
}
const LEGACY_AGENTS = {
  start: '## Your teammates (in-process, one-shot delegation tools)',
  end: 'children running.',
}

function migrate(text, legacy, kind, rendered, comment = '#') {
  if (regionBody(text, kind, comment)) return text
  const indent = legacy.indent ?? ''
  const start = `${indent}${comment} >>> generated: ${kind} (${ROSTER_REL}) >>>`
  const end = `${indent}${comment} <<< generated: ${kind} <<<`
  const block = `${start}\n${rendered}\n${end}`
  const next = replaceSpan(text, legacy.start, legacy.end, block)
  if (next === undefined) fail(`无法迁移 ${kind} 生成区：旧文本锚点未命中`)
  return next ?? text
}

// ── main ────────────────────────────────────────────────────────────────────

const rosterText = readFileSync(rel(ROSTER_REL), 'utf8')
const roster = load(rosterText)
const settingsBefore = readFileSync(rel(SETTINGS_REL), 'utf8')
validate(roster, settingsBefore)

if (mode === 'print' && problems.length === 0) {
  console.log(`preset: ${roster.preset.id}（${roster.preset.name}）`)
  console.log(`Lead: ${roster.model.provider}/${roster.model.model} · effort=${roster.model.leadEffort}`)
  console.log(`compaction: thresholdRatio=${roster.context.compaction.thresholdRatio} retainTokens=${roster.context.compaction.retainTokens}`)
  console.log(`pruning: ${roster.context.pruning.thresholdChars}/${roster.context.pruning.headChars}/${roster.context.pruning.tailChars}`)
  console.log(`review: ${roster.review.policy}`)
  for (const role of roster.roles) {
    console.log(`- ${role.title.padEnd(9)} ${role.toolName.padEnd(18)} model=${roster.model.model} effort=${role.effort.padEnd(5)} maxTokens=${role.maxTokens} maxDepth=${role.maxDepth}`)
    console.log(`  deny: [${role.toolDeny.join(', ')}]`)
  }
}

/** 1-based line number of the first line that differs between two texts. */
function firstDiffLine(before, after) {
  const a = before.split('\n')
  const b = after.split('\n')
  const max = Math.max(a.length, b.length)
  for (let i = 0; i < max; i++) {
    if (a[i] !== b[i]) return i + 1
  }
  return max
}

const plan = []
if (problems.length === 0) {
  const presetBefore = readFileSync(rel(PRESET_REL), 'utf8')
  let presetAfter = migrate(presetBefore, LEGACY_PRESET_COMPACTION, 'token-policy', renderTokenPolicyRegion(roster))
  presetAfter = applyRegion(presetAfter, 'token-policy', renderTokenPolicyRegion(roster))
  presetAfter = migrate(presetAfter, LEGACY_PRESET_ROLES, 'roles', renderRolesRegion(roster))
  presetAfter = applyRegion(presetAfter, 'roles', renderRolesRegion(roster))
  presetAfter = presetAfter.replace(/^    # ── Fixed three-role teammates.*\n/m, '')
  if (!presetAfter.replace(/\s+/g, ' ').includes('REVIEW POLICY from AGENTS.md')) {
    fail('预设 persona 必须包含 "REVIEW POLICY from AGENTS.md"（复核口径的唯一出处是 AGENTS.md 生成块）')
  }
  plan.push({ rel: PRESET_REL, before: presetBefore, after: presetAfter })

  const patchBefore = readFileSync(rel(PATCH_REL), 'utf8')
  plan.push({ rel: PATCH_REL, before: patchBefore, after: renderPatchFile(roster) })

  const agentsBefore = readFileSync(rel(AGENTS_REL), 'utf8')
  let agentsAfter = migrate(agentsBefore, LEGACY_AGENTS, 'team-policy', renderAgentsBlock(roster), '<!--')
  agentsAfter = applyRegion(agentsAfter, 'team-policy', renderAgentsBlock(roster), '<!--')
  plan.push({ rel: AGENTS_REL, before: agentsBefore, after: agentsAfter })

  const settingsAfter = renderSettings(settingsBefore, roster)
  if (settingsAfter === undefined) fail('settings.yaml 里找不到 agent-default-model.reasoningEffort')
  else plan.push({ rel: SETTINGS_REL, before: settingsBefore, after: settingsAfter })
}

if (problems.length) {
  console.error('roster 校验未通过：')
  for (const problem of problems) console.error('  - ' + problem)
  process.exitCode = 1
} else if (mode === 'check') {
  const drifted = plan.filter((entry) => entry.before !== entry.after)
  if (drifted.length) {
    console.error('生成物与 roster 不一致（运行 --write 应用）：')
    for (const entry of drifted) console.error(`  - ${entry.rel}:${firstDiffLine(entry.before, entry.after)}`)
    process.exitCode = 1
  } else {
    console.log('roster 与全部生成物一致。')
  }
} else if (mode === 'write') {
  for (const entry of plan) {
    if (entry.before === entry.after) continue
    const target = rel(entry.rel)
    const backup = target + '.roster-bak'
    if (!existsSync(backup)) copyFileSync(target, backup)
    mkdirSync(path.dirname(target), { recursive: true })
    writeFileSync(target, entry.after, 'utf8')
    const delta = entry.after.split('\n').length - entry.before.split('\n').length
    console.log(`写入 ${entry.rel}（行数变化 ${delta >= 0 ? '+' : ''}${delta}，备份 ${path.basename(backup)}）`)
  }
  const unchanged = plan.filter((entry) => entry.before === entry.after).length
  console.log(`完成：${plan.length - unchanged} 个文件更新，${unchanged} 个已一致。`)
} else {
  const drifted = plan.filter((entry) => entry.before !== entry.after)
  if (drifted.length === 0) console.log('预览：生成物已与 roster 一致，无需写入。')
  else {
    console.log('预览（dry-run，未写入）：')
    for (const entry of drifted) {
      const delta = entry.after.split('\n').length - entry.before.split('\n').length
      console.log(`  - ${entry.rel}:${firstDiffLine(entry.before, entry.after)}（行数变化 ${delta >= 0 ? '+' : ''}${delta}）`)
    }
    console.log('应用请运行：node dsh-workbench/scripts/render-team.mjs --write')
  }
}
