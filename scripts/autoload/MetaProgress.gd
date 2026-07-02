extends Node

# ─────────────────────────────────────────────────────────────────────────────
# MetaProgress — 局外/跨局成长（autoload）
#
# 解决"局间 meta 解锁"：把部分职业/物品锁在"存档历史最深打到过第几层"背后，
# 解锁后永久对所有后续局生效。**只解锁内容/多样性，绝不提升数值**——解锁不让
# 任何一局比另一局更强，只让"能拼的组合"更多（METHODOLOGY §2：真抉择三要素）。
#
# 跟 RunManager 是两层不同的状态：
#   RunManager   = 一局跑局的内存态，局结束就丢
#   MetaProgress = 跨局持久态，存到 user://，游戏重启也在
# 不碰 R7（跑局中途存档）技术债——这里只存一小份 String id 列表 + 一个 int，
# 不涉及 Hero 对象引用/Vector2i 键那些不好序列化的东西，是完全独立的小存档。
#
# 解锁触发：历史最深层数（best_layer_ever，任意一局打到过就永久算数，哪怕那局后来输了）。
# 加新解锁项 = META_UNLOCKS 加一行，不用改逻辑。
# ─────────────────────────────────────────────────────────────────────────────

const SAVE_PATH := "user://meta_progress.json"

# 解锁表：id -> 门槛层数。不在表里的 id = 默认解锁（不用挨个声明"哪些永远开放"，
# 跟 min_layer 的"缺省 0"是同一个"默认开放，只对特例加门槛"哲学）。
# type 仅供 UI 分类显示（"class"/"item"），解锁逻辑上一视同仁。
# 2026-07：地图 9→45 层后按比例重标定（约 ×4~5，取整），铺满全程而不是全挤在前9层。
const META_UNLOCKS: Dictionary = {
	"rogue":         { "type": "class", "layer": 25, "name": "盗贼" },
	"archer":        { "type": "class", "layer": 35, "name": "猎人" },
	"book_cleave":   { "type": "item",  "layer": 8,  "name": "横扫书" },
	"book_taunt":    { "type": "item",  "layer": 12, "name": "挑衅书" },
	"book_icelance": { "type": "item",  "layer": 12, "name": "冰枪书" },
	"book_purify":   { "type": "item",  "layer": 16, "name": "净化书" },
	"crit_gem":      { "type": "item",  "layer": 22, "name": "暴击宝石" },
	"berserk_ring":  { "type": "item",  "layer": 28, "name": "狂战戒" },
	"shadow_mantle": { "type": "item",  "layer": 28, "name": "暗影披风" },
	"iron_standard": { "type": "item",  "layer": 34, "name": "铁壁旗" },
	"decoy_mask":    { "type": "item",  "layer": 40, "name": "诱敌面具" },
}

var unlocked: Dictionary = {}     # id -> true（已解锁的 id 集合，Dictionary 当 Set 用）
var best_layer_ever: int = -1     # -1 = 从没跑过局

# 解锁时是否立即落盘。真实游戏恒 true（防崩溃丢解锁）；GUT 测试全程共享这个 autoload
# 单例、且默认路径就是真实存档路径——测试若不关掉这个开关，会把测试数据写进玩家真实存档。
# 测试文件请在 before_each() 里设 false（GUT 结束后不用管，进程本来就要退出）。
var autosave: bool = true


func _ready() -> void:
	load_progress()


## 该 id 是否可用：不在 META_UNLOCKS 里 = 默认解锁；在表里则要 unlocked 里有它。
func is_unlocked(id: String) -> bool:
	if not META_UNLOCKS.has(id):
		return true
	return unlocked.has(id)


## 记录本局走到的层数；若刷新历史最深纪录，检查并解锁新达标项，返回本次新解锁的 id 列表。
## 调用方（RunManager）在每次前进节点时调用；未刷新纪录时是无操作（早退，省重复扫表）。
func record_layer(layer: int) -> Array:
	if layer <= best_layer_ever:
		return []
	best_layer_ever = layer
	var newly: Array = []
	for id in META_UNLOCKS:
		if unlocked.has(id):
			continue
		if int(META_UNLOCKS[id]["layer"]) <= best_layer_ever:
			unlocked[id] = true
			newly.append(id)
	if not newly.is_empty() and autosave:
		save_progress()
	return newly


## 尚未解锁的项，按门槛升序（UI 剧透用："？？？·再打深 X 层解锁"）。
func locked_summary() -> Array:
	var out: Array = []
	for id in META_UNLOCKS:
		if unlocked.has(id):
			continue
		var def: Dictionary = META_UNLOCKS[id]
		out.append({ "id": id, "type": def["type"], "name": def["name"], "layer": int(def["layer"]) })
	out.sort_custom(func(a, b): return a["layer"] < b["layer"])
	return out


## 测试/新档用：清空到初始状态（不落盘，调用方自行决定要不要 save）。
func reset() -> void:
	unlocked = {}
	best_layer_ever = -1


# ── 存读档（user://，与 res:// 项目文件分开；纯 String/int，不碰 R7 那些难序列化的东西）──

func save_progress(path: String = SAVE_PATH) -> void:
	var data := { "unlocked": unlocked.keys(), "best_layer_ever": best_layer_ever }
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("MetaProgress: 存档写入失败 '%s'" % path)
		return
	f.store_string(JSON.stringify(data))
	f.close()

func load_progress(path: String = SAVE_PATH) -> void:
	if not FileAccess.file_exists(path):
		return   # 首次运行，无存档 → 保持初始空状态
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or not (parsed is Dictionary):
		return
	unlocked = {}
	for id in parsed.get("unlocked", []):
		unlocked[String(id)] = true
	best_layer_ever = int(parsed.get("best_layer_ever", -1))
