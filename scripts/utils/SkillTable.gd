class_name SkillTable

# ─────────────────────────────────────────────────────────────────────────────
# SkillTable — 技能效果数据表（静态工具类）
#
# 每个技能 ID 对应一条 SkillEffect 字典，BattleSimulator 读取后执行。
#
# SkillEffect 字段说明：
#   type        : String  — 效果类型，见下方枚举
#   mp_cost     : int     — 释放技能消耗的蓝量（默认 0；蓝量不足时退化为普攻）
#   power       : float   — 伤害/治疗倍率（相对于基础攻击/魔法）
#   use_magic   : bool    — true = 用 magic 属性计算，false = 用 attack
#   ignore_def  : bool    — true = 无视目标防御（防御视为 0）
#   half_def    : bool    — true = 防御减半计算（arcane_bolt 快速施法）
#   aoe         : bool    — true = 打全体敌人（总伤平分）
#   buff_attack : int     — 给施法者永久加攻击
#   buff_defense: int     — 给施法者永久加防御
#   buff_speed  : int     — 给施法者永久加速度
#   dot_power   : float   — DoT 每回合伤害倍率（基于施法者当前攻击）
#   dot_turns   : int     — DoT 持续回合数
#   stun_turns  : int     — 眩晕持续回合数（目标跳过行动）
#   slow_amount : int     — 减速量（目标速度 -N，持续 slow_turns 回合）
#   slow_turns  : int     — 减速持续回合数
#
# type 枚举（字符串）：
#   "damage"     — 造成伤害（可附加 DoT/眩晕/减速）
#   "buff_self"  — 强化自身属性（无目标，不造成伤害）
#   "heal_ally"  — 治疗血量最少的友军（power × magic = 回血量）
#   "cleanse"    — 移除全体友军 DoT（解毒）
#   "taunt_self" — 主动嘲讽：临时拉仇 taunt_turns 回合（可带 buff_defense 立防）；仅前排生效
#
# taunt_self 专属字段：
#   taunt_turns : int — 临时嘲讽持续回合数
# ─────────────────────────────────────────────────────────────────────────────


