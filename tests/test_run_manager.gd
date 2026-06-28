extends GutTest

# RunManager（autoload）跑局状态机的最小验证。

const Loadout = preload("res://scripts/systems/BackpackLoadout.gd")

# 过一个节点：胜利 → 若进 DRAFT 则用 keep 完成 draft 前进（默认不留以免污染库存）
func _advance(keep: Array = []) -> void:
	RunManager.resolve_encounter(true)
	if RunManager.state == RunManager.State.DRAFT:
		RunManager.finish_draft(keep)


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
	assert_eq(int(w_base["hp"]), 130, "战士裸base血=占位 130")
	assert_eq(int(w_base["atk"]), 16, "战士裸base攻=占位 16")

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
	RunManager.roster[0]["grid"][Vector2i(0, 0)] = "iron_sword"   # 战士摆把剑
	var alive: Array = RunManager.roster.filter(func(e): return e["hero"].is_alive())
	var party: Party = Loadout.build_party(alive, RunManager.squad_slots, false)
	var enemies: Array = RunManager.current_node().get("enemies", [])
	var result = BattleSimulator.simulate(party, enemies)
	assert_true(result is BattleResult, "遭遇战斗路径产出 BattleResult，不报错")


# ── Step 4：战利品 draft ──────────────────────────────────────────────────────

func test_normal_win_enters_draft() -> void:
	RunManager.start_run()
	RunManager.resolve_encounter(true)   # 第 0 节点是普通战斗
	assert_eq(RunManager.state, RunManager.State.DRAFT, "普通胜利 → 进入 DRAFT")
	assert_eq(RunManager.pending_draft.size(), 3, "抽出 3 件待选")
	assert_eq(RunManager.depth, 0, "depth 在 draft 完成前不前进")

func test_finish_draft_adds_kept_and_advances() -> void:
	RunManager.start_run()
	RunManager.resolve_encounter(true)
	RunManager.finish_draft(["iron_sword", "shield"])
	assert_eq(int(RunManager.owned_items.get("iron_sword", 0)), 1, "留下的物品进库存")
	assert_eq(int(RunManager.owned_items.get("shield", 0)), 1, "留下的第二件进库存")
	assert_eq(RunManager.depth, 1, "draft 完成后前进")
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
