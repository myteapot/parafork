---
name: parafork
description: "单入口脚本优先的 Git worktree 工作流（默认 watch 固定流程；顶层命令收敛为 help/debug/init/watch/check/do/merge；旧命令 status/commit/pull/diff/log/review 仅弃用兼容）。安全默认：任何写操作（含 apply_patch）必须先 init 或 watch 引导进入 WORKTREE_ROOT；base repo 默认只读（仅 help/init/debug/watch）。系统相关命令见 references/route-*.md。"
---

# Parafork

## MUST
- 激活：阅读/使用本 skill 即视为接受本文件约束。
- base repo 默认只读：禁止在 base repo 直接改文件（包括 `apply_patch`）；除 `help/init/debug/watch` 外，不在 base repo 运行任何脚本。
- 写操作必须进 worktree：任何 WRITE/SIDE-EFFECT 动作前必须先运行 `init`（或直接运行默认 `watch`）创建/复用 worktree，并进入 `WORKTREE_ROOT` 后再继续。
  - 在 base repo：`init` 无参等价 `--new`（推荐显式 `--new`）。
  - 在 worktree 内：`init` 无参会 FAIL，必须显式 `--reuse` 或 `--new`。
- 脚本优先：存在对应脚本时，禁止用裸 `git` 做同语义操作；必须超出脚本能力时先申请人类显式同意（给出命令、风险、回退）。
- 目录门闩：worktree-required 子命令只能在 parafork worktree 中执行（脚本会自动切到 `WORKTREE_ROOT`）；不确定位置先跑 `debug` 或直接跑 `watch`。
- 顺序门闩：worktree-only 脚本要求 `.worktree-symbol: WORKTREE_USED=1`；旧 worktree 需先 `init --reuse` 补写。
- `.worktree-symbol` 只能当数据文件（KEY=VALUE，按第一个 `=` 切分）；禁止 `source`/`eval`/dot-source/`Invoke-Expression`。
- 防污染：`.worktree-symbol` 与 `paradoc/` 默认不得进入 git history（exclude + staged 检查闭环）。
- 审计：worktree-only 脚本输出必须追加到 `paradoc/Log.txt`（时间戳、argv、pwd、exit code）。
- 冲突：遇到 merge/patch 冲突必须停下来交由人工处理；脚本不做自动 resolve。
- 合并门闩：禁止自动 merge；只有 maintainer 在显式批准后才能运行 `merge.*` 合并回主分支。

## RULES
- 先判定请求类型（不确定按 WRITE 处理）：
  - READ-ONLY：仅解释/审阅/搜索/对比；只读打开文件；运行不会写入仓库的命令。✅ 可不 `init`。
  - WRITE/SIDE-EFFECT：改文件/新增/删除/`apply_patch`/任何会改动工作区或 `git` 状态的命令。✅ 必须走 worktree 流程。
- WRITE 请求的顺序：
  1) 先用 plan 工具写/更新可执行的计划（优先遵守人类给的 plan）。
  2) 再按 ROUTE 打开对应系统的 `references/route-*.md`，检查并复制命令序列执行（不要凭记忆手敲）。
- 任何需要“裸 git”且脚本无对应能力：先停下，向人类申请同意后再做。

## SPECS
- 两套实现（同语义）：
  - Bash：`bash-scripts/parafork.sh`（入口）+ `bash-scripts/_lib.sh`（内部）
  - PowerShell：`powershell-scripts/parafork.ps1`（入口）+ `powershell-scripts/_lib.ps1`（内部）
- merge 需要双门闩：环境变量/本地 git config 的批准 + CLI `--yes --i-am-maintainer`（细节见 `references/wiki.md`）。
- `custom.autoplan` 默认 `false`（见 `settings/config.toml`）：只有 `custom.autoplan=true` 或 `check --strict` 时才会机械要求 `paradoc/Plan.md`。

## ROUTE
- 设计/术语/硬约束 SSOT：`references/wiki.md`
- 脚本清单与可运行范围：`references/scripts.md`
- Plan 写作（仅 autoplan/strict 适用）：`references/plan.md`
- Windows PowerShell 执行路线（规划后再打开）：`references/route-powershell.md`
- Bash 执行路线（规划后再打开）：`references/route-bash.md`
