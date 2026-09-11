# NOTES-api.md —— M0 勘察记录（原生工作台 v1）

> 纯勘察，不改任何代码。所有结论都在本机实测，附可复现命令。
> 实测时间：2026-09-11 · Mac macOS 26.6 · Swift 6.3.3（target macOS 13）· 容器 `dsh` healthy。

## 0. 结论速览

| 问题 | 结论 |
|---|---|
| docker.sock 路径 | `~/.orbstack/run/docker.sock`（真实 socket）；`/var/run/docker.sock` 是指向它的符号链接 |
| 容器内服务端调 `/api/*` 是否要 token | **要**。无凭据 401；必须先 `GET /?token=<t>` 拿 `Set-Cookie`，再带 cookie 请求 |
| 鉴权握手形态 | `GET /?token=<t>` → `303 Location: /` + `Set-Cookie: dsh-auth-<32位>…`（`HttpOnly; SameSite=Strict; Max-Age=2592000`） |
| `session/list` 返回 | 35 条（15 root / 20 child）；见第 4 节脱敏样例 |
| 投影缓存 | `$DSH_HOME/storages/session_projcache/sessions/<id>.json`，`{version:7, record:{identity, rows}}`；当前 14 个文件 ≠ 35 会话 → 必须容忍缺失 |
| 容器内有无 zstd | **无 `zstd` 命令行**（也无 curl/tar/unzip）；Node v22.23.2 自带 zstd（`process.versions.zstd=1.5.7`）。时间线只用投影缓存，不依赖 zstd |
| OrbStack 未运行时 | socket 文件不存在；`docker` CLI 报 `dial unix …: no such file or directory` |
| SF Symbols | `cube.container` **不存在**（现有 App 正在用它，等于静默空图）→ 用 `shippingbox` / `cube.box` 替代；第 7 节附逐符号核验 |
| 现有 App 基线 | `./build-app.sh` 通过；双击后正常 ready 并渲染 `/console`（截图见第 9 节说明） |

## 1. 复现命令

```bash
# 容器状态
docker ps --filter name=dsh --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# docker.sock
ls -la ~/.orbstack/run/docker.sock /var/run/docker.sock
curl -s --unix-socket ~/.orbstack/run/docker.sock http://localhost/_ping     # -> OK

# 容器内有无工具（结论：只有 node / python3）
docker exec dsh sh -lc 'command -v zstd unzstd curl wget tar unzip'

# 上游鉴权（把 <TOKEN> 换成 `docker logs dsh | grep -oE "token=[A-Za-z0-9_-]+" | tail -1 | cut -d= -f2`）
# 容器内没有 curl，用 node 探针（下面两段脚本即为实际执行体）
```

探针 A（无凭据 → 401）：

```js
// docker exec -i dsh sh -c 'cat > /tmp/probe.js' <<'EOF' … EOF ; docker exec dsh node /tmp/probe.js
const http = require('http')
const body = JSON.stringify({ type:'client-request', rpcId:'p1', method:'session/list', payload:{ args:{ _request:{} } } })
const r = http.request({ host:'127.0.0.1', port:3080, method:'POST', path:'/api/session/list',
  headers:{'content-type':'application/json','content-length':Buffer.byteLength(body)} },
  (res) => { let d=''; res.on('data',c=>d+=c); res.on('end',()=>console.log(res.statusCode, d.slice(0,80))) })
r.end(body)
```

探针 B（先握手，再带 cookie → 200）：

```js
// 1) GET /?token=<TOKEN>（redirect 不跟随）→ 取 set-cookie 的第一段
// 2) 用同一 cookie 重发上面的 session/list 请求 → 200 + JSON
```

## 2. 鉴权结论（M2 relay 的依据）

- 无凭据：`401 unauthorized`，无 `Set-Cookie`。
- `GET /?token=<t>`：`303`，`Location: /`，`Set-Cookie: dsh-auth-<32字符>=v1.<base64>`，属性 `Max-Age=2592000; Path=/; HttpOnly; SameSite=Strict`。
- 带该 cookie 调 `POST /api/session/list`：`200`，返回 `{"type":"server-response","rpcId":…,"result":{"ok":true,"value":{…}}}`。
- **relay 设计含义**：relay 与 dsh web 在同一容器内，握手完全可行。v1 接口接收 Swift 传来的 `token` 查询参数（或 body 字段），relay 进程内缓存握手 cookie（30 天有效，进程内缓存即可），后续复用；token 不落盘、不进日志。
- 说明：`dsh-auth-<32字符>` 的名称后缀不是固定值，relay 必须**解析 `Set-Cookie` 的第一段**而不是硬编码 cookie 名。

## 3. RPC 信封（实测确认）

请求：

```json
{"type":"client-request","rpcId":"probe-1","method":"session/list","payload":{"args":{"_request":{}}}}
```

响应：

```json
{"type":"server-response","rpcId":"probe-1","result":{"ok":true,"value":{"items":[ … ]}}}
```

失败时 `result.ok=false` + `result.error.message`（M2 的 502 文案直接取它）。

## 4. session/list 实测样例（已脱敏）

顶层 `result.value.items`：本次 35 条 = 15 root + 20 child。root id 形如 `session-<uuid>`，child 为裸 `<uuid>`。

root（截断，id 已替换为 `<id>`）：

```json
{
  "sessionId": "<id>", "updatedAt": 1789058237943, "running": false, "blank": false, "cwd": "/app",
  "projections": { "asOfSeq": 39, "values": {
    "title": "写一个简单的强化学习算法代",
    "turnOutline": [{ "turn": 1, "seq": 4, "prompt": "…", "response": "…" }],
    "tokenUsage": { "uncachedInputTokens": 102223, "outputTokens": 2462, "cacheReadTokens": 24576, "cacheWriteTokens": 0 },
    "sessionStats": { "turns": 1, "steps": 5, "llmMs": 44166, "toolMs": 62547 },
    "agentPreset": "team-lead",
    "modelSelection": { "lastUsed": { "provider": "tokendance", "model": "deepseek-v4-pro-0813", "reasoningEffort": "high" } },
    "sessionListMetadata": { "blank": false, "lastPromptAt": 1789058237943 },
    "plan": { "active": false, "pending": false }, "todos": null, "subagent": null
  } }
}
```

child（额外字段）：

```json
{
  "sessionId": "<id>", "parentSessionId": "<root-id>", "origin": "subagent", "running": false,
  "projections": { "values": {
    "title": "请实现一个…", "agentPreset": "team-lead",
    "subagentTiming": { "settledMs": 62406 },
    "subagent": { "mode": "one-shot", "label": "实现简单强化学习脚本", "seq": 6 },
    "modelSelection": { "lastUsed": { "reasoningEffort": "low" } }
  } }
}
```

要点：

- **运行判定**用 item 顶层 `running`（实测稳定）；投影里的 `sessionStats` 本次未见 `openStep/pendingCalls`，不要依赖它们。
- child 的角色判定沿用控制台规则：`reasoningEffort=low→coder`、`high→reviewer`、其余 `sub`。
- `subagent.label`（不是每个 child 都有）适合做「委派标题」，`subagentTiming.settledMs` 是委派耗时。
- `todos` / `plan` 可能为 `null`，缺字段一律走安全默认值。

