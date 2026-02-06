# Scripts（索引）

两套实现语义一致（Bash / PowerShell），但对外 **只有一个入口脚本**：

- Bash：`bash "<PARAFORK_BASH_SCRIPTS>/parafork.sh" [cmd] [args...]`
- PowerShell：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" <cmd> [args...]`

> 命令模板与执行顺序（渐进式披露）见：`references/route-bash.md` / `references/route-powershell.md`

## base-allowed（可在 base repo / 任意目录运行）
- `parafork help`
- `parafork debug`
- `parafork init [--new|--reuse] ...`
- `parafork watch [--new|--reuse-current] ...`（默认命令；无参等价 `watch`，默认新建）

## worktree-required（必须在 parafork worktree 中；脚本会自动切到 WORKTREE_ROOT）
- `parafork check [topic] ...`
  - `check exec|merge|plan [--strict]`
  - `check status|diff|log|review ...`
- `parafork do <action> ...`
  - `do commit --message "<msg>" [--no-check]`
  - `do pull [--strategy ff-only|rebase|merge] ...`
- `parafork merge ...`（仅 maintainer；需双门闩）

## Legacy（弃用兼容；不在 help 展示；stderr 打印 DEPRECATED）
- `status` → `check status`
- `check --phase <phase>` → `check <phase>`
- `commit` → `do commit`
- `pull` → `do pull`
- `diff` → `check diff`
- `log` → `check log`
- `review` → `check review`
