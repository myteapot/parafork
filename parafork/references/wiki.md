# Parafork v13（v13-cn）维护者手册 / Wiki

本文档目标：让任何 maintainer / contributor（人类或 AI）在阅读后，能够：
- 理解 parafork v13 的设计原则、威胁模型与硬约束
- 理解每个脚本的职责、接口、门闩、前置条件与副作用
- 能够安全地修改本仓库中的 `scripts/*.sh`、`settings/config.toml`、`assets/*`、`references/*`

SSOT（单一事实来源）在本仓库外的设计文档：
- `parafork-design-doc/v13/Wikiv13.md`（规范 / 原则）
- `parafork-design-doc/v13/prdv13.md`（需求）
- `parafork-design-doc/v13/actv13.md`（实现方案）

> 重要：本 `v13-cn` 的“当前实现”与 SSOT 在 **路径假设** 上存在差异（见《与 SSOT 的差异》）。本文以“当前实现”为准，同时标注 SSOT 期望，避免误读。

---

## 0. 角色与术语

- Maintainer（人类）：决定是否合并回 base branch（主分支）的唯一决策者。
- Contributor（Agent/人类）：在隔离 worktree 内贡献代码、产出审计材料，等待 maintainer 批准后再合并。

关键术语：
- `BASE_ROOT`：目标仓库（base repo）的 git 根目录（`git rev-parse --show-toplevel`）。
- `WORKTREE_ROOT`：某次 session 的 worktree 根目录（默认在 `<BASE_ROOT>/.parafork/<WORKTREE_ID>/`）。
- `WORKTREE_ID`：session 标识（默认 `YYMMDD-HEX4`）。
- `.worktree-symbol`：worktree 根目录的标识/数据文件，用于强约束与 UX 提示。
- `paradoc/`：worktree 内的审计材料目录（Plan/Exec/Merge/Log）。

---

## 1. 设计原则（Maintainer 级硬约束）

这些原则来自 SSOT，并由脚本实现尽可能“机械化/自动化”执行：

1) 脚本优先（Script-first）
- 有对应 `scripts/*.sh` 时必须用脚本；禁止用裸 `git` 替代同用途脚本。
- 若无脚本但必须用 `git`：必须先向 maintainer 申请同意（命令/目的/风险/回退）。

2) 安全默认（Safe by default）
- 默认阻止任何可能影响 base branch 的动作。
- 所有“回主分支”的动作必须同时满足：
  - 本地批准（env 或 base repo 的本地 git config，且必须是 untracked）
  - CLI 二次门闩（`--yes --i-am-maintainer`）

3) 目录强约束（Worktree-root guard）
- 除 `help.sh/init.sh/debug.sh` 外，所有脚本必须在 `WORKTREE_ROOT` 执行。
- 即使在 worktree 子目录，脚本也必须拒绝并提示 `cd "$WORKTREE_ROOT"`。

4) 证据链完整但默认不污染仓库历史（No git pollution by default）
- `.worktree-symbol` 与 `paradoc/` 默认不得进入 git history。
- `init.sh` 必须写入 `.git/info/exclude`（优先本地 exclude，不污染 `.gitignore`）。
- `commit.sh/check.sh` 必须在“staged/tracked”层面做闭环防污染。

5) 可审计（Auditable）
- worktree-only 脚本输出应追加到 `paradoc/Log.txt`（含时间戳、脚本名、argv、pwd、exit code）。

6) 输出可解析（Machine-friendly）
- 关键脚本在成功/失败时输出统一输出块（连续 `KEY=VALUE` 行），至少包含：`WORKTREE_ID`、`PWD`、`STATUS`、`NEXT`。

> 安全声明：这些门闩是“防误操作”不是权限边界；真正的安全边界依赖 OS 权限、不同用户、以及“不把合并权限交给 agent”。

---

## 2. 本 skill 包结构（可修改的仓库内容）

以 `<PARAFORK_ROOT>` 表示本 skill 包根目录（本开发仓库中为 `parafork-dev/v13-cn/parafork/`）：

```
<PARAFORK_ROOT>/
  SKILL.md
  scripts/
    help.sh init.sh debug.sh status.sh check.sh commit.sh pull.sh merge.sh
    diff.sh log.sh review.sh
    _lib.sh
  assets/
    Plan.md Exec.md Merge.md
  references/
    How-to-write-plan.md
    wiki.md
  settings/
    config.toml
```

