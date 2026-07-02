# 装备 / 掉落 调参手册

> 纯参考文档，不影响代码运行。你以后想调"背包深度曲线"（开局白装为主、走深了才见到更强/更多装备），
> 照这份改数据即可，不用碰逻辑代码。改完用文末命令跑测试验证没弄崩。
>
> 涉及三个独立系统：**色阶合成**（玩家自己把白装合成更强）、**深度门控**（某些物品早于某层不出现）、
> **深度掉落曲线**（走得越深，普通装备越可能直接掉出预合成好的绿/蓝）。三者互不冲突，可以自由组合。

---

## 1. 物品本体 —— `scripts/systems/backpack/BackpackModel.gd`

### 1.1 `ITEMS` 字典：每件装备一行

| 字段 | 作用 | 例子 |
|---|---|---|
| `"name"` | 中文显示名 | `"铁剑"` |
| `"atk"/"def"/"hp"/"magic"/"mp"` | 基础数值（缺省 0）| `"atk": 6` |
| `"tag"` | 协同标签（`SYNERGIES` 表按 tag 配对触发加成）| `"blade"` |
| `"shape"` | 占几格（缺省 `1x1`；可选 `1x2v`/`1x2h`/`1x3v`/`1x3h`/`2x2`，见 `SHAPES`）| `"1x2v"` |
| `"rarity"` | 掉落权重/售价档：`common`/`rare`/`epic` | `"rare"` |
| `"mergeable": true` | **纯数值装备专属**——参与色阶合成链，起手掉落恒为白，玩家自己合成变强 | 剑/甲/杖类 |
| `"fixed_tier": N` | **机制类物品专属**（光环/暴击/闪避/嘲讽件）——掉落即固定这个色阶，不参与合成 | `0`=白 … `5`=红 |
| `"min_layer": N` | 深度门控——早于这层不会掉落/不会在商店出现（缺省 0 = 起手就能遇到）| `3` |

⚠️ `mergeable` 与 `fixed_tier` **互斥**：一件物品只走其中一条路，不要同时写两个。

**加一件新装备** = 照抄一行改数值：
```gdscript
"你的id": { "name": "中文名", "atk": 10, "tag": "blade", "shape": "1x2v",
            "rarity": "rare", "mergeable": true, "min_layer": 5 },
```

### 1.2 色阶系统常量（同文件顶部，一般不用改）

```gdscript
const TIER_NAMES: Array = ["白", "绿", "蓝", "紫", "橙", "红"]
const TIER_MAX := 5                          # 红=顶级，合成的封顶
const TIER_COLORS: Array = [...]             # 背包里六档的背景色
const SCALABLE_KEYS: Array = ["atk","def","hp","magic","mp"]   # 只有这几项数值吃色阶倍率(×2^tier)
```
副属性（crit_chance/dodge_chance/taunt）和光环**不吃色阶倍率**，避免百分比属性被合成到离谱数值。

---

## 2. 掉落规则 —— `scripts/systems/LootTable.gd`

| 常量 | 作用 | 当前值 |
|---|---|---|
| `RARITY_WEIGHTS` | 三档稀有度的抽取权重（越大越常出）| `common 65 / rare 27 / epic 8` |
| `RARITY_PRICES` | 三档稀有度对应商店售价 | `50 / 120 / 250` |
| `TIER_WEIGHTS_BY_LAYER` | **深度掉落色阶曲线**——普通装备掉落时按层数掷一个色阶 | 见下 |

### 2.1 `TIER_WEIGHTS_BY_LAYER`：深度掉落色阶曲线

```gdscript
const TIER_WEIGHTS_BY_LAYER: Array = [
    { "max_layer": 10,  "weights": { 0: 100 } },                    # 层0-10：恒白
    { "max_layer": 25,  "weights": { 0: 82, 1: 16, 2: 2 } },        # 层11-25：偶见绿，罕见蓝
    { "max_layer": 999, "weights": { 0: 60, 1: 25, 2: 12, 3: 3 } }, # 层26+：绿蓝常见，罕见紫
]
```

