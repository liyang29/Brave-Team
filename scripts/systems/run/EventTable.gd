extends RefCounted

# ─────────────────────────────────────────────────────────────────────────────
# EventTable — 事件节点数据表（事件编排的唯一数据源）
#
# 加事件 = 往 EVENTS 加一条（同 SkillTable/MonsterFactory 路子）。事件本体是常量、
# 不进存档；存档只存"当前哪个事件 / 遇过哪些"这几个 String id（见 RunManager）。
#
# ── schema ───────────────────────────────────────────────────────────────────
# event = { title, desc, choices: Array[choice] }
# choice = {
#   label   : String
#   require : { 可选门槛 }   —— 不满足则选项灰掉不可选
#             支持: "gold": int(队伍金≥N) / "item": id(库存或任一背包里有) / "class": str(队里有该职业)
#   # 结果二选一：确定 or 概率
#   effects : Array[effect]            确定结果（直接应用）
#   result  : String(可选)             确定结果的提示文案
#   risk    : { "chance": float, "win": Array[effect], "lose": Array[effect] }   概率结果
#   result_win / result_lose : String(可选)   概率两支的文案
# }
# effect（精简 3 种；升级留口 = RunManager._apply_event_effect 加 type 分支即可）:
#   { "type": "gold",   "amount": int }               金币 ±（钳到 ≥0）
#   { "type": "item",   "id": String, "count": int=1 } 给物品进库存
#   { "type": "hp_pct", "amount": float }              全队存活者按最大血 ±（负=扣血，钳 ≥1 不猝死）
# ─────────────────────────────────────────────────────────────────────────────

const EVENTS: Dictionary = {

	"roadside_purse": {
		"title": "路旁钱袋",
		"desc": "路边草丛里露出一角鼓鼓的钱袋，四下无人。",
		"choices": [
			{ "label": "拾起钱袋", "effects": [ { "type": "gold", "amount": 40 } ],
			  "result": "袋里是 40 枚金币，运气不错。" },
			{ "label": "绕道而行（怕是诱饵）", "effects": [] },
		],
	},

	"mysterious_merchant": {
		"title": "神秘商人",
		"desc": "裹着斗篷的商人递来一件皮甲：“免费的，交个朋友。”",
		"choices": [
			{ "label": "收下赠礼", "effects": [ { "type": "item", "id": "leather" } ],
			  "result": "得到一件皮甲（进库存）。" },
			{ "label": "婉言谢绝", "effects": [] },
		],
	},

	"gamblers_dice": {
		"title": "赌徒的骰子",
		"desc": "赌徒晃着骰子：“押 50 金，赢了翻倍还有赚。”",
		"choices": [
			{ "label": "押注 50 金（有风险）", "require": { "gold": 50 },
			  "risk": { "chance": 0.5,
					"win":  [ { "type": "gold", "amount": 100 } ],
					"lose": [ { "type": "gold", "amount": -50 } ] },
			  "result_win": "骰子停在六点——净赚 100 金！",
			  "result_lose": "一点。50 金打了水漂。" },
			{ "label": "不玩这套", "effects": [] },
		],
	},

	"abandoned_camp": {
		"title": "废弃营地",
		"desc": "一处还有余温的废弃营地，散着些补给。",
		"choices": [
			{ "label": "就地休整（全队回血）", "effects": [ { "type": "hp_pct", "amount": 0.30 } ],
			  "result": "队伍好好歇了一口气。" },
			{ "label": "翻找补给（+金，惊动野兽受伤）",
			  "effects": [ { "type": "gold", "amount": 35 }, { "type": "hp_pct", "amount": -0.10 } ],
			  "result": "搜到些金币，但招来野兽咬了几口。" },
		],
	},

	"wounded_traveler": {
		"title": "受伤的旅人",
		"desc": "一名旅人倒在路边，伤势不轻，虚弱地求助。",
		"choices": [
			{ "label": "让牧师医治他（需牧师）", "require": { "class": "priest" },
			  "effects": [ { "type": "gold", "amount": 40 }, { "type": "item", "id": "amulet" } ],
			  "result": "旅人痊愈，回赠金币与一枚护符。" },
			{ "label": "分些金币给他", "effects": [ { "type": "gold", "amount": -20 } ],
			  "result": "你留下些盘缠，旅人千恩万谢。" },
			{ "label": "无视，继续赶路", "effects": [] },
		],
	},

	"ancient_altar": {
		"title": "古老祭坛",
		"desc": "斑驳的祭坛刻着一行字：“以财换运”。",
		"choices": [
			{ "label": "献上 50 金（有风险）", "require": { "gold": 50 },
			  "risk": { "chance": 0.4,
					"win":  [ { "type": "gold", "amount": -50 }, { "type": "item", "id": "crit_gem" } ],
					"lose": [ { "type": "gold", "amount": -50 } ] },
			  "result_win": "祭坛亮起，落下一枚暴击宝石！",
			  "result_lose": "金币化作尘埃，什么也没留下。" },
			{ "label": "不理会", "effects": [] },
		],
	},

	"trap_chest": {
		"title": "陷阱宝箱",
		"desc": "一只落灰的宝箱，锁孔透着可疑的绿光。",
		"choices": [
			{ "label": "强行撬开（有风险）",
			  "risk": { "chance": 0.6,
					"win":  [ { "type": "item", "id": "chainmail" } ],
					"lose": [ { "type": "hp_pct", "amount": -0.15 } ] },
			  "result_win": "咔哒——箱里是一件锁甲！",
			  "result_lose": "暗针弹出，全队中招。" },
			{ "label": "不碰为妙", "effects": [] },
		],
	},

	"blacksmith_relic": {
		"title": "铁匠遗物",
		"desc": "废弃的铁匠铺里，一台磨具竟还能用。",
		"choices": [
			{ "label": "磨砺你的铁剑（需铁剑）", "require": { "item": "iron_sword" },
			  "effects": [ { "type": "item", "id": "whetstone" } ],
			  "result": "得到一块磨刀石（与刀刃相邻可开刃）。" },
			{ "label": "搜刮些废料", "effects": [ { "type": "gold", "amount": 20 } ],
			  "result": "捡到些能卖钱的废铁。" },
		],
	},
}


## 取事件数据（未知 id → 空）。
static func get_event(id: String) -> Dictionary:
	return EVENTS.get(id, {})

## 所有事件 id。
static func all_ids() -> Array:
	return EVENTS.keys()
