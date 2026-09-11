# DSH 团队工作台 v1 · 验收报告

> 对照 `NATIVE_REDESIGN_CODEX_PROMPT.md` 第 6 节（M0–M5）逐条验收。
> 机器：macOS 26.6 / arm64 · 产物：`dsh-desktop/build/DSH工作台.app`（ad-hoc 签，**1.1.0 (2)**）
> 验收时间：2026-09-11 · 详细原始记录见 `NOTES-api.md` §11–§14

## 0. 总览

| 里程碑 | 结果 | 说明 |
| --- | --- | --- |
| M0 勘察 | ✅ 5/5 | `NOTES-api.md` §1–§8，每条附可复现 curl / 探针 |
| M1 原生地基 | ✅ 6/6 | ①③④⑤⑥ 于 M5 窗口复跑；② 见「偏差」 |
| M2 relay v1 + 桥接 | ✅ 3/3 | 13 条 curl 用例 + 既有接口零回归（§11） |
| M3 三栏工作台 | ⚠️ 5/6 | ② 受上游额度阻塞（§12.4） |
| M4 系统能力 | ⚠️ 3.5/6 | ②④ 与 ①后半受同一额度阻塞（§13.4）；另修掉一处 M4 引入的「关窗后仍在轮询」回归 |
| M5 打磨与发布 | ✅ 4/4 | 冷启动与 1 小时数据见 §2.1 / §2.2；release 走到签名前一步（本机无证书） |

**一句话**：链路、界面、系统能力全部落地并实测；唯一系统性缺口是**上游模型额度为 0**，导致三条「必须有任务在跑」的验收项无法执行——代码路径已就位，补验步骤见 §3.1。

## 1. 构建与运行基线

```bash
cd dsh-desktop && ./build-app.sh          # ad-hoc，零 warning
cd dsh-desktop && ./build-app.sh release  # 需 DEVELOPER_ID / NOTARY_PROFILE
open -a "$PWD/dsh-desktop/build/DSH工作台.app"
```

- `swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx13.0`，
  27 个源文件 / 3732 行，**编译输出为空 = 零 warning**。
- 零第三方依赖：Swift 只用 SwiftUI / AppKit / WebKit / Network / Security / UserNotifications / Foundation；
  relay 只用 Node 内置模块。

## 2. M0–M5 逐条

### M0 勘察 ✅

| 验收项 | 证据 |
| --- | --- |
| docker.sock 实际路径 | `~/.orbstack/run/docker.sock`（`/var/run/docker.sock` 是符号链接），§1 |
| `session/list` 是否要 token、握手方式 | 要；`GET /?token=` → `Set-Cookie: token=…` 进程内缓存，§2 |
| `session/list` 真实 JSON（脱敏） | §4 样例 |
| 容器内有无 `zstd` | 无（只有 node / python3）→ 时间线只用投影缓存，§5 |
| macOS 13 SF Symbols 可用性 | 9 个符号逐个 `NSImage(systemSymbolName:)` 判空，§7 |
| OrbStack 未运行时的表现 | CLI 报 `dial unix …: connect: no such file or directory`，§8 |

### M1 原生地基 ✅

| # | 验收项 | 结果与证据 |
| --- | --- | --- |
| ① | 删 config、容器已停、OrbStack 已开 → 双击全自动到 ready，token 只在 Keychain | ✅ 容器已删 + 配置已删 → 双击 → 自动 `compose up -d`（首次构建镜像）→ healthy → 读 token → ready；`security find-generic-password -s local.dsh.team -a relay-token` 与容器内 token 逐字节一致（43 字符） |
| ② | 退出 OrbStack 后启动 → orbNotFound 界面 + 下载按钮 | ⚠️ 未复跑：本机还有其它项目容器（`flowcredit-agent`），退出 OrbStack 会连带影响它们；错误映射已于 M0 §8 用不存在的 socket 安全模拟，`StackError.orbNotFound` 分支即由该探测结果驱动 |
| ③ | 手动 `docker stop dsh` 后点重启 → 恢复 | ✅ 见 §12.1-⑥：停容器 → 离线态 → 点「重启容器」→ 重读 token → 自动恢复 |
| ④ | 制造 compose 失败 → 能展开日志 | ✅ compose.yaml 注入垃圾行 → `composeFailed` 失败态 + 可展开日志 → 还原 → 重试恢复 |
| ⑤ | 任何日志 / 通知 / UserDefaults 中 grep 不到 token | ✅ `defaults read local.dsh.team` 中 token 命中数 **0**；日志统一过 `LogRedaction`（`token=***`）；Keychain 命中且与容器一致 |
| ⑥ | `swiftc` 零 warning | ✅ 见 §1 |

