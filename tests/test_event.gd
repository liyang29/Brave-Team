extends GutTest

# 事件节点：EventTable schema 合法性 + RunManager 门槛/效果/风险/不重复/回地图。

const EventTable = preload("res://scripts/systems/run/EventTable.gd")
const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")

const EFFECT_TYPES := ["gold", "item", "hp_pct"]
const REQUIRE_KEYS := ["gold", "item", "class"]
const CLASSES := ["warrior", "mage", "priest", "rogue", "archer"]


func _party(ids: Array) -> void:
	RunManager.roster = []
	for id in ids:
		RunManager.roster.append(RunManager.make_hero_entry(id))
	RunManager.party = RunManager.roster.map(func(e): return e["hero"])


func _check_effects(effects: Array, where: String) -> void:
	for e in effects:
		var t: String = String(e.get("type", ""))
		assert_true(t in EFFECT_TYPES, "%s：效果类型 '%s' 合法" % [where, t])
		if t == "item":
			assert_true(Backpack.ITEMS.has(String(e.get("id", ""))), "%s：物品 id 存在" % where)


# ── schema 合法性 ────────────────────────────────────────────────────────────

func test_events_wellformed() -> void:
	for id in EventTable.all_ids():
		var ev: Dictionary = EventTable.get_event(id)
		assert_ne(String(ev.get("title", "")), "", "%s 有标题" % id)
		assert_ne(String(ev.get("desc", "")), "", "%s 有描述" % id)
		var choices: Array = ev.get("choices", [])
		assert_gt(choices.size(), 0, "%s 有选项" % id)
		for ci in range(choices.size()):
			var c: Dictionary = choices[ci]
			var w := "%s#%d" % [id, ci]
			assert_ne(String(c.get("label", "")), "", "%s 有 label" % w)
			# 门槛键合法
			for k in c.get("require", {}).keys():
				assert_true(k in REQUIRE_KEYS, "%s：门槛键 '%s' 合法" % [w, k])
			if c.get("require", {}).has("item"):
				assert_true(Backpack.ITEMS.has(String(c["require"]["item"])), "%s 门槛物品存在" % w)
			if c.get("require", {}).has("class"):
				assert_true(String(c["require"]["class"]) in CLASSES, "%s 门槛职业合法" % w)
			# 结果：确定 or 风险，二者必居其一
			assert_true(c.has("effects") or c.has("risk"), "%s 有 effects 或 risk" % w)
			if c.has("effects"):
				_check_effects(c["effects"], w)
			if c.has("risk"):
				_check_effects(c["risk"].get("win", []), w + ".win")
				_check_effects(c["risk"].get("lose", []), w + ".lose")


# ── 进入 / 不重复 ────────────────────────────────────────────────────────────

func test_enter_event_picks_unused() -> void:
	RunManager.start_run()
	RunManager.used_events = EventTable.all_ids().duplicate()
	RunManager.used_events.pop_back()          # 留一个没遇过
	var last: String = EventTable.all_ids().back()
	RunManager._enter_event()
	assert_eq(RunManager.current_event, last, "优先挑没遇过的事件")

func test_resolve_marks_used() -> void:
	RunManager.start_run()
	RunManager.current_event = "roadside_purse"
	RunManager.resolve_event_choice(0)
	assert_true("roadside_purse" in RunManager.used_events, "解析后记为遇过")


# ── 门槛判定 ──────────────────────────────────────────────────────────────────

func test_require_gold() -> void:
	RunManager.start_run()
	_party(["warrior"])
	RunManager.current_event = "gamblers_dice"   # 选项0 需 50 金
	RunManager.gold = 50
	assert_true(RunManager.event_choice_available(0), "够 50 金 → 可押注")
	RunManager.gold = 10
	assert_false(RunManager.event_choice_available(0), "不够 50 金 → 灰掉")

