# 战斗手册（自动战斗怎么运作）

> 回合制 + 自动结算。玩家不手动指挥，**操控全在战前**（配技能书 / 摆站位 / 给装备）。
> 本手册讲清"开打后引擎怎么决策、伤害怎么算"。实现：`scripts/systems/combat/`。
> 数据：技能 `utils/SkillTable.gd`、怪物 `factories/MonsterFactory.gd`、副属性/协同 `experiments/BackpackModel.gd`。

---

## 1. 回合与出手顺序

- 战斗按"回合"循环，每回合开头先结算持续状态（DoT 掉血等），再让所有存活单位依次行动。
- **出手顺序 = 速度从高到低**（速度相同则英雄优先）。`BattleSimulator.gd:54`
- 不分敌我同池排序——速度最快的单位（无论敌我）先动。
- 当前低 base 速度参考：盗贼 16 > 法师/猎人 12 > 战士/牧师 9；怪物各有速度（毒虫 11、游侠 12…）。

## 2. 单个单位的回合流程 `BattleSimulator.gd:60`

轮到一个单位时，依次：
1. 技能冷却 −1
2. **被眩晕 → 跳过本回合**
3. 算对手列表 + 可触及目标（软站位下**人人可达**，站位只改伤害）
4. 嘲讽检测（场上有嘲讽单位 → 强制攻击它）
5. **选目标** `choose_target`（见 §3）
6. **选技能** `choose_skill`（见 §4；返回空 = 普攻）
7. 冷却中 / 蓝量不足 → **退化为普攻**
8. 执行（伤害/治疗/buff/施加状态）

## 3. 选目标：各职业/AI 的偏好

### 我方英雄
| 职业 | 选目标 | 定位 |
|------|--------|------|
| 战士 Warrior | **血最多**的（硬刚最肉） | 前排坦克 |
| 法师 Mage | **防最低**的（找软柿子） | 魔法核心输出 |
| 牧师 Priest | **血最少**的（补刀） | 治疗/神圣输出 |
| 盗贼 Rogue | **血最少**的（收残血） | 高速补刀 |
| 猎人 Archer | **攻最高**的（压威胁） | 远程物理 |

### 敌人 AI（`EnemyData.ai_type` → `EnemyAIFactory` → 策略）
| ai_type | 行为 |
|---------|------|
| `basic_attack` | 默认普攻（兜底） |
| `aggressive` | 激进进攻 |
| `tank` | 嘲讽，吸引火力 |
| `spellcaster` | 施放魔法 |
| `poison_caster` | 放毒（DoT） |
| `column_piercer` | 穿透/逐列 |

> 加 Boss/新 AI = 写一个 `CombatStrategy` 子类 + `EnemyAIFactory` 加分支 + 表里写 ai_type（详见 `SCALING_ROADMAP.md`）。

## 4. 选技能：来自背包技能书

- **技能 = 背包里的技能书给的**。`choose_skill` 从英雄当前技能里**随机抽一个**放。`CombatStrategy.gd:97`
- ⚠️ **空背包 = 没技能 = 只会普攻。** 给谁配什么书，直接决定他会放什么。
- 各职业放技能的概率（攻到了才 roll）：

| 职业 | 出技能概率 | 备注 |
|------|-----------|------|
| 战士 | 30% | 物理爆发 |
| 法师 | 70% | 核心输出靠魔法 |
| 盗贼 | 50%（目标 <30% 血时升 **80%** 收割） | |
| 猎人 | 40% | 物理远程技能 |
| 牧师 | 攻击 75%，但**有优先级**↓ | |

**牧师技能优先级**（`PriestStrategy`）：① 友军中毒 → 净化 `purify` ② 队友 HP<50% → 治疗 `holy_heal` ③ 自身 HP<35% → 祝福 `blessing` ④ 才轮到攻击技能。

- **冷却**：技能书带回合冷却（`ITEMS` 的 `cd`），经 Party 注入；冷却中该技能不可用 → 普攻。
- **蓝量**：技能有 `mp_cost`，不够 → 退化普攻。

## 5. 伤害公式 `BattleSimulator.gd:271` / `_calc_damage`

