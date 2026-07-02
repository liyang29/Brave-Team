# 进度 / 任务完成情况

> 源文档见 `ROGUELIKE_DESIGN.md`。本文件只记"做到哪了 / 接下来做什么"。

## ✅ 已完成（从 Brave Guild 迁入的核心）

战斗与背包核心已在 Brave Guild 验证 + 测试通过，整块迁入本项目：

- **战斗引擎**：`BattleSimulator`（回合制自动结算）+ `BattleCombatant` + 各职业/敌人 `CombatStrategy` + `SkillTable`。
- **背包构筑**（`BackpackModel` + `BackpackExperiment`）：网格背包、物品占格、**邻接协同**（开刃/重装/共鸣/生机）。验证：巧搭 20/20 胜、乱搭 0/20。
- **技能书**：技能 = 占格背包物品，**认职业 + 回合冷却**（和装备抢空间）。
- **站位**：世界树式**软调整**（`Party.positioning_mode="soft_row"`）——后排近战输出×0.5、后排受物理伤×0.7、魔法/远程不受影响；前排至少留1人、前排全灭后排顶上。另有硬触及模式 `"reach"`（Grid/Position 实验用）。
- **副属性地基**：`BattleCombatant.extra_stats` 字典 + `BackpackModel.EXTRA_KEYS`。首个副属性 = **暴击**（crit_chance/crit_dmg）。加新 A 档属性≈改数据。
- **三个实验场景**：BackpackExperiment（主，软站位+背包+技能书+暴击）、GridExperiment（网格站位+逐列掩护）、PositionExperiment（2排站位）。
- **测试**：GUT 4 个文件（battle_simulator / backpack_experiment / position_experiment / grid_experiment）。

## ⬜ 预留到后期（已讨论，暂不做）

- **AI 选目标考虑站位**（治本）：`choose_target` 按"有效伤害=基础×站位倍率"选，避免前排去捅打折后排、战士分散打两个肉盾等"瞎打"。
- **玩家目标优先级策略按钮**（安全阀）：集火残血 / 点后排威胁 / 打高攻 / 各自本能。战前设、自动执行；保持轻量，别做成 FF12 Gambit。先治本 AI 再视情加。
- **敌方 spellcaster 名副其实**：`enemy_spell` 目前是占位（不在 SkillTable → 回退普攻）；给它配真魔法技能（use_magic）。
- 站位"前→后排"数值：当前 ×0.7（两修正叠乘）；世界树原版 ×0.5（满伤仅前→前）。待玩后定。
- 公共驮兽（共享后勤背包，战斗中不可掏、有代价）、负重、金币经济、更多副属性（法抗/吸血/破甲…见 stats 目录）、技能书参与邻接协同。

## 🎯 roguelike 跑局骨架

