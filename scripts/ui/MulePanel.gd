extends VBoxContainer

# ─────────────────────────────────────────────────────────────────────────────
# MulePanel — 驮兽仓库独立视图（村庄用：整理/合成 + 丢弃 + 卖出）
#
# 跟 BackpackPrepPanel 的驮兽区块是同一套网格(RunManager.mule_grid)、同一套形状/
# 合成规则，但这里没有英雄背包/站位——只管驮兽自己，外加"卖出"（只有村庄能卖）。
# 直接读写 RunManager（VillageScreen 一贯的风格，不像 BackpackPrepPanel 那样注入
# 状态——那是为了给 BackpackExperiment 沙盒复用，这里没有复用沙盒的需求）。
#
# 拖放交互（同 BagGridView/DragSlot 的委托契约）：
#   驮兽格 ↔ 驮兽格：整理/同款同色阶=合成
#   驮兽格 → 丢弃桶：直接消失，不给钱
#   驮兽格 → 卖出格：按 LootTable.sell_price 进钱（五折，色阶不影响）
# ─────────────────────────────────────────────────────────────────────────────

const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")
const LootTable = preload("res://scripts/systems/LootTable.gd")
const DragSlot = preload("res://scripts/ui/DragSlot.gd")
const BagGridView = preload("res://scripts/ui/BagGridView.gd")

var _mule_view: BagGridView


func setup() -> void:
	add_theme_constant_override("separation", 6)
	_build_ui()
	refresh()

## 供 BagGridView(kind="mule") 读——驮兽仓库的原始 Dictionary 引用。
func mule_grid_ref() -> Dictionary:
	return RunManager.mule_grid


func _build_ui() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	_mule_view = BagGridView.new()
	_mule_view.panel = self
	_mule_view.kind = "mule"
	_mule_view.grid_w = Backpack.MULE_GRID_W
	_mule_view.grid_h = Backpack.MULE_GRID_H
	row.add_child(_mule_view)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)

	var trash := DragSlot.new()
	trash.panel = self
	trash.kind = "trash"
	trash.custom_minimum_size = Vector2(96, 72)
	trash.set_display("🗑 丢弃", Color(0.85, 0.55, 0.55))
	trash.tooltip_text = "拖到这直接丢弃，不给钱（纯腾地方）"
	actions.add_child(trash)

	var sell := DragSlot.new()
	sell.panel = self
	sell.kind = "sell"
	sell.custom_minimum_size = Vector2(96, 72)
	sell.set_display("💰 卖出", Color(1.0, 0.9, 0.5))
	sell.tooltip_text = "拖到这按稀有度五折卖出（色阶合成品按基础稀有度算，不因为合成过更贵）"
	actions.add_child(sell)

	row.add_child(actions)
	add_child(row)


func refresh() -> void:
	_mule_view.queue_redraw()


# ── 拖放回调（被 BagGridView/DragSlot 调用，契约同 BackpackPrepPanel）───────────

func grab_payload(kind: String, key) -> Variant:
	if kind != "mule":
		return null
	var anchor: Vector2i = key
	var mule: Dictionary = RunManager.mule_grid
	if not mule.has(anchor):
		return null
	return { "type": "item", "id": mule[anchor], "label": Backpack.item_name(mule[anchor]),
			"src": { "kind": "mule", "anchor": anchor } }


func can_accept(kind: String, _key, data: Dictionary) -> bool:
	return data.get("type", "") == "item" and kind in ["mule", "trash", "sell"]


func handle_drop(kind: String, key, data: Dictionary) -> void:
	if data.get("type", "") != "item":
		return
	var src: Dictionary = data["src"]
	match kind:
		"trash":
			RunManager.discard_mule_item(src.get("anchor"))
		"sell":
			RunManager.sell_mule_item(src.get("anchor"))
		"mule":
			_drop_into_mule(data, key)
	call_deferred("refresh")


func _drop_into_mule(data: Dictionary, dest_anchor: Vector2i) -> void:
	var id: String = data["id"]
	var src: Dictionary = data["src"]
	if src.get("anchor") == dest_anchor:
		return   # 原地放下，无操作
	var mule: Dictionary = RunManager.mule_grid
	var ignore = src.get("anchor")

	var merge_anchor = Backpack.merge_target(mule, id, dest_anchor, ignore)
	if merge_anchor != null:
		mule.erase(ignore)
		mule[merge_anchor] = Backpack.merge_result(id)
		return

	if not Backpack.can_place(mule, id, dest_anchor, ignore, Backpack.MULE_GRID_W, Backpack.MULE_GRID_H):
		return
	mule.erase(ignore)
	mule[dest_anchor] = id


## 驮兽格目标能否接收该物品（BagGridView 算落点幽灵 + 校验用）。
func mule_can_drop(id: String, src: Dictionary, anchor: Vector2i) -> bool:
	var mule: Dictionary = RunManager.mule_grid
	var ignore = src.get("anchor")
	if Backpack.merge_target(mule, id, anchor, ignore) != null:
		return true
	return Backpack.can_place(mule, id, anchor, ignore, Backpack.MULE_GRID_W, Backpack.MULE_GRID_H)
