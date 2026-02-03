---
name: parafork-win
description: "Parafork 的纯 Windows PowerShell 版本（兼容 Windows PowerShell 5.1 + PowerShell 7）。脚本优先的 Git worktree 工作流：init/status/check/commit/pull/merge/debug。包含严格的 worktree-root guard、WORKTREE_USED 顺序门闩、本地 merge 批准、remote base 对齐，以及防止提交 paradoc/.worktree-symbol。"
---

# Parafork（win）

用本 skill 自带的 `scripts/*.ps1` 操作一个安全、可审计的 Git worktree 工作流；默认安全，所有回主分支动作都需要 maintainer 把关。

> 本版本不依赖 bash/WSL；推荐命令统一使用：`powershell -NoProfile -ExecutionPolicy Bypass -File ...`

## 快速开始（最短路径）

本文档中 `<PARAFORK_SCRIPTS>` 指本 skill 包的 `scripts/` 目录。

1) 运行唯一入口 `init.ps1`：
   - 在 base repo：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_SCRIPTS>\\init.ps1"`（无参默认创建新 worktree）
   - 在某个 worktree 内：无参会 FAIL，必须显式二选一：
     - 继续在当前 worktree：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_SCRIPTS>\\init.ps1" --reuse`
     - 新开 worktree：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_SCRIPTS>\\init.ps1" --new`
2) 按 init 输出 `cd "<WORKTREE_ROOT>"` 进入 worktree 根目录。
3) 运行 `status.ps1` 与 `check.ps1 --phase exec`：
   - `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_SCRIPTS>\\status.ps1"`
   - `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_SCRIPTS>\\check.ps1" --phase exec`
4) 每个 task 按“微循环”推进：
   - 用模型 plan 工具规划/更新（优先遵守人类提供的 plan）
   - `commit.ps1 --message "..."` 保存进度（默认不会提交 `paradoc/` 或 `.worktree-symbol`）
   - 更新 `paradoc/Exec.md`（What/Why/Verify）
5) 合并前运行 `check.ps1 --phase merge`。
6) 合并回主分支（仅 maintainer）：
   - 一次性批准：`set PARAFORK_APPROVE_MERGE=1`（或本地 git config）
   - 运行：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_SCRIPTS>\\merge.ps1" --yes --i-am-maintainer`

## 硬规则（MUST）

- worktree-only 脚本只能在 worktree 根目录运行；不确定位置先 `debug.ps1`。
- worktree-only 脚本要求 `.worktree-symbol: WORKTREE_USED=1`（顺序门闩）：先跑 `init.ps1 --reuse` 或创建新 worktree。
- `.worktree-symbol` 只当作数据文件；禁止 dot-source / `Invoke-Expression` / `eval`。
- `.worktree-symbol` 与 `paradoc/` 默认不得进入 git history；脚本通过 worktree exclude + staged 检查闭环防污染。
- 脚本输出会追加到 `paradoc/Log.txt`（含时间戳、argv、pwd、exit code；base-allowed 脚本在能定位 worktree 时也会记录）。
- 冲突必须停下来人工处理；脚本不做自动 resolve。

## 脚本清单

允许在 base repo 运行：
- `help.ps1`：输出 quickstart 与关键约束。
- `init.ps1`：唯一入口（`--new|--reuse`），并写 `.worktree-symbol: WORKTREE_USED`。
- `debug.ps1`：定位 base/worktree 并打印可复制的 next steps。

只能在 worktree 根目录运行：
- `status.ps1`：摘要状态（替代 `git status` 的主视图）。
- `check.ps1`：校验交付物与 git 污染。
- `commit.ps1`：提交 worktree 内的进度（必须 `--message`）。
- `pull.ps1`：把 base 同步到 worktree（默认 `ff-only`；高风险策略需要“明确批准 + CLI 门闩”）。
- `merge.ps1`：把 worktree 带回 base（需要本地批准 + `--yes --i-am-maintainer`）。
- `diff.ps1` / `log.ps1` / `review.ps1`：辅助脚本。

## 参考

- 维护者手册：`references/wiki.md`
- Plan 写作指南（仅 `custom.autoplan=true` 时适用）：`references/How-to-write-plan.md`
