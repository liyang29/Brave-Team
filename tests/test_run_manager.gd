extends GutTest

# RunManager（autoload）跑局状态机的最小验证。
# 设计：起手空队，在村庄(商店+招募合一)组建；地图 村庄→战→村庄→战→泉水→战→魔王。

const Loadout = preload("res://scripts/systems/backpack/BackpackLoadout.gd")
const LootTable = preload("res://scripts/systems/LootTable.gd")
const NodeTypes = preload("res://scripts/systems/run/NodeTypes.gd")

# 过一个节点：村庄→离开；泉水→回血并离开；战斗→胜利(若进 DRAFT 用 keep 完成)前进。
func _advance(keep: Array = []) -> void:
	match RunManager.current_node().get("type"):
		"village":
			RunManager.leave_village()
		"rest":
			RunManager.rest_heal()
			RunManager.leave_rest()
		_:
			RunManager.resolve_encounter(true)
			if RunManager.state == RunManager.State.DRAFT:
				RunManager.finish_draft(keep)

# 一直过节点直到当前节点是指定类型（到不了就停在终点）。
func _goto_type(t: String) -> void:
	RunManager.start_run()
	while RunManager.current_node().get("type") != t and RunManager.depth < RunManager.nodes.size():
		_advance()

# 给名册塞一支测试队（起手空队，战斗类测试需要先组队）。
func _seed_team() -> void:
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


func test_start_run_sets_up_state() -> void:
	RunManager.start_run()
	assert_eq(RunManager.state, RunManager.State.MAP, "开局进入地图")
	assert_eq(RunManager.party.size(), 0, "起手空队（村庄招募）")
	assert_eq(RunManager.gold, RunManager.START_GOLD, "起手金币=START_GOLD(500)")
	assert_eq(RunManager.depth, 0, "起手在第 0 节点")
	assert_eq(RunManager.current_node().get("type"), "village", "第一个节点是村庄")


func test_win_advances_then_victory() -> void:
	RunManager.start_run()
	for i in range(RunManager.nodes.size()):
		_advance()
	assert_eq(RunManager.state, RunManager.State.VICTORY, "打完全部节点 = 通关")


func test_last_node_is_boss() -> void:
	RunManager.start_run()
	for i in range(RunManager.nodes.size() - 1):
		_advance()
	assert_true(RunManager.is_boss_node(), "最后一个节点是魔王")


func test_loss_is_game_over() -> void:
	RunManager.start_run()
	RunManager.resolve_encounter(false)
	assert_eq(RunManager.state, RunManager.State.GAME_OVER, "战败 = 游戏结束")


# ── 背包构筑状态 ──────────────────────────────────────────────────────────────

func test_start_run_inits_backpack_state() -> void:
	RunManager.start_run()
	assert_true(RunManager.roster.is_empty(), "起手空名册")
	assert_true(RunManager.owned_items.is_empty(), "起手库存空")
	assert_true(RunManager.squad_slots.is_empty(), "起手无站位")

func test_party_is_view_of_roster() -> void:
	_seed_team()
	assert_eq(RunManager.party.size(), RunManager.roster.size(), "party 与 roster 同长")
	for i in range(RunManager.roster.size()):
		assert_eq(RunManager.party[i], RunManager.roster[i]["hero"], "party[i] 即名册第 i 人")

func test_hero_template_base() -> void:
	var w: Dictionary = RunManager.HERO_TEMPLATES["warrior"]
	assert_eq(int(w["hp"]), 90, "战士模板血=低值 90")
	assert_eq(int(w["atk"]), 6, "战士模板攻=低值 6")

func test_backpack_state_persists_across_nodes() -> void:
	RunManager.start_run()
	_seed_team()
	RunManager.owned_items["iron_sword"] = 2
	RunManager.roster[0]["grid"][Vector2i(0, 0)] = "longsword"
	_advance()   # 村庄 → 离开，前进一个节点
	assert_eq(RunManager.depth, 1, "前进到第 1 节点")
	assert_eq(int(RunManager.owned_items.get("iron_sword", 0)), 2, "库存跨节点保留")
	assert_eq(RunManager.roster[0]["grid"].get(Vector2i(0, 0)), "longsword", "背包摆放跨节点保留")