- [x] **入口 TitleScreen**（开始冒险/实验/退出）
- [x] **RunManager**（autoload）：状态机 + 队伍 + 金币 + 节点进度 + start/enter/resolve
- [x] **RunMap**：线性节点路径（3 战斗 + 1 魔王）+ 进度/队伍状态 + 胜利/失败横幅
- [x] **Encounter**：敌人/队伍预览 → 开战(BattleSimulator 软站位) → 结果 → 回报
- [x] **闭环跑通**：标题→地图→遭遇→回地图→魔王（通关/全灭）；HP 跨节点保留(消耗战)
- [x] **把背包构筑接成"遭遇前 prep 界面"**（Step 1-3 完成）：`BackpackLoadout`(背包→Party 翻译，幂等+钳血) + RunManager 名册/库存/站位状态 + 共享 `BackpackPrepPanel`，已接进 Encounter——"开始冒险"开战前可搭背包/摆站位。**编辑改为拖放**（`DragSlot` 原生拖放：库存↔背包↔背包互拖、站位互拖；公共装备栏=带数量角标的格子）。（详见 `docs/TODO_BACKPACK_PREP.md`）
- [x] **战利品 draft（Step 4 完成）**：胜利后三选二掉落（rarity 加权，`LootTable`+`Draft` 场景），留下进库存；魔王胜直接通关。已删 debug 起手种子（库存空、纯靠掉落）。
- [x] **村庄（节点类型 `village`＝商店＋招募＋队伍列表，一屏）**：起步金币 500；商店按 rarity 上货 6 件(50/120/250 只买不卖) + 招募(3 候选/120 金/人) + 我的队伍列表（`VillageScreen`+`Village` 场景，RunManager `VILLAGE` 状态/`buy_item`/`recruit`/`leave_village`）。**起手空队**，须在村庄招 **≥2 人**才能出发（`MIN_PARTY_TO_LEAVE`；harness 实测 1 人裸队打第一关 0/20、2 人 20/20——1 人是送死陷阱，已堵；含"招不动了放行"防卡死）；去掉"必须摆装备才能开战"限制。
- [x] **英雄池**：`HERO_TEMPLATES`（5 职业含盗贼/猎人，加英雄=加一行）；`STARTER_TEAM` 空（全靠招募）。
- [x] **降 base + 平衡（Step 5）**：裸 base 降到实验低值（战力靠背包）；`test_balance` harness 量化通关率，调到中等难度（好build稳赢 / 中庸有风险 / 烂build必败，魔王是协同门槛）。
- [x] **英雄选技改确定性 + 伤害浮动 + 重平衡**：英雄"可放就放"(蓝量/CD 节流，build 可读)，敌人 AI 保持随机；战斗加 ±10% 伤害浮动(确定性下胜率本是 0/100 → 浮动恢复梯度)；据此重调敌人数值(`MonsterFactory`)，harness 锁回 好 20/20 · 中庸 ~10/20 · 烂 0/20，并加断言锁住"中庸不稳通关"。**遗留**：好 build 仍 ~100%(英雄强于中庸差距大，纯数值下"好build也冒汗"需 Boss 机制 AOE/援军，非本轮)。
- [x] **英雄连招(中间档·背包乱斗式)**：一个英雄回合内按**背包读序**把所有"就绪+条件满足"的技能依次放掉(`_hero_combo_turn`)，技能替代普攻；摆放顺序=连招(`compute` 排序)；条件门走 `should_cast`(满血不空放治疗等)；敌人保持单动作。**遗留**：① ~~没压测多书连招~~ **已压测**（见下）② ~~英雄 `choose_skill` 冗余~~ **已删**（见下）。
- [x] **多书连招压测（平衡风险排查）**：加"多书连招"参考队（战士 斩击+横扫、法师 火球+冰枪+法力护符）进 harness（`test_multibook_combo_pressure`）。结论：**不是隐藏地雷**——胜率因"好 build 本就 100%"而看不出差距，换锐度尺子（魔王战回合/剩血）看：多书 4.0 回合·剩血 89% vs 单书 6.3 回合·剩血 76%，**更强但正比投入回报**（2 攻击书换 ~1.5× 输出，且 MP 自限首回合前重后轻）。多书的"碾压"与"好 build ~100%"是同一个根：**魔王太弱、顶级 build 无压力**。→ **不改连招数据**，真解法是 **Boss 机制**（AOE/援军，已在路线图）。留待后期设计问号：堆攻是否总最优、要不要给连招边际递减/软上限（等 build 轴变多再看）。
- [x] **普攻取攻/魔更高值 + 主动嘲讽技**：普攻用 `max(攻,魔)`——法师/牧师不因物理低而软（用魔力则按魔法、不吃站位减伤）；战士主动技 **挑衅怒吼**（挑衅书，`taunt_self`：临时拉仇 N 回合 + 立防）。普攻 buff 让法/牧续航涨 → 魔王补抬 `216/19 → 238/21`，harness 锁回 中庸 ~50%。
- [x] **泉水/休息回血点（Step 6）**：节点类型 `rest`（全员回 50% 最大血）；消耗战泄压阀。
- 地图：**村庄→林间→村镇→剧毒→泉水→废墟→魔王**（起手村庄组队 + 中段村镇补员/补给）。
- [x] **分支地图（杀戮尖塔式分层 DAG）**：`MapConfig`（唯一配置源：层数/宽度/密度/类型权重/内容池）+ `MapGenerator`（路径铺图，连通无死路，种子可复现）+ RunManager 图导航（`map_nodes`/`current_node_id`/`travel_to`，**严格连线约束**：选了这条就去不了那条；取代旧线性 `nodes`+`depth`）+ `MapGraphView`（尖塔式渲染：按列摆节点 + 画连接线 + 高亮可走路）。固定锚点：首层单村庄 / 魔王前一层泉水 / 末层单魔王。**精英节点 elite** 并入（复用战斗管道、金币更多）。配 GUT（`test_map_generator` 12 条属性 + `test_run_manager` 重写导航）；190/190 绿。（了结 R2 技术债，见 `ARCHITECTURE_RISKS.md`）
- [x] **空间填装背包（Backpack Battles 式形状 · 增量 1）**：背包升级为 **4×4（16 格）**，物品有**形状**（矩形集 1×1/1×2/1×3/2×2，具名表 `SHAPES` 配置，缺省 1×1 完全向后兼容）。grid 结构 = `{锚点: item_id}`（一条目=一实例），占用格 = 锚点+形状。数据层 `BackpackModel`：`GRID_W/H`、`item_cells`/`occupied_cells`/`can_place`（界内+不重叠），协同改**按物品实例**（任意格相邻触发一次）。重塑装备：锁甲2×2、长剑/法杖1×3竖、铁剑/皮甲/圆盾1×2竖。UI：自绘 `BagGridView`（4×4 网格 + 跨格渲染 + 拖拽落点**绿=可放/红=放不下**幽灵预览；放不下则拒绝、不交换）。配 GUT（`test_backpack_shapes` + prep 面板重写）；重跑 balance harness 梯度不变（好20/中10/烂0）。**固定朝向、不做旋转**（留增量 2）。**形状以后自己配**：改 `ITEMS` 里一行 `"shape"` 即可，加新形状=`SHAPES` 加一行。
  - **增量 2（留）**：旋转（grid 升级为放置列表含朝向）、异形/可解锁袋、L/T 形状、更多物品重塑、堆攻边际递减/软上限。
