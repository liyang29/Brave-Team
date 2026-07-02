extends GutTest

# MapGenerator — 尖塔式分层 DAG 生成器的属性验证（多种子跑，防偶发）。

const MapGenerator = preload("res://scripts/systems/run/MapGenerator.gd")
const MapConfig = preload("res://scripts/systems/run/MapConfig.gd")
const NodeTypes = preload("res://scripts/systems/run/NodeTypes.gd")

# 用固定种子跑一批（确定可复现），覆盖随机分布。
const SEEDS := [1, 7, 42, 100, 2024, 99999]


func _reaches_boss(map: Dictionary) -> bool:
	var nodes: Dictionary = map["nodes"]
	var seen: Dictionary = {}
	var queue: Array = [map["start_id"]]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if seen.has(id):
			continue
		seen[id] = true
		if nodes[id]["type"] == "boss":
			return true
		for nxt in nodes[id]["next"]:
			queue.append(nxt)
	return false


func test_connected_start_to_boss_all_seeds() -> void:
	for s in SEEDS:
		var map := MapGenerator.generate(MapConfig.DEFAULT, s)
		assert_true(_reaches_boss(map), "seed %d：从起点能走到魔王" % s)

func test_layer_count_matches_config() -> void:
	var cfg := MapConfig.DEFAULT.duplicate(true)
	cfg["layers"] = 6
	var map := MapGenerator.generate(cfg, 42)
	assert_eq(int(map["layers"]), 6, "层数跟随配置（改配置即改规模）")
	# 每个节点的 layer 都在 [0, 5]
	for id in map["nodes"]:
		var l: int = int(map["nodes"][id]["layer"])
		assert_between(l, 0, 5, "节点层号在范围内")

func test_unique_start_and_boss() -> void:
	for s in SEEDS:
		var nodes: Dictionary = MapGenerator.generate(MapConfig.DEFAULT, s)["nodes"]
		var l0 := 0
		var boss := 0
		for id in nodes:
			if int(nodes[id]["layer"]) == 0:
				l0 += 1
			if nodes[id]["type"] == "boss":
				boss += 1
		assert_eq(l0, 1, "seed %d：第 0 层唯一（起点村庄）" % s)
		assert_eq(boss, 1, "seed %d：全图唯一魔王" % s)

func test_pre_boss_layer_is_rest() -> void:
	for s in SEEDS:
		var map := MapGenerator.generate(MapConfig.DEFAULT, s)
		var pre: int = int(map["layers"]) - 2
		for id in map["nodes"]:
			if int(map["nodes"][id]["layer"]) == pre:
				assert_eq(map["nodes"][id]["type"], "rest", "seed %d：魔王前一层是泉水" % s)

func test_no_dead_ends() -> void:
	# 除魔王外每个节点都有后继（生成保证：每节点都在通向魔王的路径上）。
	for s in SEEDS:
		var nodes: Dictionary = MapGenerator.generate(MapConfig.DEFAULT, s)["nodes"]
		for id in nodes:
			if nodes[id]["type"] == "boss":
				continue
			assert_false((nodes[id]["next"] as Array).is_empty(), "seed %d：节点 %s 非死路" % [s, id])

func test_only_registered_types_spawn() -> void:
	# 生成器只用已在 NodeTypes 注册的类型（未注册类型不会出现在图里）。
	for s in SEEDS:
		var nodes: Dictionary = MapGenerator.generate(MapConfig.DEFAULT, s)["nodes"]
		for id in nodes:
			var t: String = nodes[id]["type"]
			assert_true(NodeTypes.REGISTRY.has(t), "seed %d：类型 '%s' 已注册" % [s, t])

func test_elite_respects_min_layer() -> void:
	# 精英不早于 min_layer（读 MapConfig 动态值，不写死数字）。
	var min_layer: int = int(MapConfig.DEFAULT["types"]["elite"].get("min_layer", 0))
	for s in SEEDS:
		var nodes: Dictionary = MapGenerator.generate(MapConfig.DEFAULT, s)["nodes"]
		for id in nodes:
			if nodes[id]["type"] == "elite":
				assert_gte(int(nodes[id]["layer"]), min_layer, "seed %d：精英不早于第 %d 层" % [s, min_layer])

func test_deterministic_with_seed() -> void:
	# 同种子生成同一张图（复现/存档基础）。
	var a := MapGenerator.generate(MapConfig.DEFAULT, 12345)
	var b := MapGenerator.generate(MapConfig.DEFAULT, 12345)
	assert_eq(a["nodes"].size(), b["nodes"].size(), "同种子节点数一致")
	assert_eq(a["seed"], 12345, "种子回填正确")
	for id in a["nodes"]:
		assert_true(b["nodes"].has(id), "同种子节点集一致：%s" % id)
		assert_eq(a["nodes"][id]["type"], b["nodes"][id]["type"], "同种子节点类型一致：%s" % id)

func test_battle_nodes_have_enemies() -> void:
	for s in SEEDS:
		var nodes: Dictionary = MapGenerator.generate(MapConfig.DEFAULT, s)["nodes"]
		for id in nodes:
			var t: String = nodes[id]["type"]
			if t in ["battle", "elite", "boss", "mid_boss"]:
				assert_false((nodes[id]["enemies"] as Array).is_empty(), "seed %d：%s 节点有敌人" % [s, t])
			else:
				assert_true((nodes[id]["enemies"] as Array).is_empty(), "seed %d：非战斗节点 %s 无敌人" % [s, t])

func test_mid_boss_appears_exactly_at_configured_layers() -> void:
	var mid_layers: Array = MapConfig.DEFAULT.get("mid_boss_layers", [])
	assert_false(mid_layers.is_empty(), "DEFAULT 配置了中程 Boss 层")
	for s in SEEDS:
		var nodes: Dictionary = MapGenerator.generate(MapConfig.DEFAULT, s)["nodes"]
		var found_layers: Array = []
		for id in nodes:
			if nodes[id]["type"] == "mid_boss":
				found_layers.append(int(nodes[id]["layer"]))
				assert_eq(int(nodes[id]["col"]), 0, "seed %d：中程 Boss 层是单节点 funnel（col=0）" % s)
		found_layers.sort()
		assert_eq(found_layers, mid_layers, "seed %d：中程 Boss 恰好出现在配置的层" % s)

func test_mid_boss_node_carries_boss_config() -> void:
	for s in SEEDS:
		var nodes: Dictionary = MapGenerator.generate(MapConfig.DEFAULT, s)["nodes"]
		for id in nodes:
			if nodes[id]["type"] == "mid_boss":
				var bc: Dictionary = nodes[id].get("boss_config", {})
				assert_false(bc.is_empty(), "seed %d：中程 Boss 节点 %s 带 boss_config" % [s, id])
				assert_true(bc.has("base_skills"), "seed %d：boss_config 含 base_skills" % s)

func test_non_mid_boss_nodes_have_no_boss_config() -> void:
	var map := MapGenerator.generate(MapConfig.DEFAULT, 42)
	for id in map["nodes"]:
		if map["nodes"][id]["type"] != "mid_boss":
			assert_false((map["nodes"][id] as Dictionary).has("boss_config"), "非中程 Boss 节点不带 boss_config 字段")
