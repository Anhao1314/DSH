// Offline verification for the console token-usage MVP.
//
// Loads the real console page in jsdom, feeds a synthetic session/list +
// session/follow payload, and asserts the three deliverables render:
//   1. the always-on conversation token pill
//   2. the inspector "用量" pane (totals, role bars, per-turn bars)
//   3. the global stats modal breakdown (uncached / cache read / cache write / output)
//
// Run from dsh-workbench/:
//   ../../.toolchain/node-v22.23.2-darwin-arm64/bin/node tests/console-usage.test.mjs

import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const workbench = path.resolve(here, '..')
const require = createRequire(path.join(workbench, 'deepseek-harness', 'package.json'))
const { JSDOM, VirtualConsole } = require('jsdom')

const pagePath = path.join(workbench, 'dsh-home', 'console', 'index.html')
const html = readFileSync(pagePath, 'utf8')

const usage = (uncachedInputTokens, cacheReadTokens, cacheWriteTokens, outputTokens) => ({
  uncachedInputTokens, cacheReadTokens, cacheWriteTokens, outputTokens,
})

function session(fields) {
  const base = {
    sessionId: '', parentSessionId: null, updatedAt: 1757500000000, running: false,
    projections: {
      asOfSeq: 10,
      values: {
        title: '任务', modelSelection: { lastUsed: { reasoningEffort: 'medium' } },
        tokenUsage: usage(0, 0, 0, 0), sessionStats: { steps: 0, llmMs: 0 },
        turnOutline: [{ prompt: '实现二分查找并自测' }], subagent: { label: '' },
      },
    },
  }
  return Object.assign(base, fields, {
    projections: Object.assign(base.projections, fields.projections, {
      values: Object.assign(base.projections.values, fields.projections && fields.projections.values),
    }),
  })
}

const ROOT = 'session-root'
const CODER = 'session-coder'
const REVIEWER = 'session-reviewer'

const items = [
  session({
    sessionId: ROOT, updatedAt: 1757500300000,
    projections: { values: { title: '二分查找任务', tokenUsage: usage(2000, 4000, 500, 1500), sessionStats: { steps: 2, llmMs: 4000 } } },
  }),
  session({
    sessionId: CODER, parentSessionId: ROOT, updatedAt: 1757500200000,
    projections: { values: { title: 'Coder', modelSelection: { lastUsed: { reasoningEffort: 'low' } }, tokenUsage: usage(1500, 500, 0, 1000), sessionStats: { steps: 3, llmMs: 5000 } } },
  }),
  session({
    sessionId: REVIEWER, parentSessionId: ROOT, updatedAt: 1757500100000,
    projections: { values: { title: 'Reviewer', modelSelection: { lastUsed: { reasoningEffort: 'high' } }, tokenUsage: usage(800, 200, 0, 500), sessionStats: { steps: 1, llmMs: 2000 } } },
  }),
]

const message = (turn, step, inputTokens, cacheReadTokens, cacheWriteTokens, outputTokens) => ({
  type: 'assistant/message',
  data: {
    turn, step,
    usage: { inputTokens, cacheReadTokens, cacheWriteTokens, outputTokens, totalTokens: inputTokens + cacheReadTokens + cacheWriteTokens + outputTokens },
    message: { content: [{ type: 'text', text: '第 ' + turn + ' 轮回复' }] },
  },
})
const records = [
  { type: 'event', event: message(1, 0, 1000, 2000, 100, 500) },
  { type: 'event', event: message(2, 0, 1000, 2000, 400, 1000) },
]

const problems = []
const failures = []
const check = (ok, label, detail) => {
  if (ok) console.log('PASS  ' + label)
  else { failures.push(label + (detail ? ' — ' + detail : '')); console.log('FAIL  ' + label + (detail ? ' — ' + detail : '')) }
}

const virtualConsole = new VirtualConsole()
virtualConsole.on('jsdomError', (e) => problems.push('jsdomError: ' + (e && e.message ? e.message : e)))
virtualConsole.on('error', (...args) => problems.push('console.error: ' + args.join(' ')))

