# DSH 团队工作台（原生壳）

macOS 原生外壳 + 容器内自家 relay，把「DSH 团队」从浏览器标签页变成一扇常驻的窗口。
版本 **1.1.0**（build 2），部署目标 macOS 13，纯 `swiftc` 命令行编译，零第三方依赖。

## 架构

```
        Mac 侧                                        容器 dsh（OrbStack · 2 CPU / 2GiB · 唯一一个）
┌────────────────────────────────┐            ┌──────────────────────────────────────────────┐
│ DSH工作台.app（SwiftUI）        │            │ relay :3081  deepseek-harness/orbstack-relay │
│                                │            │  ├ /console-api/v1/*   本壳专用 JSON API     │
│  StackController ──── Engine ──┼── socket ─▶│  ├ /console-api/*      旧桥（产物/清理/隧道）│
│  （启动状态机 + 容器生命周期）  │   或 CLI   │  └ /                    反向代理 → dsh web    │
│                                │            │                                              │
│  AppStore ─────────────────────┼── :3081 ──▶│ dsh web :3080（上游，不修改）                │
│  （会话/时间线/指标 轮询）      │            │  ├ /console            单文件控制台（自有）  │
│                                │            │  └ /api/*              RPC（session/prompt…）│
│  RootSplitView（三栏工作台）    │            │                                              │
│   ├ SidebarView   会话 + 新任务 │            └──────────────────────────────────────────────┘
│   ├ WKWebView     控制台（同源）│
│   └ InspectorView 时间线/资源/产物
│                                │
│  ArtifactSchemeHandler         │   产物预览不走网络：dsh-artifact://list|read|open|reveal
│  （dsh-artifact:// 自定义协议）│   → 直接读 dsh-home/artifacts/<session>/
└────────────────────────────────┘
```

- 端口只绑 Mac 侧 `127.0.0.1`：App → `127.0.0.1:3081`（relay）；容器内 relay → `127.0.0.1:3080`（dsh web）。
- 只有一扇主窗、一个容器。子角色（coder/reviewer）是容器内进程内 spawn，本壳不感知也不干预。

## 目录职责

| 路径 | 职责 |
| --- | --- |
| `Sources/Main.swift` | App 场景装配：`Window`（非 WindowGroup）、`MenuBarExtra`、`Settings`、菜单命令 |
| `Sources/State/AppStore.swift` | 唯一轮询源：会话列表 / 时间线 / 容器指标 / 产物计数；可见性驱动的停表逻辑 |
| `Sources/Stack/StackController.swift` | 启动状态机（orb → compose → healthy → token → ready）与容器动作 |
| `Sources/Stack/StackError.swift` | 全部失败态与其人话文案（含修复建议） |
| `Sources/Docker/DockerEngine.swift` | Engine API 直连优先，失败降级 CLI；只操作名为 `dsh` 的容器 |
| `Sources/Docker/UnixSocketHTTP.swift` | 极简 unix socket HTTP/1.1 客户端，支持 chunked 响应 |
| `Sources/Docker/DockerModels.swift` | `/containers/json`、`/stats` 的解析模型 |
| `Sources/Relay/RelayClient.swift` | `/console-api/v1/*` 客户端（health / sessions / timeline / cancel / session） |
| `Sources/Relay/RelayModels.swift` | v1 API 的 Codable 模型，容错解码（缺字段不崩） |
| `Sources/WebView.swift` | WKWebView 封装：注册 `dsh-artifact://`、加载 `127.0.0.1:3081/console?token=…`、JS 选择桥 |
| `Sources/ArtifactPreview.swift` | 产物协议实现 + 全部校验（session 白名单、穿越、symlink、5MB 上限） |
| `Sources/ProjectLocator.swift` | 工程目录发现/校验（拒绝 `/tmp`、`$HOME`、子目录）与持久化 |
| `Sources/Security/KeychainStore.swift` | token 只落 Keychain；失败时退回内存，不写 UserDefaults |
| `Sources/System/MainWindowBridge.swift` | 把 NSWindow 交给 AppDelegate（关窗 = orderOut，不销毁） |
| `Sources/System/Notifier.swift` | 任务完成通知；窗口可见时抑制 |
| `Sources/Views/*` | 三栏界面、启动屏、首启向导、设置、菜单栏面板、通用组件 |
| `Sources/Copy.swift` | 全部 UI 文案（简体中文）集中于此 |
| `Sources/Support/LogRedaction.swift` | 日志脱敏：token 一律 `token=***` |
| `NOTES-api.md` | M0 勘察记录：RPC 信封、投影缓存、socket 路径、SF Symbols 核对 |
| `ACCEPTANCE-v1.md` | 对照规格第 6 节的逐条验收报告 |

## 运行链路（启动状态机）

```
idle → checkingOrb → (startingOrb) → composeUp → waitingHealth → readingToken → connecting → ready
                                   ↘ failed(StackError) ↙
```

- `phase == .ready` 之前显示启动屏（`BootView`），失败显示可展开日志 + 修复按钮。
- 轮询节奏（`AppStore.beat()`，1s 心跳）：会话 3s、时间线 5s、产物计数 7s、健康 15s、容器指标异步 2s。
- 窗口隐藏 / 最小化 / App 隐藏：空闲时**完全停表**；有任务在跑时降到 1/5 频率（会话每 15s）。

