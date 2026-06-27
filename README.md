# Brave Team

**小队背包 Roguelike** — Godot 4.6 + GDScript。带一支 3~5 人小队，边走边搭每个人的背包，打到魔王城。深度在**搭背包**，战斗**回合制自动结算**。

> 从 `Brave Guild`（公会经营模拟，已暂缓）迁出**战斗 + 背包核心**重新立项。参照 Megaloot / Backpack Hero / Backpack Battles（皆单角色），**差异化 = 小队**。

## 当前状态

白盒原型阶段，核心 = 可玩的**背包构筑脏实验**。主场景 `scenes/experiments/BackpackExperiment.tscn`。

已实现：网格背包 + 邻接协同、技能书（占格/认职业/回合冷却）、世界树式软站位、暴击 + 可扩展副属性地基。详见 `docs/PROGRESS.md`。

## 怎么跑

```powershell
# 运行游戏（入口 = 标题画面 TitleScreen，"开始冒险"暂进背包实验）
& $env:GODOT_PATH --path "D:\program\gameDev\Brave Team"

# 直接进背包实验（主玩法核心）
& $env:GODOT_PATH --path "D:\program\gameDev\Brave Team" res://scenes/experiments/BackpackExperiment.tscn

# 跑全部 GUT 测试（headless）
& $env:GODOT_PATH --path "D:\program\gameDev\Brave Team" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit

# 新增 class_name 后刷新全局类缓存
& $env:GODOT_PATH --path "D:\program\gameDev\Brave Team" --headless --import
```
（编辑器里直接打开本目录、F6 运行主场景亦可。）

## 文档导航

| 文档 | 内容 |
|------|------|
| `docs/ROGUELIKE_DESIGN.md` | **源文档**：定位/核心循环/四支柱/路线图/关键决策 |
| `docs/PROGRESS.md` | 任务完成情况（已做/预留/下一步）|
| `docs/METHODOLOGY.md` | 思想方法（怎么判断好不好玩、怎么做决策）|
| `docs/COMBAT_REVAMP_AUTOBATTLER.md` | 战斗模块细节 |
| `docs/COMBAT_STATS_CATALOG.md` | 战斗属性菜单（已有/可加）|
| `CLAUDE.md` | 代码库结构与开发约定 |

## 目录结构

```
scripts/
  systems/combat/     战斗核心（BattleSimulator/BattleCombatant/策略/TurnLog/BattleResult）
  systems/combat/strategies/  各职业与敌人 AI 策略
  systems/factories/  HeroFactory / EnemyAIFactory
  systems/run/        【预留】roguelike 跑局逻辑（RunManager/EncounterData/节点地图）
  systems/Party.gd    队伍（含站位/冷却/副属性注入）
  entities/           Hero/Combatant/EnemyData/StatBlock/Item 等数据层
  utils/SkillTable.gd 技能数据表
  experiments/        BackpackModel + 三个实验场景脚本
  ui/                 TitleScreen 等 UI 脚本
  autoload/           【预留】Autoload 单例（如 RunManager）
scenes/
  ui/                 TitleScreen.tscn（入口）
  experiments/        BackpackExperiment(主玩法) / Grid / Position
  run/                【预留】跑局/地图/遭遇/商店场景
resources/data/       【预留】数据驱动 .tres（enemies/items/encounters/skills）
assets/               【预留】美术/音频占位（白盒阶段可空）
tests/                GUT 测试
addons/gut/           测试框架
docs/                 设计与方法文档
```

> 标【预留】的目录已建好空架子（含 `.gitkeep` 说明），等做 roguelike 跑局骨架时填充。
