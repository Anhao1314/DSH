// Edge relay for OrbStack/Docker.
//
// The dsh web server refuses to bind 0.0.0.0 and only listens on the container
// loopback. We need an edge that (a) publishes it on 0.0.0.0 so the host can
// reach it through the published port, and (b) serves our lightweight team
// workbench at /console while proxying every other route — including SSE and
// WebSocket upgrades — untouched to the loopback server.
const http = require('node:http')
const net = require('node:net')
const fs = require('node:fs')
const path = require('node:path')

const TARGET_HOST = '127.0.0.1'
const TARGET_PORT = Number(process.env.DSH_INTERNAL_PORT || 3080)
const EDGE_PORT = Number(process.env.DSH_EDGE_PORT || 8080)
const CONSOLE_DIR = process.env.DSH_CONSOLE_DIR || '/root/.dsh/console'
const DSH_HOME = process.env.DSH_HOME || '/root/.dsh'

// Session ids are either `session-<uuid>` (root) or bare `<uuid>` (a role
// child). Locking to this shape makes the purge endpoint traversal-proof.
const SESSION_ID_RE = /^(?:session-)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

function sizeOf(target) {
  let total = 0
  let st
  try { st = fs.statSync(target) } catch { return 0 }
  if (st.isFile()) return st.size
  if (st.isDirectory()) {
    for (const entry of fs.readdirSync(target)) total += sizeOf(path.join(target, entry))
  }
  return total
}

function rmTarget(target) {
  const bytes = sizeOf(target)
  try { fs.rmSync(target, { recursive: true, force: true }) } catch { /* already gone */ }
  return bytes
}

// Permanently erase one root session (and any role children) from disk:
// durable journal dir, projection cache, and every workspace.json reference.
function purgeSessions(ids) {
  const clean = [...new Set(ids)].filter((id) => typeof id === 'string' && SESSION_ID_RE.test(id))
  let bytesFreed = 0
  const removed = []
  for (const id of clean) {
    const journalDir = path.join(DSH_HOME, 'sessions', '--app--', id)
    const cacheFile = path.join(DSH_HOME, 'storages', 'session_projcache', 'sessions', `${id}.json`)
    if (fs.existsSync(journalDir) || fs.existsSync(cacheFile)) removed.push(id)
    bytesFreed += rmTarget(journalDir)
    bytesFreed += rmTarget(cacheFile)
  }
  // Drop ordering/archive references so no stale id survives in the registry.
  const wsPath = path.join(DSH_HOME, 'storages', 'workspace.json')
  try {
    const ws = JSON.parse(fs.readFileSync(wsPath, 'utf8'))
    const drop = (arr) => Array.isArray(arr) ? arr.filter((x) => !clean.includes(x)) : arr
    if (ws.global) ws.global.archivedSessionIds = drop(ws.global.archivedSessionIds)
    if (ws.tables && ws.tables.workspaces) {
      for (const w of Object.values(ws.tables.workspaces)) w.sessionIds = drop(w.sessionIds)
    }
    fs.writeFileSync(wsPath + '.tmp', JSON.stringify(ws, null, 2))
    fs.renameSync(wsPath + '.tmp', wsPath)
  } catch { /* no workspace registry: nothing to rewrite */ }
  return { removed, bytesFreed }
}

function handlePurge(req, res) {
  let body = ''
  let oversized = false
  req.on('data', (chunk) => {
    body += chunk
    if (body.length > 65536) { oversized = true; req.destroy() }
  })
  req.on('end', () => {
    if (oversized) { res.writeHead(413); res.end(); return }
    let parsed
    try { parsed = JSON.parse(body || '{}') } catch { res.writeHead(400, { 'content-type': 'application/json' }); res.end('{"ok":false,"error":"bad json"}'); return }
    const ids = [parsed.sessionId, ...(Array.isArray(parsed.childIds) ? parsed.childIds : [])].filter(Boolean)
    if (!ids.length || !ids.every((id) => SESSION_ID_RE.test(id))) {
      res.writeHead(400, { 'content-type': 'application/json' })
      res.end('{"ok":false,"error":"invalid session id"}')
      return
    }
    const result = purgeSessions(ids)
    res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' })
    res.end(JSON.stringify({ ok: true, ...result }))
  })
}

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8' }