## 调试

```bash
cd dsh-desktop
./build-app.sh                 # 编译 + ad-hoc 签名 → build/DSH工作台.app
open "build/DSH工作台.app"      # 双击亦可
```

- 编译：`find Sources -name '*.swift' | sort` 后交给
  `swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx13.0`。
  **必须零 warning**（`./build-app.sh` 会原样打印编译输出）。
- 单独重启容器看日志：`docker logs -f dsh`；relay 的访问日志前缀是 `[relay]`，轮询证据只认它。
- 只想改图标：`./make-icon.sh`（依赖 `Assets/whale-icon.svg`）。
- 现有验收脚本（在仓库根目录跑）：

  ```bash
  NODE=./.toolchain/node-v22.23.2-darwin-arm64/bin/node
  $NODE tests/console-usage.test.mjs     # 控制台用量栏
  $NODE tests/console-history.test.mjs   # 控制台历史
  $NODE scripts/render-team.mjs --check  # roster 生成物一致性
  ```

- 排查「窗口到底在不在屏幕上」：不要相信截图缓存，用 `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` 的列表。
- 排查 token：只允许 `LogRedaction` 处理过的形式；Keychain 里的值可用「钥匙串访问」自查。

## 发布

```bash
cd dsh-desktop
DEVELOPER_ID="Developer ID Application: 你的名字 (TEAMID)" \
NOTARY_PROFILE=dsh-notary \
./build-app.sh release
```

依次完成：编译 → 版本化产物 `build/DSH工作台-1.1.0.app` → Hardened Runtime + 最小 entitlements
（`allow-jit` / `network.client` / `files.user-selected.read-only`）→ `codesign --timestamp` →
`ditto` 打包同名 zip → `notarytool submit --wait` → `stapler staple` → `codesign --verify --deep --strict` → `spctl --assess`。

- 缺 `DEVELOPER_ID` 会**立刻报错退出**，不会留下半个产物。
- 版本号唯一来源是 `Info.plist` 的 `CFBundleShortVersionString`，打包路径自动跟随。
- 装机：把 `build/DSH工作台-1.1.0.app` 拖进 `/Applications` 即可。
  **不要**覆盖用户已有的 `~/Desktop/DSH工作台.app` / `~/Applications/DSH工作台.app`。

## 降级通道（每一层都有退路）

| 出问题的一层 | 降级行为 |
| --- | --- |
| Docker Engine socket（`~/.orbstack/run/docker.sock`、`/var/run/docker.sock`） | 探测失败 → 自动落到 `docker` CLI；界面上 `StackController.transportLine` 会标明当前通道 |
| OrbStack 未启动 | 停在 `orbNotFound` 失败态，按钮直达下载页，不会无限转圈 |
| compose 起不来 | `composeFailed` 失败态 + 可展开日志；修复后点重试 |
| 上游还在 build / 未 healthy | `waitingHealth` 有超时，超时给出可操作错误而非假死 |
| token 读取（容器只在启动时打印一次，且会被 relay 访问日志顶掉） | 三层回溯：`docker logs --tail 400` → `2000` → `8000`；命中后用一次真实请求验活；仍失败则提示重启容器 |
| relay `/console-api/v1/*` 502 / 网络断 | `RelayPhase.offline`，界面显示离线态并降低轮询，不崩溃、不白屏 |
| 侧边栏切换会话时 JS 桥失效 | 记一条警告后**整页重载**兜底（`RootSplitView`） |
| Web 控制台加载失败 | 工具栏「重新载入」（⌘R）与「重启容器」（⌘⇧R）始终可用 |
| 产物预览 | 走 `dsh-artifact://` 本地协议；被拒绝的文件给出具体原因（超 5MB / 越界 / 不可读），「在访达中显示」仍是逃生口 |

## 不要回退的红线

1. 角色 / 委派 / MCP 配置只存在于预设层与 overlay，不塞进 Web 宿主补丁。
2. 永远只有一个 `dsh` 容器；不为任何界面功能新增容器或额外进程。
3. relay 对 SSE / chunked / WebSocket Upgrade 的透传、中文 `Content-Disposition` 双 filename 必须保持。
4. `dsh-artifact://` 的白名单正则、路径穿越、symlink、5MB 上限一条都不能少。
5. 端口只绑 Mac 侧 `127.0.0.1`。
6. 不删除、不移动用户已有的 `~/Desktop/DSH工作台.app`、`~/Applications/DSH工作台.app`。
7. 「急停」只能走 `session/cancel`，禁止用停容器冒充。

## 相关文档

- `NOTES-api.md` — 接口勘察与实测记录（含 relay v1 契约、投影缓存结构、踩坑）
- `ACCEPTANCE-v1.md` — v1 验收报告（对照规格逐条 + 偏差 + 后续建议）
- `../dsh-lightweight-team-starter.md` — 从零搭起这套轻量团队（含「原生工作台」一节）
- `../NATIVE_REDESIGN_CODEX_PROMPT.md` — 本次改造的规格书
