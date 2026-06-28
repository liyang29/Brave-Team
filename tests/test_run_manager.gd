extends GutTest

# RunManager（autoload）跑局状态机的最小验证。

const Loadout = preload("res://scripts/systems/BackpackLoadout.gd")
const LootTable = preload("res://scripts/systems/LootTable.gd")

# 过一个节点：村庄→离开；泉水→回血并离开；战斗→胜利(若进 DRAFT 用 keep 完成)前进。
func _advance(keep: Array = []) -> void:
	match RunManager.current_node().get("type"):
		"shop":
			RunManager.leave_shop()
		"rest":
			RunManager.rest_heal()
			RunManager.leave_rest()
		_:
			RunManager.resolve_encounter(true)
			if RunManager.state == RunManager.State.DRAFT:
				RunManager.finish_draft(keep)


func test_start_run_sets_up_state() -> void:
	RunManager.start_run()
	assert_eq(RunManager.state, RunManager.State.MAP, "开局进入地图")
	assert_eq(RunManager.party.size(), 3, "起手 3 人小队")
	assert_eq(RunManager.gold, RunManager.START_GOLD, "起手金币=START_GOLD(500)")
	assert_eq(RunManager.depth, 0, "起手在第 0 节点")
	assert_gt(RunManager.nodes.size(), 0, "地图有节点")
	assert_eq(RunManager.current_node().get("type"), "shop", "第一个节点是村庄商店")


func test_win_advances_then_victory() -> void:
	RunManager.start_run()
	var n: int = RunManager.nodes.size()
	for i in range(n):
		_advance()
	assert_eq(RunManager.state, RunManager.State.VICTORY, "打完全部节点 = 通关")
	assert_gt(RunManager.gold, 0, "胜利累积金币")


func test_last_node_is_boss() -> void:
	RunManager.start_run()
	for i in range(RunManager.nodes.size() - 1):
		_advance()
	assert_true(RunManager.is_boss_node(), "最后一个节点是魔王")


func test_loss_is_game_over() -> void:
	RunManager.start_run()
	RunManager.resolve_encounter(false)
	assert_eq(RunManager.state, RunManager.State.GAME_OVER, "战败 = 游戏结束")


# ── Step 2：背包构筑状态 ──────────────────────────────────────────────────────

func test_start_run_inits_backpack_state() -> void:
	RunManager.start_run()
	assert_eq(RunManager.roster.size(), 3, "名册 3 人")
	for e in RunManager.roster:
		assert_true(e.has("hero") and e.has("base") and e.has("grid"), "条目含 hero/base/grid")
		assert_true(e["grid"].is_empty(), "起手空背包")
	assert_true(RunManager.owned_items.is_empty(), "起手库存空（靠战利品积累）")
	assert_eq(RunManager.squad_slots.size(), 3, "默认站位摆了 3 人")

func test_party_is_view_of_roster() -> void:
	RunManager.start_run()
	assert_eq(RunManager.party.size(), RunManager.roster.size(), "party 与 roster 同长")
	for i in range(RunManager.roster.size()):
		assert_eq(RunManager.party[i], RunManager.roster[i]["hero"], "party[i] 即名册第 i 人")

func test_default_formation_warrior_front() -> void:
	RunManager.start_run()
	# 战士（roster[0]）应在前排 row0
	assert_eq(RunManager.squad_slots.get(Vector2i(0, 0)), RunManager.roster[0]["hero"], "战士默认前排")
	assert_eq(RunManager.squad_slots.get(Vector2i(0, 1)), RunManager.roster[1]["hero"], "法师默认后排")

func test_base_captures_naked_stats() -> void:
	RunManager.start_run()
	var w_base: Dictionary = RunManager.roster[0]["base"]
	assert_eq(int(w_base["hp"]), 90, "战士裸base血=低值 90")
	assert_eq(int(w_base["atk"]), 6, "战士裸base攻=低值 6")

func test_backpack_state_persists_across_nodes() -> void:
	RunManager.start_run()
	# 往库存放点东西 + 给战士背包塞一件，模拟跨节点应保留
	RunManager.owned_items["iron_sword"] = 2
	RunManager.roster[0]["grid"][Vector2i(0, 0)] = "longsword"
	_advance()   # 过一个节点（draft 不留，避免污染库存）
	assert_eq(RunManager.depth, 1, "前进到第 1 节点")
	assert_eq(int(RunManager.owned_items.get("iron_sword", 0)), 2, "库存跨节点保留")
	assert_eq(RunManager.roster[0]["grid"].get(Vector2i(0, 0)), "longsword", "背包摆放跨节点保留")