## 5. 投影缓存 + workspace.json（时间线数据源）

路径：`dsh-home/storages/session_projcache/sessions/<id>.json`（容器内 `/root/.dsh/…`，host 可直接读，无需解压）。

结构（实测 `version: 7`）：

```json
{ "version": 7,
  "record": { "identity": { "createdAt": … },
              "rows": { "<key>": { "seq": 38, "val": … } } } }
```

已观察到的 row key：`title`、`titleInput`、`goal`、`turnOutline`、`tokenUsage`、`contextPressure`、`contextBreakdown`、`agentPreset`、`turnBoundary`、`subagentTiming`（`{descriptorSeen, settledMs}`）、`subagent`（`{identity:{mode,label,seq}}`）、`sandboxMode`、`sessionStats`、`plan`、`todos`、`modelSelection`、`sessionListMetadata`。

- **缓存可能不全**：本次 35 个会话只有 14 个缓存文件（含已归档/被清理的）。`/v1/timeline` 对缺失缓存返回空事件数组，不报错。
- `turnOutline.val.turns[]` 每项 `{turn, seq, prompt, response}` → 故事线的 `turn` 与 `delegate done` 素材。
- `dsh-home/storages/workspace.json`：`global.archivedSessionIds`（本次 18 条）用于过滤归档；`tables.workspaces.<id>.sessionIds` 是每工作区的会话清单。
- 时间线排序：`rows.*.seq` 与 `identity.createdAt`/`updatedAt` 混排；同一 seq 用 kind 优先级（turn < plan < delegate < verdict）稳定排序。

## 6. 容器 & 端口链（复核）

- `dsh`：`deepseek-harness:local`，`127.0.0.1:3081 → 8080`（edge relay）→ 容器内 `127.0.0.1:3080`（dsh web）。`cpus=2.0`、`mem_limit=2g`、`restart:"no"`。
- 旁路容器（`flowcredit-agent` 等）与本项目无关；v1 的 Docker 客户端**只按名字操作 `dsh`**，不做任何按镜像/全量筛选的动作。
- 容器内：`DSH_HOME=/root/.dsh`，挂载 `/workspace`、`/world-store`。无 `zstd`/`curl`/`tar`/`unzip`；有 `node v22.23.2`、`python3`。

## 7. SF Symbols（macOS 13 口径逐个核验）

方法：本机 `/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist` → 年份对照 `year_to_release`；**年份 ≤ 2022（macOS 13.0）才算可用**。

事故点：现有 `Main.swift` 用的 **`cube.container` 不存在**（任何版本都没有），运行时会渲染成空白/占位。v1 一律改用下表已验证符号。

已核验可用（年份 ≤ 2022）：

- 容器/任务：`shippingbox`(2020)、`cube.box`(2019)、`stop.circle`/`stop.circle.fill`(2019)、`plus`(2019)、`plus.circle.fill`(2019)、`play.fill`(2019)、`power`(2019)、`arrow.triangle.2.circlepath`(2020)、`arrow.clockwise`(2019)
- 状态/结论：`checkmark.seal.fill`(2019)、`xmark.octagon.fill`(2019)、`checkmark.circle.fill`(2019)、`xmark.circle.fill`(2019)、`exclamationmark.triangle`/`.fill`(2019)、`exclamationmark.circle.fill`(2019)、`questionmark.circle`(2019)、`pause.circle.fill`(2019)、`clock`/`clock.fill`(2019)、`bolt.fill`(2019)、`waveform.path.ecg`(2019)、`dot.radiowaves.left.and.right`(2019)
- 界面：`sidebar.left`/`sidebar.right`(2019)、`safari`(2019)、`gearshape`/`gearshape.fill`(2020)、`info.circle`(2019)、`ellipsis.circle`(2019)、`chevron.right`/`chevron.down`/`chevron.left`(2019)、`circle.fill`(2019)、`circle.inset.filled`(2021)
- 资源/产物：`cpu`(2020)、`memorychip`(2020)、`chart.bar`/`chart.bar.fill`(2019)、`doc.text`(2019)、`folder`/`folder.fill`(2019)、`tray.full`(2019)、`externaldrive`/`.fill`(2020)、`magnifyingglass`(2019)、`trash`(2019)、`hammer`(2019)、`terminal`(2020)、`desktopcomputer`(2019)、`network`(2020)、`lock.shield`(2019)、`checklist`(2021)、`list.bullet`(2019)、`list.bullet.rectangle`(2020)、`person.2`/`.fill`(2019)、`text.bubble`/`.fill`(2019)、`bell`(2019)、`bell.badge`(2020)、`square.stack.3d.up`/`.fill`(2019)、`rectangle.stack`/`.fill`(2019)、`clock.arrow.circlepath`(2020)、`arrow.uturn.backward`(2020)、`arrow.down.circle`(2019)、`arrow.up.right.square`(2019)、`arrow.left.arrow.right`(2020)、`slider.horizontal.3`(2019)

不可用（已排除）：`cube.container`（不存在）、`sliders.horizontal`（不存在，用 `slider.horizontal.3`）。

## 8. OrbStack 未运行时的表现（安全模拟，未真的停 OrbStack）

```bash
ls -la ~/.orbstack/run/docker.sock            # OrbStack 运行时才有；未运行时该路径不存在
DOCKER_HOST=unix:///tmp/nope.sock docker ps   # 复现 CLI 失败形态
# -> failed to connect to the docker API at unix:///tmp/nope.sock;
#    check if the path is correct and if the daemon is running: dial unix /tmp/nope.sock: connect: no such file or directory
```

- Engine 客户端判定顺序：先看 socket 文件是否存在 → 连上后发 `GET /_ping`（8s 超时）；失败再走 `docker info` CLI 兜底。
- 未启动时 `open -a OrbStack` 后轮询 `/_ping`（M1 里最长 60s）再进入 compose 阶段。
- compose 仍走 CLI `docker compose up -d`（Engine API 无 compose 等价物），输出进启动日志缓冲，供失败面板展开。

## 9. 现有 App 基线（改动前跑通）

- `cd dsh-desktop && ./build-app.sh` 通过（`swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx13.0 Sources/*.swift`，ad-hoc 签名）。
- `./dsh-up.sh` → 容器 healthy（`127.0.0.1:3081->8080`），token 从 `docker logs dsh` 读取（43 字符）。
- `open build/DSH工作台.app` → ready 后全屏 WKWebView 正常渲染 `/console`：左侧最近任务列表、中间对话、右侧「流程/产物/用量」均在（截图已在本机核对；M5 的验收报告会补文件化截图）。
- 现有五阶段启动链（`StackController`）：检查 OrbStack → `compose up -d` → 等 healthy → grep token → `curl /console` 200。M1 保留「幂等、分阶段、每步超时」骨架，只换实现通道。

## 10. 对后续里程碑的直接影响

1. **M1 DockerEngine**：`/logs` 在非 TTY 容器上返回 8 字节帧头复用的多路流，解析时必须按帧剥离（或退回 CLI 读日志）。`/stats?stream=false` 的 CPU% 需两次采样（1s 间隔）。
2. **M2 relay**：v1 接口自己完成登录握手并缓存 cookie；所有 session id 过 `SESSION_ID_RE`；上游 5s 超时，超时/失败返回 502 `{ok:false,error}`。
3. **M2 桥接**：控制台已有 `token` 查询参数与 `select()`，桥接只需新增 `session` 参数自动选中 + `window.dshHostAPI` + `webkit.messageHandlers.dshHost` 事件（调用前判空）。
4. **M3 时间线**：数据源 = 投影缓存 + 归档集合；缓存缺失返回空数组；角色/结论规则严格复用控制台（low→coder / high→reviewer；`\bPASS\b`/`\bFAIL\b`）。