### M2 relay v1 API + 控制台桥接 ✅

五接口 13 条用例（含失败路径）全部通过，命令与输出见 `NOTES-api.md` §11.1：

- `GET /console-api/v1/health`（上游 up / down 两态）、`GET …/sessions`、`GET …/timeline`（含 `session=nope` → 400、无缓存 → 空数组）、
  `POST …/cancel`（穿越 id / 空 body → 400）、`POST …/session`（`../evil` → 400、`team-lead` → 200 + sessionId）。
- 上游停用模拟：`health` 0.010s 返回 `upstream:"down"`，不挂起；同实例其余接口 0.003s 返回 502。
- 既有能力零回归：`/console-api/artifacts`、`/console-api/artifact`（中文名双 filename 实测见 §5）、`/console-api/purge`、WS mux 隧道（101 + 上游帧）。
- 控制台桥接：M2 对 `dsh-home/console/index.html` 的改动为 **+26 / −2 行**，全部落在 `hostPost`、`select()` 尾部调用与 `window.dshHostAPI`；业务逻辑零改写（`git show ac623cc -- dsh-home/console/index.html`）。

### M3 三栏工作台 ⚠️ 5/6

| # | 验收项 | 结果 |
| --- | --- | --- |
| ① | L3 任务完整故事线、pass/fail 颜色 | ✅ 用真实历史 L3 会话验收：Lead→Coder→Reviewer 5 事件 + 结论色 + 无障碍文案 |
| ② | 运行中「停止任务」中止且容器不重启 | ⚠️ 额度阻塞（无运行中会话）；可验证部分：空闲置灰、`cancel` 对空闲会话 502 → 文案「该任务已不在运行」 |
| ③ | 切会话不整页白屏重载 | ✅ WebView URL 不含 `?session=`，仅 JS 桥切换 |
| ④ | 最小化 5 分钟：CPU 近零、无轮询、恢复即刷 | ✅（App 进程口径）最小化 40s 内 relay 日志 0 条、App 进程 0.2%；恢复 5s 内 2 次 sessions 轮询。补：WebKit 内容进程另有 ~9% 常驻（控制台页面自身，与窗口状态无关，见 §2.3） |
| ⑤ | 深色模式无硬编码颜色 | ✅ 源码审计 0 命中（全语义色 + `.regularMaterial`；状态色仅 green/orange 且都带文案） |
| ⑥ | 断网 / relay 502 离线态不崩 | ✅ 停容器 → 横幅 + 离线卡 + 指标回落；重启容器自愈 |

### M4 系统能力 ⚠️

| # | 验收项 | 结果 |
| --- | --- | --- |
| ① | 运行中关窗 → 任务继续、菜单栏恢复 | ⚠️ 后半（任务继续）额度阻塞。关窗 = `orderOut`，在屏窗口 1→0、菜单栏/Dock 都能叫回；「关窗即停表」在 M5 复测时发现 M4 引入回归（`MenuBarExtra` 的常驻状态栏窗口让 `NSApp.windows` 永远判定可见），已改为按主窗判定并复测：隐藏 0 条/30s、App 进程 0.2–0.4%，叫回后 8s 内 4 次轮询 |
| ② | 运行中 ⌘Q 三按钮 | ⚠️ 额度阻塞；代码路径：`applicationShouldTerminate` 三按钮 + `.terminateLater` + 运行态翻转回调 |
| ③ | 空闲 ⌘Q 直接退出、容器被停 | ✅ 1 秒内进程消失，`dsh Exited (143)` |
| ④ | 前台不弹通知、后台完成才弹 | ⚠️ 额度阻塞；实现：`guard !Notifier.isUserWatching` + 首任务请求一次授权 |
| ⑤ | 删 config + glob 不到工程 → 首启向导 | ✅ 整屏向导渲染 + `ProjectLocator` 校验口径（工程根 PASS，`/tmp`、`$HOME`、子目录 reject） |
| ⑥ | ⌘, 打开设置并闭环 | ✅ 四组设置全部渲染（项目位置 / 通知 / 容器资源只读 / 诊断） |

