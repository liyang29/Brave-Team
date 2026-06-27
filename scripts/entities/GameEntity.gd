class_name GameEntity extends Resource

# ─────────────────────────────────────────────────────────────────────────────
# GameEntity — 所有游戏实体的基类
#
# 继承关系：GameEntity → Combatant → Hero/Enemy
#                      → Item     → Equipment/Consumable
#                      → Facility
#
# 为什么继承 Resource？
#   Resource 是 Godot 的纯数据容器，可以序列化（存档）、可以复制，
#   不占用场景树，非常适合"英雄数据""物品数据"这类纯数据对象。
# ─────────────────────────────────────────────────────────────────────────────


# ── 字段 ──────────────────────────────────────────────────────────────────────

# 模板 ID：标识"这是什么类型的东西"，手动在数据文件里定义
# 同类型的对象共享同一个 template_id，例如所有铁剑都是 "iron_sword"
# @export 让这个字段在 Godot 编辑器 Inspector 面板里可见、可编辑
@export var template_id: String = ""

# 实例 ID：标识"这是哪一个具体的对象"，创建时自动生成
# 两把铁剑的 template_id 相同，但 instance_id 各不相同
# 没有 @export，因为不需要在编辑器里手动设置
var instance_id: String = ""

# 显示名称：在界面上展示给玩家看的文字
@export var entity_name: String = ""

# 描述：物品说明、英雄背景故事等，可以为空
@export var description: String = ""


# ── 初始化 ────────────────────────────────────────────────────────────────────

# _init 是 GDScript 的构造函数，对象被创建时自动调用一次
func _init() -> void:
	# 只在 instance_id 为空时生成，避免从存档恢复时覆盖已有的 ID
	if instance_id.is_empty():
		instance_id = _generate_instance_id()


# ── 私有方法 ──────────────────────────────────────────────────────────────────

# 生成实例 ID：时间戳（毫秒）+ 随机整数，冲突概率极低
# 前缀 _ 是 GDScript 约定，表示"内部使用，外部不要直接调用"
func _generate_instance_id() -> String:
	return "%d_%d" % [Time.get_ticks_msec(), randi()]


# ── 公共方法 ──────────────────────────────────────────────────────────────────

# to_dict：把对象的字段打包成字典，供存档系统写入 JSON 文件
# 子类应该 override 这个方法，先调用 super.to_dict() 获取基础字典，
# 再往里加自己特有的字段
func to_dict() -> Dictionary:
	return {
		"template_id": template_id,
		"instance_id": instance_id,
		"entity_name": entity_name,
		"description": description,
	}

# from_dict：从字典恢复字段，供读档系统使用
# 子类同样应该 override，先调用 super.from_dict(data)，再读取自己的字段
func from_dict(data: Dictionary) -> void:
	template_id  = data.get("template_id",  "")
	instance_id  = data.get("instance_id",  "")
	entity_name  = data.get("entity_name",  "")
	description  = data.get("description",  "")

# duplicate_instance：复制一份相同类型的对象，但生成全新的 instance_id
# 使用场景：玩家捡到第二把铁剑，需要创建一个新的物品实例
# Godot 内置的 .duplicate() 会复制 instance_id，我们不想要那个行为
func duplicate_instance() -> GameEntity:
	# duplicate() 是 Resource 的内置方法，做浅拷贝
	var copy := duplicate() as GameEntity
	# 覆盖掉复制来的 instance_id，生成全新的
	copy.instance_id = _generate_instance_id()
	return copy
