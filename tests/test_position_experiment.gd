extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_position_experiment — 方案 B 站位/克制脏实验的数值与机制验证
#
# 验证「编队解谜」的核心假设在代码层成立：
#   ① 纯近战够不到后排术士 → 被毒蚀团灭（低胜率）
#   ② 带远程（法师/弓手）→ 点掉术士 → 高胜率
#   ④ 带牧师净化 → 撑过毒 → 高胜率
#
# 同时是 BattleSimulator 站位触及规则（_get_reachable_opponents）的回归测试。
# ─────────────────────────────────────────────────────────────────────────────

const CASTER_NAME := "剧毒术士"
const TRIALS := 20

func _make_hero(cls: int, nm: String, hp: int, atk: int, def_v: int, spd: int,
				magic: int, mp: int, skills: Array) -> Hero:
	var hero: Hero = HeroFactory.create(cls)
	hero.set("base_max_hp", hp)
	hero.set("base_attack", atk)
	hero.set("base_defense", def_v)
	hero.set("base_speed",  spd)
	hero.set("base_magic",  magic)
	hero.set("base_mp",     mp)
	var sk = hero.get("skills")
	if sk != null:
		sk.clear()
	for s in skills:
		hero.learn_skill(s)
	hero.stat_block.rebuild()
	hero.entity_name = nm
	hero.current_hp = hero.get_max_hp()
	return hero

func _w(nm: String) -> Hero:
	return _make_hero(Hero.HeroClass.WARRIOR, nm, 130, 16, 12, 8, 0, 60, ["slash", "shield_bash"])
func _mage() -> Hero:
	return _make_hero(Hero.HeroClass.MAGE, "法师", 70, 8, 4, 13, 18, 80, ["fireball"])
func _archer() -> Hero:
	return _make_hero(Hero.HeroClass.ARCHER, "弓手", 100, 13, 7, 12, 0, 50, ["precise_shot"])
func _priest() -> Hero:
	return _make_hero(Hero.HeroClass.PRIEST, "牧师", 85, 6, 7, 9, 16, 80, ["purify", "holy_heal"])

func _enemy(nm: String, hp: int, atk: int, def_v: int, spd: int, prow: String,
			ranged: bool, ai: String) -> EnemyData:
	var e: EnemyData = EnemyData.new()
	e.entity_name = nm
	e.base_max_hp = hp
	e.base_attack = atk
	e.base_defense = def_v
	e.base_speed = spd
	e.base_magic = 0
	e.ai_type = ai
	e.preferred_row = prow
	e.is_ranged = ranged
	return e

func _encounter() -> Array:
	return [
		_enemy("重甲墙·甲", 170, 10, 16, 6, "front", false, EnemyData.AI_BASIC_ATTACK),
		_enemy("重甲墙·乙", 170, 10, 16, 6, "front", false, EnemyData.AI_BASIC_ATTACK),
		_enemy(CASTER_NAME, 45, 18, 2, 11, "back", true, EnemyData.AI_POISON_CASTER),
	]

# 跑 N 次，返回 { wins, caster_kills }
func _run(heroes: Array) -> Dictionary:
	var wins := 0
	var caster_kills := 0
	for i in TRIALS:
		for h in heroes:
			h.current_hp = h.get_max_hp()
		var party: Party = Party.create(heroes)
		var result: BattleResult = BattleSimulator.simulate(party, _encounter())
		if result.party_won:
			wins += 1
		for log in result.turn_logs:
			if log.target_name == CASTER_NAME and log.is_kill:
				caster_kills += 1
				break
	return { "wins": wins, "caster_kills": caster_kills }


func test_pure_melee_mostly_loses() -> void:
	var r := _run([_w("战士甲"), _w("战士乙")])
	gut.p("① 纯两战士：胜率 %d/%d，术士被点掉 %d/%d" % [r.wins, TRIALS, r.caster_kills, TRIALS])
	assert_lt(r.wins, TRIALS / 2, "纯近战够不到后排术士，应大概率团灭")
	# 注：连招买强后近战偶尔能凿穿前排、清空后够到后排术士；但仍是少数（机制：有前排掩护时够不到）。
	assert_lt(r.caster_kills, TRIALS / 2, "纯近战极少能点掉后排术士（前排没清空就够不到）")


func test_with_mage_mostly_wins() -> void:
	var r := _run([_w("战士甲"), _w("战士乙"), _mage()])
	gut.p("② 两战士+法师：胜率 %d/%d，术士被点掉 %d/%d" % [r.wins, TRIALS, r.caster_kills, TRIALS])
	assert_gt(r.wins, TRIALS * 3 / 4, "带法师应能点掉术士并高胜率")
	assert_gt(r.caster_kills, TRIALS * 3 / 4, "法师应稳定点掉后排术士")


func test_with_archer_mostly_wins() -> void:
	var r := _run([_w("战士甲"), _w("战士乙"), _archer()])
	gut.p("③ 两战士+弓手：胜率 %d/%d，术士被点掉 %d/%d" % [r.wins, TRIALS, r.caster_kills, TRIALS])
	assert_gt(r.wins, TRIALS * 3 / 4, "带弓手应能点掉术士并高胜率")
	assert_gt(r.caster_kills, TRIALS * 3 / 4, "弓手应稳定点掉后排术士")


func test_with_priest_cleanse_wins() -> void:
	var r := _run([_w("战士甲"), _w("战士乙"), _priest()])
	gut.p("④ 两战士+牧师：胜率 %d/%d（靠净化撑，不点术士）" % [r.wins, TRIALS])
	assert_gt(r.wins, TRIALS / 2, "牧师净化解毒，应能撑过消耗获胜")


func test_reach_rule_front_blocks_back() -> void:
	# 直接验证触及规则：近战面对"前排存活+后排"时只能选到前排
	var melee := BattleCombatant.new()
	melee.can_reach_back = false
	var front := BattleCombatant.new()
	front.row = "front"
	front.current_hp = 10
	front.max_hp = 10
	var back := BattleCombatant.new()
	back.row = "back"
	back.current_hp = 10
	back.max_hp = 10
	var reachable: Array = BattleSimulator._get_reachable_opponents(melee, [front, back])
	assert_eq(reachable.size(), 1, "前排存活时近战只能触及前排")
	assert_eq(reachable[0], front, "近战触及的应是前排单位")
	# 远程可触及全体
	var ranged := BattleCombatant.new()
	ranged.can_reach_back = true
	var reach2: Array = BattleSimulator._get_reachable_opponents(ranged, [front, back])
	assert_eq(reach2.size(), 2, "远程可越过前排触及全体")
