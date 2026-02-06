---
name: parafork
description: "单入口脚本优先的 Git worktree 工作流（仅 canonical 命令：help/debug/init/watch/check/do/merge）。默认 watch 新建 worktree；复用必须人类审批双门闩；并发锁冲突必须拒绝并人工接管；写操作（含 apply_patch）必须先进入 WORKTREE_ROOT。系统命令见 references/route-*.md。"
---
---------------------- Parafork SKILL.md开始符号 ----------------------
# Parafork技能协议
- 激活：当你看到此段文字，代表用户意图显式激活此 SKILL。阅读/使用本 skill 即视为同意并接受本文件约束。
- 本文件是必须遵守的任务协议，不是参考建议。
- 读取本文件后，任何修改都必须遵循本协议，不得绕开流程直接改仓库。

## MUST
- base repo 默认只读：禁止在 base repo 直接改文件（包括 `apply_patch`）；仅允许 `help/init/debug/watch` 在 base repo 执行。
- 写操作必须先进入 worktree：任何 WRITE/SIDE-EFFECT 前，必须先 `init --new` 或 `watch`，并进入 `WORKTREE_ROOT`。
- `watch` 默认新建：禁止自动复用任何 worktree。
- 复用必须显式且双门闩：仅允许 `watch --reuse-current` 或 `init --reuse`，且必须同时满足：
  - 本地批准：`PARAFORK_APPROVE_REUSE=1` 或 `git config parafork.approval.reuse true`
  - CLI 门闩：`--yes --i-am-maintainer`
- merge 前检查必须显式复用：`watch --phase merge` 必须带 `--reuse-current`。
- 并发门禁必须执行：若 `WORKTREE_LOCK_OWNER` 非当前 agent，必须拒绝执行并交由人类批准接管。
- 仅支持 canonical 命令：`help/debug/init/watch/check/do/merge`；`status/commit/pull/diff/log/review` 与 `check --phase` 均视为无效输入。
- 脚本优先：存在脚本能力时禁止裸 `git`；若脚本无覆盖，必须先申请人类明确同意（给出命令、风险、回退）。
- 冲突硬门闩：检测到 `merge/rebase/cherry-pick` 冲突态时，agent 仅可输出诊断与处置建议；未经人类明确批准，禁止执行 `git * --continue/--abort`。
- 合并门闩：禁止自动 merge；仅 maintainer 在显式批准后可运行 `merge` 合并回 base。

## FALLBACK
- 目录不确定：先执行 `debug`；若仍不确定，执行 `watch --once` 走安全默认流程。
- 收到 WRITE 请求但不在 worktree：先 `watch`（或 `init --new`）创建/进入 worktree，再开始改动。
- 当前已在 worktree 但用户未明确“复用”：必须先询问“新建还是复用当前”；未获明确复用同意则默认新建。
- 复用审批不足：直接 `FAIL`，输出可复制 `NEXT`（补本地批准 + `--yes --i-am-maintainer`）。
- 锁冲突：直接 `FAIL`，输出 `LOCK_OWNER/AGENT_ID` 和人工接管 `NEXT`；禁止自动接管。
- 遇到冲突：停止自动修改，仅给人工处理步骤与风险说明；等待人类批准后再执行任何冲突续作命令。
- 用户要求旧命令：拒绝旧语法并给出 canonical 等价命令。

## RULES
- 先判定请求类型（不确定按 WRITE）：
  - READ-ONLY：解释/检索/审阅，可只读执行。
  - WRITE/SIDE-EFFECT：改文件、`apply_patch`、会改变工作区或 git 状态的命令。
- WRITE 请求顺序：
  1) 先用 plan 工具写/更新执行计划（优先遵守人类给定 plan）。
  2) 再按 ROUTE 打开对应系统 `references/route-*.md`，复制命令序列执行（不要凭记忆手敲）。
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
