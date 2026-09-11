# DeepSeek Harness 本机轻量多 Agent 起步方案（阶段 1，已跑通）

> 形态：**单容器、单进程、进程内三角色、推理全上云、状态只落文件、按需启停**。
> 协作：Lead 一次性委派（one-shot）给 Coder / Reviewer，跑顺后再升级持久 AgentTeams。
> 更新：2026-09-09 已修复“子 Agent 无法执行命令（no sandbox backend）”与“默认预设冷启动崩溃”两个问题。
> 更新：2026-09-11 工作台已迁移到 `multi-agent-research/dsh-workbench`；新增 MCP overlay、edge relay 与 `/console` 健康检查，重新验证冷启动和中文 artifact 下载。

## 1. 架构与资源模型

```
Mac（OrbStack，唯一容器 dsh：2 CPU / 2GiB 上限，默认停止、按需启动）
└─ 单个 Node 进程（dsh web，入口 127.0.0.1:3081）
   会话挂载「团队Lead模式」(team-lead) 预设：
   ├─ Lead / Planner   主会话（规划·派发·汇总）
   ├─ delegate_coder     进程内 spawn：实现/改文件/跑命令（effort=low，maxDepth=1）
   └─ delegate_reviewer  进程内 spawn：只读独立复核（effort=high，maxDepth=1）
   状态：$DSH_HOME 的会话 JSONL + AGENTS.md（无数据库进程）
   └─ 推理：三角色全部走云端 TokenDance / deepseek-v4-pro-0813（本机不跑模型）
```

- 角色是同一 Node 进程内的 spawn 协程，**不多开容器/进程**；`maxDepth:1` 保证扁平。
- 等云端回复时本机 CPU≈0，活动内存被 2GiB 封顶；`dsh-down.sh` 停容器后占用归 0。

## 2. 三个角色（唯一事实源：`dsh-home/roster/team-lead.yml`，生成进 team-lead 预设）

| 角色 | 载体 | 档位 | 深度 | 职责 |
|---|---|---|---|---|
| Lead | team-lead 预设主会话（persona 内置） | 跟随默认模型 | 顶层 | 规划、委派、汇总，不亲自实现 |
| Coder | `delegate_coder` | low | 1 | 最小正确改动、跑命令、回报结果 |
| Reviewer | `delegate_reviewer` | high | 1 | 只读检查/测试，给 pass/issues 与证据 |

## 3. 文件清单（项目目录；容器挂载 dsh-home，改完多数热加载，无需重建镜像）

| 文件 | 作用 |
|---|---|
| `orbstack/compose.yaml` | 唯一服务；`cpus=2`、`mem_limit=2g`、`restart:"no"`、端口 3081、挂载 dsh-home；**环境变量 `DSH_PERMISSION_MODE=danger-full-access`** |
| `dsh-home/roster/team-lead.yml` | **唯一事实源**：三个角色的模型/档位/预算/工具白名单/复核口径；改它再跑 `scripts/render-team.mjs --write` |
| `dsh-home/.agent-presets/team-lead/agent.cordis.yml` | **核心**：由内置 standard 预设复制，含 bash/fs/检索；委派角色、压缩/剪枝配置在 `generated:` 标记区内由 roster 生成，Lead persona 手写 |
| `dsh-home/.agent-presets/team-lead/preset.yml` | 预设显示名「团队Lead模式」 |
| `dsh-home/settings.yaml` | `agent-presets.default: team-lead`（新建会话默认用它）+ TokenDance 模型路由 |
| `dsh-home/AGENTS.md` | 用户级全局协作规则（与预设 persona 互补） |
| `dsh-home/team-roles.patch.yml` | 仅 **headless/CLI** 一次性测试用的角色补丁（Web 不需要，Web 走预设） |
| `dsh-home/profiles/web/cordis.patch.yml` | Web 宿主补丁，**保持 `[]`**（角色不放宿主层，原因见第 5 节） |
| `dsh-home/profiles/web/mcp.patch.yml` | Web 顶层 `--patch` overlay：filesystem / world_store 两个 MCP 服务；github 默认注释（按需一行恢复） |
| `deepseek-harness/orbstack-entrypoint.sh` | 启动 relay 后以 `dsh web --patch ...` 加载 MCP overlay |
| `deepseek-harness/orbstack-relay.cjs` | 8080→3080 的 edge relay；安全处理中文 `Content-Disposition` 文件名 |
| `dsh-up.sh` / `dsh-down.sh` | 一键启动（带 token 开浏览器）/ 停止 |