---

## 11. M2 实测记录（relay v1 + 控制台桥接）

> 实测时间：2026-09-11 · 容器 `dsh` healthy · 全部命令走 Mac 侧 `127.0.0.1:3081`。
> 取 token：`TOKEN=$(docker logs dsh 2>&1 | grep -oE 'token=[A-Za-z0-9_-]+' | tail -1 | cut -d= -f2)`（43 字符）。

### 11.1 五个 v1 接口

| # | 用例 | 结果 |
|---|---|---|
| (1) | `GET /console-api/v1/health`（上游正常） | `200 {"ok":true,"upstream":"up","serverTime":…}`，10ms 级 |
| (1b) | 本机第二实例模拟上游停用（`DSH_INTERNAL_PORT=3999 DSH_EDGE_PORT=3099`） | `health` → `200 {"ok":true,"upstream":"down"}`，0.010s 不挂起；同实例 `sessions` → `502 {"ok":false,"error":"connect ECONNREFUSED 127.0.0.1:3999"}`，0.003s |
| (2) | `GET /console-api/v1/sessions?token=…` | `200`，`roots=10`；根 `id/title/role/running/updatedAt/turns/verdict/tokens{input,output,cacheRead}/children[]`，子 `id/role/label/running/updatedAt/settledMs/verdict` |
| (3) | `GET /console-api/v1/timeline?token=…&session=session-de24a617-…&limit=200` | `200`，5 事件，按 seq 有序：`4 turn lead 下发任务`、`6 delegate coder start 委派 Coder：编写简单强化学习算法代码`、`6 delegate reviewer start 委派 Reviewer：校验强化学习代码正确性`、`7 delegate coder done Coder 完成 · 83s`、`7 delegate reviewer done Reviewer 完成 · 104s` |
| (3b) | `session=nope` | `400 {"ok":false,"error":"invalid session id"}` |
| (3c) | 合法但无投影缓存的 id | `200 {"ok":true,"events":[]}`，不报错 |
| (4a) | `POST /console-api/v1/cancel` `{"sessionId":"../../etc/passwd"}` | `400 invalid session id` |
| (4b) | `POST /console-api/v1/cancel` `{}` | `400 invalid session id` |
| (4c) | 对空闲会话 cancel（真实 id） | `502 {"ok":false,"error":"session \"session-…\" not found (not attached)"}` —— 上游语义：只有运行中的会话可取消；Swift 侧按“该任务已不在运行”提示 |
| (5a) | `POST /console-api/v1/session` `{"agentPreset":"../evil"}` | `400 invalid agent preset` |
| (5b) | `POST /console-api/v1/session` `{"agentPreset":"team-lead"}` | `200 {"ok":true,"sessionId":"session-784d0871-cc0e-4726-b23a-8ca24b217650"}` |

### 11.2 实测中修掉的真 bug

1. **`turnOutline` 真实形态**：v7 投影是对象 `{turns:[{turn,seq,prompt,response}]}`，不是数组 → 原实现 `Array.isArray()` 判假，时间线只剩 delegate 事件。已加 `turnList()` 统一解包（数组 / `{turns}` 都吃）。
2. **主会话 `subagent:{}`**：空对象是 truthy → 原实现给主会话凭空发了一条 `委派 Lead：`（seq=0）。已加 `subagentIdentity()`：无 `label` 且无 `seq` 一律返回 `null`。
3. **错误码语义**：新增 `sendUpstreamError()`：上游 401 → `401 {ok:false,error:"unauthorized"}`（便于 Swift 重新握手），其余 → `502 {ok:false,error}`。

### 11.3 鉴权与既有接口回归

```bash
# 无 token 也能拿到数据：不是漏洞，是 relay 进程内已缓存握手 cookie（§0 结论不变：上游无凭据 401）
curl -s "http://127.0.0.1:3081/console-api/v1/sessions" | head -c 80
```

| 既有能力 | 验证 | 结果 |
|---|---|---|
| `GET /console-api/artifacts` | `?session=session-de24a617…` | `200 {"ok":true,"files":[{"rel":"交付报告.md",…},{"rel":"q_learning.py",…}]}` |
| `GET /console-api/artifact`（中文名） | `path=交付报告.md`（URL 编码） | `200`；`content-disposition: attachment; filename="artifact.md"; filename*=UTF-8''%E4%BA%A4%E4%BB%98%E6%8A%A5%E5%91%8A.md`（双 filename 保持） |
| `POST /console-api/purge` | `{"sessionId":"session-784d0871…"}` | `200 {"ok":true,"removed":[…],"bytesFreed":4053}`；非法 id → `400` |
| WS mux 隧道 | 先 `GET /?token=` 取 `Set-Cookie`，再带 cookie 打 Upgrade 到 `/api/remote.mux` | `101 Switching Protocols` + `Sec-WebSocket-Accept` + 上游帧；不带 cookie → `401`（预期，浏览器自带上游 cookie） |
| SSE/chunked 透传 | 未改该路径代码；Upgrade/代理分支保持原样 | 由 M3 真机使用覆盖 |

### 11.4 控制台桥接（§4.2）

- 新增 `?session=` 自动选中、`window.dshHostAPI{select,create,cancelSelected}`、`selectionChanged/runningChanged/taskFinished` 单向事件（`webkit.messageHandlers.dshHost` 判空后调用，浏览器里静默跳过）。
- 内联脚本改动只在既有函数尾部追加调用，业务逻辑零改写；`render-team.mjs --check` 与 `tests/{roster,console-usage,console-history}` 全部通过。
- 浏览器直开 `?session=` 的自动选中改为在 M3 原生壳里验收（本机 CUA 当前无可用浏览器实例，届时用 App 内 WKWebView 截图核对）。

***

## 12. M3 实测记录（三栏工作台）

> 实测时间：2026-09-11 12:44–13:15 · 产物 `dsh-desktop/build/DSH工作台.app`（ad-hoc，`swiftc` 零 warning）
> 验证通道：CUA 无障碍树（本机 CLI 无「屏幕录制」权限，`screencapture` 直接失败 → 本轮无截图，见 12.6）

### 12.1 验收逐条

