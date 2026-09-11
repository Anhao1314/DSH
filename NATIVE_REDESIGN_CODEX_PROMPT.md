# Codex 执行任务：DSH 团队工作台原生重设计 v1（Jobs-cut 基线）

> **使用方式**
>
> ：在 
>
> `dsh-workbench`
>
>  仓库根目录（即本文件所在目录，含 
>
> `orbstack/`
>
> 、
>
> `dsh-desktop/`
>
> 、
>
> `deepseek-harness/`
>
> 、
>
> `dsh-home/`
>
> ）打开 Codex，把本文件全文作为任务输入。没有特殊说明不要改动本文件范围之外的东西。



***

## 0. 工作铁律（先读，违反即返工）



1. **先勘察、后改动**：M0 必须先完成并产出 `dsh-desktop/NOTES-api.md`，再动代码。动手前先按现状把 App 和容器跑通一次（`./dsh-up.sh`、`cd dsh-desktop && ./build-app.sh`）。

2. **按里程碑顺序交付**：M1→M5，每个里程碑结束必须满足该里程碑的全部验收项、`swiftc` 零 warning、可编译可运行，再进入下一个；每个 M 一个 git commit，信息用 `feat(desktop): mN ...` 格式。

3. **零第三方依赖**：Swift 侧只用 Apple 平台框架（SwiftUI/AppKit/WebKit/Network/Security/UserNotifications/Foundation）；Node relay 只用内置模块。禁止 SPM、CocoaPods、npm install。

4. **不新增容器、不改上游**：不 fork / 不改 `deepseek-harness/packages/**` 任何上游包；容器仍是唯一一个 `dsh`，2 CPU / 2GiB / `restart:"no"` 不变；`dsh-home/roster/**`、预设生成物、`scripts/render-team.mjs` 一律不碰。

5. **允许改的自有文件**：`dsh-desktop/**`（原生壳）、`deepseek-harness/orbstack-relay.cjs`（自建 edge relay）、`dsh-home/console/index.html`（自建单文件控制台，仅允许第 4.2 节规定的最小桥接改动）、`dsh-desktop/build-app.sh`、文档。

6. 所有子进程 / 网络调用必须有超时；所有从外部进入的路径与 id 必须按现有 `SESSION_ID_RE` / `ArtifactSchemeHandler` 的标准做格式与目录穿越校验；错误信息与日志中**永远不得出现 token 明文**。

7. UI 文案用简体中文，集中管理在 `Sources/Copy.swift`；类型 / 函数 / 文件英文命名。规格与现状冲突时，优先不破坏现有行为，在最终交付说明里列出偏差，不要静默改设计。

8. 部署目标保持 macOS 13（`-target arm64-apple-macosx13.0`），保持纯 `swiftc` 命令行编译、不引入 Xcode 工程。



***

## 1. 现状基线（已勘察事实，直接采信，不必重新猜）

### 1.1 进程与端口链



* Mac 上 OrbStack 跑唯一容器 `dsh`；端口链：Mac `127.0.0.1:3081` → 容器 edge relay `8080`（`orbstack-relay.cjs`）→ 容器内 dsh web `127.0.0.1:3080`。

* relay 对 `/console*` 自服务，其余路由（含 SSE、WebSocket Upgrade）原样代理到 3080；**代理与 Upgrade 隧道逻辑不得破坏**。

* 容器内 `DSH_PERMISSION_MODE=danger-full-access`（容器即隔离边界），挂载见 `orbstack/compose.yaml`，不改。

* 现有自建 relay 路由：`GET /console`、`POST /console-api/purge`、`GET /console-api/artifacts`、`GET /console-api/artifact`（后两者的中文 `Content-Disposition` 处理是已修过的坑，保持）。

### 1.2 上游 dsh web 的 RPC 形态（relay 新 API 要复用它，不要自己解析压缩日志）



* HTTP RPC：`POST /api/<method>`，请求信封：



