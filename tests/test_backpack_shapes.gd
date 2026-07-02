extends GutTest

# 背包物品形状（空间填装）验证：占格展开 / 碰撞 / 多格协同 / 1×1 向后兼容。

const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")


# ── 占格展开 ──────────────────────────────────────────────────────────────────

func test_default_shape_is_1x1() -> void:
	# 没声明 shape 的物品 = 单格（老物品完全兼容）
	assert_eq(Backpack.shape_name("whetstone"), "1x1", "磨刀石缺省 1x1")
	assert_eq(Backpack.item_cells("whetstone", Vector2i(2, 3)), [Vector2i(2, 3)], "1×1 只占锚点自己")

func test_multicell_shapes_expand() -> void:
	# 铁剑 1×2 竖
	assert_eq(Backpack.item_cells("iron_sword", Vector2i(1, 1)),
		[Vector2i(1, 1), Vector2i(1, 2)], "铁剑 1×2竖 占锚点 + 正下方")
	# 锁甲 2×2
	var cm: Array = Backpack.item_cells("chainmail", Vector2i(0, 0))
	assert_eq(cm.size(), 4, "锁甲 2×2 占 4 格")
	for c in [Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)]:
		assert_true(c in cm, "锁甲含格 %s" % c)
	# 法杖 1×3 竖
	assert_eq(Backpack.item_cells("staff", Vector2i(3, 0)),
		[Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2)], "法杖 1×3竖")


# ── 碰撞 / 边界 ────────────────────────────────────────────────────────────────

func test_can_place_in_bounds() -> void:
	assert_true(Backpack.can_place({}, "chainmail", Vector2i(0, 0)), "空背包放锁甲 → 可")
	assert_true(Backpack.can_place({}, "chainmail", Vector2i(2, 2)), "锁甲放 (2,2) → 4×4 内 可")

func test_can_place_rejects_out_of_bounds() -> void:
	# 2×2 放在最右列 → 会越到 col4，越界
	assert_false(Backpack.can_place({}, "chainmail", Vector2i(3, 0)), "锁甲 2×2 放 col3 → 越界")
	# 1×3 竖放在 row2 → 会越到 row4
	assert_false(Backpack.can_place({}, "staff", Vector2i(0, 2)), "法杖 1×3竖 放 row2 → 越界")

func test_can_place_rejects_overlap() -> void:
	var grid := { Vector2i(0, 0): "chainmail" }   # 占 (0,0)(1,0)(0,1)(1,1)
	assert_false(Backpack.can_place(grid, "whetstone", Vector2i(1, 1)), "落在锁甲占用格 → 重叠拒绝")
	assert_true(Backpack.can_place(grid, "whetstone", Vector2i(2, 0)), "落在空格 → 可")

func test_can_place_ignore_anchor_for_move() -> void:
	# 移动某件到与自身当前占用重叠的新位：排除它自身才不会误判冲突
	var grid := { Vector2i(0, 0): "iron_sword" }   # 占 (0,0)(0,1)
	assert_false(Backpack.can_place(grid, "iron_sword", Vector2i(0, 1)), "不排除自身 → 与自己冲突")
	assert_true(Backpack.can_place(grid, "iron_sword", Vector2i(0, 1), Vector2i(0, 0)),
		"排除自身原位 → 可移到重叠新位")


# ── 占用图 ────────────────────────────────────────────────────────────────────

func test_occupied_cells_maps_to_anchor() -> void:
	var grid := { Vector2i(0, 0): "chainmail", Vector2i(3, 0): "whetstone" }
	var occ: Dictionary = Backpack.occupied_cells(grid)
	assert_eq(occ.size(), 5, "锁甲4格 + 磨刀石1格 = 5 个占用格")
	assert_eq(occ[Vector2i(1, 1)], Vector2i(0, 0), "锁甲的每个占用格都指回锚点")


# ── 协同（形状感知）─────────────────────────────────────────────────────────────

func test_multicell_synergy_fires_once() -> void:
	# 盾(1×2竖) 与 甲(2×2) 有 2 对格子相邻，但"重装"只应触发一次
	var grid := { Vector2i(0, 0): "shield", Vector2i(1, 0): "chainmail" }
	var b: Dictionary = Backpack.compute(grid)
	assert_eq(b["synergies"].count("重装"), 1, "多对相邻格 → 重装只算一次")

func test_multicell_item_stats_counted_once() -> void:
	# 锁甲占 4 格，但 def/hp 只加一次（不是 ×4）
	var b: Dictionary = Backpack.compute({ Vector2i(0, 0): "chainmail" })
	assert_eq(int(b["def"]), 6, "锁甲防御只算一次")
	assert_eq(int(b["hp"]), 10, "锁甲血量只算一次")

func test_non_adjacent_multicell_no_synergy() -> void:
	# 盾在 col0、甲在 col2，中间隔 col1 → 不相邻 → 无重装
	var grid := { Vector2i(0, 0): "shield", Vector2i(2, 0): "chainmail" }
	var b: Dictionary = Backpack.compute(grid)
	assert_false("重装" in b["synergies"], "隔开的盾甲不触发重装")