| # | 验收项 | 结果 | 证据（实测） |
|---|---|---|---|
| ① | 跑一个 L3 任务，Lead→Coder→Reviewer 完整故事线，pass/fail 颜色正确 | ✅（用真实历史会话验收） | 选中 `session-de24a617…`（真实 L3：Q-learning 交付 + 独立复核）：团队卡 `Lead，已通过` / `Coder，编写简单强化学习算法代码，完成` / `Reviewer，校验强化学习代码正确性，完成`；故事线 5 事件：`下发任务 · 第 1 轮`、`委派 Coder：…`、`委派 Reviewer：…`、`Coder 完成 · 83s`、`Reviewer 完成 · 104s`；产物卡 `2 个文件` + `在 Finder 打开`。颜色语义：pass=绿 `checkmark.seal.fill`、fail=橙 `xmark.octagon.fill`，且每处同时带无障碍文案（状态不只靠颜色） |
| ② | 运行中「停止任务」可中止且容器不重启 | ⚠️ 未完成（外部阻塞） | 上游模型额度耗尽（12.4），无法造出「运行中」会话。可验证部分：空闲时按钮 `isAnyRunning=false` 置灰；`POST /v1/cancel` 对空闲会话 → `502`，界面提示「该任务已不在运行」 |
| ③ | 切会话中间页不整页白屏重载 | ✅ | 侧边栏点行 → 中栏内容切换，AX 中 WebView `URL: …/console?token=…`（**无** `?session=`）保持不变；仅当页面未注册 `dshHostAPI` 时才降级为 `?session=` 重载 |
| ④ | 窗口最小化 5 分钟：CPU 近零、无轮询请求、恢复后立即刷新 | ✅ | 最小化后 40s：relay 访问日志 **0** 条（可见时 3–4 条/10s）、进程 CPU `0.09s/40s ≈ 0.2%`（`ps %CPU 0.0`）；从 Window 菜单恢复后 **5s 内 2 次** sessions 轮询，随后回到 3 次/10s |
| ⑤ | 深色模式无硬编码颜色 | ✅（源码级审计） | `grep -rn "Color(red:\|\.white\|\.black\|NSColor(calibrated\|NSColor(red\|#[0-9a-f]{6}"` → **0 命中**；全部为语义色/动态色：`.secondary`(14) `.tertiary`(7) `Color(nsColor: .separatorColor/.windowBackgroundColor/.tertiaryLabelColor/.secondaryLabelColor/.quaternaryLabelColor)` + `.regularMaterial` 材质；状态色仅 `.green`/`.orange` 且均带文案 |
| ⑥ | 断网 / relay 502 显示离线态而不崩 | ✅ | `docker stop dsh` → 中栏 banner「与中继的连接中断，正在自动重试…」、Inspector 离线卡「离线 … 中继没有响应（NSURLError -1004）」、容器卡回落 `CPU 0% / 内存 0M/0M`；App 不崩、侧边栏保留最后列表；点「重启容器」→ 重读 token → 自动恢复（relay 轮询恢复，WebView URL 换成新 token） |

### 12.2 本轮修掉的真 bug

1. **心跳被 Docker 指标查询拖慢**：`beat()` 里 `await pollMetrics()` 串联等待（Docker Unix socket 单次 1s+），导致 tick 从 1s 变 ~2s，sessions 实测 6–8s 一次（规格要求 3s）。改为 `startMetricsPoll()` 非阻塞 + 在途去重，实测回到 **3–4 次/10s**。
2. **测试脆弱性**：`tests/console-history.test.mjs` 原先假定列表第一条会话带用量；真实数据里新增的 0-token 会话（本条就是额度失败留下的）会让断言失败。改为显式挑选「有真实用量」的会话再断言，意图不变。

### 12.3 关键证据命令

```bash
# ④ 轮询暂停/恢复（relay 只记路径，token 永不落日志）
docker logs dsh --since 40s 2>&1 | grep -c '^\[relay\]'      # 最小化后 = 0
# ④ CPU
ps -p $(pgrep -f 'dsh-desktop/build' | head -1) -o time=,pcpu=
# ① / ③ 界面结构
#   CUA: app.getAXState() → 团队/故事线/容器/产物 + WebView URL 是否带 ?session=
```

### 12.4 外部阻塞：上游额度耗尽（导致 ② 无法验收）

诊断会话 `session-459195e0…` 的事件流显示：prompt 被正常受理（`agent/inbox/spliced` → `turn/start` → `step/start` → `request/header`），随后模型调用返回：

```
402 {"message":"用户额度不足。请先充值，到账后重试本次请求。…","code":"insufficient_quota"}
→ turn/end reason: error code QUOTA
```

- 结论：**「HTTP 下发 prompt 不运行」的旧结论是误判**——链路完全正常，失败在账户余额（Tokendance）。此前浏览器里能跑通只是额度尚未耗尽的时间差。
- 影响：M3 ②（运行中停止）与 M4 大部分验收项都要求真实运行中的任务，需充值后补测。
- 另：`dsh-home/.credentials.yaml` 里的 `DEEPSEEK_API_KEY` 调 `api.deepseek.com/user/balance` 返回 `Authentication Fails … invalid`（不可用作替代路由）。

### 12.5 CPU 归因实验（探针构建）

长时运行的旧实例曾出现 ~18% 持续 CPU（最小化/隐藏时仍在烧）。用 scratch 探针构建（同源码，仅把 `consolePane` 的 `WebView` 换成纯色）对照：

| 场景 | 进程 CPU |
|---|---|
| 探针构建（无 WebView）可见空闲 | ≈ 0.0%（20s 内 0.00s） |
| 正式构建，新实例可见空闲 | 0.25%（20s 内 0.05s） |
| 正式构建，最小化 | 0.2%（40s 内 0.09s） |
| **旧长时实例（多轮任务后）** | **~18%（最小化/隐藏时仍持续）** |

`sample` 抓到的热点是主线程 **每帧 Core Animation 事务**（`UC::DriverCore::continueProcessing` → `NSDisplayHostingView.layout` → `SwiftUI ViewGraph renderDisplayList`），即「有一个持续动画在驱动 60/120Hz 渲染」。探针无 WebView 时该现象消失 → 归因指向 **WKWebView 内的页面（控制台）存在未停止的动画**（`.spinner`/`.caret` 这类 `animation: … infinite`，在断流/异常中止后可能保持）。本轮未再复现（需「多轮任务 + 异常中止」组合）。

### 12.6 偏差与遗留（转 M4/M5）

1. **截图验收改为无障碍树 + 源码审计**：本机 CLI 无屏幕录制权限（`screencapture` 报 `could not create image from display`），⑤ 的「深色模式截图」改为源码级审计（0 硬编码颜色）+ 结构核对；M5 若获得授权再补截图。
2. **多窗口**：SwiftUI `WindowGroup` 在 `open -a` / 状态恢复时会开出第二个窗口（Window 菜单实测出现两条同名项）。规格 3.3 要求「唯一模型」。→ M4 改单窗口（`Window` 场景或禁用状态恢复）。
3. **token 轮换恢复**：容器若被 App 之外的方式重启（`docker restart/start`），App 仍持 Keychain 里的旧 token → 停在离线态（文案「登录握手失败（没有 Set-Cookie），token 可能已轮换」）。走 App 的「重启容器」可自愈。→ M4 加「401/握手失败 → 自动重读 token 重试」。
4. **WebView 动画泄漏**（12.5）：→ M4/M5 观察；若复现，考虑窗口不可见时把 WKWebView 从层级摘除（保留实例与页面状态）以彻底停掉渲染。

## 13. M4 实测记录（系统能力）

> 实测时间：2026-09-11 13:15–14:05 · 产物 `dsh-desktop/build/DSH工作台.app`（ad-hoc，`swiftc` 零 warning）
> 验证通道：CUA 无障碍树 + **CGWindowList 在屏窗口枚举** + System Events 按键 + shell 探针（见 13.3）

### 13.1 验收逐条