const json = (value) => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(value), text: () => Promise.resolve(JSON.stringify(value)) })

class FakeWebSocket {
  constructor() {
    this.readyState = 1
    setTimeout(() => { if (this.onopen) this.onopen() }, 0)
  }
  send(raw) {
    const msg = JSON.parse(raw)
    if (msg.type === 'open' && msg.endpoint === 'session/follow') {
      const frame = { streamId: msg.streamId, type: 'snapshot', value: { type: 'snapshot', records } }
      setTimeout(() => { if (this.onmessage) this.onmessage({ data: JSON.stringify(frame) }) }, 0)
    }
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
      if (u.startsWith('/api/session/page')) return json({ result: { ok: true, value: { records } } })
      if (u.startsWith('/api/')) return json({ result: { ok: true, value: {} } })
      if (u.startsWith('/console-api/artifacts')) return json({ files: [] })
      if (u.startsWith('/console-api/artifact')) return json('')
      if (u.startsWith('/?token=')) return json({})
      return json({})
    }
  },
})

const { window } = dom
const { document } = window
const $ = (id) => document.getElementById(id)
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

try {
  await sleep(80)

  const pill = $('cTokens')
  check(pill && pill.style.display !== 'none', '对话 token pill 可见')
  check(pill && pill.textContent.trim() === '12.5k tokens', 'pill 显示会话总量（root+coder+reviewer = 12500）', pill && pill.textContent.trim())
  check(pill && /12,500/.test(pill.title), 'pill tooltip 含精确总量', pill && pill.title)

  const usageTab = document.querySelector('#inspTabs .segbtn[data-tab="usage"]')
  usageTab.click()
  const pane = $('usagePane')
  const paneText = pane.textContent
  check($('pane-usage').style.display === 'block', '用量栏切换可见')
  check(paneText.includes('12.5k'), '用量栏显示总量 12.5k')
  check(paneText.includes('缓存命中率 49%'), '用量栏显示缓存命中率', paneText.replace(/\s+/g, ' ').slice(0, 200))
  check(paneText.includes('平均 2.1k tokens/步'), '用量栏显示平均每步 tokens（12500 / 6 步）', paneText.replace(/\s+/g, ' ').slice(0, 240))
  check(paneText.includes('子角色 2 个'), '用量栏显示子角色数')
  check(pane.querySelectorAll('.rolebar').length === 3, '角色分布：Lead / Coder / Reviewer 三条')
  const roleNames = [...pane.querySelectorAll('.rolebar .rn')].map((n) => n.textContent)
  check(roleNames.join(',') === 'Lead,Coder,Reviewer', '角色名称正确', roleNames.join(','))
  check(pane.querySelectorAll('.turnrow').length === 2, '逐轮图两轮')
  const turnLabels = [...pane.querySelectorAll('.turnrow .tm span:first-child')].map((n) => n.textContent)
  check(turnLabels.join(',') === '第 1 轮,第 2 轮', '逐轮标签正确', turnLabels.join(','))
  check(pane.querySelector('.turnrow .bar').style.width !== '', '逐轮柱宽按比例设置')
  check(pane.querySelectorAll('.turnrow .tseg').length > 0, '逐轮柱含分段（未缓存/缓存读/缓存写/输出）')

  $('mStats').click()
  const body = $('statsBody')
  const bodyText = body.textContent
  check($('statsModal').classList.contains('open'), '统计弹窗打开')
  check(bodyText.includes('未缓存输入') && bodyText.includes('缓存读取') && bodyText.includes('缓存写入') && bodyText.includes('输出'), '总览卡片含四类拆分')
  check(bodyText.includes('12.5k'), '总览含总量 12.5k')
  check(bodyText.includes('二分查找任务'), '总览含任务行')
  const heads = [...body.querySelectorAll('th')].map((n) => n.textContent)
  check(heads.join(',') === '任务,档位,未缓存输入,缓存读,缓存写,输出,总token', '总览表头正确', heads.join(','))

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
  console.log('\nToken 用量 MVP 渲染验证全部通过')
}