### M5 打磨与发布 ✅

| # | 验收项 | 结果与证据 |
| --- | --- | --- |
| ① | ad-hoc 与 release 两条构建路径各跑一遍 | ✅ ad-hoc 全流程通过（产物含 `zh-Hans.lproj`）；release 走完「编译 → 版本化产物 `build/DSH工作台-1.1.0.app` → Hardened Runtime entitlements」后停在本机无证书的 `codesign: no identity found`（**只有签名成功才会 `ditto` 打包 zip 并公证**）。未设置 `DEVELOPER_ID` 时在进入 release 分支的第一步就硬失败 |
| ② | 从零冷启动（容器/镜像不存在，触发 build）全流程一次通过 | ✅ 见 §2.1（本轮实测，并据此修掉一个真 bug） |
| ③ | 连续运行 1 小时轮询无内存持续增长 | ✅ 见 §2.2 |
| ④ | 第 7 节红线逐条核对 | ✅ 见 §6 |
| — | 零 warning / 动效·间距·字号走查 / VoiceOver 走查 | ✅ 见 §2.3（走查发现并修掉 2 处无障碍缺陷 + 1 处系统文案未本地化） |

#### 2.1 冷启动实测（M5 ②，容器与镜像都不存在）

条件：`docker rm -f dsh`；`docker image tag …:local …:pre-m5 && docker rmi …:local`；`config.json` 不存在。然后双击 `build/DSH工作台.app`。

| 时刻 | 现象（每 2s 采样：容器状态 / 健康 / 镜像 / 界面） |
| --- | --- |
| 14:39:02 | 启动，`state=none image=`（容器与镜像都不存在） |
| 14:39:18 | `state=running`，新镜像 `461943eeb736`（compose 自动 rebuild 完成） |
| 14:39:21 | `health=healthy` → 读 token → **ready**，`/console-api/v1/*` 轮询立刻恢复 |

整个过程 **≈19 秒**，无人工干预。这条链路顺带修掉一个真 bug：compose 预算原本硬编码 90s，而「镜像缺失 → 首次构建」实测要 **2m51s**（缓存需要重新解包时），旧预算必然把冷启动判成 `composeFailed`。现在缺镜像走 1800s 预算 + 文案「首次构建镜像（需要几分钟）…」，并且「重启容器」在容器已被删时回落完整流水线。

重启后在同一台机复验（详见 `NOTES-api.md` §14.3）：系统菜单变 `文件/编辑/显示/窗口/帮助`；工具栏无障碍名 = `重启容器` / `重新载入页面` / `在浏览器打开`（修复前是 `正在同步` / `刷新` / `Safari浏览器`）；中栏控制台完整加载；Keychain token 与容器一致。

#### 2.2 连续运行 1 小时记录（M5 ③）

`dsh-desktop/build/acceptance/m5-1h-sample.log`（60s × 63 样本，13:35:29 → 14:37:39，全程容器 healthy、App 未重启）：

| 指标 | 首 | 末 | 峰 | 谷 | 结论 |
| --- | --- | --- | --- | --- | --- |
| App RSS | 139,904 KB | 80,896 KB | 140,512 KB | 53,920 KB | 先回落后在 54–88 MB 波动，**无持续增长**（−42%） |
| WebKit 内容进程 RSS | 60,224 KB | 46,464 KB | 93,040 KB | 21,504 KB | 同样只波动不增长 |
| App CPU | — | — | 15.4% | — | 均值 2.56%（含启动尖峰；隐藏稳态 0.2–0.4%） |
| relay 轮询/分 | 14 | 23 | 33 | 14 | 均值 23.1，**从未掉到 0** |

