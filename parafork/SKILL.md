---
name: parafork
description: "Core-Lite 单入口 Git worktree 工作流（仅 help/init/do/check/merge）。默认无参执行 init --new + do exec；do exec 仅保留 --strict；复用/合并仅需 CLI 门闩；锁冲突默认新开 worktree、接管为高风险备选。执行命令仅看 references/route-bash.md 或 references/route-powershell.md。"
---
---------------------- Parafork SKILL.md开始符号 ----------------------
# Parafork 技能协议
- 当你看到此段文字，代表用户意图显式激活此 SKILL。阅读/使用本 skill 即视为同意并接受本文件约束。
- 本文件是必须遵守的任务协议，不是参考建议。读取本文件后，任何修改都必须遵循本协议，不得绕开流程直接改仓库。

## Hard Gates（硬门闩）
- **1.目录与写权限**
  - base repo 默认只读：禁止在 base repo 直接改文件（包括 `apply_patch`）；仅允许 `help/init` 在 base repo 执行。
  - 写操作必须先进入 worktree：任何 WRITE/SIDE-EFFECT 前，必须先 `init --new`（或无参默认流程），并进入 `WORKTREE_ROOT`。

- **2.命令白名单**
  - 命令面固定：仅支持 `help/init/do/check/merge`。
  - `do` 仅允许 `exec|commit`；`check` 仅允许 `status|merge`。
  - `do exec` 仅允许参数：`--strict`（不再支持 `--loop/--interval`）。

- **3.复用门闩（init --reuse）**
  - 仅允许通过 `init --reuse` 复用。
  - `init --reuse` 仅允许在已有 parafork worktree 内执行。
  - 必须携带 CLI 门闩：`--yes --i-am-maintainer`。
  - 使用前必须先向人类发起审批请求（至少包含：目的、命令、风险、回退），并收到明确同意。

- **4.并发锁门闩**
  - 若 `WORKTREE_LOCK_OWNER` 非当前 agent，必须拒绝。
  - 默认 `NEXT` 必须推荐 `init --new`（新开 worktree）。
  - 接管复用仅作为高风险备选，且必须先获人类明确批准。

- **5.合并门闩（merge）**
  - merge 禁止自动执行；仅 maintainer 显式批准后可运行。
  - 必须携带 CLI 门闩（`--yes --i-am-maintainer`），并自动触发 merge 前检查链。
  - 使用前必须先向人类发起审批请求（至少包含：目的、命令、风险、回退），并收到明确同意。

- **6.执行安全规则**
  - 脚本优先：有脚本能力时禁止裸 `git`；若脚本无覆盖，必须先申请人类同意（命令、风险、回退）。
  - 冲突硬门闩：检测到 `merge/rebase/cherry-pick` 冲突态时，仅可诊断与建议；未经人类明确批准，禁止执行相关git操作或继续前进。

- **7.数据与审计规则**
  - `.worktree-symbol` 仅作数据文件（KEY=VALUE，按首个 `=` 切分）；禁止 `source/eval/dot-source/Invoke-Expression`。
  - `.worktree-symbol` 与 `paradoc/` 默认不得进入 git history；worktree-only 输出应写入 `paradoc/Log.txt`。

## Execution Algorithm（执行算法）
- **步骤 1：判定请求类型**
  - `READ-ONLY`：解释/检索/审阅，可只读执行。
  - `WRITE/SIDE-EFFECT`：改文件、`apply_patch`、或任何会改变状态的命令。
  - `SIDE-EFFECT` 明确定义：会改变工作区、git 状态、worktree 元数据或审计状态（例如 `init --new/--reuse`、`do commit`、`merge`、写 `paradoc/Log.txt`）。

- **步骤 2：WRITE/SIDE-EFFECT 固定顺序**
  1. 先用 plan 工具写/更新执行计划（优先遵守人类给定 plan）。
  2. 再按平台只打开一个路由文档（Bash 或 PowerShell），按文档命令执行，不凭记忆手敲。
  3. 若命令包含 CLI 门闩（`--yes --i-am-maintainer`），先向人类提交审批请求并等待明确同意；未获同意不得执行。

## Failure Output（失败输出约定）
- **目录不确定**：先执行 `help --debug`；若仍不确定，停止并请求人类确认目标 repo/worktree。
- **收到 WRITE/SIDE-EFFECT 请求但不在 worktree**：先 `init --new`，再 `do exec`，之后才开始改动。
- **复用缺少 CLI 门闩或用户未明确复用**：直接 `FAIL`，输出可复制 `NEXT`（补 `--yes --i-am-maintainer`）。
- **需要 CLI 门闩但尚未获得人类明确批准**：直接 `FAIL`，输出审批请求模板；禁止自行补门闩继续执行。
- **锁冲突**：直接 `FAIL`；输出 `LOCK_OWNER/AGENT_ID/SAFE_NEXT/TAKEOVER_NEXT`，默认 `NEXT` 与 `SAFE_NEXT` 推荐 `init --new`。
- **旧命令请求**：直接 `FAIL`；旧命令指非 Core-Lite 命令（如 `watch`、`do pull`、`check diff/log/review`）。

## Route Entry（路由入口）
- **执行命令入口（仅二选一）**
  - Bash：`references/route-bash.md`
  - PowerShell：`references/route-powershell.md`

- **补充参考（非执行入口）**
  - `references/scripts.md`
  - `references/plan.md`
  - `references/regression-checklist.md`
  - `references/wiki.md`

## Specs（实现补充）
- **实现映射（同语义双栈）**
  - Bash：`bash-scripts/parafork.sh`（入口）+ `bash-scripts/_lib.sh`（内部）
  - PowerShell：`powershell-scripts/parafork.ps1`（入口）+ `powershell-scripts/_lib.ps1`（内部）

- **`custom.autoplan` 默认值与触发条件**
  - 默认 `false`（见 `settings/config.toml`）。
  - 仅 `custom.autoplan=true` 或 `check --strict` 时机械要求 `paradoc/Plan.md`。

---------------------- Parafork SKILL.md截止符号 ----------------------
