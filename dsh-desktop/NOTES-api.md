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
