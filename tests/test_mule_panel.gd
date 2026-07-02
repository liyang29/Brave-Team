extends GutTest

# ─────────────────────────────────────────────────────────────────────────────
# test_mule_panel — MulePanel（村庄用的独立驮兽视图：整理/合成 + 丢弃 + 卖出）
#
# 跟 BackpackPrepPanel 不同，MulePanel 直接读写 RunManager.mule_grid（没有英雄
# 背包/站位的复用需求），所以每条测试都要显式摆好 RunManager.mule_grid/gold。
# ─────────────────────────────────────────────────────────────────────────────

const MulePanel = preload("res://scripts/ui/MulePanel.gd")
const LootTable = preload("res://scripts/systems/LootTable.gd")

func before_each() -> void:
	RunManager.mule_grid = {}
	RunManager.gold = 0

func _make_panel() -> MulePanel:
	var p := MulePanel.new()
	add_child_autofree(p)
	p.setup()
	return p


func test_setup_builds_without_error() -> void:
	var p := _make_panel()
	assert_not_null(p, "面板实例化 + setup 不报错")
	assert_not_null(p._mule_view, "内含一个 BagGridView")


func test_grab_payload_reads_from_run_manager_mule() -> void:
	RunManager.mule_grid[Vector2i(0, 0)] = "iron_sword"
	var p := _make_panel()
	var data = p.grab_payload("mule", Vector2i(0, 0))
	assert_eq(data["id"], "iron_sword", "从 RunManager.mule_grid 读物品")
	assert_eq(data["src"], { "kind": "mule", "anchor": Vector2i(0, 0) }, "载荷标记来源锚点")

func test_grab_payload_empty_anchor_returns_null() -> void:
	var p := _make_panel()
	assert_null(p.grab_payload("mule", Vector2i(0, 0)), "空锚点抓不出东西")


func test_can_accept_item_into_mule_trash_sell() -> void:
	var p := _make_panel()
	var item := { "type": "item" }
	var hero := { "type": "hero" }
	assert_true(p.can_accept("mule", null, item), "物品可拖回驮兽格")
	assert_true(p.can_accept("trash", null, item), "物品可拖进丢弃桶")
	assert_true(p.can_accept("sell", null, item), "物品可拖进卖出格")
	assert_false(p.can_accept("mule", null, hero), "MulePanel 不认英雄载荷")


func test_reorganize_moves_item_within_mule() -> void:
	RunManager.mule_grid[Vector2i(0, 0)] = "iron_sword"
	var p := _make_panel()
	p.handle_drop("mule", Vector2i(3, 0), p.grab_payload("mule", Vector2i(0, 0)))
	assert_false(RunManager.mule_grid.has(Vector2i(0, 0)), "原锚点腾空")
	assert_eq(RunManager.mule_grid.get(Vector2i(3, 0)), "iron_sword", "移到新锚点")

func test_drop_onto_matching_item_merges() -> void:
	RunManager.mule_grid[Vector2i(0, 0)] = "iron_sword"
	RunManager.mule_grid[Vector2i(3, 0)] = "iron_sword"
	var p := _make_panel()
	p.handle_drop("mule", Vector2i(0, 0), p.grab_payload("mule", Vector2i(3, 0)))
	assert_eq(RunManager.mule_grid.get(Vector2i(0, 0)), "iron_sword@1", "同款落上去 → 原地合成为绿")
	assert_false(RunManager.mule_grid.has(Vector2i(3, 0)), "被消耗的那把腾空")

func test_drop_onto_overlap_rejected() -> void:
	RunManager.mule_grid[Vector2i(0, 0)] = "iron_sword"   # 1×2竖 占(0,0)(0,1)
	RunManager.mule_grid[Vector2i(2, 0)] = "shield"        # 1×2竖 占(2,0)(2,1)
	var p := _make_panel()
	p.handle_drop("mule", Vector2i(2, 0), p.grab_payload("mule", Vector2i(0, 0)))
	assert_eq(RunManager.mule_grid.get(Vector2i(0, 0)), "iron_sword", "重叠被拒 → 剑留在原位")
	assert_eq(RunManager.mule_grid.get(Vector2i(2, 0)), "shield", "盾也没被挤动")

func test_mule_can_drop_out_of_bounds_rejected() -> void:
	RunManager.mule_grid[Vector2i(0, 0)] = "iron_sword"
	var p := _make_panel()
	assert_false(p.mule_can_drop("iron_sword", { "kind": "mule", "anchor": Vector2i(0,0) }, Vector2i(5, 5)),
		"6×6 网格，(5,5)+1×2竖会越到 row6 → 越界拒绝")


func test_trash_discards_without_gold() -> void:
	RunManager.mule_grid[Vector2i(0, 0)] = "iron_sword"
	var p := _make_panel()
	p.handle_drop("trash", null, p.grab_payload("mule", Vector2i(0, 0)))
	assert_true(RunManager.mule_grid.is_empty(), "丢弃后驮兽腾空")
	assert_eq(RunManager.gold, 0, "丢弃不给钱")

func test_sell_awards_gold_and_clears_anchor() -> void:
	RunManager.mule_grid[Vector2i(0, 0)] = "iron_sword"
	var p := _make_panel()
	p.handle_drop("sell", null, p.grab_payload("mule", Vector2i(0, 0)))
	assert_eq(RunManager.gold, LootTable.sell_price("iron_sword"), "卖出进账五折价")
	assert_true(RunManager.mule_grid.is_empty(), "卖出后驮兽腾空")