- [x] **物品色阶合成系统（背包深度延伸）**：物品实例分**六档色阶**（白/绿/蓝/紫/橙/红），与 `rarity`(掉落权重/售价) 是**两条独立轴**——rarity 决定"好不好找"、色阶决定"合成了几次"。**同基础同色阶 2 件 → 1 件高一阶**，数值严格 ×2（红=32把白的合成，`TIER_MAX=5`）。id 编码 `base_id@tier`（tier0 就是原 id，向后兼容，旧数据/测试零改动）；`item_def()` 统一剥后缀查定义，全项目查物品定义走此入口。纯数值装备（剑/甲/杖/护符）标 `mergeable:true` 参与合成、起手恒掉白；机制类物品（光环旗/暴击闪避嘲讽件，含诱敌面具）标 `fixed_tier` **不参与合成**、直接固定色阶掉落（数值语义：只有 atk/def/hp/magic/mp 吃色阶缩放，**副属性/光环不缩放**，避免百分比属性指数爆炸）。交互两条路：**库存"⇪合成"按钮**（≥2件时出现）+ **背包内拖同款同色阶物品直接合成**（复用现有拖放，落点幽灵预览绿=可合成）。UI 背景色改按色阶六档着色（`BagGridView`/商店/战利品卡统一）。配 GUT（`test_item_tiers` 23 条）；248/248 绿。**平衡压测**：单件红装(战士武器×32) vs 白装好build，魔王战 6.4→2.0 回合、剩血 76%→95%——冲击比多书连招更大，是"严格×2"曲线的必然结果（红=32倍），靠"攒32把同款"稀缺性天然节制，**暂不改数值，留待更多游玩数据判断要不要收紧曲线**。
- [x] **物品掉落深度门控（跟精英怪 min_layer 同思路）**：机制类特殊物品（光环旗/暴击闪避嘲讽件/诱敌面具）加 `min_layer`，早于该层不会掉落/不会在商店出现（军旗类2、锋锐之刃1、epic紫装4、铁壁旗+诱敌面具5）；**普通合成链装备不设门槛**（反正起手恒掉白，深度不影响其强度，不用卡）。`Backpack.min_layer_of()` + `LootTable.draw_draft(count, layer=999)`（缺省近乎不限，旧调用零改动；池被过滤空兜底放开门槛）；`RunManager` 掉落与商店进货**同一套门槛**（不会"打不到但能买到"）。配 GUT（6 条）；254/254 绿。
- [x] **深度掉落色阶曲线 + 4 件后期新装备（补上"完全没有"这个洞）**：① 走得越深，`mergeable` 装备越有概率**直接掉出预合成好**的绿/蓝（`LootTable.TIER_WEIGHTS_BY_LAYER`：层0-4恒白 / 5-10偶见绿+罕见蓝 / 11+绿蓝常见+罕见紫）；**天然掉落封顶紫色(3)**，橙/红永远只能靠玩家自己合成 16/32 把摸到（保住"凑齐红装"的成就感）。技术上把 `draw_draft`/`_drop_id` 的 `layer` 哨兵值从 999 改成 **-1**（未指定=门槛全放开+色阶恒白，向后兼容；999 曾经会让"未传层数"意外落进最深档，属于埋雷，已避开）。② 新增 4 件深度解锁基础装备（精钢剑/秘银法杖/圣光锤/巨龙鳞甲，数值高于早期同类，min_layer 3~6）——是**新内容**不是"老装备数字变大"，复用现成 `min_layer` 机制零新代码。配 GUT（`test_item_tiers` 追加 13 条，共 36 条）；261/261 绿。
- [x] **事件节点 event（分支地图收口）**：数据驱动 `EventTable`（8 事件；加事件=加一条）。schema：choice 带 `require`（gold/item/class 门槛，不满足灰掉）+ 确定 `effects` 或 概率 `risk`(win/lose roll)。效果**精简 3 型**（gold/item/hp_pct）+ **升级口**（`_apply_event_effect` 加 type 分支即扩）。`State.EVENT` + `_enter_event`(挑未遇过) + `resolve_event_choice`(判门槛→应用/roll) + `EventScreen`(照 Rest 套路) + 注册进 NodeTypes（自动在图上生成）。**存档友好**：只加 `current_event`/`used_events`(String)。决策：扣血钳≥1 不猝死 / 一局不重复 / 全队·库存层面。配 GUT（`test_event` 12 条）；216/216 绿。**至此分支地图功能完整**（战斗/精英/泉水/村庄/事件/魔王六类节点齐了）。
- [x] **深度缩放地基（怪随层数变强）**：`MapConfig.enemy_scale`（总开关 + 血/攻/防各自 `*_per_layer` 系数，0=该项关；`skip_types` 让魔王不吃 ramp）+ `MapGenerator.scale_enemy/apply_depth_scale`（第 N 层怪属性 ×(1+N×系数)）。怪池改**分档** `battle_tiers/elite_tiers`（按 `max_layer` 选档，加档/加怪只改数据）。harness 加**深度胜率曲线**（中庸 build 层1 满胜→层20 归零，量化验证 ramp）。配 GUT（`test_depth_scaling` 7 条）；224/224 绿。**留待**：后期档要加新怪才有质变（现档复用现有怪，靠 ramp 撑难度）；多幕结构 + 深度缩放 build 参考队。
- [x] **战斗系统代码审查 + 清理死代码**：审计 `BattleSimulator/BattleCombatant/CombatStrategy/Party` 等核心文件，产出优先级清单（详见对话/commit）。本轮清掉两块确认无引用的死代码：① 5 个英雄策略（Warrior/Mage/Priest/Rogue/Archer）的 `choose_skill()` 覆写——英雄回合只走 `_hero_combo_turn`+`should_cast()`，`choose_skill()` 自"英雄改连招"起从未被调用（敌人 AI 仍用，未动）；连带删 `CombatStrategy` 基类里只被它们用的 `_is_castable/_castable_skills/_strongest_castable_damage`；旧的 6 条直测 `choose_skill()` 的测试换成等价的 `should_cast()` 测试，覆盖率不丢。② `Party.gd` 清掉一整套 Brave Guild 经营残留（`quest`/`current_tile`/`hero_share_ratio`/`calculate_payout`/`distribute_payout`/`shared_consumables`族/`travel_*`族/`pending_loot`族/`battle_reports`，grep 确认全项目零引用），`Party.create()` 签名从 `(heroes, quest, share_ratio, tile)` 简化成 `(heroes)`，8 处调用点同步更新。263/263 绿，4 个场景 smoke-load 无报错。**最高优先级待办**（下一步 Boss 机制的前置）：`simulate(party, enemy_data_list)` 输入太薄，塞不下援军/多阶段/战场规则——建议加 `EncounterData` 包装战斗输入，一次到位。
- [x] **局间 meta 解锁（跨局持久成长，方案 A：里程碑解锁）**：新 autoload `MetaProgress`——**只解锁内容/多样性，绝不提升数值**（METHODOLOGY §2）。触发条件=存档历史最深打到过第几层（`record_layer`，任意一局打到过就永久算数，哪怕后来输了）；`META_UNLOCKS` 数据表（id→门槛层数，加解锁项=加一行）。起手锁**盗贼(层5)/猎人(层8)** 两职业 + **横扫书(2)/挑衅书(3)/冰枪书(3)/净化书(4)/暴击宝石(6)/狂战戒(7)/暗影披风(7)/铁壁旗(8)/诱敌面具(9)** 共 9 件，其余（普通装备全部 + 每职业 1 本起手书）恒解锁。接入 `RunManager._roll_recruits`（招募池只出已解锁职业）+ `LootTable.draw_draft`（掉落/商店同一道门槛，跟 `min_layer` 共用"传实层数才生效"的哨兵值）。村庄新增"待解锁"剧透区块（"？？？·再打深X层解锁"）。**存档不碰 R7**——只存一份 `{unlocked, best_layer_ever}` 到 `user://meta_progress.json`，纯 String/int，不涉及 Hero 对象/Vector2i 键。踩了一个坑：GUT 测试和真实游戏共享同一个 autoload 单例+默认存档路径，测试解锁一度把测试数据写进了真实存档文件——加 `autosave` 开关(测试文件 `before_each` 关掉)修复。配 GUT（`test_meta_progress` 15 条 + `test_run_manager` 补 1 条 `MetaProgress.reset()` 隔离）；279/279 绿。
- [ ] 存档（roguelike 跑局中途存读，卡在 R7）
- [ ] 平衡（起手队伍数值现为占位）

