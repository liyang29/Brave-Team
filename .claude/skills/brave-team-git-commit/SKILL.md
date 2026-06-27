---
name: brave-team-git-commit
description: >
  Commit (and push if a remote exists) Brave Team project changes with an
  auto-generated descriptive Chinese message, AND auto-sync related docs first.
  Use whenever the user says "帮我提交", "commit", "push", "提交到 git",
  "推送一下", "提交一下", "帮我 push", "commit changes", "save to git",
  "帮我更新文档", "更新一下文档", or anything implying they want to persist work
  or keep docs in sync. Always use this skill — don't do a manual commit without it.
---

# Brave Team Git Commit + Docs Sync

自动同步相关文档、生成规范 commit message、提交（有远程则推送到当前分支）。

**项目路径**：`D:\program\gameDev\Brave Team`
**文档路径**：`D:\program\gameDev\Brave Team\docs`
（本项目是普通 git 仓库，不使用 worktree；默认分支 `master`，可能尚未配置远程。）

---

## 工作流

### 1. 检查改动

并行运行：
```bash
git -C "D:\program\gameDev\Brave Team" status
git -C "D:\program\gameDev\Brave Team" diff HEAD
```
工作区干净（无改动）→ 告知用户并停止。

---

### 2. 判断要更新哪些文档

读 diff，对照下表（**先 Read 再 Edit，不盲写**）：

| 文档 | 何时更新 |
|------|---------|
| `docs/PROGRESS.md` | **每次基本都更**：勾选已完成项 / 补"做到哪了" |
| `docs/ROGUELIKE_DESIGN.md` | 核心循环/支柱/关键决策发生变化时 |
| `docs/COMBAT_REVAMP_AUTOBATTLER.md` | 战斗模块（站位/技能/伤害/AI）有实质变化时 |
| `docs/COMBAT_STATS_CATALOG.md` | 新增/落地某战斗属性时（更新 ✓/◐/➕）|
| `README.md` | 目录结构、运行方式、入口变化时 |
| `docs/METHODOLOGY.md` | **不自动更新**，方法论讨论才改 |
| `CLAUDE.md` | **不自动更新**，开发约定/架构变化才改 |

PROGRESS.md 勾选标准：新增了对应脚本/场景/系统 → 勾 `[x]`；不确定 → 保持 `[ ]`。

---

### 3. 判断 commit 类型

| 类型 | 适用 |
|------|------|
| `feat` | 新功能/系统/场景/脚本 |
| `fix` | bug/崩溃/逻辑错误 |
| `refactor` | 行为不变的重组 |
| `docs` | 只改 docs/md |
| `balance` | 数值（技能/属性/敌人/经济）调整 |
| `chore` | 配置/.gitignore/project.godot |

代码+文档混改 → 以主要改动（代码）为准。

---

### 4. 生成 commit message

```
<type>(<scope>): <简短中文描述>

- <关键改动点1>（非显而易见时才写）
- <关键改动点2>

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

规则：
- 首行 ≤ 60 字，中文，祈使句（"修复"不是"修复了"）。
- scope 填主要受影响的系统/文件（如 `BattleSimulator`、`RunManager`、`docs`）。
- 显而易见就省略 body；多个关键点才列。
- **末尾保留 Co-Authored-By 行**（本项目约定）。
- 文档同步产生的改动包含在本次提交里，无需单独说明。

---

### 5. 暂存 + 提交

```bash
git -C "D:\program\gameDev\Brave Team" add -A
git -C "D:\program\gameDev\Brave Team" status   # 确认 .godot/ 未被包含
```
若 `.godot/` 被误暂存（.gitignore 应已忽略）：
```bash
git -C "D:\program\gameDev\Brave Team" restore --staged ".godot/"
```
提交（多行消息用 heredoc，见 Bash 工具说明）：
```bash
git -C "D:\program\gameDev\Brave Team" commit -F - <<'EOF'
<生成的 message>
EOF
```

---

### 6. 推送（仅当配置了远程）

```bash
git -C "D:\program\gameDev\Brave Team" remote
```
- **有远程**：推到当前分支
  ```bash
  BR=$(git -C "D:\program\gameDev\Brave Team" branch --show-current)
  git -C "D:\program\gameDev\Brave Team" push origin "$BR"
  ```
  push 失败（远端有新提交）→ 提示先 pull 再推，**不要强推**。
- **无远程**：跳过推送，告知用户"已本地提交；要云端备份请先新建远程仓库并 `git remote add origin <url>`"。

---

### 7. 汇报

完成后告知：短 commit hash、用的 message、同步了哪些文档、是否推送（或为何没推）。
