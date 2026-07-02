extends Control

# ─────────────────────────────────────────────────────────────────────────────
# DraftScreen — 战利品三选二
# 读 RunManager.pending_draft（胜利后抽出的 3 件）→ 玩家点掉 1 件不要的 →
# 剩下 2 件经 RunManager.finish_draft 进库存 → 回地图。
# ─────────────────────────────────────────────────────────────────────────────

const SCENE_MAP := "res://scenes/run/RunMap.tscn"
const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")

const RARITY_ZH := { "common": "普通", "rare": "稀有", "epic": "史诗" }


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	root.offset_left = 40; root.offset_top = 30; root.offset_right = -40; root.offset_bottom = -30
	add_child(root)

	var title := Label.new()
	title.text = "战利品 · 三选二"
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "点你[b]不要[/b]的那件丢弃，剩下 2 件进库存（下场遭遇前可摆进背包）"
	hint.modulate = Color(0.75, 0.78, 0.85)
	root.add_child(hint)

	var spacer := Control.new(); spacer.custom_minimum_size = Vector2(0, 10)
	root.add_child(spacer)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 16)
	root.add_child(cards)

	var draft: Array = RunManager.pending_draft
	for item_id in draft:
		cards.add_child(_make_card(item_id, draft))


func _make_card(item_id: String, draft: Array) -> Control:
	var it: Dictionary = Backpack.item_def(item_id)
	var rarity: String = it.get("rarity", "common")
	var tier_col: Color = Backpack.tier_color(Backpack.item_tier(item_id))

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(220, 0)
	box.add_theme_constant_override("separation", 6)

	var name_lbl := Label.new()
	name_lbl.text = Backpack.item_name(item_id)
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.modulate = tier_col
	box.add_child(name_lbl)

	var rar_lbl := Label.new()
	rar_lbl.text = "【%s】" % RARITY_ZH.get(rarity, rarity)
	rar_lbl.modulate = tier_col
	box.add_child(rar_lbl)

	var desc := Label.new()
	desc.text = Backpack.item_desc(item_id)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(220, 0)
	desc.modulate = Color(0.8, 0.85, 0.8)
	box.add_child(desc)

	var discard := Button.new()
	discard.text = "✕ 丢弃这件"
	discard.custom_minimum_size = Vector2(0, 40)
	discard.pressed.connect(_on_discard.bind(item_id, draft))
	box.add_child(discard)

	return box


func _on_discard(discarded: String, draft: Array) -> void:
	# 留下除被丢弃外的其余物品（三选二）
	var kept: Array = []
	var skipped := false
	for id in draft:
		if id == discarded and not skipped:
			skipped = true   # 只丢一件（即便重复也只丢一个，但同抽不会重复）
			continue
		kept.append(id)
	var overflow: Array = RunManager.finish_draft(kept)
	if overflow.is_empty():
		get_tree().change_scene_to_file(SCENE_MAP)
	else:
		_show_overflow_notice(overflow)


## 驮兽装不下时才会走到这——留下的东西没能全带走，告诉玩家一声再回地图（不静默丢东西）。
func _show_overflow_notice(overflow: Array) -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	root.offset_left = 40; root.offset_top = 30; root.offset_right = -40; root.offset_bottom = -30
	add_child(root)

	var names: Array = overflow.map(func(id): return Backpack.item_name(id))
	var msg := RichTextLabel.new()
	msg.bbcode_enabled = true
	msg.fit_content = true
	msg.add_theme_font_size_override("normal_font_size", 20)
	msg.text = "[color=orange]驮兽仓库装不下了[/color]\n没能带走：%s\n（去驮兽仓库丢弃/卖掉点东西腾地方，下次就能拿了）" % ", ".join(names)
	root.add_child(msg)

	var btn := Button.new()
	btn.text = "知道了 ▶"
	btn.custom_minimum_size = Vector2(160, 40)
	btn.pressed.connect(func(): get_tree().change_scene_to_file(SCENE_MAP))
	root.add_child(btn)
