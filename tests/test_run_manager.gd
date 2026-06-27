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