function serveConsole(req, res) {
  // Single-file workbench: /console and /console/ and /console/index.html all
  // return the same page. Anything else below /console is treated as missing.
  const file = path.join(CONSOLE_DIR, 'index.html')
  fs.readFile(file, (err, buf) => {
    if (err) {
      res.writeHead(503, { 'content-type': 'text/plain; charset=utf-8' })
      res.end('console not found: mount the workbench at ' + CONSOLE_DIR)
      return
    }
    res.writeHead(200, {
      'content-type': MIME['.html'],
      'cache-control': 'no-store',
    })
    res.end(buf)
  })
}

function proxyRequest(req, res) {
    const opts = {
      host: TARGET_HOST,
      port: TARGET_PORT,
      method: req.method,
      path: req.url,
      headers: req.headers,
    }
    const upstream = http.request(opts, (up) => {
      res.writeHead(up.statusCode || 502, up.headers)
      up.pipe(res) // streaming-safe (SSE / chunked pass through untouched)
    })
    upstream.on('error', (e) => {
      res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' })
      res.end('relay upstream error: ' + e.message)
    })
    req.pipe(upstream)
}

function artifactDir(sessionId) {
  if (!SESSION_ID_RE.test(sessionId)) return null
  return path.join(DSH_HOME, 'artifacts', sessionId)
}

// Recursively list deliverables written for one session: [{rel,size,mtimeMs}].
function handleArtifactList(query, res) {
  const base = artifactDir(query.get('session') || '')
  if (!base) { res.writeHead(400); res.end('{"ok":false,"error":"invalid session id"}'); return }
  const out = []
  const walk = (dir, relPrefix) => {
    let entries
    try { entries = fs.readdirSync(dir, { withFileTypes: true }) } catch { return }
    for (const e of entries) {
      const abs = path.join(dir, e.name), rel = relPrefix ? `${relPrefix}/${e.name}` : e.name
      if (e.isDirectory()) walk(abs, rel)
      else if (e.isFile()) {
        const st = fs.statSync(abs)
        out.push({ rel, size: st.size, mtimeMs: st.mtimeMs })
      }
    }
  }
  walk(base, '')
  out.sort((a, b) => b.mtimeMs - a.mtimeMs)
  res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' })
  res.end(JSON.stringify({ ok: true, files: out }))
}

const ART_MIME = {
  '.txt': 'text/plain; charset=utf-8', '.md': 'text/markdown; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.ts': 'text/plain; charset=utf-8', '.py': 'text/plain; charset=utf-8',
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.csv': 'text/csv; charset=utf-8', '.log': 'text/plain; charset=utf-8',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.svg': 'image/svg+xml', '.pdf': 'application/pdf',
}