| # | 验收项 | 结果 | 证据（实测） |
|---|---|---|---|
| ① | 运行中关窗 → 任务继续（relay 仍在轮询）、菜单栏可恢复窗口 | ⚠️ 部分（额度阻塞「任务在跑」） | 关窗：File▸Close 与 ⌘W 都走 `windowShouldClose` → `orderOut`，`CGWindowListCopyWindowInfo(.optionOnScreenOnly)` 由 1 扇变 **0 扇**（1280×820 消失）；App 进程存活、无崩溃。轮询：隐藏期间 `docker logs dsh --since 20s \| grep -c '^\[relay\]'` = **7**（可见时 3–4 次/10s），CPU `0.0%`。恢复：菜单栏状态项（`menu bar 2`）菜单项为「显示主窗口 / 只回复两个字：收到 · 空闲 / 停止任务 / 重启容器 / 停止容器并退出」，点「显示主窗口」→ CGWindowList 回到 1 扇。**「任务继续」这半条需运行中任务，见 13.4** |
| ② | 运行中 ⌘Q 三按钮分别验证（等待分支要真的等到结束并通知 + 退出；立即分支停容器退出；取消分支不变） | ⚠️ 未完成（额度阻塞） | 代码路径已就位：`applicationShouldTerminate` → 三按钮 NSAlert；等待分支 `isWaitingToQuit=true` + `.terminateLater`，AppStore 汇报 `onRunningStateChanged(false)` 时 `NSApp.reply(toApplicationShouldTerminate: true)` + 发通知；取消分支 `isWaitingToQuit` 不变。**需要「运行中」会话才能点三按钮**（13.4） |
| ③ | 空闲 ⌘Q 直接退出且容器被停、占用归零 | ✅ | ⌘Q 后 **1 秒内**：`pgrep -f dsh-desktop/build` 空、`docker ps` 无 dsh、`docker ps -a` 显示 `dsh Exited (143)`；即 `applicationWillTerminate → StackController.stopOnQuit()`（Policy A）生效 |
| ④ | 前台可见时不弹通知，切后台后完成才弹 | ⚠️ 未完成（额度阻塞） | 实现口径：`Notifier.post` 首行 `guard Notifier.preferenceEnabled, !Notifier.isUserWatching`；`isUserWatching` = App 活跃 **且** 存在「可见且未最小化」窗口 → 前台不打扰；授权在首个任务 `false→true` 时请求一次。设置里可整体关掉（`notifications.enabled`，默认开）。**需要「任务结束」事件才能实测**（13.4） |
| ⑤ | 删掉 config 且 glob 不到工程目录 → 首启向导；选非法目录报错、选合法目录后正常进入 | ✅（渲染 + 校验口径） | 造场景：`.app` 拷到 `/tmp/dsh-firstrun/`（bundle 祖先不含工程）+ 临时把 `orbstack/compose.yaml` 移出（让 BFS 也命中不了）→ 启动即整屏向导：标题「先找到你的 dsh-workbench 工程」+ 3 条说明 + 「选择 dsh-workbench 文件夹」按钮 + 底部实时原因「未在常见目录找到 dsh-workbench」。校验口径把 `ProjectLocator.swift` 单独编译实测：工程根 **PASS**；`/tmp`、`$HOME`、`dsh-desktop/` 子目录全部 **reject** → 对应 `ProjectChooser.choose()` 里 `Copy.firstRunInvalid` 内联报错分支。**NSOpenPanel 的「选目录」交互未能自动化**（13.6-2） |
| ⑥ | ⌘, 打开设置，改项目位置流程闭环 | ✅（打开 + 内容；「重新选择」受同一面板限制） | 系统菜单 App▸`Settings…`（标准 ⌘,）→ 设置窗（AXIdentifier `com_apple_SwiftUI_Settings_window`）四组：项目位置（工程目录绝对路径 + 在 Finder 中显示 + 重新选择）/ 通知（开关默认开 + 「窗口在前台可见时不打扰」）/ 容器资源（只读：上限 4 核 · 4.00G + 实时 6% · 505M）/ 诊断（版本 1.0.0 (1) + 打开 dsh-home + 导出最近日志）。`render-team.mjs --check` 无漂移、三个测试全过 |

### 13.2 本轮修掉的真 bug

1. **菜单栏图标不可见**：`menuBarIcon` 用了 `cube.container`，该符号在本机**不存在**（`NSImage(systemSymbolName:)` 返回 nil → 渲染空白，AX 里只剩符号名）。逐符号核验源码里全部 9 个 `systemName:` 后，只此一个 MISSING → 空闲态改为 `shippingbox`（`Main.swift` + `FirstRunView` 图标）。核验脚本见 13.3。
2. **热启动读不到 token（会挡住「退出 App 再打开」的正常路径）**：`readToken()` 只回看 `docker logs --tail 400`，而容器**只在启动时打印一次** token，之后被中继访问日志顶出窗口（实测：token 在第 274 行、总 739 行 → `--tail 400` 看不到）→ App 停在「读不到登录凭据」（新加的 M4 错误分支如实报错，但用户只能手动重启容器）。改为**分档回看 400 → 2000 → 8000 行**，仍找不到再用 Keychain 里的旧 token 做一次真实请求验证（有效即复用）；实测容器重启后冷启动、以及容器已跑 20 分钟后重启 App 两条路径都能进 ready。
3. **（方法学，不是产品 bug，但会误判）CUA `getScreenshot()` 对 `orderOut` 之后的窗口仍返回画面**：第一轮因此误判「⌘W/File▸Close 无效」；`AX` 里窗口也依旧存在（ordered-out 窗口不摘 AX 树）。**「窗口是否真的在屏」只认 `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`**；键盘路径用 System Events 发送后一律用 CGWindowList 复核。

### 13.3 关键证据命令

```bash
# 在屏窗口枚举（小工具 /tmp/wins，源码见 13.5）——判断「窗口真的藏了/回来了」的唯一判据
swiftc -O /tmp/wins.swift -o /tmp/wins && /tmp/wins DSH

# 隐藏期间轮询是否继续（任务是否还在被跟踪）
docker logs dsh --since 20s 2>&1 | grep -c '^\[relay\]'

# 菜单栏状态项（图标随状态：空闲=shippingbox / 跑任务=stop.circle.fill / 失败=警告）
osascript -e 'tell application "System Events" to tell process "DSHTeam" to get name of every menu bar item of menu bar 2'
osascript -e 'tell application "System Events" to tell process "DSHTeam" to click menu bar item 1 of menu bar 2' \
          -e 'tell application "System Events" to tell process "DSHTeam" to get name of every menu item of menu 1 of menu bar item 1 of menu bar 2'

# 键盘路径（必须先 set frontmost，否则按键会送给别的 App）
osascript -e 'tell application "System Events" to tell process "DSHTeam" to set frontmost to true' \
          -e 'delay 0.4' -e 'tell application "System Events" to keystroke "w" using command down'

# 空闲 ⌘Q → 容器被停（Policy A）
docker ps -a --filter name=dsh --format '{{.Names}} {{.Status}}'   # 期望：dsh Exited (143)

# SF Symbols 逐个核验（源码里所有 systemName:）
rg -o --no-filename 'systemName: "[^"]+"' dsh-desktop/Sources | sed 's/systemName: //' | tr -d '"' | sort -u > /tmp/symbols.txt
#   + NSImage(systemSymbolName:accessibilityDescription:) 判空（脚本见 13.5）

# 首启向导：隔离工程目录后启动
cp -R dsh-desktop/build/DSH工作台.app /tmp/dsh-firstrun/
mv orbstack/compose.yaml /tmp/compose.yaml.hold          # 让 bundle 祖先与 BFS 都命中不了
open -n -a /tmp/dsh-firstrun/DSH工作台.app
mv /tmp/compose.yaml.hold orbstack/compose.yaml          # 立刻还原
```

