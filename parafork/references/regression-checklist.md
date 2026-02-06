# Parafork 回归检查清单（Core-Lite）

> 目标：在不改外部 CLI 的前提下，快速验证重构后核心行为是否保持兼容。

## 前置

- 在目标仓库 base root 执行。
- 保证可调用对应入口脚本：
  - Bash：`bash "<PARAFORK_ROOT>/bash-scripts/parafork.sh"`
  - PowerShell：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_ROOT>\powershell-scripts\parafork.ps1"`

下文用 `<ENTRY>` 表示入口命令。

## T-01 无参入口

1) 在 base repo 执行：`<ENTRY>`
2) 期望：
   - 输出 `STATUS=PASS`
   - 输出 `NEXT` 指向 `do exec` 或下一步编辑/提交
   - 创建新 `.parafork/<WORKTREE_ID>/`

## T-02 worktree 内 init 无参拒绝

1) 进入任意 worktree 根目录。
2) 执行：`<ENTRY> init`
3) 期望：
   - `STATUS=FAIL`
   - 输出“must choose --reuse or --new”
   - `NEXT` 给出可执行恢复路径

## T-03 reuse CLI 门闩

1) 在 worktree 内执行：`<ENTRY> init --reuse`（不带门闩）
2) 期望：失败，并提示 `--yes --i-am-maintainer`。
3) 执行：`<ENTRY> init --reuse --yes --i-am-maintainer`
4) 期望：通过，并输出 `WORKTREE_USED=1`。

## T-04 锁冲突拒绝

1) 人工将 `.worktree-symbol` 的 `WORKTREE_LOCK_OWNER` 改为非当前 agent。
2) 执行：`<ENTRY> do exec`
3) 期望：
   - `STATUS=FAIL`
   - 输出 `LOCK_OWNER` 与 `AGENT_ID`
   - 默认 `NEXT` 推荐 `init --new`
   - 同时给出 `SAFE_NEXT` 与 `TAKEOVER_NEXT`（接管需人类明确批准）

## T-05 commit 污染防护

1) 使 `paradoc/` 或 `.worktree-symbol` 进入 staged。
2) 执行：`<ENTRY> do commit --message "test"`
3) 期望：
   - 拒绝提交
   - 输出 `REFUSED: git pollution staged`

## T-06 check merge 占位符检查

1) 保留 `PARAFORK_TBD` 于 `paradoc/Exec.md` 或 `paradoc/Merge.md`。
2) 执行：`<ENTRY> check merge`
3) 期望：失败并报告 `placeholder remains`。

## T-07 merge CLI 门闩

1) 执行：`<ENTRY> merge`（不带 `--yes --i-am-maintainer`）
2) 期望：失败并提示 CLI 门闩。
3) 执行：`<ENTRY> merge --yes --i-am-maintainer`
4) 期望：不再因门闩失败（后续成败取决于 merge 前检查链与冲突情况）。

## T-08 Bash/PowerShell NEXT 语义一致

1) 分别在 Bash/PowerShell 执行 `help`、`help --debug`、`do exec`、`check merge`。
2) 期望：关键输出块字段一致：`WORKTREE_ID/PWD/STATUS/NEXT`。

## T-09 strict 模式

1) 保持 `custom.autoplan=false`。
2) 执行：`<ENTRY> check merge --strict`
3) 期望：在缺 `Plan.md` 或结构不合法时失败。

## T-10 审计日志

1) 依次执行：`do exec`、`do commit`、`check merge`。
2) 期望：`paradoc/Log.txt` 中存在对应时间段、命令、exit code 记录。

## 自动化冒烟（可选）

可在 skill 目录执行：

```bash
bash scripts/regression-smoke.sh
```

该脚本会做最小只读冒烟（help/--help/语法），不替代完整 gate 与 merge 场景验证。
