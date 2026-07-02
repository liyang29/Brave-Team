extends GutTest

# BagGridView：自绘背包的悬浮提示（_get_tooltip 是位置相关的 Godot 钩子，纯逻辑可测，
# 不需要真实鼠标）。回归守卫：空间背包重构时曾把逐格 tooltip 落下，见 fix 提交。

const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")
const Prep = preload("res://scripts/ui/BackpackPrepPanel.gd")
const MulePanel = preload("res://scripts/ui/MulePanel.gd")
const BagGridView = preload("res://scripts/ui/BagGridView.gd")

const CELL := 46.0
const STEP := CELL + 4.0   # 与 BagGridView 的 CELL/GAP 对齐


func _make_bag(grid: Dictionary) -> BagGridView:
	var h: Hero = HeroFactory.create(Hero.HeroClass.WARRIOR)
	var base := { "hp": 90, "atk": 6, "def": 8, "magic": 0, "spd": 9, "mp": 40 }
	var entry := { "hero": h, "base": base, "grid": grid }
	var panel = Prep.new()
	add_child_autofree(panel)
	panel.setup([entry], {}, { Vector2i(0, 0): h })
	var bag := BagGridView.new()
	bag.panel = panel
	bag.hero_index = 0
	add_child_autofree(bag)
	return bag


func _pos_of(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * STEP + CELL * 0.5, cell.y * STEP + CELL * 0.5)


## kind="mule" 模式：panel 换成 MulePanel，网格读 RunManager.mule_grid（6×6）。
func _make_mule_bag(grid: Dictionary) -> BagGridView:
	RunManager.mule_grid = grid
	var panel = MulePanel.new()
	add_child_autofree(panel)
	panel.setup()
	var bag := BagGridView.new()
	bag.panel = panel
	bag.kind = "mule"
	bag.grid_w = Backpack.MULE_GRID_W
	bag.grid_h = Backpack.MULE_GRID_H
	add_child_autofree(bag)
	return bag


func test_tooltip_shows_item_info_at_occupied_cell() -> void:
	var bag := _make_bag({ Vector2i(0, 0): "iron_sword" })
	var tip := bag._get_tooltip(_pos_of(Vector2i(0, 0)))
	assert_eq(tip, Backpack.item_tooltip("iron_sword"), "悬浮在物品格上 → 返回该物品的完整属性文案")

func test_tooltip_works_on_any_cell_of_multicell_item() -> void:
	# 铁剑 1×2 竖：锚点(0,0) + 下方(0,1)，悬浮在下半格也该认出是同一件
	var bag := _make_bag({ Vector2i(0, 0): "iron_sword" })
	var tip := bag._get_tooltip(_pos_of(Vector2i(0, 1)))
	assert_eq(tip, Backpack.item_tooltip("iron_sword"), "多格物品的任意占用格都能查到提示")

func test_tooltip_empty_on_blank_cell() -> void:
	var bag := _make_bag({ Vector2i(0, 0): "iron_sword" })
	var tip := bag._get_tooltip(_pos_of(Vector2i(3, 3)))
	assert_eq(tip, "", "空格子不弹提示")

func test_tooltip_reflects_tier() -> void:
	var bag := _make_bag({ Vector2i(0, 0): "iron_sword@2" })   # 蓝铁剑
	var tip := bag._get_tooltip(_pos_of(Vector2i(0, 0)))
	assert_true(tip.contains("蓝"), "带色阶的物品提示里应包含色阶信息")


# ── kind="mule" 模式（驮兽仓库泛化，见 BackpackModel.MULE_GRID_W/H）─────────────

func test_mule_mode_uses_custom_grid_dims() -> void:
	var bag := _make_mule_bag({})
	assert_eq(bag.grid_w, 6, "驮兽模式宽 6")
	assert_eq(bag.grid_h, 6, "驮兽模式高 6")
	assert_eq(bag.custom_minimum_size, Vector2(6 * STEP, 6 * STEP), "自绘画布尺寸跟着 grid_w/h 走")

func test_mule_mode_never_locked() -> void:
	var bag := _make_mule_bag({})
	assert_false(bag._is_locked(), "驮兽不会\"死\"，kind=mule 时永不锁编辑")

func test_mule_mode_tooltip_reads_run_manager_mule() -> void:
	var bag := _make_mule_bag({ Vector2i(0, 0): "iron_sword" })
	var tip := bag._get_tooltip(_pos_of(Vector2i(0, 0)))
	assert_eq(tip, Backpack.item_tooltip("iron_sword"), "驮兽模式下 _grid() 读 RunManager.mule_grid")
