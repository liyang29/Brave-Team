extends GutTest

# RunManager（autoload）跑局状态机的验证。
# 设计：起手空队，在村庄(商店+招募合一)组建；地图 = 尖塔式分层 DAG（随机生成，严格连线约束）。
# 导航单测用 _chain() 注入一条确定的单后继链，避免依赖随机生成。

const Loadout = preload("res://scripts/systems/backpack/BackpackLoadout.gd")
const LootTable = preload("res://scripts/systems/LootTable.gd")
const NodeTypes = preload("res://scripts/systems/run/NodeTypes.gd")

# MetaProgress 是跨局持久的 autoload，GUT 全程共享同一个实例——本文件用 _chain()+travel_to()
# 走到较深的伪造层数（试图解锁书/职业），若不重置会把解锁状态"泄漏"给同文件的其它测试，
# 造成结果跟测试执行顺序绑定。每条测试前重置，保证互相独立。
# 关掉 autosave：默认存档路径就是玩家真实存档路径，测试解锁不该写进去。
func before_each() -> void:
	MetaProgress.reset()
	MetaProgress.autosave = false
	RunManager.RECRUIT_POOL_OVERRIDE = []   # 测试要看真实解锁池，不受玩家手动限定招募的影响

# 注入一条确定的单后继链地图（types[0]→types[1]→…），当前节点 = 第 0 个。
# 用于导航/房间/draft 单测，隔离随机生成的不确定性。
func _chain(types: Array) -> void:
	var nodes: Dictionary = {}
	for i in range(types.size()):
		var id := "n%d" % i
		nodes[id] = {
			"id": id, "layer": i, "col": 0, "type": types[i],
			"name": types[i], "enemies": [], "gold": 10, "next": [],
		}
		if types[i] in ["battle", "elite", "boss"]:
			nodes[id]["enemies"] = MonsterFactory.create_group(["wolf"])
		if i > 0:
			nodes["n%d" % (i - 1)]["next"].append(id)
	RunManager.map_nodes = nodes
	RunManager.current_node_id = "n0"
	RunManager.map_layers = types.size()

# 结束当前节点，并（若还在地图且有后继）走到第一个后继、进入它。
func _step(keep: Array = []) -> void:
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
	if RunManager.state == RunManager.State.MAP:
		var nx: Array = RunManager.reachable_next()
		if not nx.is_empty():
			RunManager.travel_to(nx[0])

# 沿确定链走到当前节点类型 == t（用于 battle/rest 等房间测试）。
func _goto_type(t: String) -> void:
	RunManager.start_run()
	_chain(["village", "battle", "rest", "battle", "boss"])
	var guard := 0
	while RunManager.current_node().get("type") != t and guard < 20:
		var before := RunManager.current_node_id
		_step()
		guard += 1
		if RunManager.current_node_id == before:
			break

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
	assert_eq(RunManager.current_layer(), 0, "起手在第 0 层")
	assert_eq(RunManager.current_node().get("type"), "village", "起点节点是村庄")


func test_beating_boss_is_victory() -> void:
	RunManager.start_run()
	_chain(["village", "battle", "boss"])
	var guard := 0
	while RunManager.state != RunManager.State.VICTORY and guard < 20:
		_step()
		guard += 1
	assert_eq(RunManager.state, RunManager.State.VICTORY, "打赢魔王 = 通关")


func test_can_reach_boss_node() -> void:
	_goto_type("boss")
	assert_true(RunManager.is_boss_node(), "沿链能走到魔王节点")


func test_loss_is_game_over() -> void:
	RunManager.start_run()
	RunManager.resolve_encounter(false)
	assert_eq(RunManager.state, RunManager.State.GAME_OVER, "战败 = 游戏结束")


# ── 分支地图（图结构 + 连线约束）──────────────────────────────────────────────

func test_map_is_generated_graph() -> void:
	RunManager.start_run()
	assert_gt(RunManager.map_nodes.size(), RunManager.map_layers, "图节点数应多于层数（中间层有宽度）")
	assert_true(RunManager.map_nodes.has(RunManager.current_node_id), "当前节点 id 在图里")

func test_start_and_boss_are_unique_anchors() -> void:
	RunManager.start_run()
	var villages_l0 := 0
	var bosses := 0
	for id in RunManager.map_nodes:
		var n: Dictionary = RunManager.map_nodes[id]
		if int(n["layer"]) == 0:
			villages_l0 += 1
			assert_eq(n["type"], "village", "第 0 层是村庄")
		if n["type"] == "boss":
			bosses += 1
	assert_eq(villages_l0, 1, "第 0 层只有一个村庄（唯一起点）")
	assert_eq(bosses, 1, "全图只有一个魔王（唯一汇点）")

