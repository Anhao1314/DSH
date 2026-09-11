// Real-history verification for the console token-usage MVP.
//
// Replays the persisted dsh-home sessions (projection cache + zstd event logs,
// no server needed) through the real console page in jsdom, then checks the
// rendered numbers against independently computed sums from the same raw data:
//   - conversation pill = root + child tokenUsage projections
//   - per-turn bars = assistant/message usage folded by turn/step
//   - the per-turn sum equals the authoritative tokenUsage projection
//
// Run from dsh-workbench/:
//   ../../.toolchain/node-v22.23.2-darwin-arm64/bin/node tests/console-history.test.mjs

import { readFileSync, readdirSync, statSync } from 'node:fs'
import { createRequire } from 'node:module'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { zstdDecompressSync } from 'node:zlib'

const here = path.dirname(fileURLToPath(import.meta.url))
const workbench = path.resolve(here, '..')
const dshHome = path.join(workbench, 'dsh-home')
const require = createRequire(path.join(workbench, 'deepseek-harness', 'package.json'))
const { JSDOM, VirtualConsole } = require('jsdom')

const ZSTD_MAGIC = 0xFD2FB528
/** Locate concatenated Zstandard frames (same container as session-persistence-jsonl). */
function scanFrames(buffer) {
  const frames = []
  let offset = 0
  while (offset < buffer.length) {
    const start = offset
    if (buffer.readUInt32LE(offset) !== ZSTD_MAGIC) throw new Error('invalid frame magic at ' + offset)
    offset += 4
    const descriptor = buffer.readUInt8(offset); offset += 1
    const contentSizeFlag = descriptor >>> 6
    const singleSegment = (descriptor & 0x20) !== 0
    const checksum = (descriptor & 0x04) !== 0
    const dictionaryFlag = descriptor & 0x03
    const dictionaryBytes = dictionaryFlag === 3 ? 4 : dictionaryFlag
    const contentSizeBytes = contentSizeFlag === 0 ? (singleSegment ? 1 : 0) : 1 << contentSizeFlag
    offset += (singleSegment ? 0 : 1) + dictionaryBytes + contentSizeBytes
    for (;;) {
      const blockHeader = buffer.readUIntLE(offset, 3); offset += 3
      const lastBlock = (blockHeader & 1) !== 0
      const blockType = (blockHeader >>> 1) & 0x03
      offset += blockType === 0x01 ? 1 : blockHeader >>> 3
      if (lastBlock) break
    }
    if (checksum) offset += 4
    frames.push({ start, end: offset })
  }
  return frames
}

function readEvents(file) {
  const buffer = readFileSync(file)
  const frames = scanFrames(buffer)
  let text = ''
  for (const frame of frames) text += zstdDecompressSync(buffer.subarray(frame.start, frame.end)).toString('utf8')
  return text.split('\n').filter(Boolean).map((line) => JSON.parse(line))
}

const projDir = path.join(dshHome, 'storages', 'session_projcache', 'sessions')
const sessionsDir = path.join(dshHome, 'sessions')
const eventFile = (root, id) => path.join(root, id, 'session.v3.jsonl.zstd')
const fmtTok = (n) => { n = Math.round(n); return n >= 1e6 ? (n / 1e6).toFixed(2) + 'M' : n >= 1e3 ? (n / 1e3).toFixed(1) + 'k' : '' + n }

const items = []
const recordsBySid = {}
const projectionBySid = {}
for (const file of readdirSync(projDir)) {
  if (!file.endsWith('.json')) continue
  const sessionId = file.slice(0, -'.json'.length)
  const rows = JSON.parse(readFileSync(path.join(projDir, file), 'utf8')).record.rows
  const seqs = Object.values(rows).map((row) => row.seq || 0)
  const values = {
    title: rows.title && rows.title.val || '',
    tokenUsage: rows.tokenUsage && rows.tokenUsage.val.totals,
    sessionStats: rows.sessionStats && rows.sessionStats.val,
    modelSelection: rows.modelSelection && rows.modelSelection.val,
    turnOutline: (rows.turnOutline && rows.turnOutline.val.turns) || [],
    subagent: (rows.subagent && rows.subagent.val.identity) || null,
    sessionListMetadata: rows.sessionListMetadata && rows.sessionListMetadata.val,
  }
  projectionBySid[sessionId] = values.tokenUsage

  let header = { id: sessionId }
  for (const root of readdirSync(sessionsDir)) {
    const candidate = eventFile(path.join(sessionsDir, root), sessionId)
    try { statSync(candidate) } catch { continue }
    const events = readEvents(candidate)
    header = events[0]
    recordsBySid[sessionId] = events.slice(1).map((event) => ({ type: 'event', event }))
    break
  }
  items.push({
    sessionId,
    ...(header.parentSession === undefined ? {} : { parentSessionId: header.parentSession }),
    updatedAt: statSync(path.join(projDir, file)).mtimeMs,
    running: false,
    projections: { asOfSeq: Math.max(...seqs), values },
  })
}