### 13.4 外部阻塞：上游额度仍然为 0（沿 M3 12.4）

- 复现（容器内脚本 `/tmp/dsh-probe.js`）：握手 → `session/create` → `session/prompt` 全部成功（`{"accepted":true}`），但投影立刻是
  `sessionStats: {turns:1, steps:1, llmMs:0}`、`tokenUsage.totals` 全 0、`turnOutline.turns[0].response: ""`。
- 即：**链路（App → relay → 容器内 web → 上游）是通的，失败发生在模型侧**（M3 时实测是 `402 用户额度不足 … insufficient_quota`）。
- 影响：M4 的 ②（运行中 ⌘Q 三按钮）与 ④（任务结束通知）**无法验收**；①的「任务继续」半条同样受影响。
- 处置：与 M3 ② 同因，如实记入遗留；额度恢复后按下表补验即可（不需要改代码）。
  | 补验项 | 一步操作 | 期望 |
  |---|---|---|
  | ①后半 | 跑一个 ≥2 分钟任务 → 关窗 | relay 轮询不断、任务完成时窗口仍隐藏 |
  | ② | 运行中 ⌘Q → 三个按钮各点一次 | 等待：跑完 → 通知 → 退出；立即：停容器退出；取消：什么都没变 |
  | ④ | 跑任务时把 App 切到后台 | 完成后弹通知；前台可见时不弹 |

### 13.5 本轮用到的临时工具（放 /tmp，不入仓库）

```swift
// /tmp/wins.swift —— 在屏窗口枚举（判断窗口是否真的藏了）
import CoreGraphics
import Foundation
let filter = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "DSH"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var found = 0
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let name = w[kCGWindowName as String] as? String ?? ""
    guard owner.contains(filter) || name.contains(filter) else { continue }
    found += 1
    print("owner=\(owner) name=\(name) layer=\(w[kCGWindowLayer as String] ?? "?") bounds=\(w[kCGWindowBounds as String] ?? [:])")
}
print("on-screen windows matching '\(filter)': \(found)")
```

```js
// /tmp/dsh-probe.js（容器内跑）—— 握手 + 建会话 + 发 prompt，用来探额度
// 用法：docker exec dsh node /tmp/dsh-probe.js "<token>" "只回复两个字：收到"
const http = require('http'); const token = process.argv[2]; let cookie = null;
function login() { /* GET /?token=… → 取 Set-Cookie 第一段 */ }
function rpc(method, argName, args) { /* POST /api/<method>，信封 {type,rpcId,method,payload:{args:{[argName]:args}}} */ }
(async () => { await login();
  const c = await rpc('session/create','request',{agentPreset:'team-lead'});
  const s = await rpc('session/prompt','request',{requestId:'probe-'+Date.now(),sessionId:c.sessionId,mode:'queue',content:[{type:'text',text:process.argv[3]}]});
  console.log(c.sessionId, JSON.stringify(s)); })();
```

```bash
# SF Symbols 判空（与上面的 rg 配合）
cat > /tmp/symcheck.swift <<'EOF'
import AppKit
let names = (try? String(contentsOfFile: "/tmp/symbols.txt", encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
for n in names { print((NSImage(systemSymbolName: n, accessibilityDescription: nil) == nil ? "MISSING " : "ok      ") + n) }
EOF
swiftc -O /tmp/symcheck.swift -o /tmp/symcheck && /tmp/symcheck
```

### 13.6 偏差与遗留（转 M5）

1. **②④ 与 ①后半未验收**：唯一原因是上游额度（13.4），代码已就位；补验步骤已列成表。
2. **NSOpenPanel 交互未能自动化**：首启向导「选非法目录报错 / 选合法目录进入」与设置里「重新选择」都依赖同一个文件选择面板。CUA 只对第一个 App 实例稳定，第二个实例的模态面板拿不到焦点；AppleScript 能打开面板（`⌘⇧G` 出 sheet）、也能写 sheet 的文本框，但「确认选择」那一步没走通 → M5 若需要，改用「临时把面板默认目录指到 /tmp」或加一个仅供测试的 `DSH_WORKBENCH_ROOT` 覆盖路径来做闭环。
3. **多窗口残留**：`defaults read local.dsh.team` 里仍有旧的 `…AppWindow-1/-2` 分栏记忆（历史 WindowGroup 时代留下），当前启动只开一扇（`Window` 场景 + `isRestorable=false`），M5 可顺手清理这条键。
4. **WebView 动画泄漏**（12.5）本轮未复现：隐藏窗口后 CPU 实测 `0.0%`（`orderOut` 之后 WKWebView 不再驱动渲染），与 12.5 的「最小化仍 18%」不同，判断是那次样本的页面状态问题 → M5 的 1 小时内存/CPU 观察继续盯。
5. **首次真正退出时容器被停**（③）会让「下次打开要等 compose up + healthy ≈ 30–60s」成为常态。当前按规格（Policy A）实现；如果体验上不接受，M5 可考虑「settings 里给一个『退出时停止容器』开关」，但规格 3.5 明确「设置里不出现生命周期策略类开关」→ 保持现状，仅记录。

***

## 14. M5 实测记录（打磨与发布）

> 实测时间：2026-09-11 13:33 起 · 产物 `build/DSH工作台.app`（ad-hoc，版本 **1.1.0 (2)**）
> 本轮改动面：只在 `dsh-desktop/**`（`git status -- dsh-home deepseek-harness` 为空）

### 14.1 本轮改了什么

| 文件 | 改动 |
| --- | --- |
| `Info.plist` | 版本 1.1.0 / build 2；`CFBundleDevelopmentRegion=zh-Hans` + `CFBundleLocalizations=[zh-Hans,en]` |
| `build-app.sh` | release 走版本化产物 `build/DSH工作台-<版本>.app` + 同名 zip；Hardened Runtime 最小 entitlements；`notarytool submit --wait` → `stapler staple` → `codesign --verify --deep --strict` → `spctl --assess`；缺 `DEVELOPER_ID` 硬失败；两种模式都生成 `Contents/Resources/zh-Hans.lproj` |
| `Docker/DockerEngine.swift` | 新增 `composeImageReference`（`docker compose config --images`）与 `imageExists`（Engine API `/images/{ref}/json`，CLI 兜底） |
| `Stack/StackController.swift` | compose 预算按「镜像是否存在」自适应：缺镜像 = 首次构建 → 1800s + 文案「首次构建镜像（需要几分钟）…」；「重启容器」在容器已不存在时回落完整流水线，而不是 `docker restart` 撞 404 |
| `Copy.swift` | 新增 `phaseBuildingImage` |
| `Views/RootSplitView.swift` | 三个纯图标工具栏按钮补 `accessibilityLabel`（VoiceOver 之前读的是 SF Symbol 自带描述） |
| `Views/Components.swift` | `HintRow` 装饰图标 `accessibilityHidden(true)` |
| `State/AppStore.swift` + `Main.swift` | 窗口可见性改由「主窗」判定并注入：`AppDelegate.mainWindowVisible` → `store.setVisibilityProvider{}`（修掉 14.3 里发现的轮询回归） |
| 新增 | `README.md`（架构 / 目录职责 / 调试发布 / 降级通道）、`ACCEPTANCE-v1.md`（对照规格 §6 逐条验收） |

