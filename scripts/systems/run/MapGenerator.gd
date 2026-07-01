extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# MapGenerator — 尖塔式分层 DAG 随机地图生成（纯静态；吃 MapConfig）
#
# 产出：{ "nodes": {id: 节点dict}, "start_id": String, "layers": int, "seed": int }
#   节点dict = { id, layer, col, type, name, enemies:Array[EnemyData], gold:int, next:Array[String] }
#     next = 后继节点 id 列表（有向边）→ "严格连线约束"：在某节点只能去它 next 里的节点。
#
# 生成流程（保证连通 + 无死路）：
#   1. 固定锚点：第 0 层单村庄（唯一起点）、L-2 层单泉水（决战前泄压）、L-1 层单魔王（唯一汇点）。
#   2. 铺 config.paths 条随机路径，从村庄逐层爬到魔王（列 ±1 抖动），沿途建节点连边、重复节点合并。
#      → 每个中间节点都在某条到魔王的路径上，天然连通、无死路。
#   3. 给中间层节点定类型（按权重 + min_layer/min_gap/weight_per_layer 约束；只用已注册类型）。
#   4. 填内容（怪组/名字/金币）。
#
# 故意不带 class_name（preload 引入），同 MapConfig/NodeTypes 路子。
# ─────────────────────────────────────────────────────────────────────────────

const MapConfig = preload("res://scripts/systems/run/MapConfig.gd")
const NodeTypes = preload("res://scripts/systems/run/NodeTypes.gd")


