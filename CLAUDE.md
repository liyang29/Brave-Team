# CLAUDE.md

本文件为 Claude Code 在 **Brave Team** 项目中工作的指南。务必遵守。

## 项目概览

**Brave Team** — Godot 4.6 + GDScript 的**小队背包 Roguelike**。从 `Brave Guild`（公会经营，已暂缓）迁出战斗+背包核心重新立项。核心 = **背包构筑**（搭背包决定战力），战斗**回合制自动结算**。差异化 = **小队**（vs Megaloot/Backpack Hero 等单角色背包游戏）。

主场景：`res://scenes/experiments/BackpackExperiment.tscn`（当前核心，背包构筑脏实验）。
测试框架：GUT。

**先读** `docs/ROGUELIKE_DESIGN.md`（方向源文档）、`docs/METHODOLOGY.md`（设计判断框架）、`docs/PROGRESS.md`（做到哪了）。

## 常用命令

Godot 可执行路径在环境变量 `$env:GODOT_PATH`（PowerShell）。

```powershell
# 运行主场景
& $env:GODOT_PATH --path "D:\program\gameDev\Brave Team" res://scenes/experiments/BackpackExperiment.tscn
# 跑全部 GUT 测试
& $env:GODOT_PATH --path "D:\program\gameDev\Brave Team" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
# 跑单个测试
& $env:GODOT_PATH --path "D:\program\gameDev\Brave Team" --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_backpack_experiment.gd -gexit
# 刷新全局类缓存（新增 class_name 后必做，否则报 "Identifier not declared"）
& $env:GODOT_PATH --path "D:\program\gameDev\Brave Team" --headless --import
```
⚠️ 经验：新建 `class_name` 类后，**单独跑一次 `--import`**（不要和测试同命令），否则缓存未刷新会报"未声明"。

## 架构：三层分离（沿用）

- **数据层**（Resource/RefCounted）：`Hero`/`Combatant`/`EnemyData`/`StatBlock`/`StatModifier`/`Item`/`Equipment`/`Consumable`，纯数据可序列化。
- **运行时层**（RefCounted，战斗后销毁）：`BattleCombatant`/`Party`/`BattleResult`/`TurnLog`。
- **视觉层**（Node）：实验场景脚本，不持有业务数据。

## 核心系统

| 文件 | 职责 |
|------|------|
| `scripts/autoload/RunManager.gd` | **跑局状态核心(autoload)**：状态机(MAP/ENCOUNTER/VICTORY/GAME_OVER)+队伍+金币+节点进度。`start_run/enter_current_node/resolve_encounter` |
| `scripts/ui/TitleScreen.gd` / `RunMap.gd` / `Encounter.gd` | 入口 / 节点地图 / 遭遇(开战→BattleSimulator→回报 RunManager) |
| `scripts/systems/combat/BattleSimulator.gd` | 回合制战斗模拟（纯静态）。入口 `simulate(party, enemy_data_list)` |
| `BattleCombatant.gd` | 战斗单位包装（含 row/col 站位、skill_cooldowns、extra_stats 副属性）|
| `CombatStrategy.gd` + `strategies/` | 各职业/敌人 AI（choose_target/choose_skill）|
| `utils/SkillTable.gd` | 技能数据表（倍率/类型/冷却等；伤害在 Simulator 实时算）|
| `systems/Party.gd` | 队伍 + 站位编队（formation_cell）+ positioning_mode + 冷却/副属性注入 |
| `systems/factories/HeroFactory.gd` | 按职业造英雄、注入策略 |
| `experiments/BackpackModel.gd` | 背包物品表 + 邻接协同 + compute()（纯数据/函数，preload 引入，无 class_name）|
| `experiments/BackpackExperiment.gd` | 背包构筑主实验场景（代码搭 UI）|

## 关键机制要点

- **伤害公式**：技能表只存倍率，伤害在 `BattleSimulator` 实时算 = `属性×倍率×暴击×站位修正 − 防御/2`。
- **站位**：`Party.positioning_mode`，`"reach"`=硬触及（默认）/`"soft_row"`=世界树软调整（背包实验用）。软站位修正在 `_row_damage_mult`。
- **暴击/副属性**：`BattleCombatant.extra_stats` 字典 + `get_stat()`；加新副属性 = 扩 `BackpackModel.EXTRA_KEYS` + 物品声明 key + 公式读 `get_stat()`。
- **普攻统一走 `_basic_attack`**（含暴击/站位/装备触发），别再单独写普攻路径（曾因此漏算站位修正）。

## 开发约定

- **向后兼容**：新机制默认不改旧行为（站位默认 reach、副属性默认空、冷却默认无）。
- **每个改动配 GUT 测试，全量绿再合并。**
- **加属性/机制前先过"真抉择三要素"**（见 METHODOLOGY）：能造新 build/克制才加，只是"数字更大"不加。
- **只做深一个系统**：深度压在背包，战斗保持轻、自动；别叠第二个深空间谜题。
- 数据驱动，数值不硬编码进逻辑；继承 ≤ 3 层。
- i18n：玩家可见中文走 SkillTable 等的 `name_zh`；按需再引入翻译表。

## Git / 工作流

- **本项目直接在 `main` 分支开发，不使用 worktree 隔离。** 改动直接提交到 `main`（用 `brave-team-git-commit` skill）。
- 启动 Claude Code 时**从主仓目录 `D:\program\gameDev\Brave Team` 启动、不要开 worktree 隔离模式**。
- ⚠️ 例外：worktree 是会话**启动时**决定的，CLAUDE.md/会话中途都改不了。若本次会话已被放进 `.claude/worktrees/...`：
  - 优先**直接对主仓操作**（绝对路径读写 + `git -C "D:\program\gameDev\Brave Team"` 提交），避免“worktree 提交→再合并”这一步；
  - 或照旧在 worktree 提交后 fast-forward 合并回 `main`。
- 别为常规改动主动新建 worktree。

## 当前阶段 & 下一步

白盒原型。**跑局骨架已跑通**（标题→节点地图→遭遇自动战斗→回地图→魔王/全灭，由 RunManager 驱动）。背包/技能书/站位/暴击核心已验证（实验场景 + 71/71 测试）。

**下一步 = 把背包构筑接成"遭遇前 prep 界面"**：让玩家在 Encounter 开战前先搭背包/摆站位，把"纯自动战斗"变回"我搭的 build 在打"。再之后：分支地图/商店/战利品/meta。

实时进度与预留项（AI 选目标考虑站位、玩家策略按钮、驮兽、负重、更多副属性等）见 `docs/PROGRESS.md`。