function contentDisposition(filename, inline) {
  const ext = path.extname(filename)
  const asciiBase = path.basename(filename, ext)
    .replace(/[\r\n]+/g, ' ')
    .replace(/["\\]/g, '_')
    .replace(/[^\x20-\x7e]/g, '')
    .replace(/\s+/g, ' ')
    .replace(/^[\. ]+|[\. ]+$/g, '')
  const asciiName = (asciiBase || 'artifact') + ext
  return (inline ? 'inline' : 'attachment')
    + `; filename="${asciiName}"`
    + `; filename*=UTF-8''${encodeURIComponent(filename)}`
}

// Stream one deliverable. `rel` is confined inside the session artifact dir.
function handleArtifactGet(query, res) {
  const base = artifactDir(query.get('session') || '')
  if (!base) { res.writeHead(400); res.end('invalid session id'); return }
  const rel = query.get('path') || ''
  const abs = path.normalize(path.join(base, rel))
  if (!abs.startsWith(base + path.sep) || rel.includes('..')) { res.writeHead(400); res.end('bad path'); return }
  fs.stat(abs, (err, st) => {
    if (err || !st.isFile()) { res.writeHead(404); res.end('not found'); return }
    const ext = path.extname(abs).toLowerCase()
    const inline = query.get('inline') === '1'
    res.writeHead(200, {
      'content-type': ART_MIME[ext] || 'application/octet-stream',
      'cache-control': 'no-store',
      'content-disposition': contentDisposition(path.basename(abs), inline),
      'content-length': st.size,
    })
    fs.createReadStream(abs).pipe(res)
  })
}


// ── v1 API（原生工作台）──────────────────────────────────────────────────────
//
// 原生壳通过 relay 读会话/时间线、发起急停与新建。上游 dsh web 需要登录握手
// （M0 结论：无凭据 401，GET /?token= 拿 Set-Cookie），这里进程内缓存 cookie；
// token 由原生壳随请求传入，relay 不落盘、不打印。

const UPSTREAM_TIMEOUT_MS = 5000
const V1_BODY_LIMIT = 65536

let upstreamCookie = null

function upstreamRequest(options) {
  return new Promise((resolve, reject) => {
    const req = http.request({
      host: TARGET_HOST,
      port: TARGET_PORT,
      method: options.method || 'GET',
      path: options.path,
      headers: options.headers || {},
    }, (res) => {
      let data = ''
      res.on('data', (chunk) => { data += chunk })
      res.on('end', () => resolve({ status: res.statusCode || 0, headers: res.headers || {}, body: data }))
    })
    req.setTimeout(options.timeoutMs || UPSTREAM_TIMEOUT_MS, () => {
      req.destroy(new Error('upstream timeout'))
    })
    req.on('error', reject)
    if (options.body) req.write(options.body)
    req.end()
  })
}

async function upstreamLogin(token) {
  const res = await upstreamRequest({
    method: 'GET',
    path: '/?token=' + encodeURIComponent(token),
    timeoutMs: UPSTREAM_TIMEOUT_MS,
  })
  const cookies = res.headers['set-cookie'] || []
  const cookie = cookies.map((c) => String(c).split(';')[0]).join('; ')
  if (!cookie) throw new Error('登录握手失败（没有 Set-Cookie），token 可能已轮换')
  upstreamCookie = cookie
  return cookie
}

function unwrapRPC(response) {
  if (response.status === 401) throw Object.assign(new Error('unauthorized'), { unauthorized: true })
  if (response.status !== 200) throw new Error('上游返回 ' + response.status)
  let envelope
  try { envelope = JSON.parse(response.body) } catch { throw new Error('上游响应不是 JSON') }
  const result = envelope && envelope.result
  if (!result) throw new Error('上游响应缺少 result')
  if (!result.ok) throw new Error((result.error && result.error.message) || 'rpc failed')
  return result.value
}

async function upstreamRPC(method, argName, args, token) {
  const body = JSON.stringify({
    type: 'client-request',
    rpcId: method + '-' + Date.now() + '-' + Math.random().toString(16).slice(2),
    method,
    payload: { args: { [argName]: args } },
  })
  const headers = { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) }
  if (upstreamCookie) headers.cookie = upstreamCookie
  let response = await upstreamRequest({ method: 'POST', path: '/api/' + method, headers, body })
  if (response.status === 401) {
    if (!token) throw Object.assign(new Error('unauthorized'), { unauthorized: true })
    await upstreamLogin(token)
    headers.cookie = upstreamCookie
    response = await upstreamRequest({ method: 'POST', path: '/api/' + method, headers, body })
  }
  return unwrapRPC(response)
}

function sendJSON(res, status, payload) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' })
  res.end(JSON.stringify(payload))
}

