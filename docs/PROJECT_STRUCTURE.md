# 项目结构（核对用清单）

> 路径 → 文件 → 属性（类型 / 所属层 / 职责）的权威清单。新增/移动文件后回来对一下，保持同步。
> 概览版在 `README.md`；本文件是**逐文件细表**。最后核对：2026-06-28。

## 顶层目录

| 路径 | 属性 | 说明 |
|------|------|------|
| `scripts/` | 源码 | 全部 GDScript 逻辑（见下分层） |
| `scenes/` | 场景 | `.tscn`，UI/实验/跑局场景 |
| `tests/` | 测试 | GUT 测试（每个核心系统配一份） |
| `resources/data/` | **预留** | 数据驱动 `.tres`（enemies/items/encounters/skills），现仅 `.gitkeep` |
| `assets/` | **预留** | 美术/音频（art/audio），白盒阶段空 |
| `docs/` | 文档 | 设计 + 方法 + 进度 + 本结构文档 |
| `addons/gut/` | 第三方 | GUT 测试框架 |

**工程事实**（来自 `project.godot`）：
- **唯一 Autoload**：`RunManager`（`res://scripts/autoload/RunManager.gd`）。
- **主场景**：`res://scenes/ui/TitleScreen.tscn`。
- 引擎：Godot 4.6 + GDScript，渲染后端 d3d12。

---

## 架构分层（三层分离，本项目核心约定）

| 层 | 基类倾向 | 生命周期 | 例 |
|----|---------|---------|-----|
| **数据层** | `Resource` / `RefCounted` | 可序列化、长存 | Hero / EnemyData / Item / StatBlock |
| **运行时层** | `RefCounted` | 战斗后销毁 | BattleCombatant / Party / BattleResult / TurnLog |
| **视觉层** | `Node`（Control） | 场景生命周期，不持有业务数据 | 各 `ui/` `experiments/` 场景脚本 |

**class_name vs preload 约定**：稳定的数据/系统类用 `class_name` 注册全局名；**场景脚本和易受"全局类缓存时序"影响的纯函数模块（如 `BackpackModel`）故意不写 class_name，改用 `preload` 引入**。

---

## `scripts/` 逐文件

### `scripts/autoload/`
| 文件 | 属性 | 职责 |
|------|------|------|
| `RunManager.gd` | **Autoload**，`extends Node`，无 class_name（autoload 名即 `RunManager`） | 跑局状态核心：状态机(NONE/MAP/ENCOUNTER/VICTORY/GAME_OVER) + 队伍 + 金币 + 节点进度。`start_run/enter_current_node/resolve_encounter` |

### `scripts/entities/`（数据层）
| 文件 | 属性 | 职责 |
|------|------|------|
| `GameEntity.gd` | `class_name`，`extends Resource` | 所有实体根基类 |
| `Combatant.gd` | `class_name`，`extends GameEntity` | 可战斗实体（属性/HP/技能基础） |
| `Hero.gd` | `class_name`，`extends Combatant` | 英雄（含 HeroClass 枚举、学技能等） |
| `EnemyData.gd` | `class_name`，`extends Combatant` | 敌人数据（ai_type / preferred_row / is_ranged 等） |
| `StatBlock.gd` | `class_name`，`extends RefCounted` | 属性聚合 + 装备/修饰重建（`rebuild()`） |
| `StatModifier.gd` | `class_name`，`extends RefCounted` | 单条属性修饰 |
| `items/Item.gd` | `class_name`，`extends GameEntity` | 物品基类 |
| `items/Equipment.gd` | `class_name`，`extends Item` | 装备 |
| `items/Consumable.gd` | `class_name`，`extends Item` | 消耗品 |

> ⚠️ 注意：`entities/items/` 的 Item/Equipment/Consumable 是**旧实体物品体系**。当前背包实验的物品走 `experiments/BackpackModel.gd` 的 `ITEMS` 字典，**两者目前未打通**（背包用的是轻量 id+dict，不是这些 Resource）。

### `scripts/systems/`（系统层）
| 文件 | 属性 | 职责 |
|------|------|------|
| `Party.gd` | **运行时**，`class_name`，`extends RefCounted` | 队伍 + 站位编队(formation_cell) + positioning_mode + 冷却/副属性注入。`create()` / `set_row` / `set_skill_cd` / `set_extra_stats` |

#### `scripts/systems/combat/`（战斗核心）
| 文件 | 属性 | 职责 |
|------|------|------|
| `BattleSimulator.gd` | **静态工具**，`class_name`（隐式 RefCounted） | 回合制自动结算。入口 `simulate(party, enemy_data_list)`。伤害公式实时算、站位修正、暴击、DOT、前排顶上 |
| `BattleCombatant.gd` | **运行时**，`class_name`，`extends RefCounted` | 战斗单位包装（row/col 站位、skill_cooldowns、extra_stats 副属性、`get_stat()`） |
| `BattleResult.gd` | **运行时**，`class_name`，`extends RefCounted` | 战斗结果（party_won / total_turns / dead_heroes / turn_logs） |
| `TurnLog.gd` | **运行时**，`class_name`，`extends RefCounted` | 单步战斗日志（actor/target/skill/damage/crit/kill） |
| `CombatStrategy.gd` | `class_name`，`extends RefCounted` | AI 策略基类（`choose_target` / `choose_skill`） |