## ⭐ 小队跨英雄协同（差异化护城河，详设见 `BUILD_DESIGN.md` §7）

- [x] **第一档·开战属性光环**：物品 `aura:{scope,属性...}`，`build_party` 阶段2按 scope 注入（team/adjacent/same_row/front_row/back_row，含持有者本人）；军旗/疾风图腾/铁壁旗/先锋号角/守护图腾；tooltip/商店/`PowerScore` 接入；配 GUT。
- [x] **第二档·第一刀 闪避T 套件**：① 闪避 `dodge_chance`（命中前 roll 完全免伤，上限 `DODGE_CAP=0.6`，物理+魔法都可闪）② 嘲讽物品化 `taunt`（`has_taunt()`→`_find_taunt_target` 优先锁定，**仅前排生效**：嘲讽=站出来挡，后排件失效）。物品：疾风斗篷/暗影披风/挑衅护符/诱敌面具；接入普攻+单体技能+AOE；`PowerScore` 给闪避(EHP 乘子)/嘲讽算分；配 GUT。涌现"前排嘲讽吸火力+闪避保后排"。
- [ ] **第二档剩余**：③ 伤害转移/分摊 ④ 事件触发型队级效果（友军死/击杀/受击，复用 `on_battle_event`）⑤ 副属性光环（光环搬暴击/闪避等副属性，非只搬 base 属性）。

## 迁移记录（2026-06）

从 `Brave Guild` 迁入：战斗核心 + 实体数据层 + HeroFactory/EnemyAIFactory + Party + 背包实验 + GUT + 3 份设计文档。
**未迁入**（留旧项目）：公会经营层（Guild/Facility/Quest/Map/Turn Manager、WorldMap、HeroAI、设施任务 UI、ItemFactory(依赖 DataManager)、Quest/Facility 实体、六边形地图）。
**迁移时改动**：`Party` 移除依赖 HexUtils/HeroManager/Quest 的 to_dict/from_dict（roguelike 持久化交给将来的 RunManager）；project.godot 清空所有公会 autoload。
