# Parafork 测试记录（2026-02-06）

## 目标

验证本次重构后行为是否与 Core-Lite 预期一致，重点覆盖：

- 默认入口（无参）
- `init --reuse` 双门闩
- 并发锁冲突拒绝与接管
- `do commit` 污染防护
- `check merge --strict` 严格模式
- Bash / PowerShell 命令面与输出块稳定性

## 环境

- 日期：2026-02-06
- 执行目录：`/mnt/c/Users/29654/Desktop/pf-dev/parafork`
- Bash 入口：`bash parafork/bash-scripts/parafork.sh`
- PowerShell 入口：`pwsh -NoProfile -File parafork/powershell-scripts/parafork.ps1`

## 执行内容

### A) 基础冒烟

执行：`bash parafork/scripts/regression-smoke.sh`

结果：`EXIT=0`

结论：通过。Bash/PowerShell 的 `help`、`check --help`、`do --help`、`merge --help` 均正常，输出块字段保持 `WORKTREE_ID/PWD/STATUS/NEXT`。

---

### B) 关键门闩行为（临时仓库）

在临时 git 仓库中执行行为验证，覆盖 T01/T02/T03/T04/T05/T09 及 PowerShell `help`：

- `T01_default_noarg`
  - 预期：无参执行创建 worktree 并 `STATUS=PASS`
  - 实际：通过（创建 `.parafork/<WORKTREE_ID>`，输出 NEXT 到 `do exec`）
  - 结论：✅

- `T02_init_auto_in_worktree`
  - 预期：在 worktree 内 `init` 无参拒绝
  - 实际：`STATUS=FAIL`，并给出 `--reuse/--new` 选择与 NEXT
  - 结论：✅

- `T03a_reuse_missing_local_approval`
  - 预期：缺本地批准拒绝
  - 实际：拒绝并提示 `PARAFORK_APPROVE_REUSE`/git config
  - 结论：✅

- `T03b_reuse_missing_cli_gate`
  - 预期：缺 `--yes --i-am-maintainer` 拒绝
  - 实际：拒绝（`--reuse requires --yes --i-am-maintainer`）
  - 结论：✅

- `T03c_reuse_full_gate`
  - 预期：双门闩齐备通过
  - 实际：`MODE=reuse`，`WORKTREE_USED=1`，`STATUS=PASS`
  - 结论：✅

- `T04_lock_conflict`
  - 预期：锁 owner 不匹配时拒绝并输出接管信息
  - 实际：拒绝，输出 `LOCK_OWNER`、`AGENT_ID` 和 takeover NEXT
  - 结论：✅

- `T04b_lock_takeover`
  - 预期：人类批准接管后恢复
  - 实际：`init --reuse --yes --i-am-maintainer` 通过
  - 结论：✅

- `T05_pollution_gate`
  - 预期：staged 含 `paradoc/` 拒绝提交
  - 实际：拒绝并提示 `git pollution staged`
  - 结论：✅

- `T09_strict_requires_plan`
  - 预期：`check merge --strict` 强制 Plan 与占位符检查
  - 实际：失败并报告：缺 `Plan.md` + `Exec/Merge` 占位符残留
  - 结论：✅

- `PS_help`
  - 预期：PowerShell `help` 正常输出
  - 实际：`STATUS=PASS`，输出命令面与 NEXT 正常
  - 结论：✅

## 总结

- 本轮覆盖的关键行为与预期一致。
- 重构目标（不改变外部 CLI 语义，仅内部收敛）在已测范围内成立。
- 建议后续在真实 worktree 流程下补充 `merge` 双门闩与冲突态人工接管的人工验收（涉及 maintainer 决策链）。

## 备注

- 失败路径（如污染防护、strict 检查）会出现额外 fallback 输出块，这属于当前脚本错误收敛输出行为，不影响门闩判定结果。