### 14.2 连续运行 1 小时（M5 验收③）

采样：`/tmp/dsh-m5-sample.sh`（60s × 70）→ 日志 `dsh-desktop/build/acceptance/m5-1h-sample.log`（副本 `/tmp/dsh-acceptance/`），
窗口 13:35:29 → 14:37:39，取满 **63 个样本（>1 小时）**，全程容器 healthy、App 未重启：

| 指标 | 首 | 末 | 峰 | 谷 | 结论 |
| --- | --- | --- | --- | --- | --- |
| App RSS | 139,904 KB | 80,896 KB | 140,512 KB | 53,920 KB | **−42%**：先回落后在 54–88 MB 间波动，无单调增长 |
| WebKit 内容进程 RSS | 60,224 KB | 46,464 KB | 93,040 KB | 21,504 KB | 同样只波动不增长（WebKit 自己回收） |
| App CPU（ps pcpu） | — | — | 15.4% | — | 均值 **2.56%**（含启动尖峰；空闲稳态见 14.3） |
| relay 轮询/分 | 14 | 23 | 33 | 14 | 均值 **23.1，从未掉到 0**（容器与 App 全程在线） |

### 14.3 冷启动（M5 验收②）+ 重启后复验

**造条件**：`docker rm -f dsh` + `docker image tag deepseek-harness:local deepseek-harness:pre-m5 && docker rmi deepseek-harness:local`
（只剩备份 tag，compose 眼里「镜像不存在」）+ `~/Library/Application Support/DSHTeam/config.json` 不存在 → 双击启动。
观测脚本每 2s 记录容器状态/健康/镜像/界面文案（`/tmp/dsh-coldstart.log`）。

| 时刻 | 现象 |
| --- | --- |
| 14:39:02 | App 启动；`state=none image=`（容器与镜像都不存在） |
| 14:39:18 | `state=running` + 新镜像 `461943eeb736`（compose 自动 rebuild 完成，缓存全热 ≈16s） |
| 14:39:21 | `health=healthy` → 读 token → ready |

**修掉的真 bug**：compose 预算原本硬编码 90s。实测「镜像缺失 → 首次构建」在缓存需要重新解包时要 **2m51s**
（`time docker compose build`：`#16 unpacking … 16.1s`、总 2:50.96），旧预算必然把冷启动判成 `composeFailed`。
现在按「镜像是否存在」自适应：缺镜像 → 1800s + 文案「首次构建镜像（需要几分钟）…」；`重启容器` 在容器已不存在时回落完整流水线。

**复验（重启后同一台机）**：

| 项 | 结果 |
| --- | --- |
| 系统菜单 | `文件 / 编辑 / 显示 / 窗口 / 帮助`（修复前 `File / Edit / View / Window / Help`） |
| 工具栏无障碍名 | `重启容器` / `重新载入页面` / `在浏览器打开`（修复前分别是 `正在同步` / `刷新` / `Safari浏览器`）；边栏开关 = `显示边栏` |
| 装饰图标 | 不再出现在无障碍树（`HintRow` 已隐藏） |
| 中栏控制台 | 加载出完整 HTML 内容树（团队工作台 + 会话列表 + 输入区）；`/console?token=…` → 200 |
| token | Keychain 与容器当前 token 43 字符且逐字节一致 |
| 截图 | `build/acceptance/m5-after-relaunch-ready.png`（三栏就绪态）、`m5-workbench-visible.png`（改造前） |

**顺带发现并修掉的回归（M4 引入）**：⌘W 关窗后 App 仍按「可见」频率轮询（实测 12 条/30s），
因为 `AppStore.windowIsVisible()` 是扫描 `NSApp.windows`，而 M4 加的 `MenuBarExtra` 自带一个常驻的
`NSStatusBarWindow` → 永远判定「有可见窗口」。改为由 `AppDelegate.mainWindowVisible`（只认被接管的主窗）注入后：
隐藏 = **0 条/30s**、App 进程 0.2–0.4% CPU；Dock/菜单栏叫回来后 8s 内 4 次轮询（立即刷新）。

**遗留**：WebKit 内容进程在「可见 / 隐藏 / 最小化」三种状态下都稳定吃 ~9% CPU（App 进程同期 0.2–3%）。
三态都一样 → 与窗口状态无关，归因于控制台页面自己的动画/定时器（`.spinner` / `.caret` / `node.run` + 2s 轮询）。
控制台不在本次可改范围（§0.5 只允许桥接改动）→ 见 14.6-5。

### 14.4 走查与修复（VoiceOver / 本地化）

- 无障碍树审计（`getAXState`）发现：工具栏「重启容器」被读成 **正在同步**、「在浏览器打开」被读成 **Safari浏览器**——都是 SF Symbol 的系统描述，`.help()` 不参与无障碍。已补 label；`HintRow` 的空态图标（“更多”“移动”）同理，改为对 VoiceOver 隐藏。
- 系统文案未本地化：菜单栏是 `File / Edit / View / Window / Help`、边栏开关是 `Hide Sidebar`。原因是 bundle 没有任何本地化声明 → AppKit 按开发区域回落英文。加 `CFBundleDevelopmentRegion` + `zh-Hans.lproj` 后复验（见 14.3）。

### 14.5 红线复核（规格 §7）

逐条结果见 `ACCEPTANCE-v1.md` §6。本轮额外取证：`docker port dsh` = `8080/tcp -> 127.0.0.1:3081`（唯一映射）；中文产物活体 `content-disposition: attachment; filename="artifact.md"; filename*=UTF-8''%E4%BA%A4%E4%BB%98%E6%8A%A5%E5%91%8A.md`；`defaults read local.dsh.team` 中 token 命中 0；Keychain 里的 token 与容器当前 token 逐字节一致。

### 14.6 遗留与偏差（转后续）

1. **上游额度为 0**：M3 ②、M4 ①②④ 仍无法验收（同 §12.4 / §13.4），补验表见 `ACCEPTANCE-v1.md` §3.1。
2. **本机无 Developer ID 证书 / 公证 profile**：release 只能验到 `codesign` 报 `no identity found`；脚本保证不会产出「看似成功」的半成品。
3. **本机 CLI 无屏幕录制权限**：视觉证据改为无障碍树 + `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` + App 内截图（落 `build/acceptance/`，`build/` 不入库）。
4. **`NSOpenPanel` 交互无法自动化**：首启向导 / 设置的目录选择只验到渲染与校验口径。
5. **控制台页面的常驻动画（本机最值得修的一条）**：`dsh-home/console/index.html` 的 `.spinner` / `.caret` / `.node.run`（61/76/144 行）让 WebKit WebContent 进程**在任何窗口状态下都吃 ~9% CPU**（可见 9.2% / 隐藏 8.7% / 最小化 9.3%），App 进程同期只有 0.2–3%。这解释了 §12.5 里那个「~18% CPU」的旧实例（当时只量了 App 进程，没量 WebKit 子进程）。控制台不在本次可改范围（§0.5 只允许桥接改动）→ 后续两条路：① 控制台侧把动画限定在真正流式输出时；② App 侧在窗口不可见时把 WKWebView 摘出层级（M3 §12.6-4 的设想）。
6. **侧边栏 12.5pt 固定字号**：全仓唯一正文级固定值（其余正文都是语义字号）；改语义字号需重核行高与截断，暂不动。
7. **多窗口时代残留的 `defaults` 分栏键**已清理（`NSSplitView Subview Frames …AppWindow-1/-2`），单窗口模型不再写这类键。

