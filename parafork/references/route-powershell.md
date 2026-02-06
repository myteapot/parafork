# ROUTE: Windows PowerShell（执行路线）

> 渐进式披露：仅在你已经确定要执行 Parafork（WRITE / SIDE-EFFECT），并且已经写好计划（或人类给了计划）之后，再阅读本文件。
>
> `SIDE-EFFECT` 指任何状态变更操作（例如 `init --new/--reuse`、`do commit`、`merge`、写入 `.worktree-symbol` / `paradoc/Log.txt`）。

## 路径约定

- `<PARAFORK_ROOT>`：本 skill 根目录
- `<PARAFORK_POWERSHELL_SCRIPTS>`：`<PARAFORK_ROOT>/powershell-scripts`

通用命令模板（唯一入口）：

`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" <cmd> [args...]`

> 无参默认流程：`init --new` + `do exec`（单次）

## 0) 定位（可选）

- 不确定当前目录/是否在 worktree：
  - `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" help --debug`

## 1) 默认固定流程（推荐）

- 直接运行：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1"`
  - 可从 base repo / worktree 子目录 / worktree 根目录启动
  - 默认总是 `init --new`（不自动复用），随后执行 `do exec`（摘要 + 校验 + NEXT）

> `do exec` 不会自动 `do commit/merge`；只输出一次 `NEXT`（可复制执行）。

## 2) 手动子命令（高级）

- 新建 worktree：
  - `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" init --new`
- 复用当前 worktree（补写 `WORKTREE_USED=1`，并刷新锁；需人类审批 CLI 门闩）：
  - 先向人类申请批准（目的、命令、风险、回退）
  - `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" init --reuse --yes --i-am-maintainer`
  - 注意：`init --reuse` 仅在已有 parafork worktree 内有效。

在 worktree 内（任意子目录均可；脚本会切到 `WORKTREE_ROOT`）：
- `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" do exec`
- `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" do exec --strict`
- `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" check status`
- `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" check merge`

每个 task 微循环（不自动 commit）：
- 更新计划 / `paradoc/Exec.md`
- `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" do commit --message "..."`

## 3) Merge（仅 maintainer）

- 可选先检查：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" check merge`
- 合并（会自动触发 merge 前检查链；需携带 CLI 门闩）：
  - 先向人类申请批准（目的、命令、风险、回退）
  - `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" merge --yes --i-am-maintainer`

## 4) 并发锁冲突（默认新开，接管高风险）

- 若提示 `REFUSED: worktree locked by another agent`：
  - 默认建议：直接新开 worktree（降低干扰风险）
    - `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" init --new`
  - 若必须接管（高风险）：先向人类发起明确审批请求，再执行接管命令
    - 审批请求建议至少包含：`LOCK_OWNER`、当前 `AGENT_ID`、接管风险与回退方案
    - 接管命令：
      - `cd "<WORKTREE_ROOT>"`
      - `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" init --reuse --yes --i-am-maintainer`
