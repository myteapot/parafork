---
name: parafork
description: "维护者级、脚本优先的 Git worktree 工作流（parafork v13），用于让 agent 在仓库中安全贡献：init/status/check/commit/pull/merge/debug。包含严格的 worktree-root guard、本地 merge 批准、remote base 对齐，以及防止提交 paradoc/.worktree-symbol。可在任意仓库直接运行（skill 本体不进仓库，仅创建 .parafork 会话容器目录）。"
---

# Parafork（v13）

用本 skill 自带的 `scripts/*.sh` 操作一个安全、可审计的 Git worktree 工作流；默认安全，所有回主分支动作都需要 maintainer 把关。

## 目标仓库内落盘内容（不要混淆）

- 本 skill 本体位于技能安装目录（例如 `~/.codex/skills/...`），不要求目标仓库存在 `parafork/` 目录。
- `<BASE_ROOT>/.parafork/`：worktree 会话容器目录（由 `init.sh` 创建；默认被 ignore，不进入仓库历史）
  - 目录结构：`<BASE_ROOT>/.parafork/<WORKTREE_ID>/...`
  - 可通过 `settings/config.toml` 的 `[workdir].root` 改名（默认就是 `.parafork`）
- `<WORKTREE_ROOT>/.worktree-symbol` 与 `<WORKTREE_ROOT>/paradoc/`：worktree 会话数据（默认不得进入 git history）

## 快速开始（最短路径）

本文档中 `<PARAFORK_SCRIPTS>` 指本 skill 包的 `scripts/` 目录。

1) 运行唯一入口 `init.sh`：
   - 在 base repo：`bash "<PARAFORK_SCRIPTS>/init.sh"`（无参默认创建新 worktree）
   - 在某个 worktree 内：必须显式二选一：
     - 继续在当前 worktree：`bash "<PARAFORK_SCRIPTS>/init.sh" --reuse`
     - 新开 worktree：`bash "<PARAFORK_SCRIPTS>/init.sh" --new`
2) 按 init 输出 `cd "<WORKTREE_ROOT>"` 进入 worktree 根目录。  
3) 运行 `bash "<PARAFORK_SCRIPTS>/status.sh"` 和 `bash "<PARAFORK_SCRIPTS>/check.sh" --phase exec`。  
4) 每个 task 按“微循环”推进：
   - 用模型 plan 工具规划/更新（优先遵守人类提供的 plan）
   - 运行 `bash "<PARAFORK_SCRIPTS>/commit.sh" --message "..."`（保存进度；默认不会提交 `paradoc/` 或 `.worktree-symbol`）
   - 更新 `paradoc/Exec.md`（What/Why/Verify）
5) 合并前运行 `bash "<PARAFORK_SCRIPTS>/check.sh" --phase merge`。  
6) 合并回主分支（仅 maintainer）：
   - 一次性批准：`PARAFORK_APPROVE_MERGE=1 bash "<PARAFORK_SCRIPTS>/merge.sh" --yes --i-am-maintainer`

## 硬规则（MUST）

- worktree-only 脚本只能在 worktree 根目录运行；不确定位置先 `bash "<PARAFORK_SCRIPTS>/debug.sh"`。
- worktree-only 脚本要求 `.worktree-symbol: WORKTREE_USED=1`（顺序门闩）：先跑 `bash "<PARAFORK_SCRIPTS>/init.sh" --reuse` 或创建新 worktree。
- `.worktree-symbol` 只当作数据文件；禁止 `source`/`eval`。
- `.worktree-symbol` 与 `paradoc/` 默认不得进入 git history；脚本通过 worktree exclude + staged 检查闭环防污染。
- worktree 内脚本输出会追加到 `paradoc/Log.txt`（含时间戳、argv、pwd、exit code；base-allowed 脚本在能定位 worktree 时也会记录）。
- 冲突必须停下来人工处理；脚本不做自动 resolve。

## 脚本清单

允许在 base repo 运行：
- `help.sh`：输出 quickstart 与关键约束。
- `init.sh`：唯一入口；在 worktree 内必须 `--reuse|--new`，并写 `.worktree-symbol: WORKTREE_USED`；创建时初始化 `paradoc/*`、写 ignore/exclude，并打印下一步。
- `debug.sh`：定位 base/worktree 并打印可复制的 `cd`/next steps。

只能在 worktree 根目录运行：
- `status.sh`：摘要状态（替代 `git status` 的主视图）。
- `check.sh`：校验交付物与 git 污染。
- `commit.sh`：提交 worktree 内的进度（必须 `--message`）。
- `pull.sh`：把 base 同步到 worktree（默认 `ff-only`；高风险策略需要“明确批准 + CLI 门闩”）。
- `merge.sh`：把 worktree 带回 base（需要本地批准 + `--yes --i-am-maintainer`）。

## pull 的高风险策略批准（rebase/merge）

`pull.sh` 默认只允许 `ff-only`。当需要 `rebase` 或 `merge` 时（高风险）：
- 需要 maintainer 明确批准（一次性 env 或本地 git config 二选一）
- 且必须显式加上 `--yes --i-am-maintainer`

示例：

```bash
# rebase（一次性批准）
PARAFORK_APPROVE_PULL_REBASE=1 bash "<PARAFORK_SCRIPTS>/pull.sh" --strategy rebase --yes --i-am-maintainer

# merge（一次性批准）
PARAFORK_APPROVE_PULL_MERGE=1 bash "<PARAFORK_SCRIPTS>/pull.sh" --strategy merge --yes --i-am-maintainer
```

## 冲突处理（resolve policy）

当 maintainer 批准的 git 操作出现冲突：
- 先看：`git status`
- 手动修复冲突文件（删除 `<<<<<<<`/`=======`/`>>>>>>>`），然后：
  - rebase：`git rebase --continue`（放弃：`git rebase --abort`）
  - merge：`git merge --continue`（放弃：`git merge --abort`）
  - cherry-pick：`git cherry-pick --continue`（放弃：`git cherry-pick --abort`）
- 继续合并前再跑一次：`bash "<PARAFORK_SCRIPTS>/check.sh" --phase merge`

## 无脚本 git 操作申请模板（可复制）

```text
请求执行无脚本 git 操作（需要批准）：
- 命令：
  1) git -C "<PATH>" <...>
  2) git -C "<PATH>" <...>
- 目的：<为什么必须做这件事>
- 风险：<可能影响历史/冲突/回滚成本>
- 回退：<例如 rebase --abort / cherry-pick --abort 等>
- 为什么脚本不足：<pull/merge/commit 等脚本为何覆盖不了>
```

## 参考

- v13 单一事实来源（SSOT）：`parafork-design-doc/v13/Wikiv13.md`, `parafork-design-doc/v13/prdv13.md`, `parafork-design-doc/v13/actv13.md`
- Plan 写作指南（仅 `custom.autoplan=true` 时适用）：`references/How-to-write-plan.md`
