extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# NodeTypes — 节点类型注册表（单一真相源）
#
# 加一种地图节点类型 = 在 REGISTRY 里加一行（同时给出"进哪个状态""路由哪个场景"），
# 不用再分别改 RunManager.enter_current_node 和 RunMap 两处 match —— 漏改即 bug。
#
#   scene    : 该节点对应的场景（RunMap 路由用）
#   state    : 进入时 RunManager 切到的状态【枚举名字符串】（RunManager 用 State[name] 转枚举）
#   on_enter : 可选，进入前 RunManager 上要调的准备方法名（如村庄上货/招募）；无则省略
#
# 故意不带 class_name（preload 引入），与 LootTable/BackpackModel 同路，避免全局类缓存时序问题。
# ─────────────────────────────────────────────────────────────────────────────

const SCENE_ENCOUNTER := "res://scenes/run/Encounter.tscn"
const SCENE_VILLAGE   := "res://scenes/run/Village.tscn"
const SCENE_REST      := "res://scenes/run/Rest.tscn"
const SCENE_EVENT     := "res://scenes/run/Event.tscn"

const REGISTRY: Dictionary = {
	"battle":  { "scene": SCENE_ENCOUNTER, "state": "ENCOUNTER" },
	"elite":   { "scene": SCENE_ENCOUNTER, "state": "ENCOUNTER" },   # 精英：复用战斗管道，敌人更强/金币更多
	"boss":    { "scene": SCENE_ENCOUNTER, "state": "ENCOUNTER" },
	"village": { "scene": SCENE_VILLAGE,   "state": "VILLAGE", "on_enter": "_enter_village" },
	"rest":    { "scene": SCENE_REST,      "state": "REST" },
	"event":   { "scene": SCENE_EVENT,     "state": "EVENT", "on_enter": "_enter_event" },
}

# 未注册类型的兜底（当作普通战斗遭遇，避免崩溃）。
const DEFAULT: Dictionary = { "scene": SCENE_ENCOUNTER, "state": "ENCOUNTER" }

## 取某节点类型的定义（未注册 → DEFAULT）。
static func get_def(node_type: String) -> Dictionary:
	return REGISTRY.get(node_type, DEFAULT)

## 该节点类型该路由到的场景（RunMap 用）。
static func scene_for(node_type: String) -> String:
	return get_def(node_type).get("scene", SCENE_ENCOUNTER)