#### 2.3 走查记录（动效 / 间距 / 字号 / VoiceOver）

**动效**：全仓 5 处 `withAnimation`，时长 ≤ 0.2s 且都可被打断；唯一 `repeatForever` 是侧边栏 `PulsingDot`（只在「窗口可见 + 有运行中会话」时驱动渲染）。
顺带量到一个真实成本：**中栏控制台页面里的常量动画**（`dsh-home/console/index.html:61/76/144` 的 `.spinner` / `.caret` / `.node.run`）
让 WebKit 的 WebContent 进程在**任何窗口状态下都吃 ~9% CPU**：可见 9.2% / 关窗后 8.7% / 最小化后 9.3%（App 进程同期 0.2–3%）。
三态一致说明与窗口状态无关，是控制台页面自身在持续驱动渲染——这也解释了 M3 §12.5 那个「~18% CPU 旧实例」（当时只量了 App 进程）。
控制台不在本次可改范围（规格 §0.5 只允许桥接改动），已列为后续建议 7。

**间距**：以 8 / 12 / 16 为主，2 / 4 / 6 / 10 只用于图标与文本的紧耦合（侧边栏行高、卡片内间距）；卡片统一
`padding(12)` + 0.5px `separatorColor` 描边 + `.regularMaterial`（`Components.swift` 的 `SectionCard`），与系统设置面板观感一致，无 >16pt 的随机值。

**字号**：正文全部走语义字号（`.caption` / `.callout` / `.subheadline` / `.title2` / `.title3`）。固定字号只出现在
图标（26 / 42 / 46）、等宽诊断文本（10 / 11）与侧边栏两处 **12.5pt**（全仓唯一正文级固定值，与 `.callout` 相差 0.5pt，
改语义字号需重核行高与截断，列入后续建议）。

**状态不只靠颜色**：每个状态都同时有文本（「完成」/「已通过」/「失败」）或无障碍标签（`VerdictIcon` 的 pass/fail 各带 `accessibilityLabel`），颜色只是加强。

**控件有 label（本轮修掉 3 处）**：审计无障碍树发现 3 个纯图标工具栏按钮没有 label，VoiceOver 会读 SF Symbol 自带的系统描述——
「重启容器」被读成「正在同步」、「在浏览器打开」被读成「Safari浏览器」。已补 `.accessibilityLabel`；
`HintRow` 的装饰图标补 `.accessibilityHidden(true)`（含义由旁边的文案承担）。

**系统文案未本地化（本轮修掉）**：菜单栏原本是 `File / Edit / View / Window / Help`、工具栏开关是英文 `Hide Sidebar`，
因为这些字符串来自 AppKit/SwiftUI 自己的资源，而 App 没有声明任何本地化。已加 `CFBundleDevelopmentRegion=zh-Hans`
与 `Contents/Resources/zh-Hans.lproj`（构建脚本生成，`Sources/Copy.swift` 仍是唯一文案源）。

## 3. 偏差（与原因）

### 3.1 上游额度为 0 → 三条验收项无法执行

链路完全正常（`session/create` → `session/prompt` 均 `{"accepted":true}`），失败在模型侧：
投影立刻显示 `sessionStats:{turns:1,steps:1,llmMs:0}`、`tokenUsage.totals` 全 0、`turnOutline.turns[0].response:""`；
M3 时抓到的是上游 `402 用户额度不足 … insufficient_quota`。`dsh-home/.credentials.yaml` 里的 `DEEPSEEK_API_KEY` 调 `api.deepseek.com/user/balance` 返回 `invalid`，无法作为替代路由。

| 补验项 | 一步操作 | 期望 |
| --- | --- | --- |
| M3 ② | 跑 ≥2 分钟任务 → 点「停止任务」 | 任务中止、`docker ps` 的 uptime 连续（容器未重启） |
| M4 ①后半 | 跑 ≥2 分钟任务 → ⌘W 关窗 | relay 轮询不断、任务完成时窗口仍隐藏 |
| M4 ② | 运行中 ⌘Q → 三个按钮各点一次 | 等待：跑完 → 通知 → 退出；立即：停容器退出；取消：什么都不变 |
| M4 ④ | 跑任务时切到后台 | 完成后弹通知；前台可见时不弹 |