```
{"type":"client-request","rpcId":"\<uuid>","method":"\<method>","payload":{"args":{"\<argName>":<参数>}}}
```

响应信封：`{"result":{"ok":true,"value":...}}` 或 `{"result":{"ok":false,"error":{"message":"..."}}}`。



* 已确认存在的方法（从 `dsh-home/console/index.html` 逆向得到，以 M0 实测为准）：


  * `session/list`（argName `_request`，参数 `{}`）：返回会话数组，元素含 `sessionId`、`parentSessionId`、`running`、`updatedAt`、`projections.values`、`projections.asOfSeq`。

  * `session/create`（argName `request`，`{agentPreset:"team-lead"}`）→ `{sessionId}`。

  * `session/cancel`（argName `request`，`{sessionId}`）：中止指定会话当前轮次，**不停止容器**，这就是 "急停"。

  * `session/page`（argName `request`，`{address:{kind:"session",sessionId},throughSeq,maxMessages}`）：历史消息。

  * `workspace/archiveSession`（argName `request`，`{sessionId}`）。

* 流式：WS `/api/remote.mux`，消息 `{type:"open"|"cancel",streamId,endpoint:"session/follow",payload:{args:{request:{address:{kind:"session",sessionId},"assistantStream":true,"maxMessages":200}}}}`。

* 浏览器侧先 `fetch('/?token=...')` 完成鉴权再调 `/api/*`。**M0 必须用 curl 实测**：relay 在容器内以服务端身份调 `127.0.0.1:3080/api/*` 是否仍需 token；若需要，新 v1 接口接收 Swift 传来的 `token` 查询参数并复刻同样的鉴权握手，结论写进 NOTES-api.md。

### 1.3 会话数据（投影缓存，relay 时间线用）



* 主会话 id 形如 `session-<uuid>`，角色子会话为裸 `<uuid>`；磁盘：`$DSH_HOME/sessions/--app--/<id>/session.v3.jsonl.zstd`（压缩，勿在 Swift 侧碰）。

* 可读投影：`$DSH_HOME/storages/session_projcache/sessions/<id>.json`，结构 `{version, record:{identity:{createdAt,...}, rows:{<key>:{seq,val}}}}`，关键字段：


  * `title.val`、`sessionListMetadata.val.lastPromptAt`、`sessionStats.val.{openStep,pendingCalls,turns,steps}`（**运行判定**：`openStep != null` 或 `pendingCalls` 非空）；

  * `subagent.identity.{mode,label,seq}`、`subagentTiming.settledMs`（一次委派的标签与耗时）；

  * `turnOutline.turns[]`（每轮 `{turn,seq,prompt,response}`，做故事线的素材）；

  * `plan`、`todos`、`tokenUsage.totals`、`modelSelection.lastUsed.reasoningEffort`。

* `storages/workspace.json` 的 `global.archivedSessionIds` 是归档集合，列表要过滤。

* 现有控制台的角色 / 结论判定规则（relay 端**原样沿用**，保持一致）：reasoningEffort `low→coder`、`high→reviewer`、其余 `sub`；`turnOutline` 文本匹配 `/\bPASS\b/i→pass`、`/\bFAIL\b/i→fail`；`asOfSeq>4` 且首条 prompt 不含 "reply with exactly one word" 才算 meaningful。

### 1.4 现有原生壳（dsh-desktop，5 个 Swift 文件，523 行）



* `Main.swift`：单 WindowGroup，ready 前显示启动屏，ready 后全屏 `WebView`；`applicationShouldTerminateAfterLastWindowClosed=true`、退出时同步 `docker compose stop`。

* `StackController.swift`：用 `/bin/zsh -lc` 拼 docker 命令串完成五阶段启动（检查 OrbStack→compose up→等 healthy→从 `docker logs` grep token→curl /console 200）。**这套流程要重构，但保留 "幂等、分阶段、每步超时" 的骨架**。

* `WebView.swift`：WKWebView 包装，启动时注入 `window.dshNativeArtifacts=true`，已注册自定义 scheme。

