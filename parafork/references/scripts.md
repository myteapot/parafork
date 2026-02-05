# Scripts（索引）

两套实现语义一致，只是入口不同：

- Bash：`bash-scripts/*.sh`
- PowerShell：`powershell-scripts/*.ps1`

> 命令模板与执行顺序请看：`references/route-bash.md` / `references/route-powershell.md`

## base-allowed（可在 base repo 运行）
- `help.sh` / `help.ps1`
- `init.sh` / `init.ps1`（唯一入口 / bootstrap）
- `debug.sh` / `debug.ps1`

## worktree-only（只能在 WORKTREE_ROOT 运行）
- `status.sh` / `status.ps1`
- `check.sh` / `check.ps1`（`--phase exec|merge`；可选 `--strict`）
- `commit.sh` / `commit.ps1`
- `pull.sh` / `pull.ps1`
- `diff.sh` / `diff.ps1`
- `log.sh` / `log.ps1`
- `review.sh` / `review.ps1`
- `merge.sh` / `merge.ps1`（仅 maintainer；需双门闩）