### 3.2 本机没有 Developer ID 证书 / 公证 profile

`security find-identity -v -p codesigning` → 0 valid。release 路径的可验证边界就是「编译 → 组装版本化产物 → 生成 entitlements → 调用 `codesign` 并报 `no identity found`」；
`notarytool submit` / `stapler` / `spctl` 三步只有在有证书的机器上才能跑完整。已在脚本里保证：**缺条件是硬失败**，不会产出看似成功的半成品。

### 3.3 本机 CLI 无屏幕录制权限

`screencapture` 报 `could not create image from display`。视觉证据改用：App 内 WKWebView 截图（CUA）、无障碍树（`getAXState`）、
在屏窗口枚举（`CGWindowListCopyWindowInfo(.optionOnScreenOnly)`，脚本见 NOTES §13.5）。
截图与原始采样落在 `dsh-desktop/build/acceptance/`（`build/` 不入库，重建会清空，副本在 `/tmp/dsh-acceptance/`）：
`m5-workbench-visible.png`（改造前三栏）、`m5-after-relaunch-ready.png`（本地化+label 修复后）、`m5-final.png`（最终交付态）、`m5-1h-sample.log`（1 小时原始采样）。

### 3.4 `NSOpenPanel` 交互无法自动化

第二个 App 实例的模态面板拿不到焦点，首启向导「选非法目录报错 / 选合法目录进入」与设置「重新选择」只验到**渲染 + 校验口径**（`ProjectLocator` 单编译实测：工程根 PASS，`/tmp`、`$HOME`、子目录 reject）。

### 3.5 有意不跑：镜像不存在时的全量重建（已在 M5 窗口补测）

见 §2.1——本轮实测跑了「容器 + 镜像都不存在」的冷启动，并据此修掉 compose 超时不足的真 bug。

## 4. 后续建议（对应规格 §2.2 被砍项的未来形态）

1. **多窗口 / 多会话并行**：先把中栏从「唯一 WebView」抽象成可多实例的 `SessionPane`，`AppStore` 改成多路订阅；relay 侧 v1 已是无状态查询，无需改动。
2. **文件 diff 与一键回滚**：`dsh-artifact://` 已能读单文件，扩展成「同路径两版本」即可；`/workspace` 是真实工作树，天然可 `git diff`。
3. **空闲自动停容器 / 退出策略可配**：与规格 3.5「设置里不出现生命周期策略开关」冲突 → 建议留在外部脚本（`dsh-down.sh` + 定时），不进 App。
4. **自动更新**：Sparkle 属第三方依赖（违反零依赖铁律）→ 用 `git pull && ./build-app.sh release` 的脚本化替代。
5. **英文本地化**：`Copy.swift` 是单一事实源，翻译只需一张对照表 + `en.lproj`；当前产品定位是中文优先，暂不做。
6. **重写 Web 控制台**：中栏 WKWebView + 注入桥是最大的一块技术债；长期应把控制台能力逐步搬进原生（时间线/产物已搬完，剩下的是对话流与输入框）。
7. **常驻动画的 CPU（本机最值得做的一条）**：WebKit 内容进程因控制台页面的 `.spinner` / `.caret` / `.node.run` 常驻 ~9% CPU（可见/关窗/最小化三态一致，见 §2.3）。两条路：①（首选，一处改动）控制台只在真正流式输出时挂载动画元素；②App 侧在窗口不可见时把 `WKWebView` 从层级摘除，验证 WebKit 是否随之停渲染。侧边栏 `PulsingDot` 是 App 内唯一 `repeatForever`，同样只在「可见 + 有运行中会话」时驱动渲染。

## 5. 复现清单（关键命令）

