---
name: parafork
description: "包含严格的 worktree-root guard、WORKTREE_USED 顺序门闩、autoplan 默认关闭、审计日志、remote base 对齐，以及防止提交 paradoc/.worktree-symbol。根据系统选择 `bash-scripts/` 或 `powershell-scripts/` 运行。脚本优先的 Git worktree 工作流：init/status/check/commit/pull/merge/debug。"
---

# Parafork（general）

本 skill 提供同一套工作流语义的两份实现：
- `bash-scripts/*.sh`：Linux/macOS/WSL/Git-Bash
- `powershell-scripts/*.ps1`：Windows（Windows PowerShell 5.1 / PowerShell 7）

本文档中：
- `<PARAFORK_BASH_SCRIPTS>` 指本 skill 包的 `bash-scripts/` 目录
- `<PARAFORK_POWERSHELL_SCRIPTS>` 指本 skill 包的 `powershell-scripts/` 目录

## 如何选择脚本（按系统）

- Windows（PowerShell 5.1 / 7）：使用 `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\<script>.ps1" ...`
- Linux/macOS/WSL/Git-Bash：使用 `bash "<PARAFORK_BASH_SCRIPTS>/<script>.sh" ...`

> 重要：两套实现都遵循同一套硬门闩与审计规则（见下文 MUST）。

## 执行规范（Windows PowerShell）

1) 运行唯一入口 `init.ps1`：
   - 在 base repo：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\init.ps1"`（无参默认创建新 worktree）
   - 在某个 worktree 内：无参会 FAIL，必须显式二选一：
     - 继续当前 worktree：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\init.ps1" --reuse`
     - 新开 worktree：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\init.ps1" --new`
2) 按 init 输出 `cd "<WORKTREE_ROOT>"` 进入 worktree 根目录。
3) 运行：
   - `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\status.ps1"`
   - `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\check.ps1" --phase exec`
4) 每个 task 按微循环推进：
   - 用模型 plan 工具规划/更新（优先遵守人类提供的 plan）
   - `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\commit.ps1" --message "..."` 保存进度
   - 更新 `paradoc/Exec.md`（What/Why/Verify）
5) 合并前：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\check.ps1" --phase merge`
6) 合并回主分支（仅 maintainer）：
   - 一次性批准：`set PARAFORK_APPROVE_MERGE=1`（或本地 git config）
   - 运行：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\merge.ps1" --yes --i-am-maintainer`

## 执行规范（Bash）

1) 运行唯一入口 `init.sh`：
   - 在 base repo：`bash "<PARAFORK_BASH_SCRIPTS>/init.sh"`（无参默认创建新 worktree）
   - 在某个 worktree 内：无参会 FAIL，必须显式二选一：
     - 继续当前 worktree：`bash "<PARAFORK_BASH_SCRIPTS>/init.sh" --reuse`
     - 新开 worktree：`bash "<PARAFORK_BASH_SCRIPTS>/init.sh" --new`
2) 按 init 输出 `cd "<WORKTREE_ROOT>"` 进入 worktree 根目录。
3) 运行：
   - `bash "<PARAFORK_BASH_SCRIPTS>/status.sh"`
   - `bash "<PARAFORK_BASH_SCRIPTS>/check.sh" --phase exec`
4) 微循环推进：
   - 用模型 plan 工具规划/更新（优先遵守人类提供的 plan）
   - `bash "<PARAFORK_BASH_SCRIPTS>/commit.sh" --message "..."` 保存进度
   - 更新 `paradoc/Exec.md`
5) 合并前：`bash "<PARAFORK_BASH_SCRIPTS>/check.sh" --phase merge`
6) 合并回主分支（仅 maintainer）：
   - 一次性批准：`PARAFORK_APPROVE_MERGE=1 bash "<PARAFORK_BASH_SCRIPTS>/merge.sh" --yes --i-am-maintainer`

## 硬规则（MUST）

- 在完成流程后必须显式申请人类同意才能merge回主仓库
- 唯一入口是 `init`（`init.sh` 或 `init.ps1`）；在 worktree 内无参运行会 FAIL，必须显式 `--reuse` 或 `--new`。
- worktree-only 脚本只能在 `WORKTREE_ROOT` 运行；不确定位置先跑 `debug`（`debug.sh` / `debug.ps1`）。
- worktree-only 脚本要求 `.worktree-symbol: WORKTREE_USED=1`（顺序门闩）：旧 worktree 需先 `init --reuse` 补写。
- `.worktree-symbol` 只当作数据文件（KEY=VALUE，按第一个 `=` 切分）；禁止 `source`/`eval`/dot-source/`Invoke-Expression`。
- `.worktree-symbol` 与 `paradoc/` 默认不得进入 git history；脚本通过 exclude + staged 检查闭环防污染。
- 审计日志：worktree-only 脚本全量输出追加到 `paradoc/Log.txt`（含时间戳、argv、pwd、exit code）；base-allowed 脚本在能定位 worktree 时也会记录。
- 冲突必须停下来人工处理；脚本不做自动 resolve。

## 脚本清单

允许在 base repo 运行（base-allowed）：
- `help.sh` / `help.ps1`
- `init.sh` / `init.ps1`
- `debug.sh` / `debug.ps1`

只能在 worktree 根目录运行（worktree-only）：
- `status.sh` / `status.ps1`
- `check.sh` / `check.ps1`
- `commit.sh` / `commit.ps1`
- `pull.sh` / `pull.ps1`
- `merge.sh` / `merge.ps1`
- `diff.sh` / `diff.ps1`
- `log.sh` / `log.ps1`
- `review.sh` / `review.ps1`

## 参考

- 维护者手册：`references/wiki.md`
- Plan 写作指南（仅 `custom.autoplan=true` 或 strict 时适用）：`references/How-to-write-plan.md`
