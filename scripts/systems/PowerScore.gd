extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# PowerScore — 把"多维属性"折成"单一战力分"（纯函数，便于测试与扩展）
#
# 为什么要它：装备/怪物会无限膨胀，手调每一个不现实。给万物一个"战力数"，
# 就能比较强弱、按预算凑遭遇、给掉落/定价排序——这是应对内容膨胀的标准工具
# （血脉：D&D 的 CR、MMO 的装等 iLvl、暗黑的 Gear Score）。
#
# 这里有两套"分"，量纲不同、用途不同（别混用）：
#   1) unit_power / enemy_power —— 一个"完整单位"的战斗评级 = 有效血量 × 输出。
#        用于：给遭遇定预算、比较敌人/英雄整体强弱。数字偏大（几百~几千）。
#   2) item_power —— 一件"装备"贡献的属性折算分（加权和）。
#        用于：给物品排序、定价、掉落分级。数字偏小（几~几十）。
#   （要和 enemy_power 比的不是 item_power，而是"建好背包的英雄"的 unit_power。）
#
# 所有权重/系数都是"可调旋钮"——先给直觉值，以后用 test_balance harness 校准。
# 故意不带 class_name（preload 引入），同 BackpackModel 路子。
# ─────────────────────────────────────────────────────────────────────────────

const Backpack = preload("res://scripts/experiments/BackpackModel.gd")


# ── 1) 单位战力（有效血量 × 输出）──────────────────────────────────────────────
# 原理：一个单位的"战斗价值"≈ 它能扛多少(EHP) × 它每回合打多少(DPS)。
#   - 玻璃大炮(高攻低血) 和 肉盾(低攻高血) 都该是"中等"；攻血双高才该"很强"。
#     乘法天然表达这点（任一项太低，乘积就低）。
#   - 防御是"乘性减伤"，所以折成"有效血量"的倍率，不是直接加血。
#   - 速度=出手频率，越快每回合等效输出越高 → 乘个速度系数。

const DEF_TO_EHP := 0.06   # 每点防御让有效血量 +6%（防御比血更值，因为乘性）
const SPD_BASE   := 10.0   # 速度基准（≈中速）；快于它=加成，慢于它=折减

## 任意单位的战力评级。def_v 用 _v 避免和保留词混淆。
## crit_chance/crit_dmg/dodge_chance 可选（敌人不传=0，不影响其评分；英雄带背包副属性时传入）。
const DODGE_CAP_PS := 0.6   # 与 BattleSimulator.DODGE_CAP 对齐（避免循环引用，本地常量）
static func unit_power(hp: int, atk: int, def_v: int, magic: int, spd: int,
		crit_chance: float = 0.0, crit_dmg: float = 0.0, dodge_chance: float = 0.0) -> float:
	# 暴击期望增伤：暴击倍率=1.5+crit_dmg，期望乘子 = 1 + 概率×(0.5+暴伤)
	var crit_mult: float = 1.0 + crit_chance * (0.5 + crit_dmg)
	var offense: float = float(max(atk, magic)) * crit_mult # 用攻/魔里高的×暴击期望
	var ehp: float = float(hp) * (1.0 + def_v * DEF_TO_EHP) # 有效血量 = 血 × 防御倍率
	# 闪避是乘性减伤 → 有效血量 ×= 1/(1-闪避率)（如 50% 闪避≈双倍 EHP）
	var dodge: float = clampf(dodge_chance, 0.0, DODGE_CAP_PS)
	if dodge > 0.0:
		ehp /= (1.0 - dodge)
	var spd_factor: float = max(0.5, float(spd) / SPD_BASE) # 出手频率系数（兜底 0.5）
	return ehp * offense * spd_factor                       # EHP × DPS = 战斗评级


## 怪物战力：从 EnemyData 读属性，套 unit_power。
## （英雄战力以后同理：对"建好背包的英雄"调 unit_power，就能和敌人同尺度比。）
static func enemy_power(data) -> float:
	return unit_power(data.base_max_hp, data.base_attack, data.base_defense,
		data.base_magic, data.base_speed)


## 一组怪物的总战力（遭遇预算用）。
static func group_power(enemy_data_list: Array) -> float:
	var sum := 0.0
	for e in enemy_data_list:
		sum += enemy_power(e)
	return sum


