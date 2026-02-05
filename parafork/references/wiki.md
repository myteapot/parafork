# Parafork（general）维护者手册 / Wiki

本文档目标：让任何 maintainer / contributor（人类或 AI）在阅读后，能够：
- 理解 parafork 的设计原则、威胁模型与硬约束
- 理解合并版（general）脚本包的目录结构与对外接口
- 能够安全地修改本仓库中的 `bash-scripts/*.sh`、`powershell-scripts/*.ps1`、`settings/config.toml`、`assets/*`、`references/*`

> 本包是 **Bash + Windows PowerShell** 合并版：同一套语义，两套实现。  
> Windows 请用 PowerShell 脚本；Linux/macOS/WSL/Git-Bash 请用 bash 脚本。

---

## 0. 角色与术语

- Maintainer（人类）：决定是否合并回 base branch（主分支）的唯一决策者。
- Contributor（Agent/人类）：在隔离 worktree 内贡献代码、产出审计材料，等待 maintainer 批准后再合并。

关键术语：
- `BASE_ROOT`：目标仓库（base repo）的 git 根目录（`git rev-parse --show-toplevel`）。
- `WORKTREE_ROOT`：某次 session 的 worktree 根目录（默认在 `<BASE_ROOT>/.parafork/<WORKTREE_ID>/`）。
- `WORKTREE_ID`：session 标识（默认 `{YYMMDD}-{HEX4}`）。
- `.worktree-symbol`：worktree 根目录的标识/数据文件，用于强约束与 UX 提示。
- `paradoc/`：worktree 内的审计材料目录（Exec/Merge/Log；Plan 为可选）。

本文档中：
- `<PARAFORK_ROOT>`：本包根目录
- `<PARAFORK_BASH_SCRIPTS>`：`<PARAFORK_ROOT>/bash-scripts`
- `<PARAFORK_POWERSHELL_SCRIPTS>`：`<PARAFORK_ROOT>/powershell-scripts`

---

## 1. 设计原则（Maintainer 级硬约束）

1) 脚本优先（Script-first）
- 有对应脚本时必须用脚本；禁止用裸 `git` 替代同用途脚本。

2) 安全默认（Safe by default）
- 默认阻止任何可能影响 base branch 的动作。
- 所有“回主分支”的动作必须同时满足：
  - 本地批准（env 或 base repo 的本地 git config）
  - CLI 二次门闩（`--yes --i-am-maintainer`）

3) 目录强约束（Worktree-root guard）
- 除 `help/init/debug` 外，所有脚本必须在 `WORKTREE_ROOT` 执行。
- worktree-only 脚本还要求 `.worktree-symbol: WORKTREE_USED=1`（顺序门闩）。

4) 证据链完整但默认不污染仓库历史（No git pollution by default）
- `.worktree-symbol` 与 `paradoc/` 默认不得进入 git history。
- `commit/check` 必须在 staged/tracked 层面做闭环防污染。

5) 可审计（Auditable）
- worktree 内脚本输出应追加到 `paradoc/Log.txt`（含时间戳、脚本名、argv、pwd、exit code）。
- base-allowed 脚本在能定位到某个 worktree 时，也会记录到该 worktree 的 `Log.txt`。

6) 输出可解析（Machine-friendly）
- 关键脚本在成功/失败时输出统一输出块（连续 `KEY=VALUE` 行），至少包含：`WORKTREE_ID`、`PWD`、`STATUS`、`NEXT`。

---

## 2. 本包结构（parafork）

以 `<PARAFORK_ROOT>` 表示本包根目录：

```
<PARAFORK_ROOT>/
  SKILL.md
  bash-scripts/
    _lib.sh
    help.sh init.sh debug.sh
    status.sh check.sh commit.sh pull.sh merge.sh
    diff.sh log.sh review.sh
  powershell-scripts/
    _lib.ps1
    help.ps1 init.ps1 debug.ps1
    status.ps1 check.ps1 commit.ps1 pull.ps1 merge.ps1
    diff.ps1 log.ps1 review.ps1
  assets/
    Plan.md Exec.md Merge.md
  references/
    plan.md
    scripts.md
    route-bash.md
    route-powershell.md
    wiki.md
  settings/
    config.toml
```

---

## 3. 目标仓库内“会出现”的内容（脚本运行后）

`init`（`init.sh --new` 或 `init.ps1 --new`）会创建：

```
<BASE_ROOT>/.parafork/<WORKTREE_ID>/
  .worktree-symbol
  paradoc/
    Exec.md
    Merge.md
    Log.txt
    Plan.md        # optional; only when custom.autoplan=true
```

并修改（追加）：
- `<BASE_ROOT>/.git/info/exclude`：忽略 `/<workdir.root>/`（默认 `/.parafork/`）
- `<WORKTREE_ROOT>/.git/info/exclude`：忽略 `/.worktree-symbol` 与 `/paradoc/`

---

## 4. 关键数据文件：`.worktree-symbol`

位置：`<WORKTREE_ROOT>/.worktree-symbol`

