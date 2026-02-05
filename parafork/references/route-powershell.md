# ROUTE: Windows PowerShell（执行路线）

> 渐进式披露：仅在你已经确定要执行 Parafork（WRITE / SIDE-EFFECT），并且已经写好计划（或人类给了计划）之后，再阅读本文件。

## 路径约定

- `<PARAFORK_ROOT>`：本 skill 根目录
- `<PARAFORK_POWERSHELL_SCRIPTS>`：`<PARAFORK_ROOT>/powershell-scripts`

通用命令模板：

`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\<script>.ps1" ...`

## 0) 定位（可选）

- 不确定当前目录/是否在 worktree：运行 `debug.ps1`（base-allowed）。

## 1) Bootstrap（只在 base repo 或目标 worktree 内）

- 新建 worktree（在 base repo；无参等价 `--new`）：`init.ps1 --new`
- 复用当前 worktree（必须在该 worktree 内）：`init.ps1 --reuse`

按 `init` 输出执行：

`cd "<WORKTREE_ROOT>"`

## 2) Exec（必须在 WORKTREE_ROOT）

- `status.ps1`
- `check.ps1 --phase exec`

每个 task 微循环：

- 更新计划 / `paradoc/Exec.md`
- `commit.ps1 --message "..."`

需要时：

- `pull.ps1`
- `diff.ps1` / `log.ps1` / `review.ps1`

## 3) Merge（仅 maintainer）

- `check.ps1 --phase merge`
- 批准门闩（任选其一）：
  - PowerShell：`$env:PARAFORK_APPROVE_MERGE=1`
  - CMD：`set PARAFORK_APPROVE_MERGE=1`
  - 或本地 git config（脚本支持的方式）
- `merge.ps1 --yes --i-am-maintainer`