* `ArtifactPreview.swift`：`dsh-artifact://` scheme handler，含 list/read/open/reveal/status 与严格路径穿越防护、5MB 上限 ——**安全逻辑原样保留**。

* `AppPaths.swift`：硬编码个人路径 `defaultProjectRoot`，是本次要消灭的工艺债。

* `build-app.sh`：`swiftc Sources/*.swift` 直编 + ad-hoc 签名，无 Xcode 工程。



***

## 2. v1 目标与非目标

### 2.1 v1 必须交付（一个完整闭环，内部按 M1–M5 顺序开发）



1. **零配置首启**：自动定位 dsh-workbench；找不到时首启向导让用户选目录并持久化；OrbStack 缺失时给可操作引导。

2. **原生三栏工作台**：左侧会话列表、中间现有 Web 控制台（保留为对话区）、右侧 Inspector（团队故事线 + 容器资源 + 产物入口）。

3. **看得见**：Lead/Coder/Reviewer 的委派与结论以 "故事线" 呈现；容器 CPU / 内存仪表；运行状态在 Dock 图标、菜单栏图标、工具栏三处一致。

4. **管得住**：工具栏可停止当前任务（session/cancel，不杀容器）、重启 / 停止容器；运行中 ⌘Q 弹三选一确认；关窗默认驻留菜单栏、任务完成发原生通知。

5. **错误态细分**：每种失败有专属图标、说明、主动作按钮和可展开的容器日志尾部。

6. **安全工艺**：token 进 Keychain，不进 URL 之外的任何持久化 / 日志；构建脚本支持 Developer ID 签名 + 公证（ad-hoc 仍为默认）。

7. 容器生命周期操作改走 **Docker Engine unix socket API（Network.framework 手写 HTTP/1.1）**，docker CLI 仅作兜底。

### 2.2 v1 明确不做（砍干净，不要顺手实现）

多窗口 / 多会话并行；文件 diff 与一键回滚；"空闲自动停容器"" 退出策略 "等用户可配策略项；自动更新；英文本地化；重写 Web 控制台；MCP/roster 相关任何改动；本地模型 / 向量库。遇到这些念头，写进交付说明的" 后续建议 " 即可。



***

## 3. 目标信息架构与交互

### 3.1 主窗口（NavigationSplitView 三栏，默认 1280×820，最小 1000×640）



```
┌ 工具栏 ───────────────────────────────────────────────────────────────┐

│ \[＋新任务]        ■ 停止任务(仅运行中可用)  ↻重启容器      ⓘ在浏览器打开 │

├──────────────┬───────────────────────────────────┬────────────────────┤

│ 侧边栏 220   │  中间：WKWebView 承载 /console     │ Inspector 300      │

│ 最近任务列表  │  （唯一允许出现 Web 内容的区域）    │  ▸ 团队             │

│ 运行中脉冲点  │                                   │    Lead ● 运行中    │

│ pass/fail 色 │                                   │    └ Coder ✓ 62s    │

│ 归档分组折叠  │                                   │    └ Reviewer …     │

│ 空态文案     │                                   │  ▸ 故事线           │

│              │                                   │  ▸ 容器 CPU/MEM 条  │

│              │                                   │  ▸ 产物(N) Finder   │

└──────────────┴───────────────────────────────────┴────────────────────┘
```



* **侧边栏**：数据来自 `GET /console-api/v1/sessions`；主会话按 updatedAt 倒序，前 8 条 "最近"，其余折叠为 "更早・N"（沿用现有控制台分组习惯）；行内显示标题（两行截断）、状态（运行中 / 已通过 / 有问题 / 完成）、HH:mm；运行中行显示呼吸圆点（opacity 动画 0.2s easeInOut）；选中行驱动中间 WebView 切换会话（4.2 桥接）与右侧 Inspector。

* **中间栏**：现有 WKWebView，加载 `/console?token=...`；切换会话时**不整页重载**，用 JS 桥接调用页面内选择；仅在容器重启 / 手动重载时 reload。`dsh-artifact` scheme 全部保留。