其中：
- `scripts/`：核心行为（尽量确定性、可审计）
- `assets/`：初始化时拷贝到 worktree 的模板
- `references/`：给 agent/maintainer/贡献者看的说明性材料
- `settings/config.toml`：默认策略（不是安全边界）

---

## 3. 目标仓库内“会出现”的内容（脚本运行后）

在目标仓库（`BASE_ROOT`）中，`init.sh` 会创建：

```
<BASE_ROOT>/.parafork/<WORKTREE_ID>/
  .worktree-symbol
  paradoc/
    Plan.md
    Exec.md
    Merge.md
    Log.txt
```

并修改（追加）：
- `<BASE_ROOT>/.git/info/exclude`：忽略 `/<workdir.root>/`（默认 `/.parafork/`）
- `<WORKTREE_ROOT>/.git/info/exclude`：忽略 `/.worktree-symbol` 与 `/paradoc/`

> 建议：IDE/rg/索引工具排除 `<BASE_ROOT>/.parafork/`，避免大仓库被拖慢。

---

## 4. 关键数据文件

### 4.1 `.worktree-symbol`（数据文件，禁止 source）

位置：`<WORKTREE_ROOT>/.worktree-symbol`

格式（硬要求）：
- 逐行 `KEY=VALUE`
- 解析必须按“第一个 `=`”分割（VALUE 允许包含空格与 `=`）
- 禁止 `source`/`eval`

当前实现写入的关键字段（最少集合）：
- `PARAFORK_WORKTREE=1`
- `PARAFORK_SPEC_VERSION=13`
- `WORKTREE_ID`
- `BASE_ROOT`
- `WORKTREE_ROOT`
- `WORKTREE_BRANCH`（默认 `parafork/<WORKTREE_ID>`）
- `WORKTREE_START_POINT`（`REMOTE/BASE_BRANCH` 或 `BASE_BRANCH`）
- `BASE_BRANCH` / `REMOTE_NAME`
- `BASE_BRANCH_SOURCE` / `REMOTE_NAME_SOURCE`（`config|cli|none`）
- `CREATED_AT`（UTC）

用途：
- guard：禁止在 base repo 或 worktree 子目录执行 worktree-only 脚本
- merge：强校验当前分支必须等于 `WORKTREE_BRANCH`，防“切错分支/拿错 worktree”
- drift：当 `*_SOURCE=config` 且 config 发生变化时，merge/pull 默认拒绝（除非 `--allow-config-drift --yes --i-am-maintainer`）

### 4.2 `paradoc/`（审计材料）

- `paradoc/Plan.md`：必须包含 `## Milestones`、`## Tasks` 且使用 checkbox
- `paradoc/Exec.md`：只写 What/Why/Verify（脚本输出在 `Log.txt`）
- `paradoc/Merge.md`：必须含 “Acceptance / Repro” 关键字（用于 `check.sh` 机械判定）
- `paradoc/Log.txt`：脚本输出（append-only），应包含时间戳段与 `exit: <code>`

模板来源：
- `init.sh` 从 `<PARAFORK_ROOT>/assets/{Plan,Exec,Merge}.md` 拷贝到 `<WORKTREE_ROOT>/paradoc/`

---

## 5. 配置：`settings/config.toml`

配置是“默认策略”，不是安全边界。

当前实现的读取位置（重要）：
- 所有脚本读取 `<PARAFORK_ROOT>/settings/config.toml`
- 若要修改默认行为，请直接修改该文件（本实现刻意不支持“外部指定 config 路径”）

字段（v13 约定）：

```toml
[base]
branch = "main"        # 真实合并目标（机械定义）

[remote]
name = "origin"        # 默认 fetch 的 remote（可为空；remote 不存在则视为不可用）

[workdir]
root = ".parafork"     # session 容器目录名（在 BASE_ROOT 下）
rule = "{YYMMDD}-{HEX4}"

[custom]
autoplan = true        # 预留：当前实现未使用
autoformat = true      # check.sh 的文档结构/占位符检查开关

[control]
squash = true          # merge.sh：true=--squash，false=--no-ff
```

强约束提醒（来自 SSOT）：
- 合并批准开关不得来自 tracked 的 `config.toml`（否则会把批准写进仓库历史并与 base clean 冲突）
- 批准只能来自：
  - `PARAFORK_APPROVE_MERGE=1`（一次性 env）
  - base repo 本地 git config：`git -C "$BASE_ROOT" config --local --bool parafork.approval.merge true`