function readJSONBody(req, limit) {
  return new Promise((resolve, reject) => {
    let body = ''
    let oversized = false
    req.on('data', (chunk) => {
      body += chunk
      if (body.length > (limit || V1_BODY_LIMIT)) { oversized = true; req.destroy() }
    })
    req.on('end', () => {
      if (oversized) { reject(Object.assign(new Error('body too large'), { status: 413 })); return }
      try { resolve(JSON.parse(body || '{}')) } catch { reject(Object.assign(new Error('bad json'), { status: 400 })) }
    })
    req.on('error', reject)
  })
}

// ── 投影缓存 / 归档集合（与现有控制台同一套规则）──────────────

function readArchivedIds() {
  try {
    const ws = JSON.parse(fs.readFileSync(path.join(DSH_HOME, 'storages', 'workspace.json'), 'utf8'))
    return new Set(Array.isArray(ws.global && ws.global.archivedSessionIds) ? ws.global.archivedSessionIds : [])
  } catch { return new Set() }
}

function readProjectionRows(sessionId) {
  if (!SESSION_ID_RE.test(sessionId)) return null
  const file = path.join(DSH_HOME, 'storages', 'session_projcache', 'sessions', sessionId + '.json')
  let parsed
  try { parsed = JSON.parse(fs.readFileSync(file, 'utf8')) } catch { return null }
  const rows = parsed && parsed.record && parsed.record.rows
  return rows && typeof rows === 'object' ? rows : null
}

/** rows{k:{seq,val}} → values{k:val}，并把 subagent 归一化成 session/list 的形态。 */
function rowsToValues(rows) {
  const values = {}
  for (const key of Object.keys(rows || {})) {
    const row = rows[key]
    values[key] = row && typeof row === 'object' && 'val' in row ? row.val : row
  }
  if (values.subagent && values.subagent.identity && !values.subagent.mode) {
    const identity = values.subagent.identity
    values.subagent = { mode: identity.mode, label: identity.label, seq: identity.seq }
  }
  return values
}

function projectionValuesFor(sessionId) {
  const rows = readProjectionRows(sessionId)
  return rows ? rowsToValues(rows) : null
}

/** turnOutline 既可能是数组（旧缓存），也可能是 {turns:[...]}（v7 投影）。 */
function turnList(values) {
  const raw = values && values.turnOutline
  if (Array.isArray(raw)) return raw
  if (raw && Array.isArray(raw.turns)) return raw.turns
  return []
}

/** subagent 可能是 {identity:{label,seq,mode}}、已归一化的 {label,seq,mode}，或空对象（主会话）。 */
function subagentIdentity(values) {
  const sub = values && values.subagent
  if (!sub || typeof sub !== 'object') return null
  const inner = sub.identity && typeof sub.identity === 'object' ? sub.identity : sub
  const label = typeof inner.label === 'string' ? inner.label : ''
  const seq = Number(inner.seq)
  if (!label && !Number.isFinite(seq)) return null
  return { label, seq: Number.isFinite(seq) ? seq : 0, mode: inner.mode || '' }
}

function itemValues(item) {
  const listValues = (item && item.projections && item.projections.values) || {}
  if (listValues.turnOutline || listValues.sessionStats) return listValues
  const cached = projectionValuesFor(item && item.sessionId)
  return cached ? Object.assign({}, cached, listValues) : listValues
}

/** 角色 / 结论 / 是否有意义：严格沿用控制台规则。 */
function classifyItem(item) {
  const values = itemValues(item)
  const effort = values.modelSelection && values.modelSelection.lastUsed && values.modelSelection.lastUsed.reasoningEffort
  const kind = effort === 'low' ? 'coder' : effort === 'high' ? 'reviewer' : 'sub'
  const outline = turnList(values)
  const text = JSON.stringify(values.turnOutline || [])
  const verdict = /\bPASS\b/i.test(text) ? 'pass' : /\bFAIL\b/i.test(text) ? 'fail' : ''
  const firstPrompt = (outline[0] && outline[0].prompt) || ''
  const asOfSeq = (item && item.projections && item.projections.asOfSeq) || 0
  const meaningful = asOfSeq > 4 && !/reply with exactly one word/i.test(firstPrompt)
  return {
    title: values.title || firstPrompt || (item && item.sessionId) || '',
    kind,
    label: (subagentIdentity(values) || {}).label || '',
    verdict,
    meaningful,
    values,
  }
}