const kidsOf = (sid) => items.filter((it) => it.parentSessionId === sid)
const sumTotals = (sids) => sids.reduce((acc, sid) => {
  const t = projectionBySid[sid] || { uncachedInputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0, outputTokens: 0 }
  return acc + t.uncachedInputTokens + t.cacheReadTokens + t.cacheWriteTokens + t.outputTokens
}, 0)
const turnsOf = (sid) => {
  const byTurn = new Map()
  for (const record of recordsBySid[sid] || []) {
    const event = record.event
    if (event.type !== 'assistant/message' || !event.data.usage) continue
    const u = event.data.usage
    byTurn.set(event.data.turn, (byTurn.get(event.data.turn) || 0)
      + (u.inputTokens || 0) + (u.cacheReadTokens || 0) + (u.cacheWriteTokens || 0) + (u.outputTokens || 0))
  }
  return [...byTurn.values()]
}

const html = readFileSync(path.join(dshHome, 'console', 'index.html'), 'utf8')
const failures = []
const problems = []
const check = (ok, label, detail) => {
  if (ok) console.log('PASS  ' + label)
  else { failures.push(label + (detail ? ' — ' + detail : '')); console.log('FAIL  ' + label + (detail ? ' — ' + detail : '')) }
}

const virtualConsole = new VirtualConsole()
virtualConsole.on('jsdomError', (e) => problems.push('jsdomError: ' + (e && e.message ? e.message : e)))
virtualConsole.on('error', (...args) => problems.push('console.error: ' + args.join(' ')))
const json = (value) => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(value), text: () => Promise.resolve('') })

class FakeWebSocket {
  constructor() {
    this.readyState = 1
    setTimeout(() => { if (this.onopen) this.onopen() }, 0)
  }
  send(raw) {
    const msg = JSON.parse(raw)
    if (msg.type !== 'open' || msg.endpoint !== 'session/follow') return
    const sid = msg.payload.args.request.address.sessionId
    const frame = { streamId: msg.streamId, type: 'snapshot', value: { type: 'snapshot', records: recordsBySid[sid] || [] } }
    setTimeout(() => { if (this.onmessage) this.onmessage({ data: JSON.stringify(frame) }) }, 0)
  }
  close() {}
}

const dom = new JSDOM(html, {
  url: 'http://127.0.0.1:3081/console',
  runScripts: 'dangerously',
  pretendToBeVisual: true,
  virtualConsole,
  beforeParse(window) {
    window.WebSocket = FakeWebSocket
    window.fetch = (url) => {
      const u = String(url)
      if (u.startsWith('/api/session/list')) return json({ result: { ok: true, value: { items } } })
      if (u.startsWith('/api/session/page')) return json({ result: { ok: true, value: { records: [] } } })
      if (u.startsWith('/api/')) return json({ result: { ok: true, value: {} } })
      if (u.startsWith('/console-api/artifacts')) return json({ files: [] })
      return json({})
    }
  },
})

const { window } = dom
const { document } = window
const $ = (id) => document.getElementById(id)
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

try {
  await sleep(120)

  const active = document.querySelector('#taskList .row.active')
  check(active !== null, '真实历史会话渲染出侧边栏选中项')
  const sid = active && active.getAttribute('data-sid')
  const childIds = sid ? kidsOf(sid).map((it) => it.sessionId) : []
  const expectedTotal = sid ? sumTotals([sid, ...childIds]) : 0
  const pill = $('cTokens')
  check(pill && pill.style.display !== 'none' && pill.textContent.trim() === fmtTok(expectedTotal) + ' tokens',
    'pill 等于真实 root+子角色投影之和', pill && pill.textContent.trim() + ' vs ' + fmtTok(expectedTotal))

  document.querySelector('#inspTabs .segbtn[data-tab="usage"]').click()
  const pane = $('usagePane')
  check(pane.textContent.includes(fmtTok(expectedTotal)), '用量栏显示同一总量')
  check(pane.querySelectorAll('.rolebar').length === 1 + childIds.length, '角色条数 = Lead + 子会话数',
    pane.querySelectorAll('.rolebar').length + ' vs ' + (1 + childIds.length))

  const expectedTurns = sid ? turnsOf(sid) : []
  const rows = [...pane.querySelectorAll('.turnrow')]
  check(rows.length === expectedTurns.length, '逐轮条数等于真实 assistant/message 轮数', rows.length + ' vs ' + expectedTurns.length)
  const shownTurns = rows.map((r) => r.querySelector('.tm span:last-child').textContent)
  const wantTurns = expectedTurns.map(fmtTok)
  check(shownTurns.join(',') === wantTurns.join(','), '逐轮数值等于独立聚合结果', shownTurns.join(',') + ' vs ' + wantTurns.join(','))

  const rootProjected = projectionBySid[sid]
  const projectedTotal = rootProjected.uncachedInputTokens + rootProjected.cacheReadTokens + rootProjected.cacheWriteTokens + rootProjected.outputTokens
  const turnSum = expectedTurns.reduce((a, b) => a + b, 0)
  check(turnSum === projectedTotal, '真实数据：逐轮聚合 = tokenUsage 投影总量', turnSum + ' vs ' + projectedTotal)

  $('mStats').click()
  const body = $('statsBody').textContent
  check($('statsModal').classList.contains('open') && body.includes('未缓存输入') && body.includes('总token'), '总览弹窗渲染真实历史拆分')
  check(problems.length === 0, '页面无 JS 错误', problems.join(' | '))
} catch (error) {
  failures.push('异常：' + (error && error.stack ? error.stack : error))
} finally {
  window.close()
}

if (failures.length) {
  console.log('\n' + failures.length + ' 项未通过')
  process.exitCode = 1
} else {
  console.log('\n真实历史数据渲染验证全部通过')
}