---

## 6. 统一输出块（机器可解析协议）

所有脚本应在关键路径输出稳定的 `KEY=VALUE` 行，便于：
- 人类快速扫描
- agent/测试程序机械解析（例如只抓最后一个连续 `KEY=VALUE` 块）

最低要求输出块（至少四行）：

```text
WORKTREE_ID=<...|UNKNOWN>
PWD=/abs/path
STATUS=PASS|FAIL
NEXT=<copy/paste next step>
```

建议：
- 输出块行尽量连续、且同一个键只出现一次（便于解析）
- `NEXT` 必须是可复制执行的命令（包含必要的 `cd` 与脚本路径）

---

## 7. 工作流（推荐最短路径）

Contributor 最短路径（典型）：
1) 在目标仓库任意子目录：运行 `init.sh` 创建 worktree
2) `cd "$WORKTREE_ROOT"` 进入 worktree 根目录
3) `status.sh` 查看摘要状态
4) 填写/更新 `paradoc/Plan.md`，按任务微循环推进：
   - 更新 Plan → `commit.sh --message "..."` → 更新 Exec
5) 完成后写 `paradoc/Merge.md`（必须有验收/复现步骤）
6) maintainer 批准后在 worktree 根目录运行 `merge.sh` 合并回 base

Maintainer 把关点：
- 是否允许 `pull.sh` 使用 `rebase/merge`（高风险策略）
- 是否批准 `merge.sh`（本地批准 + CLI 二次门闩）
- 冲突处理属于人工决策域（脚本不自动 resolve）

---

## 8. 脚本接口文档（逐个）

本节以“当前实现”为准；脚本分为两类：
- base-allowed：`help.sh/init.sh/debug.sh`
- worktree-only：其余（必须通过 guard，且只能在 `WORKTREE_ROOT` 执行）

所有脚本默认：
- `set -euo pipefail`
- 使用 `SCRIPT_DIR="$(...${BASH_SOURCE[0]}...)"` 计算脚本目录，并 `source "$SCRIPT_DIR/_lib.sh"`

### 8.1 `scripts/help.sh`（base-allowed）

目的：
- 输出 quickstart、脚本清单、门闩要求

用法：
- `bash <PARAFORK_SCRIPTS>/help.sh`
- 无参数

输出：
- 统一输出块（`NEXT` 指向 `init.sh`）
- 文本说明（包含可复制的脚本绝对路径示例）

副作用：
- 无（不写入 repo）

### 8.2 `scripts/init.sh`（base-allowed，创建 session）

目的：
- 创建 worktree session
- 写 `.worktree-symbol`
- 初始化 `paradoc/*`
- 写 base/worktree 两处 exclude（闭环防污染）

用法：

```bash
bash <PARAFORK_SCRIPTS>/init.sh [options]
```

参数（当前实现）：
- `--base-branch <branch>`：覆盖本次 session 的 `BASE_BRANCH`（并写入 `BASE_BRANCH_SOURCE=cli`）
- `--remote <name>`：覆盖本次 session 的 `REMOTE_NAME`（并写入 `REMOTE_NAME_SOURCE=cli`）
- `--no-remote`：强制本次 `REMOTE_NAME` 为空（`REMOTE_NAME_SOURCE=none`）
- `--no-fetch`：remote 可用时跳过 fetch（高风险，要求 `--yes --i-am-maintainer`）
- `--yes`、`--i-am-maintainer`：危险参数的 CLI 门闩

关键行为：
- 计算 `BASE_ROOT`（必须在 git repo 内）
- 读取 `settings/config.toml`（至少：`base.branch/remote.name/workdir.*`）
- 判定 remote 是否可用：
  - `REMOTE_NAME` 非空，且 `git -C "$BASE_ROOT" remote get-url "$REMOTE_NAME"` 成功
- remote 可用且未 `--no-fetch`：`git -C "$BASE_ROOT" fetch "$REMOTE_NAME"`
- 计算 `WORKTREE_START_POINT`：
  - remote 可用：`"$REMOTE_NAME/$BASE_BRANCH"`
  - 否则：`"$BASE_BRANCH"`
- 创建 worktree：
  - 目录：`<BASE_ROOT>/<workdir.root>/<WORKTREE_ID>`
  - 分支：`parafork/<WORKTREE_ID>`
  - 命令：`git -C "$BASE_ROOT" worktree add ... -b ... "$WORKTREE_START_POINT"`
