extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_run_map_scroll.gd — 地图自动滚到当前节点（居中显示）
#
# 深地图(45层)手动拖到自己在哪很烦，进地图应自动把当前节点滚到可视区中间。
# 用 _chain() 造一条足够长的确定链，把 current_node_id 设到中段/深处，验证
# RunMap._scroll.scroll_vertical 落在"当前节点居中"的算法预期值上。
# ─────────────────────────────────────────────────────────────────────────────

const RunMap = preload("res://scripts/ui/RunMap.gd")
const MapGraphView = preload("res://scripts/ui/MapGraphView.gd")

func before_each() -> void:
	MetaProgress.reset()
	MetaProgress.autosave = false
	RunManager.RECRUIT_POOL_OVERRIDE = []

# 同 test_run_manager.gd 的 _chain()：造一条确定的单后继链，当前节点设到指定下标。
func _chain_at(n: int, cur_index: int) -> void:
	var nodes: Dictionary = {}
	for i in range(n):
		var id := "n%d" % i
		nodes[id] = {
			"id": id, "layer": i, "col": 0, "type": "battle",
			"name": "battle", "enemies": MonsterFactory.create_group(["wolf"]),
			"gold": 10, "next": [],
		}
		if i > 0:
			nodes["n%d" % (i - 1)]["next"].append(id)
	RunManager.map_nodes = nodes
	RunManager.current_node_id = "n%d" % cur_index
	RunManager.map_layers = n
	RunManager.party = [HeroFactory.create(Hero.HeroClass.WARRIOR)]
	RunManager.state = RunManager.State.MAP


func test_current_node_control_set_to_current_layer_position() -> void:
	_chain_at(45, 30)
	var graph := MapGraphView.new()
	add_child_autofree(graph)
	assert_not_null(graph.current_node_control, "当前节点应有对应的静态面板")
	var expected_y: float = graph.MARGIN + 30 * graph.ROW_H
	assert_eq(graph.current_node_control.position.y, expected_y, "面板 y 坐标 = MARGIN + 当前层 × ROW_H")


func test_run_map_auto_scrolls_to_current_node_when_deep() -> void:
	_chain_at(45, 30)
	var map := RunMap.new()
	add_child_autofree(map)
	assert_not_null(map._scroll, "RunMap 应暴露 scroll 供校验")
	# 第30层的节点中心 y 远超一屏(420)高度，不自动滚的话默认停在顶部(scroll_vertical=0)
	assert_gt(map._scroll.scroll_vertical, 0, "深处节点应触发向下自动滚动，不再停在地图顶部")


func test_run_map_scroll_centers_current_node_in_viewport() -> void:
	_chain_at(45, 30)
	var map := RunMap.new()
	add_child_autofree(map)
	# 独立造一份 graph 只是为了拿到同样算法得出的节点中心 y，跟 RunMap 内部实际用的值对账
	var graph := MapGraphView.new()
	add_child_autofree(graph)
	var center_y: float = graph.current_node_control.position.y + graph.current_node_control.size.y * 0.5
	var expected: int = int(max(0.0, center_y - RunMap.MAP_SCROLL_HEIGHT * 0.5))
	assert_eq(map._scroll.scroll_vertical, expected, "滚动量 = 当前节点居中所需偏移")


func test_run_map_shallow_map_does_not_scroll_past_zero() -> void:
	# 浅图(层数少，内容比一屏矮)：居中算出来会是负值，钳到 0（不能滚出顶部之外）
	_chain_at(3, 1)
	var map := RunMap.new()
	add_child_autofree(map)
	assert_eq(map._scroll.scroll_vertical, 0, "本该滚成负值时钳到 0，不应真的往上滚出界")


func test_run_map_victory_state_has_no_scroll_container() -> void:
	# 通关横幅分支提前 return，不建地图/scroll——确认没崩、_scroll 保持初始 null
	RunManager.state = RunManager.State.VICTORY
	RunManager.gold = 100
	var map := RunMap.new()
	add_child_autofree(map)
	assert_null(map._scroll, "通关横幅分支不建地图，_scroll 应保持未设置")
