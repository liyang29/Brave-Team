# 进度 / 任务完成情况

> 源文档见 `ROGUELIKE_DESIGN.md`。本文件只记"做到哪了 / 接下来做什么"。

## ✅ 已完成（从 Brave Guild 迁入的核心）

战斗与背包核心已在 Brave Guild 验证 + 测试通过，整块迁入本项目：

- **战斗引擎**：`BattleSimulator`（回合制自动结算）+ `BattleCombatant` + 各职业/敌人 `CombatStrategy` + `SkillTable`。
- **背包构筑**（`BackpackModel` + `BackpackExperiment`）：网格背包、物品占格、**邻接协同**（开刃/重装/共鸣/生机）。验证：巧搭 20/20 胜、乱搭 0/20。
- **技能书**：技能 = 占格背包物品，**认职业 + 回合冷却**（和装备抢空间）。
- **站位**：世界树式**软调整**（`Party.positioning_mode="soft_row"`）——后排近战输出×0.5、后排受物理伤×0.7、魔法/远程不受影响；前排至少留1人、前排全灭后排顶上。另有硬触及模式 `"reach"`（Grid/Position 实验用）。
- **副属性地基**：`BattleCombatant.extra_stats` 字典 + `BackpackModel.EXTRA_KEYS`。首个副属性 = **暴击**（crit_chance/crit_dmg）。加新 A 档属性≈改数据。
- **三个实验场景**：BackpackExperiment（主，软站位+背包+技能书+暴击）、GridExperiment（网格站位+逐列掩护）、PositionExperiment（2排站位）。
- **测试**：GUT 4 个文件（battle_simulator / backpack_experiment / position_experiment / grid_experiment）。

## ⬜ 预留到后期（已讨论，暂不做）

- **AI 选目标考虑站位**（治本）：`choose_target` 按"有效伤害=基础×站位倍率"选，避免前排去捅打折后排、战士分散打两个肉盾等"瞎打"。
- **玩家目标优先级策略按钮**（安全阀）：集火残血 / 点后排威胁 / 打高攻 / 各自本能。战前设、自动执行；保持轻量，别做成 FF12 Gambit。先治本 AI 再视情加。
- **敌方 spellcaster 名副其实**：`enemy_spell` 目前是占位（不在 SkillTable → 回退普攻）；给它配真魔法技能（use_magic）。
- 站位"前→后排"数值：当前 ×0.7（两修正叠乘）；世界树原版 ×0.5（满伤仅前→前）。待玩后定。
- 公共驮兽（共享后勤背包，战斗中不可掏、有代价）、负重、金币经济、更多副属性（法抗/吸血/破甲…见 stats 目录）、技能书参与邻接协同。

## 🎯 roguelike 跑局骨架

- [x] **入口 TitleScreen**（开始冒险/实验/退出）
- [x] **RunManager**（autoload）：状态机 + 队伍 + 金币 + 节点进度 + start/enter/resolve
- [x] **RunMap**：线性节点路径（3 战斗 + 1 魔王）+ 进度/队伍状态 + 胜利/失败横幅
- [x] **Encounter**：敌人/队伍预览 → 开战(BattleSimulator 软站位) → 结果 → 回报
- [x] **闭环跑通**：标题→地图→遭遇→回地图→魔王（通关/全灭）；HP 跨节点保留(消耗战)
- [ ] **把背包构筑接成"遭遇前 prep 界面"**（当前遭遇是纯自动；下一步让玩家战前搭背包/摆站位）← 下一步
- [ ] 节点地图升级为分支路径（杀戮尖塔式）+ 商店/事件节点 + 战利品
- [ ] 局间 meta 解锁；存档（roguelike 跑局）
- [ ] 平衡（起手队伍数值现为占位）

## 迁移记录（2026-06）

从 `Brave Guild` 迁入：战斗核心 + 实体数据层 + HeroFactory/EnemyAIFactory + Party + 背包实验 + GUT + 3 份设计文档。
**未迁入**（留旧项目）：公会经营层（Guild/Facility/Quest/Map/Turn Manager、WorldMap、HeroAI、设施任务 UI、ItemFactory(依赖 DataManager)、Quest/Facility 实体、六边形地图）。
**迁移时改动**：`Party` 移除依赖 HexUtils/HeroManager/Quest 的 to_dict/from_dict（roguelike 持久化交给将来的 RunManager）；project.godot 清空所有公会 autoload。