func test_encounter_combat_path_runs() -> void:
	# 端到端：Encounter 的战斗路径——存活名册 → build_party(钳血) → 打真实节点敌人
	RunManager.start_run()
	RunManager.leave_shop()   # 跳过村庄到第一场战斗
	RunManager.roster[0]["grid"][Vector2i(0, 0)] = "iron_sword"   # 战士摆把剑
	var alive: Array = RunManager.roster.filter(func(e): return e["hero"].is_alive())
	var party: Party = Loadout.build_party(alive, RunManager.squad_slots, false)
	var enemies: Array = RunManager.current_node().get("enemies", [])
	var result = BattleSimulator.simulate(party, enemies)
	assert_true(result is BattleResult, "遭遇战斗路径产出 BattleResult，不报错")


# ── Step 4：战利品 draft ──────────────────────────────────────────────────────

func test_normal_win_enters_draft() -> void:
	RunManager.start_run()
	RunManager.leave_shop()              # 跳过村庄到第一场战斗（depth=1）
	RunManager.resolve_encounter(true)
	assert_eq(RunManager.state, RunManager.State.DRAFT, "普通胜利 → 进入 DRAFT")
	assert_eq(RunManager.pending_draft.size(), 3, "抽出 3 件待选")
	assert_eq(RunManager.depth, 1, "depth 在 draft 完成前不前进")

func test_finish_draft_adds_kept_and_advances() -> void:
	RunManager.start_run()
	RunManager.leave_shop()
	RunManager.resolve_encounter(true)
	RunManager.finish_draft(["iron_sword", "shield"])
	assert_eq(int(RunManager.owned_items.get("iron_sword", 0)), 1, "留下的物品进库存")
	assert_eq(int(RunManager.owned_items.get("shield", 0)), 1, "留下的第二件进库存")
	assert_eq(RunManager.depth, 2, "draft 完成后前进（村庄1→战斗后到2）")
	assert_eq(RunManager.state, RunManager.State.MAP, "回到地图")
	assert_true(RunManager.pending_draft.is_empty(), "pending_draft 清空")

func test_boss_win_skips_draft_to_victory() -> void:
	RunManager.start_run()
	for i in range(RunManager.nodes.size() - 1):
		_advance()
	assert_true(RunManager.is_boss_node(), "到了魔王节点")
	RunManager.resolve_encounter(true)   # 击败魔王
	assert_eq(RunManager.state, RunManager.State.VICTORY, "魔王胜 → 直接通关，不抽战利品")
	assert_true(RunManager.pending_draft.is_empty(), "魔王不产生 draft")


# ── 村庄商店 ──────────────────────────────────────────────────────────────────

func test_enter_shop_generates_stock() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()      # 第 0 节点是村庄
	assert_eq(RunManager.state, RunManager.State.SHOP, "进村庄 → SHOP 状态")
	assert_eq(RunManager.shop_stock.size(), RunManager.SHOP_STOCK_SIZE, "上货 6 件")

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
	var item: String = RunManager.shop_stock[0]
	assert_false(RunManager.buy_item(item), "没钱 → 买失败")
	assert_eq(int(RunManager.owned_items.get(item, 0)), 0, "没扣没进库存")

func test_leave_shop_advances_to_first_battle() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()
	RunManager.leave_shop()
	assert_eq(RunManager.depth, 1, "离开村庄 → 前进到第 1 节点")
	assert_eq(RunManager.state, RunManager.State.MAP, "回到地图")
	assert_eq(RunManager.current_node().get("type"), "battle", "第 1 节点是战斗")


# ── 泉水 / 休息点 ─────────────────────────────────────────────────────────────

func _goto_rest() -> void:
	RunManager.start_run()
	RunManager.leave_shop()   # →1 林间
	_advance()                # →2 剧毒
	_advance()                # →3 泉水

func test_node_3_is_rest() -> void:
	_goto_rest()
	assert_eq(RunManager.current_node().get("type"), "rest", "第 3 节点是泉水")

func test_enter_rest_sets_state() -> void:
	_goto_rest()
	RunManager.enter_current_node()
	assert_eq(RunManager.state, RunManager.State.REST, "进泉水 → REST 状态")

func test_rest_heals_capped() -> void:
	RunManager.start_run()
	var h = RunManager.party[0]
	h.current_hp = 1
	var mx: int = h.get_max_hp()
	RunManager.rest_heal()
	var expected: int = min(mx, 1 + int(ceil(mx * RunManager.REST_HEAL_PCT)))
	assert_eq(h.current_hp, expected, "回复 50%% 最大血（钳到上限）")
	assert_gt(h.current_hp, 1, "确实回了血")

func test_rest_does_not_revive_dead() -> void:
	RunManager.start_run()
	var h = RunManager.party[0]
	h.current_hp = 0
	RunManager.rest_heal()
	assert_eq(h.current_hp, 0, "阵亡的不被泉水复活")

func test_leave_rest_advances() -> void:
	_goto_rest()
	RunManager.enter_current_node()
	RunManager.leave_rest()
	assert_eq(RunManager.depth, 4, "离开泉水 → 第 4 节点")
	assert_eq(RunManager.current_node().get("type"), "battle", "第 4 节点是战斗（废墟）")