#### `scripts/systems/combat/strategies/`（AI 策略，皆 `class_name` + `extends CombatStrategy`）
| 文件 | 用于 |
|------|------|
| `WarriorStrategy` / `MageStrategy` / `RogueStrategy` / `ArcherStrategy` / `PriestStrategy` | 各职业英雄 AI |
| `BasicAttackStrategy` | 敌人兜底（普攻） |
| `AggressiveStrategy` / `TankStrategy` / `SpellcasterStrategy` / `PoisonCasterStrategy` / `ColumnPiercerStrategy` | 各敌人 AI 类型 |

#### `scripts/systems/factories/`（皆 `class_name`，全静态方法，无状态）
| 文件 | 职责 |
|------|------|
| `HeroFactory.gd` | 按职业造英雄：数据驱动属性/技能池(const dict) + 注入策略。`create(cls)` / `create_random()`。⚠️ `CLASS_STRATEGIES` 字典是死数据（`_inject_strategy` 实际用 match） |
| `MonsterFactory.gd` | 按 id 造怪物：`ENEMIES` const 表（加怪=加一行）→ `create(id, name_override)` 吐 `EnemyData`；`create_group(ids)` 批量。地图/实验都经它造怪（不再内联手搓） |
| `EnemyAIFactory.gd` | 按 `ai_type` 字符串造 `CombatStrategy`（只造 AI 策略，怪物数据归 MonsterFactory） |

#### `scripts/systems/run/`
| 路径 | 属性 | 说明 |
|------|------|------|
| `run/` | **预留** | 更复杂的跑局逻辑（EncounterData / 分支地图 / 商店），现仅 `.gitkeep` |

### `scripts/utils/`
| 文件 | 属性 | 职责 |
|------|------|------|
| `SkillTable.gd` | `class_name`（隐式 RefCounted），静态数据表 | 技能数据表（倍率/类型/冷却/职业/name_zh）。伤害在 Simulator 实时算 |

### `scripts/experiments/`（脏实验，背包核心在此）
| 文件 | 属性 | 职责 |
|------|------|------|
| `BackpackModel.gd` | **纯数据/函数**，`extends RefCounted`，**无 class_name（preload）** | 背包物品表 `ITEMS` + 协同 `SYNERGIES` + `compute(grid)`。背包引擎，可测可复用 |
| `BackpackExperiment.gd` | 视觉层，`extends Control`，无 class_name | 背包构筑主实验（代码搭 UI）。**当前主玩法核心** |
| `GridExperiment.gd` | 视觉层，`extends Control` | 网格站位 + 逐列掩护（硬触及）实验 |
| `PositionExperiment.gd` | 视觉层，`extends Control` | 2 排站位（硬触及）实验 |

### `scripts/ui/`（视觉层，皆 `extends Control`/容器，无 class_name）
| 文件 | 职责 |
|------|------|
| `TitleScreen.gd` | 入口标题（开始冒险直接进村庄/实验/退出） |
| `RunMap.gd` | 线性节点地图 + 进度/队伍状态 + 胜负横幅；按节点类型路由场景 |
| `Encounter.gd` | 遭遇：敌人预览 + 我方HP + **背包/站位编辑(BackpackPrepPanel)** → 开战(钳血) → 结果 → 回报 |
| `VillageScreen.gd` | 村庄：队伍列表 + 招募 + 商店（一屏；须招 ≥1 才能出发） |
| `RestScreen.gd` | 泉水：全员回 50% 血 |
| `DraftScreen.gd` | 战利品三选二 |
| `BackpackPrepPanel.gd` | 背包/站位编辑组件（VBoxContainer，拖放；实验+遭遇共用） |
| `DragSlot.gd` | 可拖放槽位（PanelContainer，实现 Godot 拖放三虚函数） |

---

## `scenes/`
| 路径 | 说明 |
|------|------|
| `scenes/ui/TitleScreen.tscn` | **主场景/入口** |
| `scenes/run/RunMap.tscn` | 节点地图 |
| `scenes/run/Encounter.tscn` | 遭遇（含背包 prep） |
| `scenes/run/Village.tscn` | 村庄（商店+招募+队伍列表） |
| `scenes/run/Rest.tscn` | 泉水回血 |
| `scenes/run/Draft.tscn` | 战利品三选二 |
| `scenes/experiments/BackpackExperiment.tscn` | **主玩法核心实验** |
| `scenes/experiments/GridExperiment.tscn` | 网格站位实验 |
| `scenes/experiments/PositionExperiment.tscn` | 站位实验 |

## `tests/`（GUT）
| 文件 | 覆盖 |
|------|------|
| `test_battle_simulator.gd` | 战斗结算 |
| `test_backpack_experiment.gd` | 背包/协同/技能书/暴击 |
| `test_grid_experiment.gd` | 网格站位 |
| `test_position_experiment.gd` | 2 排站位 |
| `test_run_manager.gd` | 跑局状态机 |

---

## 预留目录一览（已建空架子，等需要时填充）
- `resources/data/{enemies,items,encounters,skills}/` — 数据驱动 `.tres`
- `assets/{art,audio}/` — 美术/音频
- `scripts/systems/run/` — 复杂跑局逻辑

## 已知待整理（与本结构相关）
- `entities/items/`（Resource 物品体系）与 `experiments/BackpackModel.gd`（dict 物品体系）**未打通**，未来需定夺统一方案。
- `HeroFactory.CLASS_STRATEGIES` 死数据待清理。
- ~~无 MonsterFactory~~ → ✅ 已抽 `MonsterFactory` + `ENEMIES` 表，内联怪物已收编。
- 后期内容扩展（更多怪/Boss/节点/地图）方案见 `docs/SCALING_ROADMAP.md`。