- 写 exclude（追加且去重）：
  - base：`/<workdir.root>/`
  - worktree：`/.worktree-symbol`、`/paradoc/`
- 拷贝模板：`assets/{Plan,Exec,Merge}.md -> paradoc/`
- 初始化 `paradoc/Log.txt`（写入 init header）

输出：
- `WORKTREE_ROOT/WORKTREE_START_POINT/START_COMMIT/BASE_COMMIT` 的 `KEY=VALUE` 行
- 统一输出块（`NEXT=cd "$WORKTREE_ROOT" && bash "<PARAFORK_SCRIPTS>/status.sh"`）

常见失败：
- 不在 git repo：FAIL + 提示进入 `<BASE_ROOT>`
- `WORKTREE_START_POINT` 无效：ERROR（通常是 base branch/remote 配错）
- 模板缺失或目标文件已存在：ERROR（拒绝覆盖）

### 8.3 `scripts/debug.sh`（base-allowed，定位/排错入口）

目的：
- 当你不知道自己在 base 还是 worktree、或者脚本提示目录不对时，提供“下一步”指引。

行为（分支）：
- 若从当前目录向上找到 `.worktree-symbol`：
  - 输出 `SYMBOL_PATH=...`
  - 输出块 `NEXT` 指向：
    - 若能读到 `WORKTREE_ROOT`：`cd "$WORKTREE_ROOT" && status.sh`
    - 否则：`help.sh`
  - 若能唯一定位 worktree 且存在 `paradoc/Log.txt`：会追加一段 debug 记录到该 Log.txt
- 若未找到 symbol，但在 git repo 内：
  - 读取 `workdir.root`，查找 `<BASE_ROOT>/<workdir.root>/` 下的候选 worktree（新到旧）
  - 输出列表并默认选择最新的一个，给出 `cd ... && status.sh`
- 若完全不在 git repo：
  - FAIL + 提示 `cd <BASE_ROOT> && init.sh`

### 8.4 `scripts/status.sh`（worktree-only）

目的：
- 替代 `git status` 的摘要视图（并保持可审计输出）

用法：
- `bash <PARAFORK_SCRIPTS>/status.sh`

输出：
- `BRANCH/HEAD/CHANGES/BASE_BRANCH/REMOTE_NAME/WORKTREE_BRANCH`
- 输出块 `NEXT` 指向 `check.sh --phase exec`

### 8.5 `scripts/check.sh`（worktree-only）

目的：
- 机械校验交付物与“不得污染 git history”的硬约束

用法：

```bash
bash <PARAFORK_SCRIPTS>/check.sh [--phase plan|exec|merge] [--strict]
```

参数：
- `--phase plan|exec|merge`（当前默认 `merge`）
- `--strict`：强制开启文档结构检查与占位符检查

检查项（当前实现摘要）：
- 必须存在文件：
  - `paradoc/Plan.md`, `paradoc/Exec.md`, `paradoc/Merge.md`, `paradoc/Log.txt`
- 文档结构检查（受 `custom.autoformat` 控制；`--strict` 强制开启）：
  - Plan 必须含 `## Milestones`、`## Tasks`
  - Plan 必须至少有一个 checkbox 行（`- [.] `）
  - merge 阶段要求 tasks 完成：拒绝存在未完成的 `- [ ] T<number>` 行
  - Merge.md 必须包含 `Acceptance` 或 `Repro` 关键字（不区分大小写）
- 占位符检查（merge 或 strict）：
  - `PARAFORK_TBD` / `TODO_TBD` 不能残留在 Plan/Exec/Merge
- git 污染闭环（仅 merge 阶段）：
  - `git ls-files -- 'paradoc/'` 必须为空（不能被 tracked）
  - `git ls-files -- '.worktree-symbol'` 必须为空（不能被 tracked）
  - staged 不能包含 `paradoc/` 或 `.worktree-symbol`

输出：
- PASS：`CHECK_RESULT=PASS` + 输出块（`NEXT=status.sh`）
- FAIL：`CHECK_RESULT=FAIL` + `FAIL: ...` 列表 + 输出块（`NEXT=修复并重跑 check.sh`）

### 8.6 `scripts/commit.sh`（worktree-only）

目的：
- 在 worktree 内保存进度（提交到 worktree 分支），默认不允许提交 `paradoc/` 与 `.worktree-symbol`

用法：

```bash
bash <PARAFORK_SCRIPTS>/commit.sh --message "<msg>" [--no-check]
```