**单体伤害**：
```
原始 = 基础属性 × power（技能倍率）× 暴击倍率
落地 = max(1, 原始 − 防御/2) × 站位修正
```
- **基础属性**：`use_magic=true` 用魔力，否则用攻击。
- **power**：技能倍率（普攻=1.0；如斩击 1.5）。`buff_self`/`heal_ally` 类不走伤害。
- **防御**：默认减 `防御/2`；`half_def` 减 `防御/4`；`ignore_def` 无视防御。
- **AOE**（`aoe:true`）：打全体，按总伤平分。
- **治疗**（`heal_ally`）：回血量 = `power × 魔力`，给血量最少的友军。

## 6. 暴击（副属性，来自背包）`BattleSimulator._roll_crit`

- `crit_chance`（0~1 概率）+ `crit_dmg`（暴伤加成）。
- 暴击倍率 = **1.5 + crit_dmg**（例：crit_dmg 0.5 → ×2.0）。普攻/单体/AOE 都吃暴击。
- 无副属性的单位永远 ×1.0（向后兼容）。来源：背包暴击宝石/锋锐之刃/狂战戒，经 `Party.extra_stats` 注入。

## 7. 站位（世界树式"软调整"，`positioning_mode="soft_row"`）

- **人人可被打到**，站位只改伤害（不限制能打谁）。
- 伤害修正（`_row_damage_mult`，**只作用于物理**，魔法不受影响）：
  - 后排发起物理攻击：×**0.5**（`SOFT_BACK_ATTACK_MULT`）
  - 物理攻击打到后排目标：×**0.7**（`SOFT_BACK_DEFENSE_MULT`）
  - 后排打后排（叠乘）：×0.35
- **前排至少留 1 人**；前排全灭 → 后排自动顶上前排（`_promote_if_front_empty`）。
- 另有硬模式 `reach`（近战打不到后排），实验场景用，跑局不用。

## 8. 状态效果（技能数据声明，敌我通用）

| 效果 | 技能字段 | 说明 |
|------|---------|------|
| 增益 buff | `buff_attack/defense/speed/magic` + `buff_turns`(-1=全程) | 给施法者加属性，到期还原 |
| 眩晕 stun | `stun_turns` | 目标跳过 N 回合 |
| 减速 slow | `slow_amount` + `slow_turns` | 目标速度 −N，持续 N 回合 |
| 持续伤害 DoT | `dot_power` + `dot_turns` | 每回合开头掉血（中毒）|
| 治疗 | `type:"heal_ally"` | 回血量最少友军 |
| 群伤 | `aoe:true` | 全体，总伤平分 |

> 这些效果挂在 `BattleCombatant`（`apply_buff/apply_stun/apply_dot` + `tick_effects` 计时），**英雄和怪物同一套**——所以怪物能用任何技能（含英雄技能）。加新效果种类（如混乱）= 扩这套框架。

## 9. 玩家怎么影响战斗（战前三件事）

自动战斗里你的"操控"全在战前：
1. **配什么技能书** → 决定每个英雄会放什么技能（空背包=只普攻）。
2. **谁站前/后排** → 决定挨打与输出的站位修正。
3. **谁拿什么装备 + 凑什么协同 + 副属性** → 决定属性/暴击。

战前搭好，开打就照本手册的规则自动跑。

## 10. 已知粗糙处（待优化，见 PROGRESS 预留项）

- **AI 不按"有效伤害"选目标**：软站位下战士能打后排，但它只看"血最多"，可能跑去捅一个被站位打 7 折的后排肉盾，而非按"基础×站位倍率"挑最优。治本优化（`choose_target` 算有效伤害）尚未做。
- **站位修正只分物理/魔法，未单独豁免"远程"**：`_row_damage_mult` 按 `use_magic` 判定，后排弓手的物理攻击当前也吃 ×0.5（与"远程不受影响"的设计说明有出入，待对齐）。
- 玩家目标优先级策略按钮（集火残血/点后排等安全阀）：未做。

## 11. 相关文件
- `scripts/systems/combat/BattleSimulator.gd` — 主循环 / 伤害 / 站位 / 暴击 / 状态结算
- `scripts/systems/combat/CombatStrategy.gd` + `strategies/` — 选目标/选技能（各职业与敌人 AI）
- `scripts/systems/combat/BattleCombatant.gd` — 战斗单位（HP/站位/冷却/副属性/状态）
- `scripts/utils/SkillTable.gd` — 技能数据（倍率/类型/费用/状态）
- `scripts/systems/factories/{EnemyAIFactory,MonsterFactory,HeroFactory}.gd` — 造 AI / 怪物 / 英雄
