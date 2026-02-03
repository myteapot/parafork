
### 我在使用此md的过程中遇到一个问题：如果我当前打开了一个其他worktree中的文件，那么当前的active目录会显示在worktree中。此时，如果我提出需求，agent不会运行init.sh新建worktree，而是在此worktree中继续工作。我希望：通过一个需要强行人类确认的参数来确定是否要在此worktree中继续修改，还是仍然新建一个worktree。必须经过人类同意。如何做？

#### 结论 / 实现方案（已落地到 parafork v13-cn）

现象原因：parafork 的脚本约束的是“脚本运行位置”（`_lib.sh: parafork_guard_worktree_root`），并不会强制 agent 每次任务都新建 session；当 IDE/active cwd 已经在某个 worktree 里时，agent 合理地会继续在该 worktree 推进。

为避免“人在不知情时复用已有 worktree”，落地方案把“选择 reuse/new”的逻辑合并进 `init.sh`（不新增 `enter.sh`），并引入 `.worktree-symbol: WORKTREE_USED` 的硬门闩：

- `init.sh` 是唯一入口：
  - 在 base repo：`bash "<PARAFORK_SCRIPTS>/init.sh"` 无参默认创建新 worktree（等同 `--new`）
  - 在某个 worktree 内：无参直接 FAIL，并输出“当前在什么 worktree”，要求显式二选一：
    - `--reuse`：继续在当前 worktree 内工作（并写入 `WORKTREE_USED=1`）
    - `--new`：回到 `BASE_ROOT` 并创建一个新的 worktree（避免在 worktree 里套 worktree）

- `.worktree-symbol` 增加字段 `WORKTREE_USED=0|1`：
  - 新创建 worktree：直接写 `WORKTREE_USED=1`（创建后立刻可用）
  - 旧 worktree（没有该字段）：第一次运行任意 worktree-only 脚本会 FAIL，提示先 `init.sh --reuse` 补写

- worktree-only 脚本增加硬门闩（顺序门闩）：
  - `_lib.sh: parafork_guard_worktree_root` 在校验 `.worktree-symbol` 后先检查 `WORKTREE_USED==1`
  - 若不是 1：直接 FAIL，且输出块 `NEXT` 指向 `bash "<PARAFORK_SCRIPTS>/init.sh" --reuse`

- 可审计日志（`paradoc/Log.txt`）：
  - worktree-only 脚本保持“tee + exit code trap”
  - base-allowed 脚本（`help.sh/debug.sh/init.sh`）在能定位到某个 worktree 时，也会把输出记到该 worktree 的 `paradoc/Log.txt`


### parafork中的check.sh是如何检查md文件是否规范的？如果我想要修改模板，能修改哪些部分？

#### check.sh 机械检查点（落地后）
- 必需文件：`paradoc/Exec.md`, `paradoc/Merge.md`, `paradoc/Log.txt`
- 可选文件：`paradoc/Plan.md`（仅当 `custom.autoplan=true` 或 `--strict` 时要求存在并检查）
- 文档结构检查（受 `custom.autoformat` 控制；`--strict` 强制开启）：
  - 启用 Plan 时：Plan 必须含 `## Milestones`、`## Tasks`，且至少一个 checkbox；merge 阶段不允许存在未完成的 `- [ ] T<number>`
  - Merge.md 必须包含 `Acceptance` 或 `Repro` 关键字（不区分大小写）
- 占位符检查（merge 或 strict）：`PARAFORK_TBD` / `TODO_TBD` 不得残留在 Exec/Merge（启用 Plan 时也会检查 Plan）
- merge 阶段 git 污染闭环：不得 tracked/staged `paradoc/` 或 `.worktree-symbol`

#### 模板能修改哪些部分？
- 可以自由修改“内容与格式”，但如果不想改 `check.sh`，必须保留这些机械约束：
  - `assets/Merge.md`：必须保留 `Acceptance` 或 `Repro` 关键字（否则 `check.sh` 会 FAIL）
  - `assets/Exec.md` / `assets/Merge.md`：merge/strict 阶段不能残留 `PARAFORK_TBD`/`TODO_TBD`
  - `assets/Plan.md`：仅在 `custom.autoplan=true` 时会被创建并检查；此时必须保留 `## Milestones` / `## Tasks` 与 checkbox 结构
- 若要更改“机械规则”（例如换关键字/换标题），需要同步修改 `scripts/check.sh` 的判定逻辑。

#### 关于 Plan 的策略
- 默认 `custom.autoplan=false`：更推荐使用模型 plan 工具；Plan.md 不再是默认交付物
- 若人类提供了 plan（对话或文件），应优先遵守（这是 agent 工作约束，不是脚本硬约束）