func test_graph_is_connected_start_to_boss() -> void:
	# BFS 从起点必须能到魔王（无死路：生成保证每条路径都通向魔王）。
	RunManager.start_run()
	var seen: Dictionary = {}
	var queue: Array = [RunManager.current_node_id]
	var reached_boss := false
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if seen.has(id):
			continue
		seen[id] = true
		if RunManager.map_nodes[id]["type"] == "boss":
			reached_boss = true
		for nxt in RunManager.map_nodes[id]["next"]:
			queue.append(nxt)
	assert_true(reached_boss, "从起点能走到魔王")

func test_travel_only_to_successors() -> void:
	RunManager.start_run()
	_chain(["village", "battle", "boss"])
	assert_false(RunManager.can_travel_to("n2"), "不能直接跳到非后继节点（连线约束）")
	assert_true(RunManager.can_travel_to("n1"), "能去直接后继")
	assert_false(RunManager.travel_to("n2"), "travel 非后继失败")
	assert_eq(RunManager.current_node_id, "n0", "失败的 travel 不移动")

func test_travel_moves_and_enters() -> void:
	RunManager.start_run()
	_chain(["village", "battle", "boss"])
	RunManager.leave_village()                        # 结束村庄 → 回地图
	assert_true(RunManager.travel_to("n1"), "去后继 battle 成功")
	assert_eq(RunManager.current_node_id, "n1", "当前节点已移动到 battle")
	assert_eq(RunManager.state, RunManager.State.ENCOUNTER, "travel 会进入该节点（战斗 → ENCOUNTER）")

func test_pre_boss_layer_is_rest() -> void:
	# 决战前泄压：魔王前一层是泉水（funnel）。
	RunManager.start_run()
	var pre := RunManager.map_layers - 2
	for id in RunManager.map_nodes:
		var n: Dictionary = RunManager.map_nodes[id]
		if int(n["layer"]) == pre:
			assert_eq(n["type"], "rest", "魔王前一层是泉水")


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
	_chain(["village", "battle", "boss"])
	_seed_team()
	RunManager.owned_items["iron_sword"] = 2
	RunManager.roster[0]["grid"][Vector2i(0, 0)] = "longsword"
	_step()   # 村庄 → 走到下一节点
	assert_eq(RunManager.current_layer(), 1, "前进到第 1 层")
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
	var id: String = RunManager.current_node_id
	RunManager.resolve_encounter(true)
	assert_eq(RunManager.state, RunManager.State.DRAFT, "普通胜利 → 进入 DRAFT")
	assert_eq(RunManager.pending_draft.size(), 3, "抽出 3 件待选")
	assert_eq(RunManager.current_node_id, id, "draft 完成前不移动节点")

func test_finish_draft_adds_kept_and_returns_to_map() -> void:
	_goto_type("battle")
	var id: String = RunManager.current_node_id
	RunManager.resolve_encounter(true)
	RunManager.finish_draft(["iron_sword", "shield"])
	assert_eq(int(RunManager.owned_items.get("iron_sword", 0)), 1, "留下的物品进库存")
	assert_eq(int(RunManager.owned_items.get("shield", 0)), 1, "留下的第二件进库存")
	assert_eq(RunManager.state, RunManager.State.MAP, "回到地图（等玩家选后继）")
	assert_eq(RunManager.current_node_id, id, "draft 结束不自动前进（分支图由玩家选后继）")
	assert_true(RunManager.pending_draft.is_empty(), "pending_draft 清空")

func test_boss_win_skips_draft_to_victory() -> void:
	_goto_type("boss")
	assert_true(RunManager.is_boss_node(), "到了魔王节点")
	RunManager.resolve_encounter(true)
	assert_eq(RunManager.state, RunManager.State.VICTORY, "魔王胜 → 直接通关，不抽战利品")
	assert_true(RunManager.pending_draft.is_empty(), "魔王不产生 draft")


# ── 阵亡英雄自动腾出站位格（随葬品：装备/roster 不动，只清 squad_slots）───────

func test_resolve_encounter_vacates_dead_hero_squad_slot() -> void:
	_goto_type("battle")
	_seed_team()
	var mage = RunManager.roster[1]["hero"]
	var result := BattleResult.victory([], [mage], {}, [], 3)
	RunManager.resolve_encounter(true, result)
	assert_false(RunManager.squad_slots.has(Vector2i(0, 1)), "阵亡法师的站位格被自动清空")
	assert_eq(RunManager.squad_slots.get(Vector2i(0, 0)), RunManager.roster[0]["hero"], "存活战士的站位格不受影响")
	assert_true(mage in RunManager.roster.map(func(e): return e["hero"]), "阵亡英雄仍留在 roster（永久死亡=标记不删除）")

