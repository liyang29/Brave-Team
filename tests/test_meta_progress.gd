extends GutTest

# MetaProgress：局外/跨局成长——解锁判定 / 层数触发 / 存读档 / 接入招募池&掉落池。
# MetaProgress 是跨局持久的 autoload，每条测试前后都要重置，避免状态漏到别的测试文件。

const TMP_SAVE := "user://test_meta_progress_tmp.json"
const LootTable = preload("res://scripts/systems/LootTable.gd")
const Backpack = preload("res://scripts/systems/backpack/BackpackModel.gd")


func before_each() -> void:
	MetaProgress.reset()
	MetaProgress.autosave = false   # 默认存档路径=玩家真实存档，测试解锁不该写进去

func after_each() -> void:
	MetaProgress.reset()
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(TMP_SAVE)


# ── is_unlocked 默认值 ────────────────────────────────────────────────────────

func test_ids_not_in_table_are_always_unlocked() -> void:
	assert_true(MetaProgress.is_unlocked("warrior"), "起手职业不在解锁表里 → 恒解锁")
	assert_true(MetaProgress.is_unlocked("iron_sword"), "普通装备不在解锁表里 → 恒解锁")

func test_ids_in_table_locked_by_default() -> void:
	assert_false(MetaProgress.is_unlocked("rogue"), "盗贼在解锁表里、未解锁 → 锁定")
	assert_false(MetaProgress.is_unlocked("book_cleave"), "横扫书在解锁表里、未解锁 → 锁定")


# ── record_layer：层数触发解锁 ────────────────────────────────────────────────

func test_record_layer_below_threshold_unlocks_nothing() -> void:
	var newly: Array = MetaProgress.record_layer(1)   # 最早的门槛(book_cleave)是层2
	assert_true(newly.is_empty(), "第1层没有任何解锁项达标")
	assert_false(MetaProgress.is_unlocked("book_cleave"), "仍锁定")

func test_record_layer_at_threshold_unlocks() -> void:
	var newly: Array = MetaProgress.record_layer(2)
	assert_true("book_cleave" in newly, "第2层达标 → 横扫书本次新解锁")
	assert_true(MetaProgress.is_unlocked("book_cleave"), "解锁状态生效")

func test_record_layer_unlocks_everything_up_to_that_layer() -> void:
	MetaProgress.record_layer(5)
	assert_true(MetaProgress.is_unlocked("book_cleave"), "层2门槛已达标")
	assert_true(MetaProgress.is_unlocked("book_taunt"), "层3门槛已达标")
	assert_true(MetaProgress.is_unlocked("book_icelance"), "层3门槛已达标")
	assert_true(MetaProgress.is_unlocked("book_purify"), "层4门槛已达标")
	assert_true(MetaProgress.is_unlocked("rogue"), "层5门槛已达标")
	assert_false(MetaProgress.is_unlocked("archer"), "层8门槛未达标 → 仍锁定")

func test_record_layer_does_not_regress_or_retrigger() -> void:
	MetaProgress.record_layer(5)
	var newly: Array = MetaProgress.record_layer(2)   # 比历史最深浅 → 无操作
	assert_true(newly.is_empty(), "比历史最深浅的层数不触发（也不返回重复解锁）")
	assert_eq(MetaProgress.best_layer_ever, 5, "历史最深纪录不倒退")

func test_record_layer_only_returns_newly_unlocked_this_call() -> void:
	MetaProgress.record_layer(2)   # 解锁 book_cleave
	var newly: Array = MetaProgress.record_layer(3)   # 再深一层
	assert_false("book_cleave" in newly, "book_cleave 上次已解锁，这次不该再出现在'新解锁'里")
	assert_true("book_taunt" in newly and "book_icelance" in newly, "这次新达标的两项都在")


# ── locked_summary：UI 剧透用 ─────────────────────────────────────────────────

func test_locked_summary_sorted_by_layer_ascending() -> void:
	var summary: Array = MetaProgress.locked_summary()
	for i in range(1, summary.size()):
		assert_true(int(summary[i-1]["layer"]) <= int(summary[i]["layer"]), "按门槛升序排列")

func test_locked_summary_excludes_unlocked() -> void:
	var before_count: int = MetaProgress.locked_summary().size()
	MetaProgress.record_layer(2)   # 解锁 book_cleave 一项
	var after_count: int = MetaProgress.locked_summary().size()
	assert_eq(after_count, before_count - 1, "已解锁的项从待解锁列表消失")


# ── 存读档往返 ────────────────────────────────────────────────────────────────

func test_save_and_load_roundtrip() -> void:
	MetaProgress.record_layer(6)   # 解锁一批
	var unlocked_before: Dictionary = MetaProgress.unlocked.duplicate()
	var best_before: int = MetaProgress.best_layer_ever
	MetaProgress.save_progress(TMP_SAVE)

	MetaProgress.reset()
	assert_eq(MetaProgress.best_layer_ever, -1, "reset 后确实清空了")

	MetaProgress.load_progress(TMP_SAVE)
	assert_eq(MetaProgress.best_layer_ever, best_before, "读档恢复历史最深层")
	for id in unlocked_before:
		assert_true(MetaProgress.unlocked.has(id), "读档恢复解锁项 %s" % id)

func test_load_missing_file_keeps_default_state() -> void:
	MetaProgress.load_progress("user://this_file_does_not_exist_xyz.json")
	assert_eq(MetaProgress.best_layer_ever, -1, "文件不存在 → 保持初始空状态，不报错")


# ── 接入招募池 / 掉落池 ────────────────────────────────────────────────────────

func test_recruit_pool_excludes_locked_classes() -> void:
	RunManager.start_run()
	RunManager.enter_current_node()
	assert_false("rogue" in RunManager.tavern_offers, "盗贼未解锁 → 不会出现在招募候选里")
	assert_false("archer" in RunManager.tavern_offers, "猎人未解锁 → 不会出现在招募候选里")

func test_recruit_pool_includes_unlocked_classes_after_unlock() -> void:
	MetaProgress.record_layer(5)   # 解锁盗贼；record_layer(0)(start_run内部调) 不会让纪录倒退
	# 候选是随机洗牌抽取，多跑几次应至少看到一次盗贼出现（候选数已等于已解锁职业数=全体）
	var saw_rogue := false
	for i in range(20):
		RunManager.start_run()
		RunManager.enter_current_node()
		if "rogue" in RunManager.tavern_offers:
			saw_rogue = true
			break
	assert_true(saw_rogue, "解锁后盗贼应能出现在招募候选里")

func test_loot_pool_excludes_locked_items_at_shallow_layer() -> void:
	for i in range(60):
		var draft: Array = LootTable.draw_draft(3, 0)
		for id in draft:
			assert_true(MetaProgress.is_unlocked(Backpack.base_id(id)), "第0层掉落 %s 不该含未解锁物品" % id)

func test_loot_pool_includes_unlocked_items_after_unlock() -> void:
	MetaProgress.record_layer(2)   # 解锁 book_cleave
	var saw_it := false
	for i in range(80):
		var draft: Array = LootTable.draw_draft(3, 2)
		if "book_cleave" in draft:
			saw_it = true
			break
	assert_true(saw_it, "解锁后 book_cleave 应能出现在掉落里")