- 结构：数组按顺序取**第一个 `max_layer` ≥ 当前层**的那档。
- `weights` 的 key = 色阶索引（0白/1绿/2蓝/3紫/4橙/5红），value = 权重，占比 = 该值 ÷ 本档权重总和。
- 想调"多快开始见到预合成装备" → 改 `max_layer` 分界点。
- 想调"概率大小" → 改各档 `weights` 里的数字。
- ⚠️ **不要在任何一档写 `4` 或 `5`**（橙/红）——这两档故意只留给玩家自己合成（16/32 把同款），
  保住"凑齐红装"的成就感。写了会被 `test_tier_weights_by_layer_never_exceed_cap` 测试拦下来提醒你。

只对 `mergeable` 物品生效；`fixed_tier` 物品固定用自己的档，不吃这条曲线。

---

## 3. 三条轴的关系（容易搞混）

| 轴 | 决定什么 | 配置在哪 | 影响谁 |
|---|---|---|---|
| `rarity` | 这个**物品类型**好不好找、多贵 | `ITEMS` 每行 | 所有物品 |
| `min_layer` | 这个**物品类型**最早第几层出现 | `ITEMS` 每行 | 所有物品 |
| `TIER_WEIGHTS_BY_LAYER` | 掉落这个物品时，**这一件**是白是绿是蓝 | `LootTable.gd` | 仅 `mergeable` 物品 |

三者互相独立、自由组合：一件 `rarity:rare, min_layer:3` 的精钢剑，在第 20 层被抽中时，还会再按
`TIER_WEIGHTS_BY_LAYER` 掷一次色阶，决定它这一件是白是绿是蓝。

---

## 4. 装备 × 层数 对照表（当前数据快照）

> 这不是代码里真实存在的一张表——是把 `ITEMS` 里所有 `min_layer` 扫一遍拼出来的。改了 `ITEMS` 数据，
> 这张表就该跟着过期，回来手动更新（或直接照 §1.1 的字段自己去 `ITEMS` 里查）。

> 2026-07-02 起地图拉长到 45 层（塞 3 个中程 Boss），下表门槛已按比例重标定（约 ×5）。

| 最早出现层 | 装备 | 类型 |
|---|---|---|
| **0（起手）** | 铁剑、长剑、磨刀石、圆盾、锁甲、皮甲、法杖、魔典、圣徽、护符、红宝石、法力护符 | 普通装备（合成链）|
| **0（起手）** | 斩击书、横扫书、挑衅书、火球书、冰枪书、治疗书、净化书 | 技能书（不参与色阶系统）|
| **5** | 锋锐之刃 | 绿（固定色阶）|
| **10** | 军旗、疾风图腾、先锋号角、守护图腾、疾风斗篷、挑衅护符 | 蓝（固定色阶）|
| **15** | 精钢剑、秘银法杖、圣光锤 | 后期新装备（合成链）|
| **20** | 暴击宝石、狂战戒、暗影披风 | 紫（固定色阶）|
| **25** | 铁壁旗、诱敌面具 | 橙（固定色阶）|
| **30** | 巨龙鳞甲 | 后期新装备（合成链，epic）|

---

## 5. 改完怎么验证

```powershell
& $env:GODOT_PATH --path "D:\program\gameDev\Brave Team" --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_item_tiers.gd -gexit
```

这份测试覆盖：色阶数值缩放、合成规则、掉落分流（mergeable 恒白 / fixed_tier 固定色 / 深度曲线）、
封顶紫色不被突破、深度门控生效、新物品字段正确。改完这份文档提到的任何常量/字段，先跑它。

若改动影响到整局难度曲线（比如让深度掉落曲线更"大方"），再跑一次平衡 harness 看数据：

```powershell
& $env:GODOT_PATH --path "D:\program\gameDev\Brave Team" --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_balance.gd -gexit
```
