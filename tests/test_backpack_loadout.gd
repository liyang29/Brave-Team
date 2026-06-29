extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_backpack_loadout — BackpackLoadout（背包→可战斗Party 翻译器）
#
# 锁定 Step 1 的核心：属性=裸base+背包、技能书按职业过滤、站位/冷却/副属性注入，
# 以及两个关键设计点：
#   - 幂等：重复 build 不叠加（跑局每场重编背包必须从裸 base 重算）
#   - HP 做法 A：full_heal=false 钳血、加 +HP 装备不回血、上限回落时 current 钳下来
# ─────────────────────────────────────────────────────────────────────────────

const Loadout = preload("res://scripts/systems/BackpackLoadout.gd")


func _hero(cls: int) -> Hero:
	var h: Hero = HeroFactory.create(cls)
	var sk = h.get("skills")
	if sk != null:
		sk.clear()   # 技能改由背包技能书注入
	return h

func _base(hp: int, atk: int, def_v: int, magic: int, spd: int, mp: int) -> Dictionary:
	return { "hp": hp, "atk": atk, "def": def_v, "magic": magic, "spd": spd, "mp": mp }


# ── 属性 = 裸 base + 背包 ──────────────────────────────────────────────────────

func test_stats_are_naked_base_plus_backpack() -> void:
	var w := _hero(Hero.HeroClass.WARRIOR)
	# 剑6 + 磨刀石2 + 开刃6(相邻协同) = 攻 +14
	var grid := { Vector2i(0,0): "iron_sword", Vector2i(1,0): "whetstone" }
	Loadout.build_party([{ "hero": w, "base": _base(90,6,8,0,9,40), "grid": grid }], {}, true)
	assert_eq(w.base_attack, 6 + 14, "裸攻6 + 背包14 = 20")
	assert_eq(w.base_max_hp, 90, "背包无血加成 → 上限=裸 base 90")
	assert_eq(w.base_speed, 9, "速度=裸 base（背包不改）")
	assert_eq(w.base_mp, 40, "蓝量=裸 base（背包不改）")


# ── 幂等：重复 build 不叠加（最关键的坑）────────────────────────────────────────

func test_idempotent_rebuild_does_not_stack() -> void:
	var w := _hero(Hero.HeroClass.WARRIOR)
	var base := _base(90,6,8,0,9,40)
	var grid := { Vector2i(0,0): "iron_sword" }   # 攻 +6
	var loadouts := [{ "hero": w, "base": base, "grid": grid }]
	Loadout.build_party(loadouts, {}, true)
	var first := w.base_attack
	Loadout.build_party(loadouts, {}, true)   # 模拟下一场遭遇前重编背包，再 build
	assert_eq(w.base_attack, first, "重复 build 结果一致（不读已 buff 值）")
	assert_eq(w.base_attack, 12, "始终 6+6=12，不是越叠越高的 18")


# ── 技能书按职业过滤 + 冷却注入 ────────────────────────────────────────────────

func test_skillbook_filtered_by_class() -> void:
	var m := _hero(Hero.HeroClass.MAGE)
	# 火球书(法师可用) + 斩击书(战士技能，法师不能用)
	var grid := { Vector2i(0,0): "book_fireball", Vector2i(1,0): "book_slash" }
	var party: Party = Loadout.build_party(
		[{ "hero": m, "base": _base(55,3,3,5,12,70), "grid": grid }], {}, true)
	assert_true("fireball" in m.skills, "法师装上火球")
	assert_false("slash" in m.skills, "斩击是战士技能，法师装不上")
	assert_eq(int(party.get_skill_cd(m).get("fireball", 0)), 2, "火球书 cd=2 注入 party")


# ── 副属性注入 ────────────────────────────────────────────────────────────────

func test_extra_stats_injected() -> void:
	var w := _hero(Hero.HeroClass.WARRIOR)
	var grid := { Vector2i(0,0): "crit_gem" }   # crit_chance 0.15
	var party: Party = Loadout.build_party(
		[{ "hero": w, "base": _base(90,6,8,0,9,40), "grid": grid }], {}, true)
	assert_almost_eq(float(party.get_extra_stats(w).get("crit_chance", 0.0)), 0.15, 0.001,
		"暴击副属性注入 party")


# ── 站位来自 squad_slots ───────────────────────────────────────────────────────