行为：
- 默认先跑：`check.sh --phase exec`（可用 `--no-check` 跳过）
- `git add -A -- .` 后检查 staged：
  - 若包含 `paradoc/` 或 `.worktree-symbol`：拒绝并提示 `git reset -q`
- 若无 staged 变更：拒绝（提示先修改文件）
- `git commit -m "<msg>"`

输出：
- `COMMIT=<shortsha>` + 输出块（`NEXT=status.sh`）

### 8.7 `scripts/pull.sh`（worktree-only）

目的：
- 把 base 的更新同步到 worktree（默认 `ff-only`，高风险策略必须“批准 + CLI 门闩”）

用法：

```bash
bash <PARAFORK_SCRIPTS>/pull.sh [--strategy ff-only|rebase|merge] [--no-fetch] [--allow-config-drift] [--yes --i-am-maintainer]
```

策略：
- `ff-only`（默认）：`git merge --ff-only "$upstream"`（非快进则拒绝）
- `rebase`（高风险）：需要批准 + `--yes --i-am-maintainer`，执行 `git rebase "$upstream"`
- `merge`（高风险）：需要批准 + `--yes --i-am-maintainer`，执行 `git merge --no-ff "$upstream"`

批准来源（高风险策略）：
- rebase：`PARAFORK_APPROVE_PULL_REBASE=1` 或 `git -C "$BASE_ROOT" config --bool parafork.approval.pull.rebase true`
- merge：`PARAFORK_APPROVE_PULL_MERGE=1` 或 `git -C "$BASE_ROOT" config --bool parafork.approval.pull.merge true`

其他要点：
- remote 可用且未 `--no-fetch`：先在 base repo `git fetch "$REMOTE_NAME"`，并以 `"$REMOTE_NAME/$BASE_BRANCH"` 作为 upstream
- 配置漂移：若 `*_SOURCE=config` 且 config 变化，默认拒绝；需要 `--allow-config-drift --yes --i-am-maintainer`

### 8.8 `scripts/merge.sh`（worktree-only，唯一回主分支入口）

目的：
- 把 worktree 改动带回 base branch（默认 squash merge）

用法：

```bash
bash <PARAFORK_SCRIPTS>/merge.sh [--message "<msg>"] [--no-fetch] [--allow-config-drift] --yes --i-am-maintainer
```

门闩与前置校验（当前实现）：
1) guard：必须在 worktree 根目录
2) config drift：默认拒绝（见 pull.sh）
3) 当前 worktree 分支强校验：
   - `git rev-parse --abbrev-ref HEAD` 必须等于 `.worktree-symbol: WORKTREE_BRANCH`
4) `check.sh --phase merge` 必须 PASS
5) base repo 清洁度（tracked）：
   - base tracked 必须 clean（忽略 untracked，但输出计数）
6) base branch 强校验：
   - base 当前分支必须等于 `.worktree-symbol: BASE_BRANCH`
7) remote base 对齐（严格）：
   - remote 可用且未 `--no-fetch`：`git -C "$BASE_ROOT" fetch "$REMOTE_NAME"` 后，
     必须 `git -C "$BASE_ROOT" merge --ff-only "$REMOTE_NAME/$BASE_BRANCH"` 成功，否则拒绝
   - 若使用 `--no-fetch`：需要 `--yes --i-am-maintainer`，并打印风险提示
8) preview（无论是否批准都会打印）：
   - commits：`$BASE_BRANCH..$WORKTREE_BRANCH`
   - files：`$BASE_BRANCH...$WORKTREE_BRANCH`
9) 本地批准（必须）：
   - `PARAFORK_APPROVE_MERGE=1` 或 `git -C "$BASE_ROOT" config --bool parafork.approval.merge true`
10) CLI 二次门闩（必须）：
   - `--yes --i-am-maintainer`

真实合并策略：
- 读取 `settings/config.toml [control].squash`：
  - `true`：`git -C "$BASE_ROOT" merge --squash "$WORKTREE_BRANCH"` + `git commit -m "<msg>"`
  - `false`：`git -C "$BASE_ROOT" merge --no-ff "$WORKTREE_BRANCH" -m "<msg>"`

输出：
- `MERGED_COMMIT=<shortsha>` + 输出块（`NEXT=run acceptance steps in paradoc/Merge.md`）

冲突策略：
- 脚本不自动 resolve；若冲突，脚本会停止并提示 maintainer 手动处理并继续/中止（`merge --continue/--abort` 或 `rebase --continue/--abort`）。