func test_require_class() -> void:
	RunManager.start_run()
	RunManager.current_event = "wounded_traveler"   # 选项0 需牧师
	_party(["warrior", "priest"])
	assert_true(RunManager.event_choice_available(0), "有牧师 → 可医治")
	_party(["warrior", "mage"])
	assert_false(RunManager.event_choice_available(0), "无牧师 → 灰掉")

func test_require_item_checks_inventory_and_bags() -> void:
	RunManager.start_run()
	_party(["warrior"])
	RunManager.current_event = "blacksmith_relic"   # 选项0 需铁剑
	assert_false(RunManager.event_choice_available(0), "无铁剑 → 灰掉")
	RunManager.owned_items["iron_sword"] = 1
	assert_true(RunManager.event_choice_available(0), "库存有铁剑 → 可选")
	RunManager.owned_items.erase("iron_sword")
	RunManager.roster[0]["grid"][Vector2i(0, 0)] = "iron_sword"
	assert_true(RunManager.event_choice_available(0), "背包里有铁剑也算")


# ── 效果应用 ──────────────────────────────────────────────────────────────────

func test_effect_gold_clamped() -> void:
	RunManager.start_run()
	RunManager.gold = 30
	RunManager._apply_event_effect({ "type": "gold", "amount": -50 })
	assert_eq(RunManager.gold, 0, "扣金钳到 ≥0")
	RunManager._apply_event_effect({ "type": "gold", "amount": 40 })
	assert_eq(RunManager.gold, 40, "加金正常")

func test_effect_item_to_inventory() -> void:
	RunManager.start_run()
	RunManager._apply_event_effect({ "type": "item", "id": "leather" })
	assert_eq(int(RunManager.owned_items.get("leather", 0)), 1, "物品进库存")

func test_effect_hp_pct_heal_and_damage_clamped() -> void:
	RunManager.start_run()
	_party(["warrior"])
	var h = RunManager.party[0]
	var mx: int = h.get_max_hp()
	# 扣血钳 ≥1：先设 1 血再扣 90%
	h.current_hp = 1
	RunManager._apply_event_effect({ "type": "hp_pct", "amount": -0.9 })
	assert_eq(h.current_hp, 1, "扣血钳到 ≥1，不猝死")
	# 回血钳到上限
	h.current_hp = mx - 1
	RunManager._apply_event_effect({ "type": "hp_pct", "amount": 0.5 })
	assert_eq(h.current_hp, mx, "回血钳到最大血")


# ── 风险 roll ─────────────────────────────────────────────────────────────────

func test_risk_win_and_lose_branches() -> void:
	RunManager.start_run()
	_party(["warrior"])
	# gamblers_dice 选项0：chance 0.5，win +100 / lose -50
	RunManager.current_event = "gamblers_dice"
	RunManager.gold = 100
	var win: Dictionary = RunManager.resolve_event_choice(0, 0.0)   # roll<0.5 → win
	assert_true(win["ok"], "满足门槛 → 可解析")
	assert_eq(RunManager.gold, 200, "赢 → +100")
	# 重置再试输
	RunManager.used_events = []
	RunManager.current_event = "gamblers_dice"
	RunManager.gold = 100
	RunManager.resolve_event_choice(0, 0.99)   # roll≥0.5 → lose
	assert_eq(RunManager.gold, 50, "输 → -50")

func test_resolve_blocked_when_require_unmet() -> void:
	RunManager.start_run()
	_party(["warrior"])
	RunManager.current_event = "gamblers_dice"
	RunManager.gold = 10                        # 不够 50
	var res: Dictionary = RunManager.resolve_event_choice(0, 0.0)
	assert_false(res["ok"], "门槛不满足 → 解析失败")
	assert_eq(RunManager.gold, 10, "金币不变")


# ── 回地图 ────────────────────────────────────────────────────────────────────

func test_leave_event_returns_to_map() -> void:
	RunManager.start_run()
	RunManager.leave_event()
	assert_eq(RunManager.state, RunManager.State.MAP, "离开事件 → 回地图")
