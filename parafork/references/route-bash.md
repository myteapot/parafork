# ROUTE: Bash（执行路线）

> 渐进式披露：仅在你已经确定要执行 Parafork（WRITE / SIDE-EFFECT），并且已经写好计划（或人类给了计划）之后，再阅读本文件。

适用环境：Linux / macOS / WSL / Git-Bash。

## 路径约定

- `<PARAFORK_ROOT>`：本 skill 根目录
- `<PARAFORK_BASH_SCRIPTS>`：`<PARAFORK_ROOT>/bash-scripts`

通用命令模板：

`bash "<PARAFORK_BASH_SCRIPTS>/<script>.sh" ...`

## 0) 定位（可选）

- 不确定当前目录/是否在 worktree：运行 `debug.sh`（base-allowed）。

## 1) Bootstrap（只在 base repo 或目标 worktree 内）

- 新建 worktree（在 base repo；无参等价 `--new`）：`init.sh --new`
- 复用当前 worktree（必须在该 worktree 内）：`init.sh --reuse`

按 `init` 输出执行：

`cd "<WORKTREE_ROOT>"`

## 2) Exec（必须在 WORKTREE_ROOT）

- `status.sh`
- `check.sh --phase exec`

每个 task 微循环：

- 更新计划 / `paradoc/Exec.md`
- `commit.sh --message "..."`

需要时：

- `pull.sh`
- `diff.sh` / `log.sh` / `review.sh`

## 3) Merge（仅 maintainer）

- `check.sh --phase merge`
- 批准门闩（任选其一）：
  - 临时环境变量：`PARAFORK_APPROVE_MERGE=1`
  - 或本地 git config（脚本支持的方式）
- `PARAFORK_APPROVE_MERGE=1 bash "<PARAFORK_BASH_SCRIPTS>/merge.sh" --yes --i-am-maintainer`