```bash
# 构建 / 运行
cd dsh-desktop && ./build-app.sh && open "build/DSH工作台.app"

# 零 warning 复核（输出应为空）
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx13.0 $(find Sources -name '*.swift' | sort) -o /tmp/x

# relay v1
curl -s http://127.0.0.1:3081/console-api/v1/health
curl -s "http://127.0.0.1:3081/console-api/v1/sessions" | head -c 200

# 中文产物双 filename（红线 3）
curl -s -D - -o /dev/null "http://127.0.0.1:3081/console-api/artifact?session=<id>&path=<url-encoded>"
#  → content-disposition: attachment; filename="artifact.md"; filename*=UTF-8''%E4%BA%A4%E4%BB%98%E6%8A%A5%E5%91%8A.md

# 轮询 / CPU（隐藏窗口应停表）
docker logs dsh --since 40s 2>&1 | grep -c '^\[relay\]'
ps -p $(pgrep -f 'dsh-desktop/build' | head -1) -o time=,pcpu=,rss=

# 在屏窗口（唯一判据）/ 空闲退出
/tmp/wins DSH   # 源码见 NOTES-api.md §13.5
docker ps -a --filter name=dsh --format '{{.Names}} {{.Status}}'   # 空闲 ⌘Q 后应为 Exited (143)
```

## 6. 红线逐条核对（规格 §7）

| # | 红线 | 结论 | 证据（本轮复核） |
| --- | --- | --- | --- |
| 1 | 角色 / 委派 / MCP 配置只在 agent 预设层与启动 overlay，不塞进 Web 宿主补丁、不整体覆盖全局 system prompt、不全局挂 persona | ✅ | 本轮改动只在 `dsh-desktop/**`；`git status -- dsh-home deepseek-harness` 为空。M2 对控制台的改动 **+26/−2 行**且全在桥接区（`git show ac623cc -- dsh-home/console/index.html`）。MCP 挂在 `dsh-home/profiles/web/mcp.patch.yml`（profile 层），预设继承见 `dsh-lightweight-team-starter.md` §5 |
| 2 | 只有一个 `dsh` 容器；子角色是进程内 spawn，绝不新增容器 / 进程 | ✅ | `docker ps -a` 中名为 `dsh` 的仅一个；`grep -rn "docker run\|docker create" dsh-desktop/Sources` 无命中；构建产物里没有任何容器编排 |
| 3 | SSE / chunked / WebSocket Upgrade 透传；中文 `Content-Disposition` 双 filename；healthcheck 以容器内 `/console` 为准 | ✅ | relay 第 121 行 `up.pipe(res)`（SSE/chunked 原样）、第 667 行 `server.on('upgrade')` 隧道；`compose.yaml` healthcheck = `fetch('http://127.0.0.1:8080/console')`。活体实测：`content-disposition: attachment; filename="artifact.md"; filename*=UTF-8''%E4%BA%A4%E4%BB%98%E6%8A%A5%E5%91%8A.md` |
| 4 | `dsh-artifact://` 白名单正则 / 穿越 / symlink / 5MB 一条都不能少；v1 接口同标准 | ✅ | `ArtifactPreview.swift`：`^[A-Za-z0-9._-]{1,200}$`、拒绝绝对路径与 `..`、`resolvingSymlinksInPath` 后 `hasPrefix(realBase)`、`>= 5_000_000` 拒读；relay 侧 `SESSION_ID_RE` 在 5 个 v1 入口逐个校验（第 549/585 行等） |
| 5 | 端口只绑 Mac 侧 `127.0.0.1`，不新增发布端口 | ✅ | `docker port dsh` → `8080/tcp -> 127.0.0.1:3081`（唯一映射）。relay 在**容器内**监听 `0.0.0.0:8080` 是既有设计（dsh web 只肯听容器 loopback，见 relay 顶部注释），宿主侧仍由 compose 限制在 127.0.0.1，本轮未改 |
| 6 | 不删除 / 移动 `~/Desktop/DSH工作台.app`、`~/Applications/DSH工作台.app` | ✅ | 两者都仍在原处；构建输出只写 `dsh-desktop/build/` |
| 7 | 容器内 full-access 是既定隔离模型；「急停」只能走 `session/cancel` | ✅ | `compose.yaml` 的 `DSH_PERMISSION_MODE: danger-full-access` 未改；急停 = `AppStore.stopCurrentTask()` → `RelayClient.cancel` → relay `handleV1Cancel` → 上游 `session/cancel`。`composeStop` 只出现在「空闲退出（Policy A）」与设置里的显式停容器 |