## 15. 模型路由切换（TokenDance → DeepSeek 官方）与委派路径修复

### 15.1 换 key 实测：新 key 只对官方端点有效

| 探测 | 结果 |
|---|---|
| 新 key `sk-5c54…` → `tokendance.space/gateway/v1` | `401 API 密钥不存在`（新 key 不是 TokenDance 的） |
| 旧 key `sk-6a96…` → 同一网关 | `402 insufficient_quota`（§12.4 / §13.4 的欠费根因） |
| 旧 key → `api.deepseek.com` | `401 invalid`（同 §13.4，不能当替代路由） |
| 新 key → `api.deepseek.com` | `200`；`/v1/models` = `deepseek-flash` + `deepseek-v4-pro`；余额 `{"is_available":true,"total_balance":"4.48"}` CNY |
| `reasoning_effort` low/medium/high/max、`thinking:{enabled\|disabled}` | 全部 200；响应带 `reasoning_content`，`tool_calls` 正常 |

→ 路由整体切到官方：`settings.yaml` 的 `tokendance` provider → `deepseek`（`apiKeyEnv: DEEPSEEK_API_KEY`、`baseURL: https://api.deepseek.com/v1`）。
`dsh-home/.credentials.yaml` 里 `DEEPSEEK_API_KEY` 换成新 key，顺手删掉已无人引用的 `TOKENDANCE_API_KEY`（该文件 git-ignored，不入库）。

### 15.2 默认模型选 V4.1 Flash，不选 V4 Pro

官方定价页实测（2026-09-11，单位 $/1M tokens，off-peak / peak）：

| 模型 | 输入·命中缓存 | 输入·未命中 | 输出 |
|---|---|---|---|
| `deepseek-flash`（V4.1 Flash） | 0.003 / 0.006 | 0.15 / 0.3 | 0.6 / 1.2 |
| `deepseek-v4-pro` | 0.022 / 0.044 | 0.66 / 1.32 | 1.98 / 3.96 |

官方在同一页注明：V4.1 Flash「在质量、成本、速度与总耗时上全面超过 V4 Pro」，且 **2026-09-14 12:00（北京）起 `deepseek-v4-pro` 的请求全部转由 V4.1 Flash 承接、按 Flash 计价**。

→ roster 默认 `deepseek-flash`；`deepseek-v4-pro` 保留在 `models` 列表里可手选（同一 1M 窗口）。
→ Lead 档位仍走 §16 之前的 token 治理：`leadEffort: medium`（可改 low），coder `low`、reviewer `high` 不变。
→ 成本量级：一次 24k 输入 + 0.7k 输出的 L2 委派 ≈ $0.004；`¥4.48` 余额够跑数百次这种任务，缓存命中率越高越省。

### 15.3 首次真机委派抓到的真 bug：deny 名单混了两个命名空间

第一次真机委派（session `a0d037dd`）在第 10 步抛出：

```
Error: tools.restrict() names unknown global tools "subagent", "subagent_claude_code";
known global tools: ask_user_question, bash, create_goal, delegate_coder, delegate_reviewer, edit,
exit_plan_mode, get_goal, glob, grep, interrupt_agent, job_kill, job_list, job_output, list_agents,
mcp__filesystem__*, mcp__world_store__*, ralph, read, read_image, send_message, skill,
subagent_codex, subagent_fork, todo_write, update_goal, web_fetch, web_search, workflow, write
```

- **根因**：`toolDeny` 里的 `subagent` / `subagent_claude_code` 是**另一套 profile 的命名**（默认内置子代理名），本部署（Web profile + filesystem/world_store MCP）没有 → `tools.restrict()` 直接抛错 → 委派在「子会话还没建」就失败。表象像卡住：Lead 失败两次后转去调 `ask_user_question` 等人回答，投影停在 `pendingCalls`。
- **修 1**：`roster/team-lead.yml` 两个 `toolDeny` 收敛为运行时真实存在的名字（`web_search, web_fetch, subagent_fork, subagent_codex, delegate_coder, delegate_reviewer`；reviewer 再加 `write, edit`）。
- **修 2**：`scripts/render-team.mjs` 增加 `KNOWN_TOOLS` 白名单——deny 里出现未知名字时渲染直接失败并点名（`mcp__` 前缀不校验，随 profile 装载变化）。
- **修 3**：`tests/roster.test.mjs` 增加两条断言：干净树名单正确、注入 `subagent_claude_code` 后 `--check` 退出码 1 且点名。
- **残留**：`subagent` 是**预设级**工具（由 preset 注册），不在全局注册表里 → `tools.restrict()` 既不能校验也不能 deny 它，子会话因此仍看得到 `subagent`；但 `maxDepth: 1` 已封死再下钻，风险受控。

### 15.4 真机复验（session `5a3db70a`，2026-09-11）

- Lead：3 步完成，结论「L2：delegate_coder 一次委派 + Lead 核验，未触发 reviewer——非 L3 且无可逆性风险」；用量 未命中 6065 + 命中缓存 47104 + 输出 690。
- 子会话 `e5703f68`（coder）：`request/header.config = {provider: deepseek, model: deepseek-flash, reasoningEffort: low, maxTokens: 32768}`；工具表 41 个，deny 名单逐条核对**全部缺席**（只剩预设级 `subagent`）。
- 产物：`/workspace/rq-check.txt` = `quota-ok\n`（9 字节，`cat -A` + `wc -c` 双证）；子会话一条 `bash` 建成并自验，约 3 秒。
- 复现命令（容器内）：`docker exec dsh node /tmp/dsh-probe.js "<token>" "用 delegate_coder 在 /workspace 下创建 rq-check.txt，内容写 quota-ok，然后报告文件路径。"`

### 15.5 剩余风险

1. **余额只有 ¥4.48**：够验证、不够长期跑。按 §15.2 单价，建议用起来之前先充值，或把 `leadEffort` 调 `low`（改一个字段 + `render-team.mjs --write`）。
2. **旧会话的模型选择指向已下线的 `tokendance/deepseek-v4-pro-0813`**：那些会话重开后需在模型选择里重新选一次（新会话默认已是 `deepseek/deepseek-flash`）。
3. **relay 重启后的 502 窗口**：容器重启会换 token，App 在拿到新 token 前会刷出几行 `/console-api/v1/sessions 502`，拿到新 token 后自愈（本轮实测：重启后约 1 分钟内恢复 200）。若要彻底消除，App 侧应在 5xx 时也触发一次 token 重读（现只在 401 路径上做）。
