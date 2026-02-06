# Parafork 测试记录（2026-02-06）

## 目标

验证本次重构后行为是否与 Core-Lite 预期一致，重点覆盖：

- 默认入口（无参）
- `init --reuse` CLI 门闩
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

- `T03a_reuse_missing_cli_gate`
  - 预期：缺 `--yes --i-am-maintainer` 拒绝
  - 实际：拒绝（`--reuse requires --yes --i-am-maintainer`）
  - 结论：✅

- `T03b_reuse_full_gate`
  - 预期：CLI 门闩齐备通过
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

---

### C) 门闩模型变更补充验证（CLI-only + 审批前置）

- 范围：复用/合并的本地门闩移除，仅保留 CLI 门闩（`--yes --i-am-maintainer`）；并在 skill/route 文档中明确“先人类审批，再执行带门闩命令”。
- 代码核对：Bash 与 PowerShell 的 `init --reuse`、`merge` 均仅检查 CLI 门闩，未再读取本地 approval 配置。
- 文档核对：`SKILL.md`、`route-bash.md`、`route-powershell.md` 已统一“审批前置”文案。
- 冒烟复跑：`bash parafork/scripts/regression-smoke.sh` `EXIT=0`，命令面与帮助文本保持稳定。
- 结论：✅ 行为与当前设计一致（高风险动作由 CLI 门闩触发，策略层要求先获人类明确批准）。

---

### D) 文档冻结 + 脚本重写（中等简化）回归

- 日期：2026-02-07（UTC）
- 范围：`SKILL.md`、route/scripts/wiki/checklist 文档对齐；Bash/PowerShell 入口脚本按文档重写并收敛参数面。
- 参数面变更：`do exec` 仅保留 `--strict`，删除 `--loop/--interval`。
- 调试策略变更：`help --debug` 在 base 且存在旧 worktree 时，默认 `NEXT` 推荐 `init --new`，并输出 `SAFE_NEXT/TAKEOVER_NEXT` 与风险提示。

执行方式：

- 全回归脚本（临时仓库）：`/tmp/pf-check2.sh`
- 冒烟脚本：`bash parafork/scripts/regression-smoke.sh`

结果（T01~T10 + T08b）：

- `T01` 无参入口：✅
- `T02` worktree 内 `init` 无参拒绝：✅
- `T03` reuse CLI 门闩（缺失拒绝/齐备通过）：✅
- `T04` 锁冲突拒绝与接管恢复：✅
- `T05` commit 污染防护：✅
- `T06` merge 占位符检查：✅
- `T07` merge CLI 门闩（缺失拒绝/齐备进入链路）：✅
- `T08` Bash/PowerShell `STATUS/NEXT` 语义一致：✅
- `T08b` 文档路由一致性：✅
- `T09` strict 模式：✅
- `T10` 审计日志：✅

结论：✅ 本轮“文档先行 + 脚本重写 + 全回归 + 冒烟”通过。

## 总结

- 本轮覆盖的关键行为与预期一致。
- 在保留 `help/init/do/check/merge` 命令面的前提下，`do exec` 参数收敛为 `--strict`，并完成 Bash/PowerShell 双栈同语义重写。
- 建议后续在真实多人并发会话下补充“锁冲突接管审批链”的人工演练验证。

## 备注

- 失败路径（如污染防护、strict 检查）会出现额外 fallback 输出块，这属于当前脚本错误收敛输出行为，不影响门闩判定结果。