### 8.9 `scripts/diff.sh`（worktree-only，SHOULD）

目的：
- 快速输出与 base branch 的 diff（stat + full diff）

输出：
- `DIFF_RANGE=$BASE_BRANCH...HEAD` + `git diff --stat` + `git diff` + 输出块

### 8.10 `scripts/log.sh`（worktree-only，SHOULD）

用法：
- `bash <PARAFORK_SCRIPTS>/log.sh [--limit N]`

输出：
- `git log --oneline --decorate -n N` + 输出块

### 8.11 `scripts/review.sh`（worktree-only，SHOULD）

目的：
- 生成可直接复制进 `paradoc/Merge.md` 的 review 素材（commits/files/notes）

输出：
- commits：`$BASE_BRANCH..$WORKTREE_BRANCH`
- files：`$BASE_BRANCH...$WORKTREE_BRANCH`
- notes 提示
- 输出块 `NEXT` 指向：编辑 `Merge.md` 后跑 `check.sh --phase merge`

### 8.12 `scripts/_lib.sh`（开发期共享库）

定位：
- 由各脚本 `source "$SCRIPT_DIR/_lib.sh"` 引入（脚本目录通过 `BASH_SOURCE[0]` 计算，避免依赖 `pwd`）

主要职责（函数族）：
- 时间与错误处理：`parafork_now_utc`、`parafork_die`、`parafork_warn`
- 路径定位：`parafork_script_dir`、`parafork_root_dir`、`parafork_script_path`
- TOML 读取（轻量 awk）：`parafork_toml_get_str`、`parafork_toml_get_bool`
- git 工具：`parafork_git_toplevel`、`parafork_git_path_abs`、`parafork_is_remote_available`
- symbol：`parafork_symbol_find_upwards`、`parafork_symbol_get`
- guard（硬约束）：`parafork_guard_worktree_root`
- 日志包装：`parafork_enable_worktree_logging`（tee + exit code trap）
- 门闩：`parafork_require_yes_i_am_maintainer_for_flag`
- 漂移检测：`parafork_check_config_drift`

实现注意点：
- `.worktree-symbol` 解析按第一个 `=` 分割，且不 `source`
- `parafork_enable_worktree_logging` 使用 bash 的进程替换（必须 bash）

> SSOT 建议：开发期可用 `_lib.sh` 聚合公共逻辑；收敛期若坚持“每脚本自足”，可复制片段内联并移除 `_lib.sh`（见 `parafork-design-doc/v13/actv13.md` 的内联策略章节）。

---

## 9. 路径要求
- 不要求目标仓库存在 `parafork/` 目录；脚本之间通过 `SCRIPT_DIR`（脚本自身位置）互相调用。
- 配置从 `<PARAFORK_ROOT>/settings/config.toml` 读取；不支持外部显式覆盖（如 env 指定 config 路径）。
---

## 10. 开发与修改指南（修改脚本前必读）

### 10.1 修改任何脚本时必须保持的约束

- worktree-only 脚本必须调用 guard（否则会破坏“禁止在主目录执行”）
- 合并相关脚本必须保持“本地批准 + CLI 二次门闩”
- 不得引入 `source`/`eval` 解析 `.worktree-symbol`
- 不得让 `paradoc/` 与 `.worktree-symbol` 默认进入 git history
- 输出块（至少 `WORKTREE_ID/PWD/STATUS/NEXT`）必须稳定可解析

### 10.2 常用冒烟检查（建议）

在修改脚本后建议至少做：
- bash 语法检查：`bash -n scripts/*.sh`
- 选择一个临时 git repo，跑一遍：
  - `init.sh` → `cd` → `status.sh` → `check.sh --phase plan/exec/merge`
  - 修改一个文件并 `commit.sh`
  - `review.sh` 填充 Merge.md
  - 配置好批准后 `merge.sh`（建议在测试仓库）

### 10.3 常见扩展点

- 新增脚本：
  - 明确是 base-allowed 还是 worktree-only
  - worktree-only 必须复用 guard + logging + 输出块约定
- 加强污染闭环：
  - `commit.sh` 可考虑在 `git add` 时增加 pathspec 排除（双保险）
- 增加 `clean.sh`（危险操作）：
  - 必须设为 MAY
  - 必须要求 maintainer 明确批准（建议复用 `--yes --i-am-maintainer` + env/local config）