* **Inspector**：


  * 「团队」：Lead 一行（蓝色圆点），其下按时间缩进 Coder（绿）/Reviewer（橙）子会话行，显示标签、状态、耗时；结论用 `checkmark.seal.fill`（pass 绿）/`xmark.octagon.fill`（fail 橙）。

  * 「故事线」：纵向时间轴，事件节点见 `/v1/timeline`；每条一行标题 + 一行次要说明，超长折叠 "展开"；空态 "Lead 尚未委派，等待中…"。

  * 「容器」：CPU%、内存（如 0.42G/2G），`monospacedDigit`，两条细进度条；旁边小字 "OrbStack・2 核上限"。

  * 「产物」：数量 + 按钮在 Finder 打开 `dsh-home/artifacts/<session>`（复用 AppPaths 与安全校验）。

* 三栏都要支持深色模式；非 Web 区域使用系统材质（`.regularMaterial` 卡片背景），不得自造网页感配色；SF Symbols 只用 macOS 13 确定存在的符号，拿不准的在 M0 列清单逐个核实。

### 3.2 启动屏（ready 前）



* 正常态：`cube.container` 图标 + "正在准备团队工作台" + `ProgressView` + 当前阶段句（检查 OrbStack / 启动 OrbStack / 启动容器 / 等待就绪 / 读取凭据 / 连接中继）。

* 失败态：按 `StackError` 分别显示图标、一句话标题、说明正文、**一个主动作按钮**（重试 / 下载 OrbStack / 重新选择项目目录），下方 DisclosureGroup"查看日志" 展示 `docker logs dsh` 最后 40 行（同样过滤 token）。

### 3.3 菜单栏驻留（MenuBarExtra，样式 .menu）



* 图标随状态：运行任务 =`stop.circle` 着强调色；空闲 =`cube.container`；容器停止 = 灰色。

* 菜单项：显示主窗口 / ── / 当前任务标题与状态 / 停止当前任务（仅运行中可用）/ 重启容器 / ── / 停止容器并退出。

* **关窗模型（唯一模型，不提供设置项）**：点红色关闭按钮 = 隐藏窗口、容器与任务继续；Dock 图标点击或菜单 "显示主窗口" 恢复；只有 ⌘Q / 菜单 "停止容器并退出" 才真正终止，终止时沿用 Policy A 停掉容器使占用归零。

* **运行中 ⌘Q**：模态 NSAlert 三按钮 ——"等任务完成后退出"（后台等待，完成后发通知并自动 terminate；期间菜单栏可见进度）、"立即退出（任务与容器将停止）"、"取消"。空闲时 ⌘Q 直接退出。

### 3.4 通知（UNUserNotificationCenter）



* 首次有任务运行时请求通知授权；运行态 true→false 时发一条：标题 = 会话标题截断 30 字，正文 =`Coder 已完成`/`Reviewer 判定：通过（或：发现问题）`/`任务已停止`；窗口可见时不打扰（不弹）。容器变 unhealthy 也通知一条。

### 3.5 设置（标准 Settings 场景，⌘, 打开）与首启向导



* 设置仅四组：①项目位置（路径只读显示 + "在 Finder 中显示" + "重新选择"）②通知开关（默认开）③容器资源（只读展示 compose 的 CPU / 内存上限与当前占用）④诊断（打开 dsh-home、导出最近日志、版本号）。**不出现**生命周期策略类开关。

* 首启向导（定位不到合法项目目录时全屏替代主界面）：三句话解释这是什么 → "选择 dsh-workbench 文件夹" 按钮（NSOpenPanel，校验必须同时含 `orbstack/compose.yaml` 与 `deepseek-harness/orbstack-relay.cjs`，非法目录给内联报错）→ 选定后写入配置并进入正常启动流程。



***

## 4. 接口契约

### 4.1 relay 新增：`/console-api/v1/*`（改 `deepseek-harness/orbstack-relay.cjs`）

