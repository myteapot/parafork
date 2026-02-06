# ROUTE: Windows PowerShell（执行路线）

> 渐进式披露：仅在你已经确定要执行 Parafork（WRITE / SIDE-EFFECT），并且已经写好计划（或人类给了计划）之后，再阅读本文件。

## 路径约定

- `<PARAFORK_ROOT>`：本 skill 根目录
- `<PARAFORK_POWERSHELL_SCRIPTS>`：`<PARAFORK_ROOT>/powershell-scripts`

通用命令模板（唯一入口）：

`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" <cmd> [args...]`

> 无参默认流程：`init --new` + `do exec`（单次）

## 0) 定位（可选）

- 不确定当前目录/是否在 worktree：运行 `parafork help --debug`（base-allowed）。

## 1) 默认固定流程（推荐）

- 直接运行：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1"`
  - 可从 base repo / worktree 子目录 / worktree 根目录启动
  - 默认总是 `init --new`（不自动复用），随后执行 `do exec`（摘要 + 校验 + NEXT）

> `do exec` 不会自动 `do commit/do pull/merge`；只输出一次 `NEXT`（可复制执行）。

## 2) 手动子命令（高级）

- 新建 worktree：`... init --new`
- 复用当前 worktree（补写 `WORKTREE_USED=1`，并刷新锁；需人类审批双门闩）：
  - `$env:PARAFORK_APPROVE_REUSE=1; ... init --reuse --yes --i-am-maintainer`

在 worktree 内（任意子目录均可；脚本会切到 `WORKTREE_ROOT`）：
- `... do exec`
- `... do exec --loop --interval 2`
- `... check status`
- `... check diff`
- `... check log --limit 20`
- `... check review`

每个 task 微循环（不自动 commit）：
- 更新计划 / `paradoc/Exec.md`
- `... do commit --message "..."`
- 需要时：`... do pull`

## 3) Merge（仅 maintainer）

- 可选先检查：`... check merge`
- 批准门闩（任选其一）：`$env:PARAFORK_APPROVE_MERGE=1` 或 base repo 本地 git config
- 合并（会自动触发 merge 前检查链）：
  - `$env:PARAFORK_APPROVE_MERGE=1; powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" merge --yes --i-am-maintainer`

## 4) 并发锁冲突（人工接管）

- 若提示 `REFUSED: worktree locked by another agent`，先由人类批准接管，再执行：
  - `cd "<WORKTREE_ROOT>"`
  - `$env:PARAFORK_APPROVE_REUSE=1; powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" init --reuse --yes --i-am-maintainer`