func test_encounter_combat_path_runs() -> void:
	# 端到端：走到首战 → 组队 → build_party(钳血) → 打真实节点敌人
	_goto_type("battle")
	_seed_team()
	RunManager.roster[0]["grid"][Vector2i(0, 0)] = "iron_sword"
	var alive: Array = RunManager.roster.filter(func(e): return e["hero"].is_alive())
	var party: Party = Loadout.build_party(alive, RunManager.squad_slots, false)
	var result = BattleSimulator.simulate(party, RunManager.current_node().get("enemies", []))
	assert_true(result is BattleResult, "遭遇战斗路径产出 BattleResult，不报错")


# ── 战利品 draft ──────────────────────────────────────────────────────────────

func test_normal_win_enters_draft() -> void:
	_goto_type("battle")               # 走到首战
	var d: int = RunManager.depth
	RunManager.resolve_encounter(true)
	assert_eq(RunManager.state, RunManager.State.DRAFT, "普通胜利 → 进入 DRAFT")
	assert_eq(RunManager.pending_draft.size(), 3, "抽出 3 件待选")
	assert_eq(RunManager.depth, d, "depth 在 draft 完成前不前进")

func test_finish_draft_adds_kept_and_advances() -> void:
	_goto_type("battle")
	var d: int = RunManager.depth
	RunManager.resolve_encounter(true)
	RunManager.finish_draft(["iron_sword", "shield"])
	assert_eq(int(RunManager.owned_items.get("iron_sword", 0)), 1, "留下的物品进库存")
	assert_eq(int(RunManager.owned_items.get("shield", 0)), 1, "留下的第二件进库存")
	assert_eq(RunManager.depth, d + 1, "draft 完成后前进一个节点")
	assert_eq(RunManager.state, RunManager.State.MAP, "回到地图")
	assert_true(RunManager.pending_draft.is_empty(), "pending_draft 清空")

func test_boss_win_skips_draft_to_victory() -> void:
	RunManager.start_run()
	for i in range(RunManager.nodes.size() - 1):
		_advance()
	assert_true(RunManager.is_boss_node(), "到了魔王节点")
	RunManager.resolve_encounter(true)
	assert_eq(RunManager.state, RunManager.State.VICTORY, "魔王胜 → 直接通关，不抽战利品")
	assert_true(RunManager.pending_draft.is_empty(), "魔王不产生 draft")


# ── 村庄（商店 + 招募合一）────────────────────────────────────────────────────

func test_enter_village_state_and_offers() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()      # 第 0 节点是村庄
	assert_eq(RunManager.state, RunManager.State.VILLAGE, "进村庄 → VILLAGE 状态")
	assert_eq(RunManager.shop_stock.size(), RunManager.SHOP_STOCK_SIZE, "商店上货 6 件")
	assert_eq(RunManager.tavern_offers.size(), RunManager.TAVERN_OFFERS, "招募上 3 候选")

func test_buy_item_deducts_gold_and_stocks() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()
	var item: String = RunManager.shop_stock[0]
	var cost: int = LootTable.price(item)
	var g0: int = RunManager.gold
	assert_true(RunManager.buy_item(item), "金币够 → 买成功")
	assert_eq(RunManager.gold, g0 - cost, "扣对应金币")
	assert_eq(int(RunManager.owned_items.get(item, 0)), 1, "买到的进库存")
	assert_false(item in RunManager.shop_stock, "买后下架")

func test_buy_fails_without_gold() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()
	RunManager.gold = 0
	assert_false(RunManager.buy_item(RunManager.shop_stock[0]), "没钱 → 买失败")

func test_leave_village_advances() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()
	RunManager.recruit(RunManager.tavern_offers[0])   # 招 1 人才好出发
	RunManager.leave_village()
	assert_eq(RunManager.depth, 1, "离开村庄 → 前进到第 1 节点")
	assert_eq(RunManager.current_node().get("type"), "battle", "第 1 节点是战斗")


# ── 招募 ──────────────────────────────────────────────────────────────────────

func test_recruit_adds_hero_and_deducts_gold() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()
	RunManager.gold = 1000
	var n0: int = RunManager.roster.size()
	var tid: String = RunManager.tavern_offers[0]
	var g0: int = RunManager.gold
	assert_true(RunManager.recruit(tid), "金币够且未满 → 招募成功")
	assert_eq(RunManager.roster.size(), n0 + 1, "名册多一人")
	assert_eq(RunManager.party.size(), n0 + 1, "party 同步多一人")
	assert_eq(RunManager.gold, g0 - RunManager.RECRUIT_COST, "扣招募费")
	assert_false(tid in RunManager.tavern_offers, "招过的候选下架")