func test_resolve_encounter_no_dead_heroes_keeps_squad_slots() -> void:
	_goto_type("battle")
	_seed_team()
	var before: Dictionary = RunManager.squad_slots.duplicate()
	RunManager.resolve_encounter(true, BattleResult.victory([], [], {}, [], 3))
	assert_eq(RunManager.squad_slots, before, "无人阵亡 → 站位格原样不动")

func test_resolve_encounter_without_result_does_not_crash() -> void:
	# 兼容旧调用（result 缺省 null，见其它测试如 test_loss_is_game_over）：不该报错
	_goto_type("battle")
	_seed_team()
	RunManager.resolve_encounter(true)
	assert_eq(RunManager.state, RunManager.State.DRAFT, "result=null 时仍正常走完流程")


# ── 村庄（商店 + 招募合一）────────────────────────────────────────────────────

func test_enter_village_state_and_offers() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()      # 起点是村庄
	assert_eq(RunManager.state, RunManager.State.VILLAGE, "进村庄 → VILLAGE 状态")
	assert_eq(RunManager.shop_stock.size(), RunManager.SHOP_STOCK_SIZE, "商店上货 6 件")
	# 招募候选 = 已解锁的职业数（局外成长起手锁盗贼/猎人）；TAVERN_OFFERS 只是"最多上几个"上限
	var unlocked_classes: int = RunManager.HERO_TEMPLATES.keys().filter(func(id): return MetaProgress.is_unlocked(id)).size()
	assert_eq(RunManager.tavern_offers.size(), unlocked_classes, "招募候选=当前已解锁的职业数")

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

func test_can_leave_village_requires_min_party() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()
	RunManager.gold = 1000
	assert_false(RunManager.can_leave_village(), "0 人不能出发")
	RunManager.recruit(RunManager.tavern_offers[0])
	assert_false(RunManager.can_leave_village(), "1 人(还招得起)不能出发——避免 1 人送死第一关")
	RunManager.recruit(RunManager.tavern_offers[0])
	assert_true(RunManager.can_leave_village(), "招满 2 人 → 可出发")

func test_can_leave_village_escape_when_cannot_recruit() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()
	RunManager.gold = 1000
	RunManager.recruit(RunManager.tavern_offers[0])   # 1 人
	RunManager.gold = 0                                # 招不动了
	assert_true(RunManager.can_leave_village(), "1 人但没钱再招 → 放行，避免卡死")

func test_leave_village_returns_to_map() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()
	RunManager.recruit(RunManager.tavern_offers[0])
	RunManager.leave_village()
	assert_eq(RunManager.state, RunManager.State.MAP, "离开村庄 → 回地图")
	assert_false(RunManager.reachable_next().is_empty(), "村庄有后继可选（不是死路）")


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

func test_tavern_offers_covers_every_class() -> void:
	# TAVERN_OFFERS 是手动同步的数字（GDScript 常量表达式不能调 .size()）；
	# 守住"酒馆一次上全部职业"这个设计意图——加/删英雄职业忘了同步这条会红。
	assert_eq(RunManager.TAVERN_OFFERS, RunManager.HERO_TEMPLATES.size(),
		"TAVERN_OFFERS 应等于英雄池大小（酒馆全职业候选，不漏显示也不多要）")


# ── 节点类型注册表（单一真相源守卫）──────────────────────────────────────────

func test_every_map_node_type_is_registered() -> void:
	# 生成图里出现的每种节点类型都必须在 NodeTypes 注册 —— 加类型漏注册时这条会红。
	RunManager.start_run()
	for id in RunManager.map_nodes:
		var t: String = RunManager.map_nodes[id].get("type", "")
		assert_true(NodeTypes.REGISTRY.has(t), "节点类型 '%s' 已在 NodeTypes 注册" % t)

func test_registry_state_names_are_valid_states() -> void:
	for t in NodeTypes.REGISTRY:
		var sname: String = NodeTypes.REGISTRY[t].get("state", "")
		assert_true(RunManager.State.has(sname), "状态名 '%s' 是合法 State" % sname)

func test_enter_rest_via_registry() -> void:
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

func test_leave_rest_returns_to_map() -> void:
	_goto_type("rest")
	RunManager.enter_current_node()
	RunManager.leave_rest()
	assert_eq(RunManager.state, RunManager.State.MAP, "离开泉水 → 回地图选后继")