通用要求：`cache-control: no-store`；`content-type: application/json`；POST body 上限 64KB（沿用 purge 的做法）；session id 一律过 `SESSION_ID_RE`；任何上游调用失败返回 `{ok:false,error}` 与 502，不允许让请求挂死（设 5s 超时）；保持纯内置模块；不新增监听端口。

**(1)&#x20;**`GET /console-api/v1/health` → `{ok:true,upstream:"up"|"down",serverTime}`（relay 探测一次 3080）。

**(2)&#x20;**`GET /console-api/v1/sessions?token=<t>`：relay 端调用上游 `session/list`（信封见 1.2，鉴权方式按 M0 结论），结合投影缓存与 workspace.json 归档集合，输出归一化结构：



```
{

&#x20; "ok": true,

&#x20; "serverTime": 1789058261732,

&#x20; "roots": \[{

&#x20;   "id": "session-xxxx", "title": "实现Q-learning", "role": "lead",

&#x20;   "running": false, "updatedAt": 1789058261784, "turns": 3,

&#x20;   "verdict": "pass",

&#x20;   "tokens": {"input": 74900, "output": 4152, "cacheRead": 46080},

&#x20;   "children": \[{

&#x20;     "id": "bare-uuid", "role": "coder", "label": "实现简单强化学习脚本",

&#x20;     "running": false, "updatedAt": 1789058261000,

&#x20;     "settledMs": 62406, "verdict": ""

&#x20;   }]

&#x20; }]

}
```



* roots 只含主会话（无 parentSessionId）、过滤 archived、过滤非 meaningful（规则 1.3）；children 按 parentSessionId 挂载，角色与 verdict 规则同 1.3；缺失字段用安全默认值，绝不抛崩。

**(3)&#x20;**`GET /console-api/v1/timeline?token=<t>&session=<rootId>&limit=200`：只读该主会话及其 children 的投影文件，输出有序故事事件（按 seq / 时间混合排序）：



```
{"ok":true,"events":\[

&#x20; {"seq":4,"ts":1789058261000,"kind":"turn","role":"lead","title":"下发任务","detail":"\<prompt 截断 600 字>"},

&#x20; {"seq":6,"ts":1789058262000,"kind":"delegate","role":"coder","status":"start","title":"委派 Coder：实现简单强化学习脚本"},

&#x20; {"seq":30,"ts":1789058324000,"kind":"delegate","role":"coder","status":"done","title":"Coder 完成 · 62s","detail":"\<response 截断 600 字>"},

&#x20; {"seq":31,"ts":1789058325000,"kind":"verdict","role":"reviewer","status":"pass|fail","title":"Reviewer 判定：通过/发现问题"}

]}
```

kind 仅允许 `turn | delegate | plan | todo | verdict`；plan/todos 存在才输出；投影缺失时返回空数组而非报错。

**(4)&#x20;**`POST /console-api/v1/cancel`：body `{sessionId}`（可选带 token 字段），relay 转为上游 `session/cancel` 调用，返回 `{ok:true}`；id 非法 400，上游失败 502 并带 message。

**(5)&#x20;**`POST /console-api/v1/session`：body `{agentPreset:"team-lead"}`，转上游 `session/create`，返回 `{ok:true,sessionId}`。

### 4.2 控制台最小桥接（改 `dsh-home/console/index.html`，只加不改逻辑）



* 页面加载时读取 URL 查询参数 `session`，若存在且列表中有该 id，启动后自动选中它（复用现有 `select()`）。

* 暴露稳定 JS API：`window.dshHostAPI = { select(id){...}, create(){...}, cancelSelected(){...} }`，内部调用页面已有的 rpc/select，不得重写其业务逻辑。

* 向 native 单向发事件：在现有 running 状态变化、选中会话变化、任务结束的位置调用 `window.webkit.messageHandlers.dshHost.postMessage({type:"runningChanged"|"selectionChanged"|"taskFinished",sessionId,running,verdict})`；**调用前必须判空**（浏览器 / Safari 打开时不存在该 handler）。

