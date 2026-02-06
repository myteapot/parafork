# 如何写 `paradoc/Plan.md`

> 说明：默认 `settings/config.toml` 的 `custom.autoplan=false`，因此新 worktree 不会自动创建 `paradoc/Plan.md`，且 `check`（`parafork check`）默认也不会要求它存在。
>
> 当你把 `custom.autoplan=true`（或使用 `check --strict`）时，本指南适用并会被机械检查。

目标：让 maintainer 能机械判定“要做什么 / 进度如何 / 怎么验收”，并让 contributor 按 task 微循环稳定推进。

## 1) 结构（必须）

Plan 必须包含两个标题（严格字符串）：

- `## Milestones`
- `## Tasks`

并使用 checkbox：

```md
## Milestones
- [ ] M1: PARAFORK_TBD

## Tasks
- [ ] T1: PARAFORK_TBD（milestone: M1）— 验收：PARAFORK_TBD
```

## 2) 写 milestones

- milestone 是“可验收的阶段交付物”，通常 2–5 个即可。
- 每个 milestone 用一句话描述“交付是什么”，避免写成过程。

示例：
- `M1: Backend API`
- `M2: Frontend integration`
- `M3: Acceptance material`

## 3) 写 tasks（最重要）

每个 task 必须包含：
- 任务标题（可执行）
- 所属 milestone（`milestone: Mx`）
- 验收方式（必须可复制执行或可观察）

示例：
- `T2: 实现 GET /api/v1/search（milestone: M1）— 验收：curl 返回 total/items 且无 500`

## 4) 微循环（每个 task 的节奏）

完成一个 task（或达到可提交的最小增量）就做一次：
1) 更新 Plan（勾选/状态）
2) 运行提交命令保存进度：`parafork do commit --message "..."`
3) 更新 `paradoc/Exec.md`（What/Why/Verify）

## 5) 常见坑

- 只写 TODO、不写验收：会导致 merge 阶段 `check` 难以通过，也让 maintainer 无法复刻。
- task 太大：拆小到“1–2 次 commit 可完成”的粒度。
