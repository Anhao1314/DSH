# DeepSeek Harness（DSH）适用项目清单

> 检索时间：2026-09-09（GitHub）。DSH 基于 Cordis「万物皆插件」，官方插件发现主题为 **`topic:dsh-plugin`**，安装用 `dsh plugin …` / 内置市场。
> star 为检索时快照；该生态很新（绝大多数项目 2026-08 后才建立），数字变化快。已剔除同名无关仓库（Dshell 取证框架、DSharpPlus Discord 库、DsHidMini 手柄驱动等）。
> 形态分三类：**原生插件**（直接装进 DSH）、**Skill/MCP**（通过技能或 MCP 标准接入）、**跨引擎**（把 DSH 作为支持的引擎之一）。

## 0. 本体与生态导航
| 项目 | star | 作用 |
|---|---|---|
| [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) | 216.5k | 官方本体，Cordis 插件架构，自带 web/tui/acp/sdk 多 profile |
| [awesome-dsh-plugin/awesome-dsh-plugin](https://github.com/awesome-dsh-plugin/awesome-dsh-plugin) | 15.0k | 最大社区精选清单，数百个 Web UI 插件的全量索引（找长尾先看它） |
| [0xsline/awesome-deepseek-harness](https://github.com/0xsline/awesome-deepseek-harness) | 1.0k | 插件/工具/基础设施生态精选 |
| [Dominic789654/awesome-deepseek-harness](https://github.com/Dominic789654/awesome-deepseek-harness) | 233 | 按 插件/Skills/MCP/patch/profile/编排/UI 分类 |
| [libukai/awesome-deepseek-harness](https://github.com/libukai/awesome-deepseek-harness) | 254 | 中文上手指南+精选 |
| [dsh-market/dsh-market](https://github.com/dsh-market/dsh-market) | 3.5k | DSH 内可视化插件市场，浏览/搜索/一键安装 |
| [LivXue/dsh-plugin-shop](https://github.com/LivXue/dsh-plugin-shop) | 432 | 每日更新、发布前审核的插件商店 |
| [AdamPlatin123/dsh-plugin-radar](https://github.com/AdamPlatin123/dsh-plugin-radar) | 1.5k | 可自部署「生态雷达」，自动发现上万候选并做运行级实测 |
| [zhu1090093659/dsh-web](https://github.com/zhu1090093659/dsh-web) | 7.2k | Web 插件聚合生态 / 创意工坊分发 |

## 1. 客户端外壳：桌面 / 终端 / 编辑器 / 移动端
**桌面端**
| 项目 | star | 作用 |
|---|---|---|
| [anywhere-labs/dsh-desktop](https://github.com/anywhere-labs/dsh-desktop) | 24.6k | 现代化桌面端，「桌面本身也是插件」 |
| [dataelement/dsh-desktop](https://github.com/dataelement/dsh-desktop) | 4.6k | DSHDesktop 桌面版 |
| [zouyuxuan122/DSH-Desktop-EAC](https://github.com/zouyuxuan122/DSH-Desktop-EAC) | 1.6k | Electron，内置完整 dsh-CLI 内核、10 套主题 |
| [dsh-tauri-desk/deepseek-harness-desktop](https://github.com/dsh-tauri-desk/deepseek-harness-desktop) | 1.8k | Tauri 5MB 安装包，三平台、预置插件、免环境配置 |
| [myYangyunfan/dsh_desktop](https://github.com/myYangyunfan/dsh_desktop) | 643 | Windows 桌面客户端，内置 Node+dsh CLI |
| [whitelonng/dshcode](https://github.com/whitelonng/dshcode) | 714 | Electron 一键桌面伴侣（mac/win） |
| [lencx/Minke](https://github.com/lencx/Minke) | 628 | DSH Desktop（Tauri） |
| [vibeinging/dsh-desktop](https://github.com/vibeinging/dsh-desktop) | 584 | 本地工作区：会话/项目/文件/联网研究/办公产物 |
| [xiincs/deepseek-harness-desktop](https://github.com/xiincs/deepseek-harness-desktop) | 56 | Tauri2 内置 Node、托盘常驻、自动更新 |

**终端 TUI**
| 项目 | star | 作用 |
|---|---|---|
| [ccch1mneyyy/dsh-TUI](https://github.com/ccch1mneyyy/dsh-TUI) | 2.9k | Claude Code 风终端：鲸鱼顶栏/流式思考/双击 Esc 回滚/上下文进度+TPS |
| [kouyichi/dsh-tui-app](https://github.com/kouyichi/dsh-tui-app) | — | Ink 终端聊天：工具卡、jobs、全文检索、轨迹回放、多会话、A2A 派发 |
| [Kirkice/dsh-makimaTUI](https://github.com/Kirkice/dsh-makimaTUI) | — | 终端工作台：流式/工具执行/会话/provider 管理/图片输入 |

**编辑器 / 移动 / 远程**
| 项目 | star | 作用 |
|---|---|---|
| [skymecode/deepseek-harness-for-vscode](https://github.com/skymecode/deepseek-harness-for-vscode) | 146 | 原生 VSCode 扩展：会话管理/流式 Markdown/斜杠命令/插件中心，免起 WebUI |
| [shaobeichen/dsh-pocket](https://github.com/shaobeichen/dsh-pocket) | 1.0k | 手机扫码同屏访问电脑端 dsh（局域网+公网隧道） |
| [yukiykchen/deepseek-harness-mobile](https://github.com/yukiykchen/deepseek-harness-mobile) | 26 | 安卓 App：远程连 dsh web 或手机本地起 agent |

## 2. 多智能体 / 编排 / 工作流
| 项目 | star | 作用 |
|---|---|---|
| [ruvnet/ruflo](https://github.com/ruvnet/ruflo) | 71.7k | agent meta-harness：多角色 swarm、自治工作流、自适应记忆/RAG（跨引擎含 DSH） |
| [yjh051108/dsh-routing-suite](https://github.com/yjh051108/dsh-routing-suite) | 7.1k | 运行时注入器 + 任务感知「推理模式路由器」预设 |
| [Q00/ouroboros](https://github.com/Q00/ouroboros) | 5.8k | 自进化 Agent OS：面试门控+分阶段评估+预算化演化循环，14 运行时 |
| [huangruiteng/loopx](https://github.com/huangruiteng/loopx) | 5.7k | 长周期任务控制面，跨 harness 治理（含 DSH） |
| [chuspeeism/dashi-taskboard](https://github.com/chuspeeism/dashi-taskboard) | 3.0k | 可嵌入任务面板（Codex / DSH） |
| [NanmiCoder/dsh-agent-teams](https://github.com/NanmiCoder/dsh-agent-teams) | 1.5k | 原生 AgentTeams：持久 roster、任务板、mailbox 协作 |
| [xuanyuanzhifeng/dsh-plugin-agent-workflow](https://github.com/xuanyuanzhifeng/dsh-plugin-agent-workflow) | 149 | Agent 工作流插件 |
| [lihang-lh/dsh-task-panel](https://github.com/lihang-lh/dsh-task-panel) | — | 侧栏任务面板：plan/develop/review 子代理 + 面板内验收 |

## 3. 记忆 / RAG / 知识库
| 项目 | star | 作用 |
|---|---|---|
| [volcengine/OpenViking](https://github.com/volcengine/OpenViking) | 36.1k | 自进化上下文数据库，统一 记忆+RAG+Skills |
| [EverMind-AI/EverOS](https://github.com/EverMind-AI/EverOS) | 12.8k | 可移植记忆层，本地优先、Markdown、跨应用自进化 |
| [MemTensor/MemOS](https://github.com/MemTensor/MemOS) | 11.2k | 自进化记忆 OS：超持久记忆/混合检索/技能复用，省 token |
| [plastic-labs/honcho](https://github.com/plastic-labs/honcho) | 7.1k | 构建有状态 agent 的记忆库 |
| [Tencent/WeKnora](https://github.com/Tencent/WeKnora) | 21.9k | 文档→可查询 RAG、推理 agent、自维护 Wiki |
| [agentscope-ai/ReMe](https://github.com/agentscope-ai/ReMe) | 3.4k | 记忆管理套件（Remember/Refine Me） |
| [zilliztech/memsearch](https://github.com/zilliztech/memsearch) | 2.6k | Markdown+Milvus 的统一持久记忆层 |
| [syncable-dev/memtrace-public](https://github.com/syncable-dev/memtrace-public) | 469 | 双时态图「结构记忆」，MCP 原生、零 LLM 调用 |
| [mnemon-dev/mnemon](https://github.com/mnemon-dev/mnemon) | 566 | 图召回跨会话记忆，单二进制、LLM 监督 |
| [Swd146296/dsh-memos-bridge](https://github.com/Swd146296/dsh-memos-bridge) | — | 经 MCP 把 MemOS 桥成 `mcp__memos__*` 工具 |

## 4. 能力扩展：视觉 / 浏览器 / 电脑操控 / IM / 办公 / 设计
**给纯文本模型外挂视觉**
| 项目 | star | 作用 |
|---|---|---|
| [tt-a1i/archify](https://github.com/tt-a1i/archify) | 55.0k | 架构/时序/数据流/生命周期图 skill，自包含 HTML 动效导出 |
| [liustack/modlens](https://github.com/liustack/modlens) | 3.9k | 首个 DSH 视觉插件：贴图→结构化 JSON（OCR/版面/语义） |
| [ysr666/dsh-vision-router](https://github.com/ysr666/dsh-vision-router) | 1.1k | 内置免费视觉链+像素级工具（grounding/裁剪/像素diff/OCR/截图），免 Python |
| [Anionex/dsh-vision-toolkit](https://github.com/Anionex/dsh-vision-toolkit) | 865 | DSH 原生视觉工具箱：多图问答/长截图 OCR/前端 UI 还原/GUI 自动化 |

**浏览器与电脑操控**
| 项目 | star | 作用 |
|---|---|---|
| [Tencent/BrowserSkill](https://github.com/Tencent/BrowserSkill) | 1.9k | 复用你已登录的真实浏览器做自动化，CLI+扩展，跨 agent |
| [strukto-ai/mirage](https://github.com/strukto-ai/mirage) | 3.6k | AI agent 虚拟终端 / 虚拟文件系统（沙箱化执行） |
| [Lum1104/dsh-browser](https://github.com/Lum1104/dsh-browser) | 601 | Chrome 侧边栏扩展，让 DSH 直接操控浏览器（不依赖视觉） |
| [Yu-tao-Li/dsh-computer-use-win](https://github.com/Yu-tao-Li/dsh-computer-use-win) | 11 | Windows 电脑操控：MCP stdio + PowerShell UIA，22 个桌面工具 |

**IM / 办公 / 设计 / 领域**
| 项目 | star | 作用 |
|---|---|---|
| [nexu-io/open-design](https://github.com/nexu-io/open-design) | 95.0k | 设计插件：原型/落地页/仪表盘/幻灯片/图像视频，导出 HTML/PDF/PPTX/MP4 |
| [xmanrui/dsh-im](https://github.com/xmanrui/dsh-im) | 1.2k | 9 平台 IM 机器人接入：飞书/微信/钉钉/企微/QQ/Slack/TG/Discord/WhatsApp |
| [sunchaokun/PPT-Design-Skill](https://github.com/sunchaokun/PPT-Design-Skill) | 1.2k | 专业 PPT 设计 skill，产出可编辑 PPTX |
| [Jesse-njx/dsh-cowork](https://github.com/Jesse-njx/dsh-cowork) | — | 办公文档读写：xlsx/pdf/docx/pptx/ipynb，工具+MCP+CLI |
| [AATINF/pdf-extractor-dsh-plugin](https://github.com/AATINF/pdf-extractor-dsh-plugin) | — | 纯本地 PDF 提取/拆分/合并/旋转，提供 Skill/MCP/Cordis 三种接入 |
| [Smalldy/godot-bridge](https://github.com/Smalldy/godot-bridge) | 23 | 用原生工具驱动运行中的 Godot 4 游戏（替代 godot-mcp） |
| [zhuyifang/tonghuasun-agent](https://github.com/zhuyifang/tonghuasun-agent) | 184 | 在 agent 内查同花顺行情/K线/持仓/LV2 委托与逐笔 |
| [helibeiqi/dsh-quant-data-mcp](https://github.com/helibeiqi/dsh-quant-data-mcp) | 2 | A 股数据 MCP（免 key、零依赖 stdio 模板） |
| 语音系列 | — | `GooDAnDReaDY/dsh-tts`、`haoku123/dsh-voice`、`FuzzySoul/dsh-chatvoice`、`qishuilalala/dsh-voice-mode` 等：TTS 朗读/语音输入/全双工，多数本地免 key |

## 5. MCP / ACP 协议接入
**DSH 作为 MCP 宿主：管理面板与连接器**
| 项目 | star | 作用 |
|---|---|---|
| [PerryLink/dsh-mcp-panel](https://github.com/PerryLink/dsh-mcp-panel) | 53 | 官方 MCP 客户端的管理台：`/mcp` 健康诊断、管线试调用、服务端 CRUD（带审批/备份） |
| [duhu2000/dsh-mcp-connector](https://github.com/duhu2000/dsh-mcp-connector) | 18 | 100+ MCP 连接器市场，OAuth2 PKCE/APIKey、stdio/HTTP、mcpServers JSON 导入 |
| [hyqhyq3/dsh-mcp-manager](https://github.com/hyqhyq3/dsh-mcp-manager) | 15 | MCP 服务端管理，OAuth 动态注册，工具注册为 `mcp__<名>__*` |
| [xxxyz/DeepSeekHarness-MCP-Manager](https://github.com/xxxyz/DeepSeekHarness-MCP-Manager) | 12 | 持久化 MCP 管理：设置 UI + HTTP API + `mcp_manager_*` 模型工具 |
| [KYinCode/dsh-project-mcp-bridge](https://github.com/KYinCode/dsh-project-mcp-bridge) | 2 | 项目级：往项目放 `.dsh/mcp.json` 即自动加载，支持热更 |
| [6pofx/dsh-tool-explorer](https://github.com/6pofx/dsh-tool-explorer) | 1 | 技能+MCP 一体控制台，GitHub 多选批量装技能、可恢复删除 |
| [felix-lj-ct/dsh-mcp-workspace-scope](https://github.com/felix-lj-ct/dsh-mcp-workspace-scope) | 2 | 按工作区目录限定 MCP 工具注入范围 |

**反向：把 DSH 暴露为服务端**
| 项目 | star | 作用 |
|---|---|---|
| [liiiubai/dsh-mcp-bridge](https://github.com/liiiubai/dsh-mcp-bridge) | 1 | 把 DSH 工具暴露为标准 MCP server（streamable HTTP），供 Claude Code/Codex 反向驱动 |
| [maojindao55/deepseek-harness-acp](https://github.com/maojindao55/deepseek-harness-acp) | 5 | 独立 ACP server：流式/推理轨迹/MCP 工具/会话恢复（可接 Zed 等 ACP 编辑器） |

## 6. 配置预设 / 上下文工程 / 代码质量
| 项目 | star | 作用 |
|---|---|---|
| [xiaobright/dsh-anchored-standard](https://github.com/xiaobright/dsh-anchored-standard) | 3.8k | 两阶段预设：Minimal 对齐引导 → 完整 Standard 工具集 |
| [bowenliang123/dsh-context](https://github.com/bowenliang123/dsh-context) | 1.3k | 上下文可视化：面板/浏览器/命令，透视组成、演进、压缩、剪枝 |
| [hyhmrright/brooks-lint](https://github.com/hyhmrright/brooks-lint) | 1.5k | 基于 12 本工程经典的 AI 代码审查，6 种模式+全量自动修 |
| [GanyuanRan/Aegis](https://github.com/GanyuanRan/Aegis) | 1.2k | 让 agent 有架构意识：基线优先、证据核验、长任务漂移检查 |
| [songoao25/dsh-auto-compact](https://github.com/songoao25/dsh-auto-compact) | — | 调优自动压缩阈值/保留预算/分模型策略，幂等可回滚 |
| [lemonorangeapple/dsh-effort-switcher](https://github.com/lemonorangeapple/dsh-effort-switcher) | — | Codex 风推理强度（effort）切换器 |
| [HenryZ838978/deepseek-harness](https://github.com/HenryZ838978/deepseek-harness) | 49 | 协议层 witness 一致性校验栈 + `dsh doctor` 探针 |

## 7. Web UI 增强（长尾，列代表；完整见 awesome-dsh-plugin）
| 方向 | 代表项目 | 作用 |
|---|---|---|
| 侧边栏/工作台底座 | [omdsh-dev/DSH-better-sidebar](https://github.com/omdsh-dev/DSH-better-sidebar)（3.4k）、[Aisland-SJL/dsh-worktable](https://github.com/Aisland-SJL/dsh-worktable)（543） | 可三方注册的侧边栏：文件编辑/终端/侧聊/Git/子代理；分屏工作台 |
| 文件/diff/预览 | [WindyPro-rourou/dsh-code-studio](https://github.com/WindyPro-rourou/dsh-code-studio)、[left0ver/dsh-file-review](https://github.com/left0ver/dsh-file-review)、[liguobao/dsh-file-viewer](https://github.com/liguobao/dsh-file-viewer)、[lee259/dsh-workbench](https://github.com/lee259/dsh-workbench) | 实时逐行 diff、一键还原、改动审查批注、多格式文件预览 |
| 输入增强 | [FSMargoo/dsh-at-file](https://github.com/FSMargoo/dsh-at-file)（507）、[WhitePlusMS/dsh-input-plus](https://github.com/WhitePlusMS/dsh-input-plus)、`*/dsh-prompt-optimizer`（LCQ-1024/winditer/wmengxiang/LHF198） | `@文件`路径提及、历史提示复用、发送前优化/润色提示词 |
| 生成式 UI | [lhuans/dsh-genui](https://github.com/lhuans/dsh-genui)、[KLRSL/dsh-fuse](https://github.com/KLRSL/dsh-fuse)、[pengyue-polaron/deepseek-harness-genui](https://github.com/pengyue-polaron/deepseek-harness-genui) | 在回复里内联渲染图表/表单/计算器/小应用，动作回流对话 |
| 导航/折叠/流式 | dsh-turn-fold、dsh-codex-timeline、dsh-chat-outline、dsh-smooth-stream、dsh-conversation-density-map | 步骤折叠、轮次导航轨、会话大纲、平滑流式渲染 |
| 技能管理 | [lcthe/dsh-skills-hub](https://github.com/lcthe/dsh-skills-hub) | 浏览/启停技能，从 Codex/Claude/ZCode/WorkBuddy 导入 |
| 皮肤/桌宠/趣味 | [Small-tailqwq/dsh-deep-whale](https://github.com/Small-tailqwq/dsh-deep-whale)（2.0k）、[MeteorNOX/DeepSeek-Balance-Whale-Widget](https://github.com/MeteorNOX/DeepSeek-Balance-Whale-Widget)（1.9k）、[PC2005-cloud/dsh-pet](https://github.com/PC2005-cloud/dsh-pet)、[Nagi-ovo/dsh-ads](https://github.com/Nagi-ovo/dsh-ads) | 鲸鱼娘皮肤、账户余额悬浮鲸、桌面宠物、恶搞门户风 |

## 8. Skills 技能库 / 跨引擎技能
| 项目 | star | 作用 |
|---|---|---|
| [titanwings/distilly](https://github.com/titanwings/distilly) | 24.5k | 把「人的做事方式」蒸馏成可复用 Skill（原同事 Skill） |
| [liyupi/ai-guide](https://github.com/liyupi/ai-guide) | 19.7k | AI 资源/Vibe Coding 零基础教程与导航 |
| [anbeime/skill](https://github.com/anbeime/skill) | 6.4k | 大型技能商店，自动抓取上万 Skills 并分类排序 |
| [foryourhealth111-pixel/Vibe-Skills](https://github.com/foryourhealth111-pixel/Vibe-Skills) | 3.2k | 智能技能路由与工作流编排 |
| [Jesseovo/last30days-skill-cn](https://github.com/Jesseovo/last30days-skill-cn) | 1.8k | 自动检索 8 大平台近 30 天内容并生成研究报告 |

## 9. 多引擎聚合工作台（DSH 作为其中一个引擎）
| 项目 | star | 作用 |
|---|---|---|
| [CherryHQ/cherry-studio](https://github.com/CherryHQ/cherry-studio) | 51.6k | AI 生产力工作室：智能对话+自治 agent+300 助手 |
| [Devin-AXIS/iPolloWork](https://github.com/Devin-AXIS/iPolloWork) | 5.6k | 企业级本地多引擎工作台（Codex/DSH/OpenCode） |
| [YaoApp/yao](https://github.com/YaoApp/yao) | 7.9k | 自托管多 agent/工作区看板，桌面/移动/浏览器/API |
| [zhukunpenglinyutong/desktop-cc-gui](https://github.com/zhukunpenglinyutong/desktop-cc-gui) | 4.2k | Tauri 多引擎编码桌面端（Claude/Codex/Gemini/OpenCode/DSH） |
| [xintaofei/codeg](https://github.com/xintaofei/codeg) | 3.3k | 多 agent 协作工作区，桌面/自托管/Docker |
| [edison7009/EchoBird](https://github.com/edison7009/EchoBird) | 3.2k | 一键安装并在 15+ CLI（含 DSH）间切换 |

## 10. 教程 / 手册 / 源码解读
| 项目 | star | 作用 |
|---|---|---|
| [walkinglabs/learn-harness-engineering](https://github.com/walkinglabs/learn-harness-engineering) | 15.0k | Harness Engineering 从 0 到 1 |
| [Electricitysheep/dsh-handbook](https://github.com/Electricitysheep/dsh-handbook) | 762 | 中文深度手册：安装/插件开发/调优/多 agent 实测（中英 PDF） |
| [sandbaseai/deepseek-harness-handbook](https://github.com/sandbaseai/deepseek-harness-handbook) | 165 | 173 条源证运行时/插件/MCP/沙箱手册 + 74 条资源 |
| [warmsum/deepseek-harness-python-tutorial](https://github.com/warmsum/deepseek-harness-python-tutorial) | 126 | Python 17 章手写 AgentLoop/插件/工具/Session/子代理 |
| [Prism-Shadow/deepseek-harness-book](https://github.com/Prism-Shadow/deepseek-harness-book) | 86 | 《从零开始玩转 DeepSeek Harness》 |

---

## 选型与安装提示
- **先装「市场/导航」**：`dsh-market` 或直接看 `awesome-dsh-plugin`，避免在海量长尾里盲找。
- **三种接入形态**：原生 Cordis 插件（改 UI/交互最贴合）、MCP server（跨工具可复用、最通用）、Skill（纯提示词/流程，零代码）。能力类优先 MCP，界面类才用原生插件。
- **我们这套是 OrbStack 容器**：插件/配置写入挂载的 `dsh-home/`（即容器 `/root/.dsh`），重装容器不丢；但 Web UI 类插件作用于浏览器前端，桌面/TUI 类外壳在容器内无意义，应装在 Mac 主机侧。
- **安全甄别**：生态新、长尾多，安装前看是否原生插件、是否要额外 key/本地 bridge、open issues 与最近更新；`dsh-plugin-radar` 的运行级实测可辅助筛选。