function truncate(text, max) {
  const value = String(text == null ? '' : text)
  return value.length > max ? value.slice(0, max) + '…' : value
}

const ROLE_LABEL = { coder: 'Coder', reviewer: 'Reviewer', sub: '子任务', lead: 'Lead' }

function normalizeChild(item) {
  const info = classifyItem(item)
  const timing = info.values.subagentTiming || {}
  return {
    id: item.sessionId,
    role: info.kind,
    label: info.label || truncate(info.title, 60),
    running: !!item.running,
    updatedAt: item.updatedAt || 0,
    settledMs: Number(timing.settledMs) || 0,
    verdict: info.verdict,
  }
}

function normalizeRoot(item) {
  const info = classifyItem(item)
  const usage = info.values.tokenUsage || {}
  return {
    id: item.sessionId,
    title: truncate(info.title, 120),
    role: 'lead',
    running: !!item.running,
    updatedAt: item.updatedAt || 0,
    turns: Number(info.values.sessionStats && info.values.sessionStats.turns)
      || turnList(info.values).length,
    verdict: info.verdict,
    tokens: {
      input: Number(usage.uncachedInputTokens) || 0,
      output: Number(usage.outputTokens) || 0,
      cacheRead: Number(usage.cacheReadTokens) || 0,
    },
  }
}

async function handleV1Health(res) {
  let upstream = 'down'
  try {
    const response = await upstreamRequest({ method: 'GET', path: '/', timeoutMs: 3000 })
    if (response.status > 0) upstream = 'up'
  } catch { upstream = 'down' }
  sendJSON(res, 200, { ok: true, upstream, serverTime: Date.now() })
}

/** 上游失败：401 单独区分，便于 Swift 侧重新握手；其余 502。 */
function sendUpstreamError(res, error) {
  if (error && error.unauthorized) {
    sendJSON(res, 401, { ok: false, error: 'unauthorized' })
    return
  }
  sendJSON(res, 502, { ok: false, error: String((error && error.message) || error) })
}

async function handleV1Sessions(query, res) {
  const token = query.get('token') || ''
  try {
    const value = await upstreamRPC('session/list', '_request', {}, token)
    const items = Array.isArray(value.items) ? value.items : []
    const archived = readArchivedIds()
    const roots = []
    for (const item of items) {
      if (item.parentSessionId) continue
      if (archived.has(item.sessionId)) continue
      const info = classifyItem(item)
      if (!info.meaningful) continue
      const root = normalizeRoot(item)
      root.children = items
        .filter((child) => child.parentSessionId === item.sessionId)
        .sort((a, b) => (a.updatedAt || 0) - (b.updatedAt || 0))
        .map(normalizeChild)
      roots.push(root)
    }
    roots.sort((a, b) => b.updatedAt - a.updatedAt)
    sendJSON(res, 200, { ok: true, serverTime: Date.now(), roots })
  } catch (error) {
    sendUpstreamError(res, error)
  }
}

