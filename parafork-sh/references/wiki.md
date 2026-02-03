# Parafork（sh）维护者手册 / Wiki

本文档目标：让任何 maintainer / contributor（人类或 AI）在阅读后，能够：
- 理解 parafork 的设计原则、威胁模型与硬约束
- 理解 bash/sh 版本每个脚本的职责、接口、门闩、前置条件与副作用
- 能够安全地修改本仓库中的 `scripts/*.sh`、`settings/config.toml`、`assets/*`、`references/*`

> 本目录是 bash/sh 版本（适用于 Linux/macOS/WSL/Git-Bash）。

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

---

## 1. 设计原则（Maintainer 级硬约束）

1) 脚本优先（Script-first）
- 有对应 `scripts/*.sh` 时必须用脚本；禁止用裸 `git` 替代同用途脚本。

2) 安全默认（Safe by default）
- 默认阻止任何可能影响 base branch 的动作。
- 所有“回主分支”的动作必须同时满足：
  - 本地批准（env 或 base repo 的本地 git config）
  - CLI 二次门闩（`--yes --i-am-maintainer`）

3) 目录强约束（Worktree-root guard）
- 除 `help.sh/init.sh/debug.sh` 外，所有脚本必须在 `WORKTREE_ROOT` 执行。
- worktree-only 脚本还要求 `.worktree-symbol: WORKTREE_USED=1`（顺序门闩）。

4) 证据链完整但默认不污染仓库历史（No git pollution by default）
- `.worktree-symbol` 与 `paradoc/` 默认不得进入 git history。
- `commit.sh/check.sh` 必须在 staged/tracked 层面做闭环防污染。

5) 可审计（Auditable）
- worktree 内脚本输出应追加到 `paradoc/Log.txt`（含时间戳、脚本名、argv、pwd、exit code）。
- base-allowed 脚本在能定位到某个 worktree 时，也会记录到该 worktree 的 `Log.txt`。

6) 输出可解析（Machine-friendly）
- 关键脚本在成功/失败时输出统一输出块（连续 `KEY=VALUE` 行），至少包含：`WORKTREE_ID`、`PWD`、`STATUS`、`NEXT`。

---

## 2. 本包结构（parafork-sh）

以 `<PARAFORK_ROOT>` 表示本包根目录：

```
<PARAFORK_ROOT>/
  SKILL.md
  scripts/
    _lib.sh
    help.sh init.sh debug.sh
    status.sh check.sh commit.sh pull.sh merge.sh
    diff.sh log.sh review.sh
  assets/
    Plan.md Exec.md Merge.md
  references/
    How-to-write-plan.md
    wiki.md
  settings/
    config.toml
```

---

## 3. 目标仓库内“会出现”的内容（脚本运行后）

`init.sh --new` 会创建：

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
- 禁止 `source`/`eval`

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

## 6. 工作流（推荐最短路径）

1) 在 base repo 运行入口：`bash "<PARAFORK_SCRIPTS>/init.sh"`
2) 按 init 输出 `cd "<WORKTREE_ROOT>"` 进入 worktree 根目录
3) 运行 `status.sh` / `check.sh --phase exec` 查看摘要与基础检查
4) 微循环推进：更新 `paradoc/Exec.md` → `commit.sh --message "..."` 保存进度
5) 合并前：写 `paradoc/Merge.md` → `check.sh --phase merge`
6) maintainer 批准后运行 `merge.sh --yes --i-am-maintainer` 合并回 base

---

## 7. 脚本清单与分类

允许在 base repo 运行（base-allowed）：
- `help.sh`
- `init.sh`
- `debug.sh`

只能在 worktree 根目录运行（worktree-only）：
- `status.sh`
- `check.sh`
- `commit.sh`
- `pull.sh`
- `merge.sh`
- `diff.sh` / `log.sh` / `review.sh`