const SKILLS: Dictionary = {

	# ── 战士 ──────────────────────────────────────────────────────────────────

	"slash": {
		"hero_class": "warrior",
		"name_zh":    "斩击",
		"type":       "damage",
		"mp_cost":    10,   # 10←15：战士蓝量紧张，降低门槛维持技能节奏
		"power":      1.5,
		"use_magic":  false,
	},

	"shield_bash": {
		"hero_class":  "warrior",
		"name_zh":     "盾击",
		"type":        "damage",
		"mp_cost":     15,  # 15←20：同上
		"power":       1.0,
		"use_magic":   false,
		"stun_turns":  2,
	},

	"battle_cry": {
		"hero_class":   "warrior",
		"name_zh":      "战吼",
		"type":         "buff_self",
		"mp_cost":      25,
		"buff_attack":  8,
		"buff_turns":   -1,   # -1 = 战斗全程持续（不过期）
	},

	"cleave": {
		"hero_class": "warrior",
		"name_zh":    "横扫",
		"type":       "damage",
		"mp_cost":    30,
		"power":      0.9,  # 0.9←1.2：AOE不拆分后总伤过高，折减到与单体持平
		"use_magic":  false,
		"aoe":        true,
	},

	"taunt_roar": {
		"hero_class":   "warrior",
		"name_zh":      "挑衅怒吼",
		"type":         "taunt_self",   # 临时拉仇（仅前排生效）+ 立防
		"mp_cost":      15,
		"taunt_turns":  2,              # 嘲讽持续 2 回合
		"buff_defense": 4,              # 拉仇同时立起防御，名副其实"我顶上来挡"
		"buff_turns":   2,              # 防御与嘲讽同步时长
	},

	# ── 法师 ──────────────────────────────────────────────────────────────────

	"fireball": {
		"hero_class": "mage",
		"name_zh":    "火球",
		"type":       "damage",
		"mp_cost":    25,
		"power":      2.0,
		"use_magic":  true,
	},

	"ice_lance": {
		"hero_class":  "mage",
		"name_zh":     "冰枪",
		"type":        "damage",
		"mp_cost":     20,
		"power":       1.5,
		"use_magic":   true,
		"slow_amount": 8,
		"slow_turns":  2,
	},

	"arcane_bolt": {
		"hero_class": "mage",
		"name_zh":    "奥术弹",
		"type":       "damage",
		"mp_cost":    10,    # 快速施法，消耗少
		"power":      1.2,
		"use_magic":  true,
		"half_def":   true,
	},

	"mana_surge": {
		"hero_class": "mage",
		"name_zh":    "法力涌动",
		"type":       "damage",
		"mp_cost":    35,
		"power":      1.2,  # 1.2←1.8：AOE不拆分后对3敌总伤过于强力，折减
		"use_magic":  true,
		"aoe":        true,
	},

	# ── 盗贼 ──────────────────────────────────────────────────────────────────

	"backstab": {
		"hero_class": "rogue",
		"name_zh":    "背刺",
		"type":       "damage",
		"mp_cost":    20,
		"power":      2.5,
		"use_magic":  false,
	},

	"shadow_strike": {
		"hero_class":  "rogue",
		"name_zh":     "暗影打击",
		"type":        "damage",
		"mp_cost":     25,
		"power":       2.0,  # 2.0←1.5：无视防御技能效率低于 backstab，提升使其有差异化价值
		"use_magic":   false,
		"ignore_def":  true,
	},

	"poison_blade": {
		"hero_class":  "rogue",
		"name_zh":     "毒刃",
		"type":        "damage",
		"mp_cost":     15,
		"power":       1.0,
		"use_magic":   false,
		"dot_power":   0.6,  # 0.6←0.3：DoT 每回合伤害提升，使毒伤有实际威胁
		"dot_turns":   2,
	},

	"evasion": {
		"hero_class":   "rogue",
		"name_zh":      "闪避",
		"type":         "buff_self",
		"mp_cost":      20,
		"buff_speed":   6,       # 原 buff_defense:10 → 改为 buff_speed:6，维护刺客定位
		"buff_turns":   -1,
	},

	# ── 弓手 ──────────────────────────────────────────────────────────────────

	"precise_shot": {
		"hero_class": "archer",
		"name_zh":    "精准射击",
		"type":       "damage",
		"mp_cost":    20,
		"power":      1.8,
		"use_magic":  false,
	},

	"multi_shot": {
		"hero_class": "archer",
		"name_zh":    "多重射击",
		"type":       "damage",
		"mp_cost":    30,
		"power":      1.3,
		"use_magic":  false,
		"aoe":        true,
	},

	"piercing_arrow": {
		"hero_class":  "archer",
		"name_zh":     "穿透箭",
		"type":        "damage",
		"mp_cost":     25,
		"power":       1.8,  # 1.8←1.5：无视防御技能伤害低于 precise_shot，修正倒挂
		"use_magic":   false,
		"ignore_def":  true,
	},

	"eagle_eye": {
		"hero_class":   "archer",
		"name_zh":      "鹰眼",
		"type":         "buff_self",
		"mp_cost":      15,
		"buff_attack":  6,
		"buff_speed":   4,
		"buff_turns":   -1,
	},

	# ── 牧师 ──────────────────────────────────────────────────────────────────

	"holy_smite": {
		"hero_class": "priest",
		"name_zh":    "圣光击",
		"type":       "damage",
		"mp_cost":    15,
		"power":      1.4,
		"use_magic":  true,
		"half_def":   true,
	},

	"divine_wrath": {
		"hero_class":  "priest",
		"name_zh":     "神圣之怒",
		"type":        "damage",
		"mp_cost":     30,
		"power":       1.8,
		"use_magic":   true,
		"ignore_def":  true,
	},

	"radiance": {
		"hero_class": "priest",
		"name_zh":    "圣光辐射",
		"type":       "damage",
		"mp_cost":    25,
		"power":      0.85, # 0.85←1.1：AOE不拆分折减，牧师AOE仍比单体技能有优势
		"use_magic":  true,
		"aoe":        true,
	},

	"blessing": {
		"hero_class":    "priest",
		"name_zh":       "神圣祝福",
		"type":          "buff_self",
		"mp_cost":       20,
		"buff_defense":  10,
		"buff_turns":    -1,
	},

	"holy_heal": {
		"hero_class": "priest",
		"name_zh":    "圣愈术",
		"type":       "heal_ally",   # 治疗血量最少的友军
		"mp_cost":    25,
		"power":      1.2,           # 治疗量 = 施法者.magic × 1.2
	},

	"purify": {
		"hero_class": "priest",
		"name_zh":    "净化",
		"type":       "cleanse",     # 移除全体友军身上的 DoT（解毒），方案 B 克制 poison 遭遇
		"mp_cost":    15,
	},

	# ── 敌人专用技能（方案 B 实验：剧毒术士）──────────────────────────────────
	"venom_bolt": {
		"name_zh":    "毒液弹",
		"type":       "damage",
		"mp_cost":    0,             # 敌人不参与蓝量系统
		"power":      0.5,           # 直伤偏低，威胁全在持续毒
		"use_magic":  false,         # DoT 基于施法者 attack
		"dot_power":  1.0,           # 每回合毒伤 ≈ 施法者 attack
		"dot_turns":  3,
	},

	# ── 敌人专用技能（方案 B 网格实验：列穿刺）────────────────────────────────
	# 命中目标所在「整列」（前+后排，无视掩护）→ 惩罚把单位堆在同一列
	"plasma_pierce": {
		"name_zh":    "电浆穿刺",
		"type":       "damage",
		"mp_cost":    0,
		"power":      0.85,
		"use_magic":  false,
		"aoe":        true,
		"aoe_shape":  "column",
	},

	# ── 中程 Boss 专属技能（EncounterData 引用；不参与蓝量系统，靠 cd 节流）─────
	"boss_smash": {
		"name_zh":    "石破天惊",
		"type":       "damage",
		"mp_cost":    0,
		"power":      2.2,
		"use_magic":  false,
		"stun_turns": 1,
	},
	"boss_venom_nova": {
		"name_zh":    "剧毒新星",
		"type":       "damage",
		"mp_cost":    0,
		"power":      1.0,
		"use_magic":  true,
		"aoe":        true,
	},
	"boss_frenzy": {
		"name_zh":      "深渊狂暴",
		"type":         "buff_self",
		"mp_cost":      0,
		"buff_attack":  10,
		"buff_turns":   -1,
	},
	"boss_abyss_strike": {
		"name_zh":     "深渊一击",
		"type":        "damage",
		"mp_cost":     0,
		"power":       2.5,
		"use_magic":   true,
		"ignore_def":  true,
	},
}


## 获取技能数据，未知 ID 返回 null
static func get_skill(skill_id: String) -> Dictionary:
	return SKILLS.get(skill_id, {})


## 获取技能的本地化显示名（统一入口，UI 一律调用此方法）。
## 中文（zh*）→ name_zh；其它语言 → name_en，缺失则由 id 人性化（shield_bash → Shield Bash）。
## 未知技能回退为人性化 id，永远不会显示原始下划线 ID。
static func get_display_name(skill_id: String) -> String:
	var skill: Dictionary = SKILLS.get(skill_id, {})
	if TranslationServer.get_locale().begins_with("zh"):
		return skill.get("name_zh", skill_id.capitalize())
	return skill.get("name_en", skill_id.capitalize())


## 该技能是否使用魔法伤害
static func is_magic(skill_id: String) -> bool:
	return SKILLS.get(skill_id, {}).get("use_magic", false)


## 该技能是否为 AoE
static func is_aoe(skill_id: String) -> bool:
	return SKILLS.get(skill_id, {}).get("aoe", false)