# ── 1×1 向后兼容 ──────────────────────────────────────────────────────────────

func test_1x1_adjacency_unchanged() -> void:
	# 铁剑(1×2竖) + 磨刀石(1×1) 相邻仍触发开刃（形状改造后老协同不丢）
	var adj := Backpack.compute({ Vector2i(0, 0): "iron_sword", Vector2i(1, 0): "whetstone" })
	assert_true("开刃" in adj["synergies"], "剑+磨刀石相邻 → 开刃")
	var far := Backpack.compute({ Vector2i(0, 0): "iron_sword", Vector2i(2, 0): "whetstone" })
	assert_false("开刃" in far["synergies"], "隔开 → 不开刃")


# ── 驮兽仓库：网格函数泛化支持任意宽高（MULE_GRID_W/H=6×6）────────────────────

func test_mule_grid_size_constants() -> void:
	assert_eq(Backpack.MULE_GRID_W, 6, "驮兽仓库宽 6（先定成这样，以后升级容量改这个数）")
	assert_eq(Backpack.MULE_GRID_H, 6, "驮兽仓库高 6")

func test_in_bounds_respects_custom_dims() -> void:
	assert_true(Backpack.in_bounds(Vector2i(5, 5), 6, 6), "6×6 网格里 (5,5) 在界内")
	assert_false(Backpack.in_bounds(Vector2i(4, 0), 4, 4), "同一坐标在 4×4 英雄背包里越界")

func test_can_place_respects_custom_dims() -> void:
	# 锁甲 2×2 放 (4,4)：4×4 背包越界，6×6 驮兽不越界
	assert_false(Backpack.can_place({}, "chainmail", Vector2i(4, 4)), "缺省尺寸(4×4) → 越界")
	assert_true(Backpack.can_place({}, "chainmail", Vector2i(4, 4), null, 6, 6), "传 6×6 → 界内可放")


# ── first_free_anchor / has_room（自动放置 + 容量判定）──────────────────────────

func test_first_free_anchor_finds_top_left_first() -> void:
	assert_eq(Backpack.first_free_anchor({}, "whetstone", 6, 6), Vector2i(0, 0), "空网格从左上角开始找")

func test_first_free_anchor_skips_occupied() -> void:
	var grid := { Vector2i(0, 0): "whetstone" }
	assert_eq(Backpack.first_free_anchor(grid, "whetstone", 6, 6), Vector2i(1, 0), "(0,0)占了 → 找下一个")

func test_first_free_anchor_returns_sentinel_when_full() -> void:
	# 塞满 6×6=36 个 1×1，再找就没地方了
	var grid: Dictionary = {}
	for y in range(6):
		for x in range(6):
			grid[Vector2i(x, y)] = "whetstone"
	assert_eq(Backpack.first_free_anchor(grid, "whetstone", 6, 6), Vector2i(-1, -1), "满了 → 哨兵值")

func test_has_room_true_when_space_exists() -> void:
	assert_true(Backpack.has_room({}, "chainmail", 6, 6), "空驮兽装得下锁甲")

func test_has_room_false_when_grid_full() -> void:
	var grid: Dictionary = {}
	for y in range(6):
		for x in range(6):
			grid[Vector2i(x, y)] = "whetstone"
	assert_false(Backpack.has_room(grid, "whetstone", 6, 6), "塞满 36 格后装不下新的")


# ── merge_target（英雄背包/驮兽仓库拖放合成共用判定，原两处面板脚本各抄一份）────

func test_merge_target_same_base_same_tier() -> void:
	var grid := { Vector2i(0, 0): "iron_sword" }
	assert_eq(Backpack.merge_target(grid, "iron_sword", Vector2i(0, 0)), Vector2i(0, 0), "同款同色阶 → 返回该锚点")

func test_merge_target_null_when_different_tier() -> void:
	var grid := { Vector2i(0, 0): "iron_sword@1" }
	assert_null(Backpack.merge_target(grid, "iron_sword", Vector2i(0, 0)), "色阶不同 → 不合成")

func test_merge_target_null_when_non_mergeable() -> void:
	var grid := { Vector2i(0, 0): "crit_gem" }
	assert_null(Backpack.merge_target(grid, "crit_gem", Vector2i(0, 0)), "非合成链物品 → 不合成")

func test_merge_target_null_when_empty_cell() -> void:
	assert_null(Backpack.merge_target({}, "iron_sword", Vector2i(0, 0)), "空格子 → 没有合成目标")

func test_merge_target_null_when_ignoring_own_anchor() -> void:
	# 物品在网格内挪动时排除自身原占用，不会跟自己"合成"
	var grid := { Vector2i(0, 0): "iron_sword" }
	assert_null(Backpack.merge_target(grid, "iron_sword", Vector2i(0, 0), Vector2i(0, 0)),
		"ignore=自身锚点 → 不当合成目标")
