# 待办：把背包构筑接成「遭遇前 prep 界面」

> 状态：**方案已敲定（2026-06-28 问答确认），待开工**。
> 背景源：`PROGRESS.md` 下一步、`ROGUELIKE_DESIGN.md`。落地后并回 PROGRESS。

## 一句话目标

让玩家在 `Encounter` 开战前先搭背包 / 摆站位，把"纯自动战斗"变回"我搭的 build 在打"。
力量全来自背包，背包靠**战利品**积累，HP 跨节点**消耗**。

---

## 复用结论（已读透两个文件）

- **`BackpackModel.gd` — 100% 直接复用，一行不改。** 纯数据/纯函数：`compute(grid)` 吃 `{Vector2i: item_id}`，吐 `{atk/def/hp/magic, synergies, books, extra}`。背包引擎。
  - ⚠️ 唯一要加的：给 `ITEMS` 每件加 **`rarity` 字段**（战利品加权抽取用）。
- **`BackpackExperiment.gd`（529 行单体 Control）混了三样**，只有一样是真金：
  1. **状态**（`_heroes` 的 grid、`_pool`、`_squad_slots`）—— 实验自己 hardcode，跑局里换成 RunManager 持有 + 跨节点保留。
  2. **`_on_fight` 的 426–471 行「grid → 可战斗 Party」转换** ← **核心金子**。把网格翻译成英雄属性 + 技能书（按职业过滤）+ 冷却 + 副属性 + 带站位的 Party。接入本质 = 抽成共享、可测的函数。
  3. **UI**（物品池 / 站位板 / 3 背包面板 + 交互，~250 行）—— 抽成共享组件（决定 ④=A）。

---

## 已定方案（2026-06-28 确认）

| # | 决定 | 说明 |
|---|------|------|
| ① 回血 | **不回血 + 钳血** | 开战不治疗；换背包只重算 max、current 钳到新 max。纯消耗战。写进 builder（`full_heal` 参数：实验 true、跑局 false）。 |
| ② 编辑频率 | **每场遭遇前自由编辑** | 每个 Encounter 开战前都能搭背包/摆站位。之后再视情收紧。 |
| ③ 物品来源 | **战利品 draft（三选二）** | 每场战斗**胜利后**给 3 件、玩家**丢 1 留 2**，留下的进库存。 |
| ④ 掉落内容 | **rarity 加权抽取** | ITEMS 加 `rarity` 字段，按权重随机（普通多/稀有少）。 |
| ⑤ 起手 | **空背包，纯靠掉落** | 起手两手空空，首战裸打。 |
| ⑥ prep UI | **(A) 抽 `BackpackPrepPanel`** | 池/站位板/背包面板抽成共享组件，实验场景 + Encounter 共用。 |

### 连带影响（重要）
1. **没有"固定物品池"概念了。** 改成 RunManager 持有**已拥有物品库存**（owned items，会涨）。prep 里的"池"= 拥有但未摆入格子的物品。多一个 `DRAFT` 状态 + draft 选择界面。
2. **首战裸打必须能赢。** 空背包 + 低 base → 第一个节点敌人要调弱到"裸队险胜"，否则开局卡死。**平衡约束，开工时一起调。**
3. **空间暂不紧张**（4 节点 × 留 2 ≈ 6–8 件 vs 18 格）→ "空间有限=取舍"这个支柱此切片暂不咬人；取舍来自"丢哪件/放谁/怎么相邻"。MVP 可接受，以后靠掉落量/格子数调。⚠️ 别忘了这个支柱后面要补回来。

---

## 修订后的切法（按此顺序执行）

- **✅ Step 1（已完成）抽 builder**：`scripts/systems/backpack/BackpackLoadout.gd` 的 `build_party(loadouts, squad_slots, full_heal)`，实验改调它（`full_heal=true`），跑局将传 `false` 钳血。配 `test_backpack_loadout.gd`（含幂等、HP做法A）。
- **✅ Step 2（已完成）状态进 RunManager**：名册 `roster=[{hero,base,grid}]` + `owned_items` 库存 + `squad_slots` 站位，`start_run` 初始化（空背包/空库存/默认站位），`party` 改为名册视图。裸 base 暂用占位高值（低值留到 Step 3）。扩 `test_run_manager`。
- **✅ Step 3（已完成）抽 `BackpackPrepPanel` + Encounter 用它**：共享编辑组件 `scripts/ui/BackpackPrepPanel.gd`（VBoxContainer，按引用操作 roster/owned_items/squad_slots）。实验场景 + Encounter 都改用它。Encounter 开战前嵌入 → 调 `build_party(full_heal=false)` 钳血 → simulate → resolve。配 `test_backpack_prep_panel`（放入/退回/校验）+ RunManager 端到端战斗路径测试。
  - ~~DEBUG 起手种子~~ → **Step 4 已删，库存改回空 `{}`**。
- **✅ Step 4（已完成）战利品 draft**：ITEMS 加 `rarity`（普通/稀有/史诗）+ `scripts/systems/LootTable.gd`（权重 65/27/8 加权不重复抽）。RunManager 加 `State.DRAFT` + `pending_draft` + `finish_draft()`：普通胜利 → 抽 3 件进 DRAFT；魔王胜 → 直接通关不抽。新建 `scenes/run/Draft.tscn`+`DraftScreen.gd`（三选二，点丢 1 留 2 进库存）。已删 debug 种子、库存改回空。配 `test_loot_table` + RunManager draft 用例。共 97/97 绿。
- **✅ Step 5（已完成）降 base + 平衡**：裸 base 降到实验低值（战90/6/8、法55/3/5、牧65/3/5），战力主要靠背包。新增 `test_balance.gd` harness（模拟好/中庸/烂 build 跑整局，输出通关率）。调敌人到中等难度：**好build 20/20 · 中庸 ~12/20 · 烂build 0/20**——好build稳赢、中庸有真风险（优化有意义）、烂build必败；魔王是协同/优化的检验门槛。
- **✅ Step 6（已完成）休息/泉水回血点**：节点类型 `rest` + `State.REST` + `Rest` 场景；进泉水全员回 50% 最大血（`REST_HEAL_PCT`，钳上限、不复活）。地图：村庄→林间→剧毒→**泉水**→废墟→魔王。消耗战泄压阀，整局张弛有度。

> 验证目标（火花）：玩家搭出的 build 在跑局里真的起作用 + "丢哪件/放谁"的 draft 抉择有意思 + 消耗战配回血点后整局张弛有度（不是必死）。

---

## 相关文件速查
- `scripts/systems/backpack/BackpackModel.gd`（复用 + 加 rarity）
- `scripts/experiments/BackpackExperiment.gd:426`（要抽的转换逻辑）+ 250 行 UI（要抽成 Panel）
- `scripts/autoload/RunManager.gd`（加 grids/owned_items/squad_slots + DRAFT 状态）
- `scripts/ui/Encounter.gd`（嵌 prep panel）
- 新建：`scripts/systems/backpack/BackpackLoadout.gd`、`scripts/ui/BackpackPrepPanel.gd`、战利品 draft 界面