格式（硬要求）：
- 逐行 `KEY=VALUE`
- 解析必须按“第一个 `=`”分割（VALUE 允许包含空格与 `=`）
- 禁止任何形式的 eval/source/dot-source/`Invoke-Expression`

关键字段（最少集合）：
- `PARAFORK_WORKTREE=1`
- `WORKTREE_ID` / `BASE_ROOT` / `WORKTREE_ROOT`
- `WORKTREE_BRANCH` / `WORKTREE_START_POINT`
- `WORKTREE_USED`（`0|1`；顺序门闩，worktree-only 脚本要求为 `1`）
- `BASE_BRANCH` / `REMOTE_NAME`
- `BASE_BRANCH_SOURCE` / `REMOTE_NAME_SOURCE`（`config|cli|none`）
- `CREATED_AT`（UTC）

---

## 5. 配置：`settings/config.toml`

配置是“默认策略”，不是安全边界。

字段约定：

```toml
[base]
branch = "main"

[remote]
name = "origin"

[workdir]
root = ".parafork"
rule = "{YYMMDD}-{HEX4}"

[custom]
autoplan = false       # true=创建+检查 paradoc/Plan.md
autoformat = true      # check 的文档结构/占位符检查开关

[control]
squash = true          # merge：true=--squash，false=--no-ff
```

---

## 6. 统一输出块（机器可解析协议）

最低要求输出块（至少四行）：

```text
WORKTREE_ID=<...|UNKNOWN>
PWD=C:\abs\path
STATUS=PASS|FAIL
NEXT=<copy/paste next step>
```

---

## 7. 工作流（推荐最短路径）

Contributor 最短路径（典型）：

1) 在 base repo 运行 `init`（唯一入口）：

Windows（PowerShell）：
- `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\init.ps1"`
- 若已在某个 worktree 内：无参直接 FAIL，必须显式二选一：
  - 继续当前：`... init.ps1 --reuse`
  - 新开一个：`... init.ps1 --new`

Bash（Linux/macOS/WSL/Git-Bash）：
- `bash "<PARAFORK_BASH_SCRIPTS>/init.sh"`
- 若已在某个 worktree 内：无参直接 FAIL，必须显式二选一：
  - 继续当前：`... init.sh --reuse`
  - 新开一个：`... init.sh --new`

2) `cd "<WORKTREE_ROOT>"` 进入 worktree 根目录
3) 运行 `status` / `check --phase exec` 查看摘要与基础检查：

Windows（PowerShell）：
- `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\status.ps1"`
- `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\check.ps1" --phase exec`

Bash（Linux/macOS/WSL/Git-Bash）：
- `bash "<PARAFORK_BASH_SCRIPTS>/status.sh"`
- `bash "<PARAFORK_BASH_SCRIPTS>/check.sh" --phase exec`

4) 按 task 微循环推进：
   - 用模型 plan 工具规划/更新（优先遵守人类提供的 plan）
   - 更新 `paradoc/Exec.md`（What/Why/Verify）
   - 运行 `commit --message "..."` 保存进度：
     - PowerShell：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\commit.ps1" --message "..."`
     - Bash：`bash "<PARAFORK_BASH_SCRIPTS>/commit.sh" --message "..."`
   - 仅当 `custom.autoplan=true` 时维护 `paradoc/Plan.md`（会被 `check` 纳入检查）

5) 合并前：
- 写 `paradoc/Merge.md`（必须包含验收/复现步骤关键字：Acceptance / Repro）
- 运行 merge 阶段检查：
  - PowerShell：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\check.ps1" --phase merge`
  - Bash：`bash "<PARAFORK_BASH_SCRIPTS>/check.sh" --phase merge`

6) 合并回 base（仅 maintainer；需要本地批准 + CLI 门闩）：

Windows（PowerShell）：
- 一次性 env 批准：`set PARAFORK_APPROVE_MERGE=1`
- 合并：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\merge.ps1" --yes --i-am-maintainer`

Bash（Linux/macOS/WSL/Git-Bash）：
- 合并：`PARAFORK_APPROVE_MERGE=1 bash "<PARAFORK_BASH_SCRIPTS>/merge.sh" --yes --i-am-maintainer`

不确定自己在哪个 worktree：
- PowerShell：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\debug.ps1"`
- Bash：`bash "<PARAFORK_BASH_SCRIPTS>/debug.sh"`

---

## 8. 脚本清单与分类

允许在 base repo 运行（base-allowed）：
- `help.sh` / `help.ps1`
- `init.sh` / `init.ps1`
- `debug.sh` / `debug.ps1`

只能在 worktree 根目录运行（worktree-only）：
- `status.sh` / `status.ps1`
- `check.sh` / `check.ps1`
- `commit.sh` / `commit.ps1`
- `pull.sh` / `pull.ps1`
- `merge.sh` / `merge.ps1`
- `diff.sh` / `diff.ps1`
- `log.sh` / `log.ps1`
- `review.sh` / `review.ps1`
