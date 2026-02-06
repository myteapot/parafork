# Scripts（索引）

两套实现语义一致（Bash / PowerShell），但对外 **只有一个入口脚本**：

- Bash：`bash "<PARAFORK_BASH_SCRIPTS>/parafork.sh" [cmd] [args...]`
- PowerShell：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" <cmd> [args...]`

> 命令模板与执行顺序（渐进式披露）见：`references/route-bash.md` / `references/route-powershell.md`

## base-allowed（可在 base repo / 任意目录运行）
- `parafork help [debug|--debug]`
- `parafork init [--new|--reuse] ...`

## worktree-required（必须在 parafork worktree 中；脚本会自动切到 WORKTREE_ROOT）
- `parafork do <action> ...`
  - `do exec [--loop] [--interval <sec>] [--strict]`
  - `do commit --message "<msg>" [--no-check]`
  - `do pull [--strategy ff-only|rebase|merge] ...`
- `parafork check [topic] ...`
  - `check merge [--strict]`
  - `check status|diff|log|review ...`
- `parafork merge ...`（仅 maintainer；需双门闩）

## 默认入口
- 无参运行会执行：`init --new` + `do exec`（单次检查并输出 NEXT）。

## 复用审批与并发门禁
- 复用审批（`init --reuse`）需要双门闩：
  - 本地批准：`PARAFORK_APPROVE_REUSE=1` 或 `git config parafork.approval.reuse true`
  - CLI 门闩：`--yes --i-am-maintainer`
- worktree 并发门禁通过 `.worktree-symbol` 中 `WORKTREE_LOCK*` 字段执行；锁冲突时脚本会拒绝并要求人工接管。

## 兼容性
- 仅支持 canonical 顶层命令：`help/init/do/check/merge`。
- `watch`、顶层 `debug`、`check exec`、`check plan` 均不再支持。
