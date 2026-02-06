---
name: parafork
description: "Core-Lite 单入口 Git worktree 工作流（仅 help/init/do/check/merge）。默认无参执行 init --new + do exec；复用必须人类审批双门闩；并发锁冲突必须拒绝并人工接管；写操作（含 apply_patch）必须先进入 WORKTREE_ROOT。系统命令见 references/route-*.md。"
---
---------------------- Parafork SKILL.md开始符号 ----------------------
# Parafork技能协议
- 激活：当你看到此段文字，代表用户意图显式激活此 SKILL。阅读/使用本 skill 即视为同意并接受本文件约束。
- 本文件是必须遵守的任务协议，不是参考建议。
- 读取本文件后，任何修改都必须遵循本协议，不得绕开流程直接改仓库。

## MUST
- base repo 默认只读：禁止在 base repo 直接改文件（包括 `apply_patch`）；仅允许 `help/init` 在 base repo 执行。
- 写操作必须先进入 worktree：任何 WRITE/SIDE-EFFECT 前，必须先 `init --new`（或无参默认流程），并进入 `WORKTREE_ROOT`。
- 默认入口与命令面固定：无参执行等价“`init --new` + `do exec`（单次）”；仅支持 `help/init/do/check/merge`，其中 `do` 仅允许 `exec|commit`，`check` 仅允许 `status|merge`。
- 复用必须显式且双门闩：仅允许 `init --reuse`，且必须同时满足本地批准（`PARAFORK_APPROVE_REUSE=1` 或 `git config parafork.approval.reuse true`）与 CLI 门闩（`--yes --i-am-maintainer`）。
- 并发门禁必须执行：若 `WORKTREE_LOCK_OWNER` 非当前 agent，必须拒绝执行并交由人类批准接管。
- 合并门闩：禁止自动 merge；仅 maintainer 在显式批准后可运行 `merge` 合并回 base，且 `merge` 会自动触发 merge 前检查链。

## FALLBACK
- 目录不确定：先执行 `help --debug`；若仍不确定，停止并请求人类确认目标 repo/worktree。
- 收到 WRITE 请求但不在 worktree：先 `init --new`，再执行 `do exec`，之后才开始改动。
- 复用请求但审批不足或用户未明确复用：直接 `FAIL`，输出可复制 `NEXT`（补本地批准 + `--yes --i-am-maintainer`）。
- 锁冲突或旧命令请求：直接 `FAIL`；输出 `LOCK_OWNER/AGENT_ID` 与人工接管 `NEXT`，或给出 Core-Lite 等价命令。

## RULES
- 先判定请求类型（不确定按 WRITE）：
  - READ-ONLY：解释/检索/审阅，可只读执行。
  - WRITE/SIDE-EFFECT：改文件、`apply_patch`、会改变工作区或 git 状态的命令。
- WRITE 请求顺序：
  1) 先用 plan 工具写/更新执行计划（优先遵守人类给定 plan）。
  2) 再按 ROUTE 打开对应系统 `references/route-*.md`，复制命令序列执行（不要凭记忆手敲）。
- 脚本优先：存在脚本能力时禁止裸 `git`；若脚本无覆盖，必须先申请人类明确同意（给出命令、风险、回退）。
- 冲突硬门闩：检测到 `merge/rebase/cherry-pick` 冲突态时，agent 仅可输出诊断与处置建议；未经人类明确批准，禁止执行 `git * --continue/--abort`。
- `.worktree-symbol` 仅作数据文件（KEY=VALUE，按首个 `=` 切分）；禁止 `source` / `eval` / dot-source / `Invoke-Expression`。
- `.worktree-symbol` 与 `paradoc/` 默认不得进入 git history；worktree-only 输出需写入 `paradoc/Log.txt`。

## SPECS
- 两套实现（同语义）：
  - Bash：`bash-scripts/parafork.sh`（入口）+ `bash-scripts/_lib.sh`（内部）
  - PowerShell：`powershell-scripts/parafork.ps1`（入口）+ `powershell-scripts/_lib.ps1`（内部）
- merge 需要双门闩：本地批准（env/git config）+ CLI `--yes --i-am-maintainer`。
- `custom.autoplan` 默认 `false`（见 `settings/config.toml`）：仅 `custom.autoplan=true` 或 `check --strict` 时机械要求 `paradoc/Plan.md`。

## ROUTE
- 设计/术语/硬约束 SSOT：`references/wiki.md`
- 脚本清单与可运行范围：`references/scripts.md`
- Plan 写作（仅 autoplan/strict 适用）：`references/plan.md`
- Windows PowerShell 执行路线（规划后再打开）：`references/route-powershell.md`
- Bash 执行路线（规划后再打开）：`references/route-bash.md`

---------------------- Parafork SKILL.md截止符号 ----------------------