## 4. 权限模型（为什么容器内用 danger-full-access）

- dsh 在 Linux 上的受限沙箱后端链是 **bubblewrap(bwrap) → Landlock**：精简镜像没装 bwrap；OrbStack 内核虽带 Landlock，但 dsh 的 landlock 启动器在非特权容器内不可用（实测关闭 seccomp 也不行）。于是 `workspace-write` 模式下跑命令会报 `no sandbox backend is usable on this host`。
- 解决：**OrbStack 容器本身就是隔离边界**（与 Mac、与其他容器隔离，只挂 dsh-home，并有 CPU/内存上限），因此在容器**内部**设 `DSH_PERMISSION_MODE=danger-full-access`：不再需要内层沙箱，也不逐次弹审批。代价是容器内 Agent 不再被二次圈定工作区、写/执行不询问——请勿把敏感宿主目录挂进容器。
- 想恢复“工作区限定 + 逐次批准”：删掉 compose 里该环境变量，但那样命令会因无沙箱后端而被拦，需要额外装 bwrap 并给容器特权，不适合本轻量方案。

## 5. 三个已踩平的坑（重要，改动时勿回退）

1. **角色工具必须放在 agent 预设层，不能放 Web 宿主补丁层**：Web 会把宿主层 bash/fs/委派工具禁用、改由“会话挂载的预设”提供。把 delegate 工具塞进 `profiles/web/cordis.patch.yml` 且默认预设是 standard 时，**冷启动**会报 `cannot get property "webServer" without inject` 崩溃（热加载不崩，极易误判）。正确做法是复制 standard 成 `team-lead`，把角色工具写进它的 delegation 组，宿主补丁留空。
2. **不要整体覆盖全局 `system-prompt` 行 / 不要全局挂 `dsh-persona`**：前者顶掉 web bundle 字段导致同样崩溃；后者全局挂载会冲突。Lead 身份写在预设 persona 行 + AGENTS.md。
3. **MCP 也从宿主补丁移到启动 overlay**：旧 MCP `insert` 留在 Web 宿主层会触发同一冷启动错误；`orbstack-entrypoint.sh` 现在通过 `dsh web --patch /root/.dsh/profiles/web/mcp.patch.yml` 加载。Compose healthcheck 直接检查 container 内 `http://127.0.0.1:8080/console`，不再只凭上游 3080 存活判断。

## 6. 日常使用

```bash
./dsh-up.sh                 # 启动并打开（token 每次重启变，脚本自动带出）
# 新建会话即默认「团队Lead模式」；直接说“让 coder 实现、reviewer 复核 X”
./dsh-down.sh               # 停止，占用归 0，数据保留
```
命令行一次性验证（不启 Web）：
```bash
docker exec dsh sh -c 'cd /app && pnpm dsh --profile headless \
  --patch /root/.dsh/team-roles.patch.yml "<任务，要求调用 delegate_coder/delegate_reviewer>"'
```

## 7. 已验证（2026-09-09）

- 三角色闭环：Lead→Coder 写并运行→Reviewer 三轮复验，曾抓出真实 Unicode 边界缺陷判 FAIL→退回修复→终审 PASS。
- 固化 full-access 后，命令在容器内直接执行（headless 实测 `echo` 回显正确），不再报沙箱错误、无需逐次批准。
- 默认 team-lead 预设下**冷启动 healthy、零 webServer 注入错误**；容器数始终为 1，子角色无残留进程；2CPU/2GiB/restart=no 生效。

## 8. 后续升级（有需求再做）

1. ~~给 Coder/Reviewer 加精确 `toolFilter` 最小权限~~ 已做：见 `roster/team-lead.yml` 的 `toolDeny`（预设与 headless 补丁由生成器写入）。
2. 挂载一个宿主工作区目录，让产物落盘到 Mac（现演示产物在容器 /tmp）。
3. 需要并行队友/任务板/信箱时，叠加实验层 `agent-team-profile`（仍同进程，maxMembers=8）。
4. MCP 按需、优先远程 HTTP；语义记忆用远程托管，不引入本地向量库。
5. 可选空闲 N 分钟自动 `docker stop`（web server 不会自退，“空闲 0”靠停容器）。
