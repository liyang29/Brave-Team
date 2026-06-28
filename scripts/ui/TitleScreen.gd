extends Control

# ─────────────────────────────────────────────────────────────────────────────
# TitleScreen — 标题/入口（白盒）
#
# 仿照 Brave Guild 的入口结构（标题 + 按钮 → 切场景），但去掉了旧项目的
# ScaleManager / UI 贴图 / DataManager 存档依赖，纯代码搭白盒 UI。
#
# "开始冒险" 暂时进背包实验（当前唯一可玩核心）；等 RunManager + 跑局场景
# 做好后，改为进正式跑局场景即可。
# ─────────────────────────────────────────────────────────────────────────────

const SCENE_RUNMAP   := "res://scenes/run/RunMap.tscn"
const SCENE_SHOP     := "res://scenes/run/Shop.tscn"
const SCENE_ENCOUNTER := "res://scenes/run/Encounter.tscn"
const SCENE_BACKPACK := "res://scenes/experiments/BackpackExperiment.tscn"
const SCENE_GRID     := "res://scenes/experiments/GridExperiment.tscn"
const SCENE_POSITION := "res://scenes/experiments/PositionExperiment.tscn"

func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "BRAVE TEAM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "小队背包 Roguelike · 白盒原型"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.7, 0.75, 0.85)
	box.add_child(subtitle)

	box.add_child(_spacer(18))

	# 主按钮：开始冒险（占位 → 背包实验；将来接跑局场景）
	box.add_child(_make_button("▶  开始冒险", _on_start, true))

	box.add_child(_spacer(10))
	var dev_label := Label.new()
	dev_label.text = "— 开发实验 —"
	dev_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dev_label.modulate = Color(0.55, 0.55, 0.6)
	box.add_child(dev_label)

	box.add_child(_make_button("🎒  背包构筑实验", func(): _goto(SCENE_BACKPACK)))
	box.add_child(_make_button("⊞  网格站位实验", func(): _goto(SCENE_GRID)))
	box.add_child(_make_button("↕  前后排实验",   func(): _goto(SCENE_POSITION)))

	box.add_child(_spacer(18))
	box.add_child(_make_button("✕  退出", func(): get_tree().quit()))


func _make_button(text: String, on_pressed: Callable, primary: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 44 if primary else 36)
	btn.add_theme_font_size_override("font_size", 20 if primary else 16)
	if primary:
		btn.modulate = Color(1.0, 0.92, 0.6)
	btn.pressed.connect(on_pressed)
	return btn


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _on_start() -> void:
	# 开新跑局 → 直接进第 0 节点（村庄商店）；离开村庄后才回到节点地图
	RunManager.start_run()
	RunManager.enter_current_node()
	var node: Dictionary = RunManager.current_node()
	_goto(SCENE_SHOP if node.get("type") == "shop" else SCENE_ENCOUNTER)


func _goto(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