function timelineEventsFor(id, role, running, updatedAt) {
  const values = projectionValuesFor(id)
  if (!values) return []
  const events = []
  const roleLabel = ROLE_LABEL[role] || ROLE_LABEL.sub
  const outline = turnList(values)

  if (role === 'lead') {
    for (const turn of outline) {
      if (!turn) continue
      events.push({
        seq: Number(turn.seq) || 0,
        ts: updatedAt,
        kind: 'turn',
        role: 'lead',
        title: outline.length > 1 && turn.turn ? '下发任务 · 第 ' + turn.turn + ' 轮' : '下发任务',
        detail: truncate(turn.prompt, 600),
      })
    }
  }

  const identity = subagentIdentity(values)
  const timing = values.subagentTiming || {}
  const firstTurn = outline[0] || {}
  if (identity) {
    const startSeq = Number(identity.seq) || 0
    events.push({
      seq: startSeq,
      ts: updatedAt,
      kind: 'delegate',
      role,
      status: 'start',
      title: '委派 ' + roleLabel + '：' + truncate(identity.label || firstTurn.prompt || '', 80),
    })
    const settledMs = Number(timing.settledMs) || 0
    const done = firstTurn.response
    if (done || settledMs) {
      const seconds = settledMs > 0 ? Math.max(1, Math.round(settledMs / 1000)) : 0
      events.push({
        seq: startSeq + 1,
        ts: updatedAt,
        kind: 'delegate',
        role,
        status: 'done',
        title: roleLabel + ' 完成' + (seconds ? ' · ' + seconds + 's' : ''),
        detail: truncate(done, 600),
      })
    }
    const info = classifyItem({ sessionId: id, projections: { values, asOfSeq: 0 } })
    if (info.verdict) {
      events.push({
        seq: startSeq + 2,
        ts: updatedAt,
        kind: 'verdict',
        role,
        status: info.verdict,
        title: roleLabel + ' 判定：' + (info.verdict === 'pass' ? '通过' : '发现问题'),
      })
    }
  }

  if (values.plan && (values.plan.active || values.plan.pending)) {
    events.push({ seq: 1, ts: updatedAt, kind: 'plan', role: 'lead', title: '制定计划' })
  }
  const todos = Array.isArray(values.todos) ? values.todos : (values.todos && values.todos.items) || []
  if (todos.length) {
    events.push({ seq: 2, ts: updatedAt, kind: 'todo', role: 'lead', title: '待办 ' + todos.length + ' 项' })
  }
  if (running) {
    events.push({ seq: Number.MAX_SAFE_INTEGER - 1, ts: updatedAt, kind: 'delegate', role, status: 'start', title: roleLabel + ' 进行中…' })
  }
  return events
}

const TIMELINE_KIND_ORDER = { turn: 0, plan: 1, todo: 2, delegate: 3, verdict: 4 }

async function handleV1Timeline(query, res) {
  const token = query.get('token') || ''
  const sessionId = query.get('session') || ''
  const limit = Math.min(500, Math.max(1, Number(query.get('limit')) || 200))
  if (!SESSION_ID_RE.test(sessionId)) {
    sendJSON(res, 400, { ok: false, error: 'invalid session id' })
    return
  }
  try {
    const value = await upstreamRPC('session/list', '_request', {}, token)
    const items = Array.isArray(value.items) ? value.items : []
    const rootItem = items.find((item) => item.sessionId === sessionId)
    const children = items.filter((item) => item.parentSessionId === sessionId)
    let events = []
    if (rootItem) {
      events = events.concat(timelineEventsFor(sessionId, 'lead', !!rootItem.running, rootItem.updatedAt || 0))
    }
    for (const child of children) {
      const info = classifyItem(child)
      events = events.concat(timelineEventsFor(child.sessionId, info.kind, !!child.running, child.updatedAt || 0))
    }
    events.sort((a, b) => {
      if (a.seq !== b.seq) return a.seq - b.seq
      const order = (TIMELINE_KIND_ORDER[a.kind] || 9) - (TIMELINE_KIND_ORDER[b.kind] || 9)
      if (order !== 0) return order
      return (a.ts || 0) - (b.ts || 0)
    })
    sendJSON(res, 200, { ok: true, events: events.slice(0, limit) })
  } catch (error) {
    sendUpstreamError(res, error)
  }
}

async function handleV1Cancel(req, res) {
  let body
  try { body = await readJSONBody(req) } catch (error) {
    sendJSON(res, error.status || 400, { ok: false, error: String(error.message || error) })
    return
  }
  const sessionId = String(body.sessionId || '')
  if (!SESSION_ID_RE.test(sessionId)) {
    sendJSON(res, 400, { ok: false, error: 'invalid session id' })
    return
  }
  try {
    await upstreamRPC('session/cancel', 'request', { sessionId }, String(body.token || ''))
    sendJSON(res, 200, { ok: true })
  } catch (error) {
    sendUpstreamError(res, error)
  }
}

