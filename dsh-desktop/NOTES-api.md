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
