extends GutTest

# RunManager（autoload）跑局状态机的最小验证。

func test_start_run_sets_up_state() -> void:
	RunManager.start_run()
	assert_eq(RunManager.state, RunManager.State.MAP, "开局进入地图")
	assert_eq(RunManager.party.size(), 3, "起手 3 人小队")
	assert_eq(RunManager.gold, 0, "起手金币 0")
	assert_eq(RunManager.depth, 0, "起手在第 0 节点")
	assert_gt(RunManager.nodes.size(), 0, "地图有节点")
	assert_eq(RunManager.current_node().get("type"), "battle", "第一个节点是战斗")


func test_win_advances_then_victory() -> void:
	RunManager.start_run()
	var n: int = RunManager.nodes.size()
	for i in range(n):
		RunManager.resolve_encounter(true)
	assert_eq(RunManager.state, RunManager.State.VICTORY, "打完全部节点 = 通关")
	assert_gt(RunManager.gold, 0, "胜利累积金币")


func test_last_node_is_boss() -> void:
	RunManager.start_run()
	for i in range(RunManager.nodes.size() - 1):
		RunManager.resolve_encounter(true)
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
	assert_true(RunManager.owned_items.is_empty(), "起手库存为空（靠战利品）")
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
	assert_eq(int(w_base["hp"]), 130, "战士裸base血=占位 130")
	assert_eq(int(w_base["atk"]), 16, "战士裸base攻=占位 16")

func test_backpack_state_persists_across_nodes() -> void:
	RunManager.start_run()
	# 往库存放点东西 + 给战士背包塞一件，模拟跨节点应保留
	RunManager.owned_items["iron_sword"] = 2
	RunManager.roster[0]["grid"][Vector2i(0, 0)] = "longsword"
	RunManager.resolve_encounter(true)   # 过一个节点
	assert_eq(RunManager.depth, 1, "前进到第 1 节点")
	assert_eq(int(RunManager.owned_items.get("iron_sword", 0)), 2, "库存跨节点保留")
	assert_eq(RunManager.roster[0]["grid"].get(Vector2i(0, 0)), "longsword", "背包摆放跨节点保留")