func test_rows_from_squad_slots() -> void:
	var w := _hero(Hero.HeroClass.WARRIOR)
	var m := _hero(Hero.HeroClass.MAGE)
	var loadouts := [
		{ "hero": w, "base": _base(90,6,8,0,9,40), "grid": {} },
		{ "hero": m, "base": _base(55,3,3,5,12,70), "grid": {} },
	]
	var slots := { Vector2i(0,0): w, Vector2i(0,1): m }   # 战前排 / 法后排
	var party: Party = Loadout.build_party(loadouts, slots, true)
	assert_eq(party.positioning_mode, "soft_row", "软站位模式")
	assert_eq(party.get_row(w), "front", "战士在 row0 → 前排")
	assert_eq(party.get_row(m), "back", "法师在 row1 → 后排")


# ── HP 按百分比同步：满血 / 加血装按比例补 / 摘装按比例缩 ──────────────────────

func test_full_heal_true_fills_hp() -> void:
	var w := _hero(Hero.HeroClass.WARRIOR)
	w.current_hp = 1
	Loadout.build_party([{ "hero": w, "base": _base(90,6,8,0,9,40), "grid": {} }], {}, true)
	assert_eq(w.current_hp, w.get_max_hp(), "full_heal=true → 满血")

func test_full_hp_stays_full_when_adding_hp_item() -> void:
	# 玩家诉求：满血时加血上限，应仍满血（不再出现"满血却不满"）
	var w := _hero(Hero.HeroClass.WARRIOR)
	var base := _base(90,6,8,0,9,40)
	Loadout.build_party([{ "hero": w, "base": base, "grid": {} }], {}, false)
	assert_eq(w.current_hp, 90, "起始满血 90")
	Loadout.build_party([{ "hero": w, "base": base, "grid": { Vector2i(0,0): "charm" } }], {}, false)
	assert_eq(w.get_max_hp(), 110, "上限 90+20=110")
	assert_eq(w.current_hp, 110, "满血加血上限仍满血")

func test_partial_hp_scales_by_percent() -> void:
	# 剩约 60% 时加上限，当前血按比例同步（不是不动、也不是补满）
	var w := _hero(Hero.HeroClass.WARRIOR)
	var base := _base(100,6,8,0,9,40)   # max 100 便于算比例
	Loadout.build_party([{ "hero": w, "base": base, "grid": {} }], {}, false)
	w.current_hp = 60   # 60%
	Loadout.build_party([{ "hero": w, "base": base, "grid": { Vector2i(0,0): "charm" } }], {}, false)
	assert_eq(w.get_max_hp(), 120, "上限 100+20=120")
	assert_eq(w.current_hp, 72, "60% × 120 = 72（按比例补 12，不是补满）")

func test_removing_hp_item_scales_down() -> void:
	var w := _hero(Hero.HeroClass.WARRIOR)
	var base := _base(100,6,8,0,9,40)
	Loadout.build_party([{ "hero": w, "base": base, "grid": { Vector2i(0,0): "charm" } }], {}, false)
	w.current_hp = 60   # 60% of 120 = ... set explicitly
	Loadout.build_party([{ "hero": w, "base": base, "grid": {} }], {}, false)
	assert_eq(w.get_max_hp(), 100, "摘掉血装上限回落 100")
	assert_eq(w.current_hp, 50, "60/120=50% × 100 = 50（按比例缩，摘戴不白嫖）")

func test_dead_hero_not_revived_by_rebuild() -> void:
	var w := _hero(Hero.HeroClass.WARRIOR)
	var base := _base(90,6,8,0,9,40)
	Loadout.build_party([{ "hero": w, "base": base, "grid": {} }], {}, false)
	w.current_hp = 0   # 阵亡
	Loadout.build_party([{ "hero": w, "base": base, "grid": { Vector2i(0,0): "charm" } }], {}, false)
	assert_eq(w.current_hp, 0, "阵亡不被重算复活")

func test_backpack_mp_added_to_base() -> void:
	var m := _hero(Hero.HeroClass.MAGE)
	Loadout.build_party([{ "hero": m, "base": _base(55,3,3,5,12,70), "grid": { Vector2i(0,0): "mana_charm" } }], {}, true)
	assert_eq(m.base_mp, 70 + 30, "法力护符 +30 蓝加到 base_mp")