* Swift 侧 WKWebView 注册 `WKScriptMessageHandler("dshHost")`；native→页面用 `evaluateJavaScript("window.dshHostAPI.select('...')")`，失败时降级为整页带 `?session=` 重载。

### 4.3 Docker Engine 客户端（Swift，新建 `Sources/Docker/`）



* 用 Network.framework 的 `NWConnection` 连 unix domain socket 手写极简 HTTP/1.1 客户端（GET/POST，解析状态行 /headers/body，支持 chunked 只需读到 Content-Length；stats 用单次模式）。socket 候选路径按序探测：`~/.orbstack/run/docker.sock`、`/var/run/docker.sock`（M0 实测确认并记录）。

* 方法：`containers()`（GET `/containers/json?all=1`）、`start/stop/restart(name)`（POST 对应路径，stop 超时 20s）、`health(name)`（GET `/containers/<name>/json` 取 State.Health.Status）、`stats(name)`（GET `/stats?stream=false`，CPU% 按两次采样（间隔 1s）的 `cpu_stats`/`precpu_stats` 与 `online_cpus` 计算，内存取 `memory_stats.usage/limit`）、`logsTail(name, lines=40)`（GET `/logs?stdout=1&stderr=1&tail=40`）。

* 全部 async 接口、单飞（避免重复请求）、默认 8s 超时（compose up/restart 除外，给 90s）。socket 不可用时**降级**到现有 zsh CLI 模式（把现有 shell 实现抽到 `Sources/Support/ProcessShell.swift` 保留），并在诊断里注明当前走的通道。

* `docker compose up -d`（构建 / 拉起编排）仍走 CLI（Engine API 无 compose 等价物），但输出要实时进入启动阶段日志缓冲，供失败界面展示。



***

## 5. Swift 代码结构（在 dsh-desktop/Sources 下组织）