## 英雄战力（含背包）：最终属性 = 裸 base + 背包 compute，套同一个 unit_power。
## entry = 名册条目 { "base": {hp,atk,def,magic,spd,mp}, "grid": {格子→物品} }。
## 与 enemy_power 同尺度，可直接和遭遇 group_power 比。
static func hero_power(entry: Dictionary) -> float:
	var base: Dictionary = entry.get("base", {})
	var b: Dictionary = Backpack.compute(entry.get("grid", {}))
	var ex: Dictionary = b.get("extra", {})
	return unit_power(
		int(base.get("hp", 0))    + int(b.get("hp", 0)),
		int(base.get("atk", 0))   + int(b.get("atk", 0)),
		int(base.get("def", 0))   + int(b.get("def", 0)),
		int(base.get("magic", 0)) + int(b.get("magic", 0)),
		int(base.get("spd", 0)),
		float(ex.get("crit_chance", 0.0)),
		float(ex.get("crit_dmg", 0.0)),
		float(ex.get("dodge_chance", 0.0)))


## 队伍总战力（名册各人 hero_power 之和）。和 group_power(遭遇) 比 = 难度比值。
static func team_power(roster: Array) -> float:
	var sum := 0.0
	for e in roster:
		sum += hero_power(e)
	return sum


# ── 2) 物品战力（属性加权和）──────────────────────────────────────────────────
# 原理：装备是"属性增量"，不是完整单位 → 用加权和，每点属性值多少"分"。
#   权重反映该属性的战斗价值：防御每点比血更值（乘性减伤）；暴击按百分点折算。
#   技能书不给属性、价值在"技能效用 + 占格机会成本" → 先给个基础分。
#   注：协同加成是"摆位触发的情境收益"，不算进单件物品的固有分。

const W_ATK   := 1.0
const W_MAGIC := 1.0
const W_DEF   := 1.6   # 防御每点 > 血每点
const W_HP    := 0.4
const W_MP    := 0.15  # 蓝量：间接价值（多放几个技能），权重低
const W_SPD   := 0.8   # 速度
const W_CRIT_CHANCE := 0.3   # 每 1% 暴击率
const W_CRIT_DMG    := 0.2   # 每 1% 暴伤
const W_DODGE_CHANCE := 0.5  # 每 1% 闪避（乘性减伤，比暴击更值）
const TAUNT_POWER   := 4.0   # 嘲讽：无裸输出/生存，价值在站位 → 给个小固定分（免商店定价为 0）
const SKILLBOOK_POWER := 8.0 # 技能书基础分（先拍，后续可按技能效用细化）
const AURA_MULT := 1.8       # 光环影响多个队友 → 同等属性更值钱

# 各属性权重表（光环算分复用）
const _STAT_W: Dictionary = { "atk": W_ATK, "magic": W_MAGIC, "def": W_DEF, "hp": W_HP, "mp": W_MP, "spd": W_SPD }

static func item_power(item_id: String) -> float:
	var it: Dictionary = Backpack.ITEMS.get(item_id, {})
	if it.is_empty():
		return 0.0
	if it.get("tag", "") == "skillbook":
		return SKILLBOOK_POWER
	var p := 0.0
	p += int(it.get("atk", 0))   * W_ATK
	p += int(it.get("magic", 0)) * W_MAGIC
	p += int(it.get("def", 0))   * W_DEF
	p += int(it.get("hp", 0))    * W_HP
	p += int(it.get("mp", 0))    * W_MP
	p += float(it.get("crit_chance", 0.0)) * 100.0 * W_CRIT_CHANCE
	p += float(it.get("crit_dmg", 0.0))    * 100.0 * W_CRIT_DMG
	p += float(it.get("dodge_chance", 0.0)) * 100.0 * W_DODGE_CHANCE
	if int(it.get("taunt", 0)) > 0:
		p += TAUNT_POWER
	# 光环：按属性加权 × 倍率（影响多个队友更值钱）
	if it.has("aura"):
		var aura: Dictionary = it["aura"]
		for k in _STAT_W:
			p += int(aura.get(k, 0)) * float(_STAT_W[k]) * AURA_MULT
	return p
