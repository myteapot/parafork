# Scripts（索引）

两套实现语义一致（Bash / PowerShell），但对外 **只有一个入口脚本**：

- Bash：`bash "<PARAFORK_BASH_SCRIPTS>/parafork.sh" [cmd] [args...]`
- PowerShell：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\\parafork.ps1" <cmd> [args...]`

> 命令模板与执行顺序（渐进式披露）见：`references/route-bash.md` / `references/route-powershell.md`

## base-allowed（可在 base repo / 任意目录运行）
- `parafork help [debug|--debug]`
- `parafork init`
- `parafork init --new`

> `init --reuse` 不属于 base-allowed：它仅在已有 parafork worktree 内有效。

## worktree-required（必须在 parafork worktree 中；脚本会自动切到 WORKTREE_ROOT）
- `parafork do <action> ...`
  - `do exec [--strict]`
  - `do commit --message "<msg>" [--no-check]`
- `parafork check [topic] ...`
  - `check merge [--strict]`
  - `check status`
- `parafork merge ...`（仅 maintainer；需 CLI 门闩）
- `parafork init --reuse --yes --i-am-maintainer`

## 默认入口
- 无参运行会执行：`init --new` + `do exec`（单次检查并输出 NEXT）。

## 复用 CLI 门闩与并发门禁
- 复用（`init --reuse`）需要 CLI 门闩：`--yes --i-am-maintainer`。
- 带 CLI 门闩命令（`init --reuse` / `merge`）在策略层要求先获人类明确批准。
- worktree 并发门禁通过 `.worktree-symbol` 中 `WORKTREE_LOCK*` 字段执行；锁冲突时默认推荐 `init --new`，接管仅为高风险备选。

## 兼容性
- 仅支持 canonical 顶层命令：`help/init/do/check/merge`。
- 非 Core-Lite 命令/主题（如 `watch`、`do pull`、`check diff/log/review`）均不再支持。

## 回归建议
- 重构后可按 `references/regression-checklist.md` 做最小回归，覆盖无参入口、CLI 门闩、并发锁、污染防护与 merge 前检查链。
- 本次执行记录见：`references/test-report-2026-02-06.md`。
