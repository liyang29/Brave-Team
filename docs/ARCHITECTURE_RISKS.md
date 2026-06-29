# 架构风险 / 技术债清单（R1–R8）

> 2026-06-29 架构体检产出。记录"核心代码能否扛功能膨胀"的隐患,按严重度排,带状态与建议。
> 关联:`PROJECT_STRUCTURE.md`(分层)、`SCALING_ROADMAP.md`(内容扩展)、`COMBAT_MANUAL.md`(战斗规则)。
>
> 状态:✅ 已修　⬜ 待办　🔧 进行中。**改动前先在此查一遍,改完回来更新状态。**

---

## 总评

核心战斗循环扩展性好——尤其 `BattleSimulator.simulate(party, enemy_data_list) → BattleResult` 是干净纯函数缝,战斗与 UI/RunManager 解耦。三层分离、工厂、策略模式、数据表、`extra_stats` 副属性通路都健康。

但有几处原型期欠债:**内容膨胀(加怪/物品/英雄)扛得住;功能膨胀(分支地图/事件/存档)会卡住**,需先补地基。

---

## 🔴 严重(扩张前优先)

### R1. 两套物品系统并存、未打通　⬜
- **问题**:`entities/items/`(Item/Equipment/Consumable 的 Resource 体系)是**死代码**;真正在跑的是 `experiments/BackpackModel.gd` 的 `ITEMS` 字典。物品是核心深度来源,真相源却住在 `experiments/`(脏实验)文件夹、顶着 `BackpackModel` 的名。
- **风险**:掉落/商店/套装/合成长出来后,命名与位置的"谎"会反复绊人。
- **建议**:正式认 dict 体系 → 搬出 experiments/(如 `systems/items/ItemTable.gd`)→ 退役 Resource 物品体系。
- **证据**:`PROJECT_STRUCTURE.md` 第 57/149 行自己已标。

### R2. 地图是写死的线性结构(分支地图的真正拦路石)　⬜
- **问题**:`RunManager.nodes: Array` + `depth: int` 索引——**线性数组+整数下标表达不了分支**(杀戮尖塔式一节点连多后继)。
- **建议**:数据模型升级为**节点图**(节点带 id + 邻接边),`depth` 换成"当前节点 id";写吃"群系配置(类型+权重+长度+分支规则)"的 `MapGenerator`(放 `systems/run/`)。
- **依赖**:R3/R4 是它的前置清理(已完成)。这是地图随机生成的主体工程。
- **证据**:`RunManager._build_map()`、`SCALING_ROADMAP.md` §2"地图"行。

---

## 🟡 注意(暂能扛,要盯着)

### R3. 节点类型派发分散在两处 match　✅ 已修(2026-06-29)
- **原问题**:`RunManager.enter_current_node`(type→state)与 `RunMap`(type→场景)各一份 `match type`,加类型要改两处、漏一处即 bug。
- **已做**:新增 `systems/run/NodeTypes.gd` 注册表(type→{scene, state, on_enter}),两处改为读注册表。加节点类型只改一行。配 GUT 守卫(地图类型必已注册 + state 名合法)。

### R4. "前进到下一节点"逻辑复制三份　✅ 已修(2026-06-29)
- **原问题**:`leave_rest`/`leave_village`/`finish_draft` 各自 `depth+=1 → 越界检查 → set MAP/VICTORY`,bug 磁铁。
- **已做**:抽 `RunManager._advance()` 共用。(boss 胜利那条语义是"通关"非"前进",故意保持显式。)

### R5. RunManager 正在长成"上帝单例"　⬜
- **问题**:autoload 里挤了 状态机+队伍+名册+金币+地图构建+商店+酒馆+draft+休息+英雄模板。现 ~300 行,加事件/存档/meta 会爆。
- **建议**:逐步拆 `MapGenerator`/`EncounterData`/`ShopService` 到 `systems/run/`,RunManager 只当状态机协调者。
- **证据**:`scripts/autoload/RunManager.gd`(`HERO_TEMPLATES`、`_build_map`、商店/酒馆逻辑都内联)。

### R6. 战斗输入太薄,只有 enemy_data_list　⬜
- **问题**:`simulate(party, enemy_data_list)` 只吃敌人列表。未来的敌人布局、多波次、战场 modifier、非"全歼"胜利条件(护送/存活 N 回合)无处安放。
- **建议**:引入 `EncounterData`(敌人 + 布局 + 修正 + 胜利条件)当战斗入口包装,`simulate` 签名不必反复改。现在做很便宜。
- **附**:`BattleSimulator` 已 ~630 行,机制(暴击/闪避/嘲讽/站位/AOE/触发)全内联;AI 用策略模式拆了但机制没有。关键词再多可考虑抽"关键词/效果注册表"(参照 `equipment_triggers`)。不急,盯着。

### R7. 数据模型对"存档"不友好(潜在雷)　⬜
- **问题**:roster 装 `Hero` 对象引用,`squad_slots` 用 `Vector2i → Hero 引用` 当键值,`grid` 用 `Vector2i` 当键——**对象引用和 Vector2i 键都不好 JSON 序列化**。roguelike 迟早要存盘,现结构不是按可序列化设计的。
- **建议**:站位/背包尽早改用**稳定 hero id**(而非对象引用)做键,为存档铺路。
- **证据**:`RunManager.roster`/`squad_slots`、`BackpackModel` 的 `grid`。

### R8. Hero 被全局原地改写,存在"双真相源"　⬜
- **问题**:`BackpackLoadout` 把 `base_*` 写回 Hero、`BattleCombatant.from_hero` 把 current_hp 写回 Hero。真相源其实是 roster 的 `base` dict,Hero 是被反复重建覆盖的"视图"。
- **风险**:等"跨战斗持续状态/装备/升级"长出来,`base dict vs Hero 字段`这对双源会变脆。
- **现状**:有测试兜着、能跑,属已知锋利边缘——别在上面叠太多。
- **证据**:`BackpackLoadout.build_party`、`BattleCombatant.from_hero`。

---

## 建议落地顺序(都不大,从小到大)

1. ✅ **R4**(`_advance`,几行)
2. ✅ **R3**(节点类型注册表)
3. ⬜ **R6**(`EncounterData` 包战斗输入)
4. ⬜ **R2**(图模型 + `MapGenerator`)— 最大,R3/R4 是其前置
5. ⬜ **R1**(物品系统统一)— 可独立挑时间做
6. ⬜ **R5/R7/R8** — 随 存档/meta/事件 需求到来时一并处理

> 一句话:已有对的骨架(工厂+策略+数据表),扩展 = 补全骨架 + 加生成器 + 加 harness/Debug 菜单,不是推倒重来。