async function handleV1Create(req, res) {
  let body
  try { body = await readJSONBody(req) } catch (error) {
    sendJSON(res, error.status || 400, { ok: false, error: String(error.message || error) })
    return
  }
  const preset = String(body.agentPreset || 'team-lead')
  if (!/^[a-z0-9][a-z0-9-]{0,40}$/.test(preset)) {
    sendJSON(res, 400, { ok: false, error: 'invalid agent preset' })
    return
  }
  try {
    const value = await upstreamRPC('session/create', 'request', { agentPreset: preset }, String(body.token || ''))
    sendJSON(res, 200, { ok: true, sessionId: value && value.sessionId })
  } catch (error) {
    sendUpstreamError(res, error)
  }
}

const server = http.createServer((req, res) => {
  const pathname = (req.url || '/').split('?')[0]
  // 访问日志只记「方法 + 路径 + 状态 + 耗时」：绝不记 query（token 就在 query 里）。
  // 用途：M3 验收「窗口最小化后没有轮询请求」时需要可核对的证据。
  if (pathname.startsWith('/console-api/')) {
    const startedAt = Date.now()
    res.on('finish', () => {
      console.log(`[relay] ${req.method} ${pathname} ${res.statusCode} ${Date.now() - startedAt}ms`)
    })
  }
  if (pathname === '/console-api/v1/health' && req.method === 'GET') {
    handleV1Health(res)
    return
  }
  if (pathname === '/console-api/v1/sessions' && req.method === 'GET') {
    handleV1Sessions(new URL(req.url, 'http://x').searchParams, res)
    return
  }
  if (pathname === '/console-api/v1/timeline' && req.method === 'GET') {
    handleV1Timeline(new URL(req.url, 'http://x').searchParams, res)
    return
  }
  if (pathname === '/console-api/v1/cancel' && req.method === 'POST') {
    handleV1Cancel(req, res)
    return
  }
  if (pathname === '/console-api/v1/session' && req.method === 'POST') {
    handleV1Create(req, res)
    return
  }
  if (pathname === '/console' || pathname === '/console/' || pathname === '/console/index.html') {
    serveConsole(req, res)
    return
  }
  if (pathname === '/console-api/purge' && req.method === 'POST') {
    handlePurge(req, res)
    return
  }
  if (pathname === '/console-api/artifacts' && req.method === 'GET') {
    handleArtifactList(new URL(req.url, 'http://x').searchParams, res)
    return
  }
  if (pathname === '/console-api/artifact' && req.method === 'GET') {
    handleArtifactGet(new URL(req.url, 'http://x').searchParams, res)
    return
  }
  proxyRequest(req, res)
})

// Preserve WebSocket (and any Upgrade) by tunnelling the raw bytes after we
// replay the original request line and headers to the loopback target.
server.on('upgrade', (req, clientSocket, head) => {
  const upstream = net.connect({ host: TARGET_HOST, port: TARGET_PORT }, () => {
    const lines = [`${req.method} ${req.url} HTTP/${req.httpVersion}`]
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      lines.push(`${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}`)
    }
    upstream.write(lines.join('\r\n') + '\r\n\r\n')
    if (head && head.length) upstream.write(head)
    upstream.pipe(clientSocket)
    clientSocket.pipe(upstream)
  })
  const close = () => { clientSocket.destroy(); upstream.destroy() }
  clientSocket.on('error', close)
  upstream.on('error', close)
})

server.listen(EDGE_PORT, '0.0.0.0', () => {
  console.log(`[relay] 0.0.0.0:${EDGE_PORT} -> ${TARGET_HOST}:${TARGET_PORT} (L7; /console served from ${CONSOLE_DIR})`)
})