func test_recruit_auto_places_in_slot() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()
	RunManager.gold = 1000
	var before: int = RunManager.squad_slots.size()
	RunManager.recruit(RunManager.tavern_offers[0])
	assert_eq(RunManager.squad_slots.size(), before + 1, "新人自动占一个站位格")

func test_recruit_blocked_when_party_full() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()
	RunManager.gold = 9999
	# 直接填满到上限（每村只 3 候选，靠多村累积；这里直接造满验证守卫）
	while not RunManager.party_is_full():
		RunManager.roster.append(RunManager.make_hero_entry("warrior"))
	assert_true(RunManager.party_is_full(), "已达队伍上限")
	var n0: int = RunManager.roster.size()
	assert_false(RunManager.recruit(RunManager.tavern_offers[0]), "满队 → 招募失败")
	assert_eq(RunManager.roster.size(), n0, "满队后人数不变")

func test_recruit_blocked_without_gold() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()
	RunManager.gold = 0
	assert_false(RunManager.recruit(RunManager.tavern_offers[0]), "没钱 → 招募失败")
	assert_eq(RunManager.roster.size(), 0, "人数不变（仍空）")

func test_hero_pool_has_rogue_and_archer() -> void:
	assert_true(RunManager.HERO_TEMPLATES.has("rogue"), "英雄池含盗贼")
	assert_true(RunManager.HERO_TEMPLATES.has("archer"), "英雄池含猎人")


# ── 节点类型注册表（R3：单一真相源守卫）──────────────────────────────────────

func test_every_map_node_type_is_registered() -> void:
	# 地图里出现的每种节点类型都必须在 NodeTypes 注册 —— 加类型漏注册时这条会红。
	RunManager.start_run()
	for n in RunManager.nodes:
		var t: String = n.get("type", "")
		assert_true(NodeTypes.REGISTRY.has(t), "节点类型 '%s' 已在 NodeTypes 注册" % t)

func test_registry_state_names_are_valid_states() -> void:
	# 注册表里的 state 名必须是合法的 RunManager.State 枚举名（State[name] 才不会炸）。
	for t in NodeTypes.REGISTRY:
		var sname: String = NodeTypes.REGISTRY[t].get("state", "")
		assert_true(RunManager.State.has(sname), "状态名 '%s' 是合法 State" % sname)

func test_enter_rest_via_registry() -> void:
	# 回归：rest 节点经注册表进入 REST（不再靠 enter_current_node 里的 match）。
	_goto_type("rest")
	RunManager.enter_current_node()
	assert_eq(RunManager.state, RunManager.State.REST, "rest 节点 → REST 状态（注册表驱动）")


# ── 泉水 / 休息点 ─────────────────────────────────────────────────────────────

func test_can_reach_rest() -> void:
	_goto_type("rest")
	assert_eq(RunManager.current_node().get("type"), "rest", "地图里能走到泉水节点")

func test_enter_rest_sets_state() -> void:
	_goto_type("rest")
	RunManager.enter_current_node()
	assert_eq(RunManager.state, RunManager.State.REST, "进泉水 → REST 状态")

func test_rest_heals_capped() -> void:
	RunManager.start_run()
	_seed_team()
	var h = RunManager.party[0]
	h.current_hp = 1
	var mx: int = h.get_max_hp()
	RunManager.rest_heal()
	var expected: int = min(mx, 1 + int(ceil(mx * RunManager.REST_HEAL_PCT)))
	assert_eq(h.current_hp, expected, "回复 50%% 最大血（钳到上限）")
	assert_gt(h.current_hp, 1, "确实回了血")

func test_rest_does_not_revive_dead() -> void:
	RunManager.start_run()
	_seed_team()
	var h = RunManager.party[0]
	h.current_hp = 0
	RunManager.rest_heal()
	assert_eq(h.current_hp, 0, "阵亡的不被泉水复活")

func test_leave_rest_advances() -> void:
	_goto_type("rest")
	var d: int = RunManager.depth
	RunManager.enter_current_node()
	RunManager.leave_rest()
	assert_eq(RunManager.depth, d + 1, "离开泉水 → 前进一个节点")
