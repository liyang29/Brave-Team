extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_balance — 跑局平衡 harness（Step 5）
#
# 模拟"好 build vs 烂 build"跑完整条线（HP 跨节点累积、泉水回血、build_party 钳血），
# 输出通关率。目标：中等难度——好 build 多数能通关、烂 build 多数过不去。
# 数值不达标就回 RunManager._build_map 拧敌人，再跑本测试。
# ─────────────────────────────────────────────────────────────────────────────

const Loadout = preload("res://scripts/systems/backpack/BackpackLoadout.gd")
const TRIALS := 20


# 好 build：协同相邻 + 放对人 + 带本职技能书
func _good_grids() -> Array:
	return [
		# 战士：开刃(剑+磨刀石) + 重装(盾+甲) + 斩击书
		{ Vector2i(0,0): "iron_sword", Vector2i(1,0): "whetstone", Vector2i(2,0): "book_slash",
		  Vector2i(0,1): "shield", Vector2i(1,1): "chainmail" },
		# 法师：共鸣(法杖+魔典) + 火球书
		{ Vector2i(0,0): "staff", Vector2i(1,0): "tome", Vector2i(2,0): "book_fireball" },
		# 牧师：生机(护符+红宝石) + 圣徽 + 治疗书
		{ Vector2i(0,0): "holy_symbol", Vector2i(2,0): "book_heal",
		  Vector2i(0,1): "amulet", Vector2i(1,1): "charm" },
	]

# 中庸 build：放对人、有装备有技能书，但没凑相邻协同（衡量"协同到底多关键"）
func _ok_grids() -> Array:
	return [
		{ Vector2i(0,0): "iron_sword", Vector2i(2,0): "chainmail", Vector2i(2,1): "book_slash" },
		{ Vector2i(0,0): "staff", Vector2i(2,0): "book_fireball" },
		{ Vector2i(0,0): "amulet", Vector2i(2,0): "book_heal" },
	]

# 烂 build：放错人、无协同、无对职业技能书
func _bad_grids() -> Array:
	return [
		{ Vector2i(0,0): "staff" },        # 战士拿法杖（魔力对物理战士没用）
		{ Vector2i(0,0): "iron_sword" },   # 法师拿剑（攻击对法系没用）
		{ Vector2i(0,0): "shield" },       # 牧师只有个盾
	]


# 组一支测试队（战/法/牧）并装上 build，返回 loadouts + 站位
func _team(grids: Array) -> Dictionary:
	var ids := ["warrior", "mage", "priest"]
	var loadouts: Array = []
	for i in range(ids.size()):
		var e: Dictionary = RunManager.make_hero_entry(ids[i])
		e["grid"] = grids[i].duplicate()
		loadouts.append(e)
	var slots := {
		Vector2i(0, 0): loadouts[0]["hero"],
		Vector2i(0, 1): loadouts[1]["hero"],
		Vector2i(1, 1): loadouts[2]["hero"],
	}
	return { "loadouts": loadouts, "slots": slots }

# 单关满血胜率：每次新队满血单独打这关 N 次（隔离每关难度，不含跨关消耗）
func _node_winrate(grids: Array, enemies: Array) -> int:
	var wins := 0
	for t in range(TRIALS):
		var tm: Dictionary = _team(grids)
		var party: Party = Loadout.build_party(tm["loadouts"], tm["slots"], true)
		if BattleSimulator.simulate(party, enemies).party_won:
			wins += 1
	return wins

