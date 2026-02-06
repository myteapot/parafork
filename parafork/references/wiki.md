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
- 所有“回主分支”的动作必须携带 CLI 二次门闩（`--yes --i-am-maintainer`）。

3) 目录强约束（Worktree-root guard）
- 除 `help/init` 外，其余子命令必须在 parafork worktree 中执行（脚本会自动切到 `WORKTREE_ROOT`）。
- worktree-required 子命令还要求 `.worktree-symbol: WORKTREE_USED=1`（顺序门闩）。

4) 证据链完整但默认不污染仓库历史（No git pollution by default）
- `.worktree-symbol` 与 `paradoc/` 默认不得进入 git history。
- `do commit/check` 必须在 staged/tracked 层面做闭环防污染。

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
    parafork.sh
  powershell-scripts/
    _lib.ps1
    parafork.ps1
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

`init`（`parafork init --new`；或直接无参运行触发默认流程）会创建：

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
- `WORKTREE_BRANCH`
- `WORKTREE_USED`（`0|1`；顺序门闩，worktree-required 子命令要求为 `1`）
- `WORKTREE_LOCK`（`1`）/ `WORKTREE_LOCK_OWNER` / `WORKTREE_LOCK_AT`（并发门禁）
- `BASE_BRANCH`
- `CREATED_AT`（UTC）

并发门禁规则：
- 若缺失 `WORKTREE_LOCK*`（旧 worktree），脚本首次进入时会自动补锁。
- 若 `WORKTREE_LOCK_OWNER` 与当前 agent 不一致，worktree-required 命令会拒绝执行并要求人工接管。

---

## 5. 配置：`settings/config.toml`

配置是“默认策略”，不是安全边界。

字段约定：

```toml
[base]
branch = "main"

[workdir]
root = ".parafork"
rule = "{YYMMDD}-{HEX4}"

[custom]
autoplan = false       # true=创建+检查 paradoc/Plan.md
autoformat = true      # check 的文档结构/占位符检查开关

[control]
squash = true          # merge：true=--squash，false=--no-ff
```

Core-Lite 约束：创建/检查/合并均仅基于本地 `base.branch` 的已提交状态；不再依赖 remote 同步路径。

复用审批门闩：
- CLI 门闩：`--yes --i-am-maintainer`
- 必须满足后，`init --reuse` 才会放行。

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

1) 运行默认固定流程（无参）：

Windows（PowerShell）：
- `powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\parafork.ps1"`

Bash（Linux/macOS/WSL/Git-Bash）：
- `bash "<PARAFORK_BASH_SCRIPTS>/parafork.sh"`

> 可从 base repo / worktree 子目录 / worktree 根目录启动；默认总是 `init --new`（不自动复用），随后执行 `do exec`（摘要 + 校验）。

2) 按 task 微循环推进（`do exec` 不会自动 commit）：
   - 更新 `paradoc/Exec.md`（What/Why/Verify）
   - 运行 `do commit --message "..."` 保存进度：
     - PowerShell：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\parafork.ps1" do commit --message "..."`
     - Bash：`bash "<PARAFORK_BASH_SCRIPTS>/parafork.sh" do commit --message "..."`
   - 需要时可运行：`check status`（只读）

3) 合并前：
- 写 `paradoc/Merge.md`（必须包含验收/复现步骤关键字：Acceptance / Repro）
- 可先跑 `check merge` 生成材料 + 检查，并按 `NEXT` 执行

4) 合并回 base（仅 maintainer；需要 CLI 门闩）：

Windows（PowerShell）：
- 合并：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\parafork.ps1" merge --yes --i-am-maintainer`

Bash（Linux/macOS/WSL/Git-Bash）：
- 合并：`bash "<PARAFORK_BASH_SCRIPTS>/parafork.sh" merge --yes --i-am-maintainer`

不确定自己在哪个 worktree：
- PowerShell：`powershell -NoProfile -ExecutionPolicy Bypass -File "<PARAFORK_POWERSHELL_SCRIPTS>\parafork.ps1" help --debug`
- Bash：`bash "<PARAFORK_BASH_SCRIPTS>/parafork.sh" help --debug`

---

## 8. 顶层命令与分类

help 中仅展示以下顶层命令：
- `help` / `init`
- `do <action>`
- `check [topic]`
- `merge`（仅 maintainer；需 CLI 门闩）

允许在 base repo / 任意目录运行（base-allowed）：
- `parafork help [debug|--debug]`
- `parafork init ...`

必须在 parafork worktree 中运行（worktree-required；脚本会自动切到 `WORKTREE_ROOT`）：
- `parafork do exec|commit ...`
- `parafork check merge|status ...`
- `parafork merge ...`（仅 maintainer；需 CLI 门闩）

兼容性说明：
- 仅支持 canonical 顶层命令：`help/init/do/check/merge`。
- 非 Core-Lite 命令/主题（如 `watch`、`do pull`、`check diff/log/review`）均不再支持。
