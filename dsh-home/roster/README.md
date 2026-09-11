# Roster —— 团队角色清单

一边一个文件的“单一事实源”：`team-lead.yml`。预设、headless 补丁与
`AGENTS.md` 里的角色规则都由它生成，手改那些生成区会被 `--check` 抓出来。

## 30 秒加一个角色

1. 在 `team-lead.yml` 的 `roles:` 里追加一段（照抄 coder，改 `id`、`toolName`、
   `effort`、`persona` 与 `toolDeny`）。
2. `node dsh-workbench/scripts/render-team.mjs` 预览，确认后加 `--write`。
3. 在预设的 Lead persona 里补一句该角色的用途（persona 是手写区，生成器只校验）。

## 常用命令

```bash
node dsh-workbench/scripts/render-team.mjs --print    # 角色表
node dsh-workbench/scripts/render-team.mjs --check    # 漂移检查（退出码 1 = 有漂移）
node dsh-workbench/scripts/render-team.mjs --write    # 应用；首次会留下 *.roster-bak
```

## 注意

- `leadEffort` / 角色 `effort` 必须是当前 provider 在该模型上**声明过的档位**
  （见 `dsh-home/settings.yaml` 的 `reasoningEfforts`）；生成器会校验，写错会拒绝。
- 回滚：重跑生成器是确定性的；`.roster-bak` 是首次改动前的副本。