| 文件                                                                                                                                                                                                                          | 状态 | 职责                                                                                                                                                       |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Main.swift`                                                                                                                                                                                                                | 改  | 三个 Scene：WindowGroup（RootSplitView）、`MenuBarExtra`、`Settings`；AppDelegate 管关窗驻留 / 运行中退出 / 退出时停容器                                                         |
| `Copy.swift`                                                                                                                                                                                                                | 新  | 全部中文文案常量，一处维护                                                                                                                                            |
| `AppPaths.swift`                                                                                                                                                                                                            | 改  | 不再硬编码：全部取值来自 ProjectLocator                                                                                                                              |
| `ProjectLocator.swift`                                                                                                                                                                                                      | 新  | 定位顺序：环境变量 `DSH_WORKBENCH_ROOT` → `~/Library/Application Support/DSHTeam/config.json` → 限定深度 glob 默认 Documents 目录 → nil（触发首启向导）；合法性校验；持久化                 |
| `Docker/UnixSocketHTTP.swift`、`Docker/DockerEngine.swift`、`Docker/DockerModels.swift`                                                                                                                                       | 新  | 4.3                                                                                                                                                      |
| `Support/ProcessShell.swift`                                                                                                                                                                                                | 新  | 从 StackController 抽出的 zsh 执行器，仅作降级路径                                                                                                                     |
| `Security/KeychainStore.swift`                                                                                                                                                                                              | 新  | token 的增读删（service `local.dsh.team`，account `relay-token`），调试日志断言不含 token                                                                                |
| `Relay/RelayClient.swift`、`Relay/RelayModels.swift`                                                                                                                                                                         | 新  | 消费 4.1 五个接口；轮询调度（可见时 sessions 3s、stats 2s，窗口隐藏 / 最小化立即暂停，恢复即刷）；解析容错（单字段失败不拖垮整屏）                                                                          |
| `Stack/StackController.swift`                                                                                                                                                                                               | 改  | 显式状态机：`idle→checkingOrb→startingOrb→composeUp→waitingHealth→readingToken(入 Keychain)→connecting→ready`；`failed(StackError)`；ready 后派生 `idle/running` 子状态 |
| `Stack/StackError.swift`                                                                                                                                                                                                    | 新  | 枚举：orbNotFound /orbStartTimeout/composeFailed /healthTimeout/tokenMissing /relayUnreachable/projectMissing /socketFailed，各自携带用户文案、主动作类型、日志尾部             |
| `State/AppStore.swift`                                                                                                                                                                                                      | 新  | 全局 ObservableObject：选中会话、会话集合、时间线、stats、运行态边沿触发（发通知的唯一位置）                                                                                                |
| `Views/RootSplitView.swift`、`SidebarView.swift`、`ConsolePaneView.swift`、`InspectorView.swift`、`TimelineStoryView.swift`、`TransportBar.swift`、`BootView.swift`、`FirstRunView.swift`、`SettingsView.swift`、`MenuBarView.swift` | 新  | 第 3 节全部界面                                                                                                                                                |
| `WebView.swift`                                                                                                                                                                                                             | 改  | 注册 dshHost message handler、暴露 evaluateJavaScript 桥接、按会话切换；其余不动                                                                                           |
| `ArtifactPreview.swift`                                                                                                                                                                                                     | 不动 | 安全逻辑保持                                                                                                                                                   |



***

## 6. 里程碑与验收（每个 M 完成后逐条自测，写进交付说明）

### M0 勘察（只产出文档 `dsh-desktop/NOTES-api.md`，不改代码）



* 记录：docker.sock 实际路径；容器内服务端调 `/api/session/list` 是否需要 token 及握手方式；`session/list` 真实 JSON 样例（脱敏）；容器内有无 `zstd`（结论：时间线只用投影缓存，不依赖 zstd）；macOS 13 上拟用 SF Symbols 的可用性核对；OrbStack 未运行时 socket/CLI 的表现。

* 验收：NOTES 覆盖以上每一项，附可复现 curl 命令。

### M1 原生地基（界面仍是单窗，但底层全部换血）



* ProjectLocator + 配置持久化；DockerEngine（socket 优先 / CLI 降级）；Keychain；StackController 新状态机与 StackError；BootView 按 3.2 重做。

* 验收：①删掉 config、容器已停、OrbStack 已开 → 双击 App 全自动到 ready，token 只存在 Keychain；②退出 OrbStack 后启动 → orbNotFound 界面，按钮可打开下载页；③手动 `docker stop dsh` 后点重启 → 恢复；④制造 compose 失败（临时改坏 compose.yaml 再还原）→ composeFailed 界面能展开日志；⑤全程任何日志 / 通知 / UserDefaults 中 grep 不到 token；⑥`swiftc` 零 warning。

### M2 relay v1 API + 控制台桥接



* 实现 4.1 五接口、4.2 三处最小桥接；用 curl 逐个验证（含非法 session id 返回 400、上游停用时 health 返回 down 且不挂起）。

* 验收：①五个接口的 curl 成功 / 失败用例全部通过并把命令与输出摘进 NOTES；②浏览器直接开 `/console?token=...&session=<id>` 能自动选中；③原有 `/console-api/artifact(s)`、`/console-api/purge`、WS mux、SSE 代理行为零回归（现有控制台功能手动走一遍：新建、对话、产物下载中文名、删除 / 归档）。

### M3 三栏工作台



* 完成第 5 节所有 Views 与 AppStore；侧边栏选择经 JS 桥切换会话（失败降级重载）；Inspector 时间线 / 资源 / 产物；轮询在窗口隐藏时暂停。

* 验收：①跑一个 L3 任务，能看到 Lead→Coder→Reviewer 完整故事线，pass/fail 颜色正确；②运行中工具栏 "停止任务" 可中止且容器不重启（`docker ps` uptime 连续）；③切会话中间页不整页白屏重载；④窗口最小化 5 分钟，CPU 占用近零、无轮询请求（用 relay 访问日志验证），恢复后立即刷新；⑤深色模式截图检查无硬编码颜色；⑥断网 /relay 502 时界面显示离线态而不崩。

### M4 系统能力



* MenuBarExtra、关窗驻留、运行中退出三选一、完成通知、Settings、首启向导。

* 验收：①运行中关窗→任务继续（relay 日志可见仍在跑），菜单栏可恢复窗口；②运行中 ⌘Q 三按钮分别验证（等待分支要真正等到结束并通知 + 退出；立即分支停容器退出；取消分支什么都不变）；③空闲 ⌘Q 直接退出且容器被停、占用归零；④前台可见时不弹通知，切到后台后完成才弹；⑤把 config 删掉且 glob 不到工程目录→首启向导，选非法目录报错、选合法目录后正常进入；⑥⌘, 打开设置，改项目位置流程闭环。

### M5 打磨与发布



* 零 warning、动效 / 间距 / 字号走查、VoiceOver 走查三栏（控件有 label、状态不只靠颜色表达）；`build-app.sh` 升级：默认仍 ad-hoc；`./build-app.sh release` 时读取环境变量 `DEVELOPER_ID`，启用 Hardened Runtime（带最小 entitlements）、`--timestamp` 签名、`xcrun notarytool submit --wait`、`stapler staple`，产物输出 `build/DSH工作台-1.1.0.app` 与同名 zip；版本号升到 1.1.0；新增 `dsh-desktop/README.md`（架构图、目录职责、调试与发布步骤、降级通道说明）；在 `dsh-lightweight-team-starter.md` 增补 "原生工作台" 一节；输出最终验收报告（对照本清单逐条 + 实测截图 / 输出位置）。

* 验收：①ad-hoc 与 release 两条构建路径各跑一遍；②从零冷启动（容器不存在镜像，触发 build）全流程一次通过；③连续运行 1 小时轮询无内存持续增长（Activity Monitor 观察记录首尾值）；④本文件第 7 节红线逐条核对无违反。



***

## 7. 红线（已踩平的坑，禁止回退）



1. 角色 / 委派 / MCP 配置只能存在 agent 预设层与启动 overlay，不得塞进 Web 宿主补丁、不得整体覆盖全局 system prompt、不得全局挂 persona（详见 `dsh-lightweight-team-starter.md` 第 5 节三个坑）。

2. 始终只有一个 `dsh` 容器；子角色是进程内 spawn，绝不新增容器 / 进程来实现任何界面功能。

3. relay 对 SSE、chunked、WebSocket Upgrade 的透传隧道必须保持；中文 `Content-Disposition` 双 filename 处理必须保持；healthcheck 仍以容器内 `/console` 为准。

4. `dsh-artifact://` 的 session 白名单正则、路径穿越校验、symlink 解析、5MB 上限一条都不能少；新 v1 接口同等标准。

5. 端口仍只绑定 Mac 侧 `127.0.0.1`，不得为 "方便调试" 改成 0.0.0.0 或新增发布端口。

6. 不删除 / 移动用户已有的 `~/Desktop/DSH工作台.app`、`~/Applications/DSH工作台.app`；安装新版本只产出在 `dsh-desktop/build/`，由用户自行替换。

7. 容器内 full-access 是既定隔离模型，本次不做也不改权限模式；"急停" 只能走 session/cancel，禁止用停容器冒充急停。



***

## 8. 最终交付物清单



1. 按 M1–M5 的五个 git commit；`dsh-desktop/NOTES-api.md`、`dsh-desktop/README.md`。

2. `build/DSH工作台.app`（ad-hoc，可直接双击）与 release 路径产物。

3. 一份验收报告（可放在 `dsh-desktop/ACCEPTANCE-v1.md`）：逐条对应第 6 节验收项，附命令、现象、截图路径；列出与本规格的任何偏差及原因；列出 "后续建议"（即 2.2 被砍项的未来形态）。

4. 更新后的 `dsh-lightweight-team-starter.md`。

开始：先执行 M0，产出 NOTES-api.md 后简要汇报关键结论，再继续 M1。