# ── 逐关体检表（用法 A：模拟当尺子，给每关标难易）────────────────────────────
func test_per_node_health_report() -> void:
	RunManager.start_run()
	gut.p("===== 逐关体检（每关满血单独打 %d 次）=====" % TRIALS)
	gut.p("关卡            好build   中庸build")
	for node in RunManager.nodes:
		var enemies: Array = node.get("enemies", [])
		if enemies.is_empty():
			continue
		var g := _node_winrate(_good_grids(), enemies)
		var o := _node_winrate(_ok_grids(), enemies)
		gut.p("%-12s    %d/%d      %d/%d" % [node.get("name", "?"), g, TRIALS, o, TRIALS])
	# 阵亡分布：整局中庸 build 在哪一关倒下（消耗战难度真正的落点）
	gut.p("--- 中庸 build 整局阵亡分布（%d 局）---" % TRIALS)
	var dist: Dictionary = {}
	for t in range(TRIALS):
		var where := _run_track(_ok_grids())
		dist[where] = int(dist.get(where, 0)) + 1
	for k in dist:
		gut.p("  %-12s ×%d" % [k, dist[k]])
	assert_true(true, "体检报告（看 gut.p 输出）")

# 跑一整局，返回在哪一关失败（节点名），通关则返回"通关"
func _run_track(grids: Array) -> String:
	RunManager.start_run()
	var tm: Dictionary = _team(grids)
	RunManager.roster = tm["loadouts"]
	RunManager.party = RunManager.roster.map(func(e): return e["hero"])
	RunManager.squad_slots = tm["slots"]
	for d in range(RunManager.nodes.size()):
		var node: Dictionary = RunManager.nodes[d]
		match node.get("type"):
			"village":
				pass
			"rest":
				RunManager.rest_heal()
			_:
				var alive: Array = RunManager.roster.filter(func(e): return e["hero"].is_alive())
				var party: Party = Loadout.build_party(alive, RunManager.squad_slots, false)
				if not BattleSimulator.simulate(party, node.get("enemies", [])).party_won:
					return String(node.get("name", "?"))
	return "通关"


# 跑一整局，返回是否通关（魔王也打过）
func _run_once(grids: Array) -> bool:
	RunManager.start_run()
	# 起手空队 → 直接组一支固定测试队（战/法/牧）并装上 build
	RunManager.roster = [
		RunManager.make_hero_entry("warrior"),
		RunManager.make_hero_entry("mage"),
		RunManager.make_hero_entry("priest"),
	]
	RunManager.party = RunManager.roster.map(func(e): return e["hero"])
	RunManager.squad_slots = {
		Vector2i(0, 0): RunManager.roster[0]["hero"],
		Vector2i(0, 1): RunManager.roster[1]["hero"],
		Vector2i(1, 1): RunManager.roster[2]["hero"],
	}
	for i in range(grids.size()):
		RunManager.roster[i]["grid"] = grids[i].duplicate()
	for d in range(RunManager.nodes.size()):
		var node: Dictionary = RunManager.nodes[d]
		match node.get("type"):
			"village":
				pass
			"rest":
				RunManager.rest_heal()
			_:
				var alive: Array = RunManager.roster.filter(func(e): return e["hero"].is_alive())
				if alive.is_empty():
					return false
				var party: Party = Loadout.build_party(alive, RunManager.squad_slots, false)
				var result: BattleResult = BattleSimulator.simulate(party, node.get("enemies", []))
				if not result.party_won:
					return false
	return true


func _win_rate(grids: Array) -> int:
	var wins := 0
	for t in range(TRIALS):
		if _run_once(grids):
			wins += 1
	return wins


func test_good_build_beats_bad_build() -> void:
	var good := _win_rate(_good_grids())
	var ok := _win_rate(_ok_grids())
	var bad := _win_rate(_bad_grids())
	gut.p("通关率  好build %d/%d  ·  中庸 %d/%d  ·  烂build %d/%d" % [good, TRIALS, ok, TRIALS, bad, TRIALS])
	assert_gt(good, bad, "好 build 通关率应明显高于烂 build")
	assert_gte(good, int(TRIALS * 0.5), "好 build 至少一半能通关（不是必死）")
	assert_lte(bad, int(TRIALS * 0.5), "烂 build 多数过不去（build 要有意义）")