## 生成一张地图。seed<0 = 随机种子（并回填到结果，便于复现/存档）。
static func generate(config: Dictionary = MapConfig.DEFAULT, seed: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	var used_seed: int
	if seed < 0:
		rng.randomize()
		used_seed = int(rng.seed)
	else:
		rng.seed = seed
		used_seed = seed

	var L: int = max(3, int(config.get("layers", 9)))
	var W: int = max(1, int(config.get("max_width", 4)))
	var fixed: Dictionary = config.get("fixed", {})
	var nodes: Dictionary = {}

	# 1. 固定锚点
	var start_id := _make(nodes, 0, 0, String(fixed.get("first", "village")))
	_make(nodes, L - 2, 0, String(fixed.get("pre_boss", "rest")))   # 魔王前一层：泉水（funnel）
	_make(nodes, L - 1, 0, String(fixed.get("last", "boss")))       # 末层：魔王（唯一汇点）

	# 2. 铺路径
	var paths: int = max(1, int(config.get("paths", 6)))
	for p in range(paths):
		var prev_id := start_id
		var prev_col := 0
		for layer in range(1, L):
			var col := 0
			if layer < L - 2:                       # L-2/L-1 是单节点 funnel（col 恒 0）
				col = clampi(prev_col + rng.randi_range(-1, 1), 0, W - 1)
			var id := _node_id(layer, col)
			if not nodes.has(id):
				_make(nodes, layer, col, "")        # 中间层类型待定（第 3 步定）
			_link(nodes, prev_id, id)
			prev_id = id
			prev_col = col

	# 3. 定类型 + 4. 填内容
	_assign_types(nodes, config, rng)
	for id in nodes:
		_fill_content(nodes[id], config, rng)

	return { "nodes": nodes, "start_id": start_id, "layers": L, "seed": used_seed }


# ── 类型分配 ─────────────────────────────────────────────────────────────────

# 给所有"待定类型"的中间节点定类型。按层升序处理，min_gap 用"最近放置层"跟踪。
static func _assign_types(nodes: Dictionary, config: Dictionary, rng: RandomNumberGenerator) -> void:
	var type_cfg: Dictionary = config.get("types", {})
	# 只用"已在 NodeTypes 注册"的类型 → event 未注册前不会出现，无需改生成器。
	var spawnable: Array = []
	for t in type_cfg.keys():
		if NodeTypes.REGISTRY.has(t):
			spawnable.append(t)

	var ids: Array = nodes.keys()
	ids.sort_custom(func(a, b): return int(nodes[a]["layer"]) < int(nodes[b]["layer"]))

	var last_layer: Dictionary = {}   # type -> 最近放置的 layer（含固定锚点，让 min_gap 也躲开锚点）
	for id in ids:
		var n: Dictionary = nodes[id]
		if String(n["type"]) != "":
			last_layer[n["type"]] = int(n["layer"])
			continue
		var chosen := _weighted_type(spawnable, type_cfg, int(n["layer"]), last_layer, rng)
		n["type"] = chosen
		last_layer[chosen] = int(n["layer"])


# 按权重 + 约束在 spawnable 里挑一个类型。约束把所有类型排除时兜底 battle。
static func _weighted_type(spawnable: Array, type_cfg: Dictionary, layer: int,
		last_layer: Dictionary, rng: RandomNumberGenerator) -> String:
	var cand: Array = []
	var weights: Array = []
	for t in spawnable:
		var c: Dictionary = type_cfg[t]
		var min_layer: int = int(c.get("min_layer", 0))
		if layer < min_layer:
			continue
		var gap: int = int(c.get("min_gap", 0))
		if gap > 0 and last_layer.has(t) and (layer - int(last_layer[t])) < gap:
			continue
		var w: int = int(c.get("weight", 1)) + int(c.get("weight_per_layer", 0)) * (layer - min_layer)
		if w <= 0:
			continue
		cand.append(t)
		weights.append(w)
	if cand.is_empty():
		return "battle"

	var total: int = 0
	for w in weights:
		total += w
	var roll: int = rng.randi_range(0, total - 1)
	for i in range(cand.size()):
		roll -= weights[i]
		if roll < 0:
			return cand[i]
	return cand[cand.size() - 1]


# ── 内容填充 ─────────────────────────────────────────────────────────────────

static func _fill_content(n: Dictionary, config: Dictionary, rng: RandomNumberGenerator) -> void:
	var t: String = n["type"]
	var names: Dictionary = config.get("names", {})
	var gold: Dictionary = config.get("gold", {})
	match t:
		"village":
			n["name"] = "营地" if int(n["layer"]) == 0 else _pick_name(names, "village", rng, "村镇")
		"rest":
			n["name"] = _pick_name(names, "rest", rng, "泉水")
		"event":
			n["name"] = _pick_name(names, "event", rng, "事件")
		"boss":
			n["name"] = String(names.get("boss", "魔王城"))
			n["enemies"] = MonsterFactory.create_group(config.get("boss_group", []))
			n["gold"] = int(gold.get("boss", 100))
		"elite":
			n["name"] = _pick_name(names, "elite", rng, "精英战")
			n["enemies"] = MonsterFactory.create_group(_pick(config.get("elite_groups", []), rng))
			n["gold"] = int(gold.get("elite", 45))
		_:  # battle（含未知类型兜底）
			n["name"] = _pick_name(names, "battle", rng, "遭遇")
			n["enemies"] = MonsterFactory.create_group(_pick(config.get("battle_groups", []), rng))
			n["gold"] = int(gold.get("battle", 20))


# ── 小工具 ───────────────────────────────────────────────────────────────────

static func _node_id(layer: int, col: int) -> String:
	return "L%dC%d" % [layer, col]

static func _make(nodes: Dictionary, layer: int, col: int, type: String) -> String:
	var id := _node_id(layer, col)
	nodes[id] = {
		"id": id, "layer": layer, "col": col, "type": type,
		"name": "", "enemies": [], "gold": 0, "next": [],
	}
	return id

static func _link(nodes: Dictionary, from_id: String, to_id: String) -> void:
	if from_id == to_id:
		return
	var nx: Array = nodes[from_id]["next"]
	if not (to_id in nx):
		nx.append(to_id)

static func _pick(arr: Array, rng: RandomNumberGenerator):
	if arr.is_empty():
		return []
	return arr[rng.randi_range(0, arr.size() - 1)]

static func _pick_name(names: Dictionary, key: String, rng: RandomNumberGenerator, fallback: String) -> String:
	var pool = names.get(key, [])
	if pool is Array and not pool.is_empty():
		return String(pool[rng.randi_range(0, pool.size() - 1)])
	return fallback
