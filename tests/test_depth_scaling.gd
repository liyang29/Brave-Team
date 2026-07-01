extends GutTest

# 深度缩放：scale_enemy 数学 / 分档选怪 / 总开关 / 单项开关 / 魔王不缩放。

const MapGenerator = preload("res://scripts/systems/run/MapGenerator.gd")
const MapConfig = preload("res://scripts/systems/run/MapConfig.gd")

func _scale_cfg() -> Dictionary:
	return MapConfig.DEFAULT["enemy_scale"]


func test_scale_math() -> void:
	var e: EnemyData = MonsterFactory.create("wolf")   # hp 70
	var base_hp: int = e.base_max_hp
	MapGenerator.scale_enemy(e, 10, { "hp_per_layer": 0.05, "atk_per_layer": 0.0, "def_per_layer": 0.0 })
	assert_eq(e.base_max_hp, int(round(base_hp * 1.5)), "第10层 hp ×(1+10×0.05)=×1.5")

func test_deeper_is_stronger() -> void:
	var shallow: EnemyData = MonsterFactory.create("wolf")
	var deep: EnemyData = MonsterFactory.create("wolf")
	MapGenerator.scale_enemy(shallow, 2, _scale_cfg())
	MapGenerator.scale_enemy(deep, 20, _scale_cfg())
	assert_gt(deep.base_max_hp, shallow.base_max_hp, "越深怪越肉")
	assert_gt(deep.base_attack, shallow.base_attack, "越深怪越疼")

func test_master_switch_off_no_scale() -> void:
	var e: EnemyData = MonsterFactory.create("wolf")
	var hp0: int = e.base_max_hp
	MapGenerator.apply_depth_scale([e], 20, "battle",
		{ "enemy_scale": { "enabled": false, "hp_per_layer": 0.5 } })
	assert_eq(e.base_max_hp, hp0, "总开关关 → 完全不缩放")

func test_per_stat_switch_off() -> void:
	# def_per_layer=0 → 防御这一样不缩放（单项开关）
	var e: EnemyData = MonsterFactory.create("stone_guard")   # def 8
	var d0: int = e.base_defense
	MapGenerator.scale_enemy(e, 10, { "hp_per_layer": 0.05, "atk_per_layer": 0.04, "def_per_layer": 0.0 })
	assert_eq(e.base_defense, d0, "def系数0 → 防御不变")
	assert_gt(e.base_max_hp, 70, "血仍缩放")

func test_boss_skipped() -> void:
	var e: EnemyData = MonsterFactory.create("demon_lord")
	var hp0: int = e.base_max_hp
	MapGenerator.apply_depth_scale([e], 30, "boss", MapConfig.DEFAULT)
	assert_eq(e.base_max_hp, hp0, "boss 在 skip_types → 不吃 ramp（终点门槛手调）")

func test_pick_group_by_layer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var tiers: Array = MapConfig.DEFAULT["battle_tiers"]
	var early = MapGenerator._pick_group(tiers, 1, rng)
	assert_true(early in tiers[0]["groups"], "第1层从前期档选怪")
	var late = MapGenerator._pick_group(tiers, 50, rng)
	assert_true(late in tiers[tiers.size() - 1]["groups"], "第50层从后期档选怪")

func test_generated_battle_has_enemies_all_layers() -> void:
	# 分档 + 缩放后，任意层的战斗节点仍有敌人（分档不漏空）
	for s in [1, 42, 2024]:
		var nodes: Dictionary = MapGenerator.generate(MapConfig.DEFAULT, s)["nodes"]
		for id in nodes:
			if nodes[id]["type"] in ["battle", "elite", "boss"]:
				assert_false((nodes[id]["enemies"] as Array).is_empty(),
					"seed %d：%s 有敌人" % [s, nodes[id]["type"]])
