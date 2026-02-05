# Scripts（索引）

两套实现语义一致（Bash / PowerShell），但对外 **只有一个入口脚本**：

- Bash：`bash "<PARAFORK_BASH_SCRIPTS>/parafork.sh" [cmd] [args...]`
- PowerShell：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" <cmd> [args...]`

> 命令模板与执行顺序（渐进式披露）见：`references/route-bash.md` / `references/route-powershell.md`

## base-allowed（可在 base repo / 任意目录运行）
- `parafork help`
- `parafork debug`
- `parafork init [--new|--reuse] ...`
- `parafork watch ...`（默认命令；无参等价 `watch`）

## worktree-required（必须在 parafork worktree 中；脚本会自动切到 WORKTREE_ROOT）
- `parafork status`
- `parafork check --phase plan|exec|merge [--strict]`
- `parafork commit --message "<msg>" [--no-check]`
- `parafork pull [--strategy ff-only|rebase|merge] ...`
- `parafork diff`
- `parafork log [--limit <n>]`
- `parafork review`
- `parafork merge ...`（仅 maintainer；需双门闩）
