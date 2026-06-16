extends Control

# 这是模拟器面板的总入口：
# 负责读取和校验配置、选择流派策略、启动战斗模拟、显示结果、导出复盘文件。
# 战斗怎么结算交给战斗模拟器，玩家怎么决策交给策略脚本。
const CONFIG_PATH = "res://data/sample_config.json"
const EXPORT_JSON = "user://last_result.json"
const EXPORT_RESULT_CSV = "user://last_result.csv"
const EXPORT_BATCH_CSV = "user://batch_summary.csv"
const EXPORT_COMPARE_CSV = "user://strategy_compare.csv"
const EXPORT_ARCHIVE_DIR = "user://exports"
const CombatSimulatorScript = preload("res://scripts/combat/combat_simulator.gd")

var config: Dictionary = {}
var selected_strategy_id = "crit_strategy"
var selected_mode = "turn_based"
var last_result: Dictionary = {}
var replay_events: Array = []
var replay_source: Dictionary = {}
var replay_index = 0
var replay_timer = 0.0
var replay_active = false
var replay_log_lines: Array[String] = []
var strategy_scripts = {
	"crit_strategy": preload("res://scripts/strategy/crit_strategy.gd"),
	"burn_strategy": preload("res://scripts/strategy/burn_strategy.gd"),
	"summon_strategy": preload("res://scripts/strategy/summon_strategy.gd")
}

@onready var status_label: Label = %StatusLabel
@onready var player_bar: ProgressBar = %PlayerHpBar
@onready var enemy_bar: ProgressBar = %EnemyHpBar
@onready var player_label: Label = %PlayerLabel
@onready var enemy_label: Label = %EnemyLabel
@onready var strategy_option: OptionButton = %StrategyOption
@onready var mode_option: OptionButton = %ModeOption
@onready var result_label: Label = %ResultLabel
@onready var log_text: TextEdit = %LogText
@onready var curve_graph: Control = %CurveGraph
@onready var curve_text: TextEdit = %CurveText
@onready var batch_runs_spin: SpinBox = %BatchRunsSpin
@onready var stage_preview_label: Label = %StagePreviewLabel
@onready var enemy_preview_container: HBoxContainer = %EnemyPreviewContainer
@onready var damage_hint_label: Label = %DamageHintLabel
@onready var compare_chart_panel: PanelContainer = %CompareChartPanel
@onready var compare_chart_box: VBoxContainer = %CompareChartBox


func _ready() -> void:
	_setup_options()
	_load_config()
	_handle_command_line()


func _process(delta: float) -> void:
	if not replay_active:
		return
	replay_timer -= delta
	if replay_timer > 0.0:
		return
	replay_timer = 0.12
	_step_replay()


func _setup_options() -> void:
	strategy_option.clear()
	strategy_option.add_item("裂芯暴击流", 0)
	strategy_option.set_item_metadata(0, "crit_strategy")
	strategy_option.add_item("余火持续输出流", 1)
	strategy_option.set_item_metadata(1, "burn_strategy")
	strategy_option.add_item("余烬召唤流", 2)
	strategy_option.set_item_metadata(2, "summon_strategy")
	mode_option.clear()
	mode_option.add_item("回合制", 0)
	mode_option.set_item_metadata(0, "turn_based")
	mode_option.add_item("实时 Tick 制", 1)
	mode_option.set_item_metadata(1, "realtime")


func _load_config() -> void:
	# 配置文件是策划数据和程序之间的契约。
	# 这里严格读取和解析，是为了让错误配置在进入模拟器前就暴露出来。
	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		_show_error("配置加载失败：" + CONFIG_PATH + "；" + error_string(FileAccess.get_open_error()))
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_show_error("配置解析失败：JSON 顶层必须是 Object。")
		return
	config = parsed
	var validation_error = _validate_config(config)
	if validation_error != "":
		_show_error("配置校验失败：" + validation_error)
		return
	_setup_options_from_config()
	status_label.text = "配置加载成功：" + CONFIG_PATH
	log_text.text = "已加载配置。请选择流派和模式后运行模拟。\n"
	_hide_compare_chart()
	_render_stage_preview()


func _validate_config(data: Dictionary) -> String:
	# 配置校验用来保护扩展点。
	# 以后如果新增技能、道具、怪物或构筑预设，只要引用关系或数值不合法，
	# 就会在这里给出明确错误，而不是带着脏数据进入战斗。
	for key in ["schema_version", "game", "characters", "skills", "items", "monsters", "stages", "build_presets"]:
		if not data.has(key):
			return "缺少顶层字段 " + key
	if typeof(data.get("schema_version")) != TYPE_STRING or String(data.get("schema_version", "")) == "":
		return "schema_version 必须是非空字符串"
	if typeof(data.get("game")) != TYPE_DICTIONARY:
		return "game 必须是 Object"
	for key in ["characters", "skills", "items", "monsters", "stages", "build_presets"]:
		if typeof(data.get(key)) != TYPE_ARRAY:
			return key + " 必须是 Array"
	if data.has("item_affixes") and typeof(data.get("item_affixes")) != TYPE_ARRAY:
		return "item_affixes 必须是 Array"
	if data.get("characters", []).is_empty():
		return "characters 不能为空"
	if data.get("stages", []).is_empty():
		return "stages 不能为空"
	var game: Dictionary = data.get("game", {})
	var game_error = _validate_non_negative_numbers(game, "game", [])
	if game_error != "":
		return game_error
	for required_number in ["starting_stat_points", "item_slots", "max_turns", "max_seconds", "tick_seconds"]:
		if not game.has(required_number):
			return "game 缺少字段 " + required_number
	if game.has("reward_affix_chance"):
		var reward_affix_chance = float(game.get("reward_affix_chance", 0.0))
		if reward_affix_chance < 0.0 or reward_affix_chance > 1.0:
			return "game.reward_affix_chance 必须在 0 到 1 之间"
	var duplicate_error = _validate_unique_ids(data.get("characters", []), "characters")
	if duplicate_error != "":
		return duplicate_error
	duplicate_error = _validate_unique_ids(data.get("skills", []), "skills")
	if duplicate_error != "":
		return duplicate_error
	duplicate_error = _validate_unique_ids(data.get("items", []), "items")
	if duplicate_error != "":
		return duplicate_error
	duplicate_error = _validate_unique_ids(data.get("monsters", []), "monsters")
	if duplicate_error != "":
		return duplicate_error
	duplicate_error = _validate_unique_ids(data.get("stages", []), "stages")
	if duplicate_error != "":
		return duplicate_error
	duplicate_error = _validate_unique_ids(data.get("build_presets", []), "build_presets")
	if duplicate_error != "":
		return duplicate_error
	var skill_ids = _collect_ids(data.get("skills", []))
	var item_ids = _collect_ids(data.get("items", []))
	var monster_ids = _collect_ids(data.get("monsters", []))
	for character in data.get("characters", []):
		if typeof(character.get("base_stats")) != TYPE_DICTIONARY:
			return "角色 %s 缺少 base_stats" % character.get("id", "")
		if typeof(character.get("stat_growth")) != TYPE_DICTIONARY:
			return "角色 %s 缺少 stat_growth" % character.get("id", "")
		if typeof(character.get("skill_ids")) != TYPE_ARRAY:
			return "角色 %s 的 skill_ids 必须是 Array" % character.get("id", "")
		var base_stats_error = _validate_non_negative_numbers(character.get("base_stats", {}), "characters.%s.base_stats" % character.get("id", ""), ["crit_rate"])
		if base_stats_error != "":
			return base_stats_error
		var crit_rate = float(character.get("base_stats", {}).get("crit_rate", 0.0))
		if crit_rate < 0.0 or crit_rate > 1.0:
			return "角色 %s 的 crit_rate 必须在 0 到 1 之间" % character.get("id", "")
		var growth_error = _validate_non_negative_numbers(character.get("stat_growth", {}), "characters.%s.stat_growth" % character.get("id", ""), [])
		if growth_error != "":
			return growth_error
		for skill_id in character.get("skill_ids", []):
			if not skill_ids.has(String(skill_id)):
				return "角色 %s 引用了不存在的技能 %s" % [character.get("id", ""), skill_id]
	for skill in data.get("skills", []):
		for field_name in ["cooldown", "energy_cost", "power"]:
			if float(skill.get(field_name, -1.0)) < 0.0:
				return "技能 %s 的 %s 不能为负数" % [skill.get("id", ""), field_name]
	for item in data.get("items", []):
		if item.has("charges") and int(item.get("charges", -1)) < 0:
			return "道具 %s 的 charges 不能为负数" % item.get("id", "")
	for monster in data.get("monsters", []):
		if typeof(monster.get("stats")) != TYPE_DICTIONARY:
			return "怪物 %s 缺少 stats" % monster.get("id", "")
		var stats_error = _validate_non_negative_numbers(monster.get("stats", {}), "monsters.%s.stats" % monster.get("id", ""), [])
		if stats_error != "":
			return stats_error
	for stage in data.get("stages", []):
		if typeof(stage.get("waves")) != TYPE_ARRAY:
			return "关卡 %s 的 waves 必须是 Array" % stage.get("id", "")
		for wave in stage.get("waves", []):
			var monster_id = String(wave.get("monster_id", ""))
			if not monster_ids.has(monster_id):
				return "关卡 %s 引用了不存在的怪物 %s" % [stage.get("id", ""), monster_id]
			if int(wave.get("count", 0)) <= 0:
				return "关卡 %s 的怪物数量必须大于 0" % stage.get("id", "")
	for preset in data.get("build_presets", []):
		if typeof(preset.get("stat_points")) != TYPE_DICTIONARY:
			return "流派预设 %s 的 stat_points 必须是 Object" % preset.get("id", "")
		if typeof(preset.get("item_ids")) != TYPE_ARRAY:
			return "流派预设 %s 的 item_ids 必须是 Array" % preset.get("id", "")
		var strategy_id = String(preset.get("strategy_id", ""))
		if not strategy_scripts.has(strategy_id):
			return "流派预设 %s 引用了未注册的策略 %s" % [preset.get("id", ""), strategy_id]
		if int(round(_sum_numeric_dict(preset.get("stat_points", {})))) != int(game.get("starting_stat_points", 0)):
			return "流派预设 %s 的属性点总和必须等于 starting_stat_points" % preset.get("id", "")
		if preset.get("item_ids", []).size() > int(game.get("item_slots", 0)):
			return "流派预设 %s 的初始道具数量超过 item_slots" % preset.get("id", "")
		for item_id in preset.get("item_ids", []):
			if not item_ids.has(String(item_id)):
				return "流派预设 %s 引用了不存在的道具 %s" % [preset.get("id", ""), item_id]
	for affix in data.get("item_affixes", []):
		if String(affix.get("id", "")) == "":
			return "item_affixes 中存在空 id"
		if affix.has("weight") and float(affix.get("weight", 0.0)) < 0.0:
			return "词缀 %s 的 weight 不能为负数" % affix.get("id", "")
	return ""


func _setup_options_from_config() -> void:
	strategy_option.clear()
	var added = {}
	var item_index = 0
	for preset in config.get("build_presets", []):
		var strategy_id = String(preset.get("strategy_id", ""))
		if strategy_id == "" or added.has(strategy_id) or not strategy_scripts.has(strategy_id):
			continue
		strategy_option.add_item(String(preset.get("name", strategy_id)), item_index)
		strategy_option.set_item_metadata(item_index, strategy_id)
		added[strategy_id] = true
		item_index += 1
	if item_index == 0:
		_setup_options()
		return
	var selected_index = 0
	for i in range(strategy_option.item_count):
		if String(strategy_option.get_item_metadata(i)) == selected_strategy_id:
			selected_index = i
			break
	strategy_option.select(selected_index)
	selected_strategy_id = String(strategy_option.get_item_metadata(selected_index))


func _render_stage_preview() -> void:
	var monsters_by_id = {}
	for monster in config.get("monsters", []):
		monsters_by_id[monster.get("id", "")] = monster
	var lines: Array[String] = ["场景预览：玩家 1 个；怪物按队列依次出场"]
	_clear_enemy_preview()
	var wave_index = 0
	for wave in config.get("stages", [])[0].get("waves", []):
		wave_index += 1
		var monster: Dictionary = monsters_by_id.get(wave.get("monster_id", ""), {})
		lines.append("波次 %d：%s x%s" % [wave_index, monster.get("name", wave.get("monster_id", "")), wave.get("count", 0)])
		for i in range(int(wave.get("count", 0))):
			enemy_preview_container.add_child(_make_enemy_token(monster, wave_index))
	stage_preview_label.text = "\n".join(lines)
	damage_hint_label.text = "伤害提示：等待战斗开始"


func _clear_enemy_preview() -> void:
	for child in enemy_preview_container.get_children():
		child.queue_free()


func _make_enemy_token(monster: Dictionary, wave_index: int) -> Control:
	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(82, 76)
	var color = ColorRect.new()
	color.custom_minimum_size = Vector2(58, 38)
	color.color = _monster_color(monster.get("id", ""))
	var label = Label.new()
	label.text = "W%d\n%s" % [wave_index, monster.get("name", "敌人")]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(color)
	box.add_child(label)
	return box


func _monster_color(monster_id: String) -> Color:
	match monster_id:
		"ash_crawler":
			return Color(0.55, 0.43, 0.32)
		"furnace_guard":
			return Color(0.80, 0.22, 0.12)
		_:
			return Color(0.35, 0.35, 0.35)


func _on_reload_button_pressed() -> void:
	_load_config()


func _on_back_menu_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/LaunchMenu.tscn")


func _on_run_button_pressed() -> void:
	if config.is_empty():
		_show_error("配置为空，无法运行。")
		return
	_stop_replay()
	_update_selection()
	last_result = _run_once(selected_strategy_id, selected_mode, Time.get_ticks_usec())
	_render_result(last_result)


func _on_batch_button_pressed() -> void:
	if config.is_empty():
		_show_error("配置为空，无法批量模拟。")
		return
	_stop_replay()
	_update_selection()
	var runs = int(batch_runs_spin.value)
	_run_batch(runs, Time.get_ticks_usec())


func _on_compare_button_pressed() -> void:
	if config.is_empty():
		_show_error("配置为空，无法对照运行。")
		return
	_stop_replay()
	_update_selection()
	var runs = int(batch_runs_spin.value)
	_run_strategy_compare(runs, Time.get_ticks_usec())


func _run_batch(runs: int, base_seed: int) -> Dictionary:
	# 批量模式用来验证设计假设。
	# 同一套策略连续跑多次，统计胜率和平均表现，再导出结果供复盘。
	var batch = _run_batch_for_strategy(selected_strategy_id, selected_mode, runs, base_seed)
	var results: Array[Dictionary] = batch.get("results", [])
	var summary: Dictionary = batch.get("summary", {})
	last_result = {
		"type": "batch",
		"base_seed": base_seed,
		"summary": summary,
		"results": results
	}
	_render_batch(summary, results)
	var csv_archive = _export_batch_csv(results, summary)
	if csv_archive != "":
		last_result["csv_archive_path"] = ProjectSettings.globalize_path(csv_archive)
	_export_last_result_json()
	return last_result


func _run_batch_for_strategy(strategy_id: String, run_mode: String, runs: int, base_seed: int) -> Dictionary:
	# 随机种子的步长固定，保证每局既能复现，又不会重复同一组随机结果。
	# 表格里的任意失败行，都可以按“基础随机种子 + 局数序号”精确重跑。
	var original_strategy_id = selected_strategy_id
	var original_mode = selected_mode
	selected_strategy_id = strategy_id
	selected_mode = run_mode
	var started_ms = Time.get_ticks_msec()
	var results: Array[Dictionary] = []
	for i in range(runs):
		results.append(_run_once(strategy_id, run_mode, base_seed + i * 7919))
	var elapsed_ms = max(1, Time.get_ticks_msec() - started_ms)
	var summary = _summarize_batch(results)
	_attach_batch_metadata(summary, results, base_seed, elapsed_ms)
	selected_strategy_id = original_strategy_id
	selected_mode = original_mode
	return {"summary": summary, "results": results}


func _run_strategy_compare(runs: int, base_seed: int) -> Dictionary:
	# 公平对照：每个流派使用同一关卡、同一模式、同一批随机种子。
	# 这样比较出来的是策略强弱，而不是哪一组随机结果更走运。
	var started_ms = Time.get_ticks_msec()
	var compare_summaries: Array[Dictionary] = []
	var compare_results: Dictionary = {}
	for strategy_id in _configured_compare_strategy_ids():
		var batch = _run_batch_for_strategy(strategy_id, selected_mode, runs, base_seed)
		var summary: Dictionary = batch.get("summary", {})
		compare_summaries.append(summary)
		compare_results[strategy_id] = batch.get("results", [])
	var elapsed_ms = max(1, Time.get_ticks_msec() - started_ms)
	var total_runs = runs * max(1, compare_summaries.size())
	last_result = {
		"type": "strategy_compare",
		"mode": selected_mode,
		"base_seed": base_seed,
		"runs_per_strategy": runs,
		"elapsed_ms": elapsed_ms,
		"runs_per_second": float(total_runs) * 1000.0 / float(elapsed_ms),
		"summaries": compare_summaries,
		"results_by_strategy": compare_results
	}
	_render_strategy_compare(compare_summaries, runs)
	var csv_archive = _export_compare_csv(compare_summaries)
	if csv_archive != "":
		last_result["csv_archive_path"] = ProjectSettings.globalize_path(csv_archive)
	_export_last_result_json()
	return last_result


func _on_export_button_pressed() -> void:
	if last_result.is_empty():
		_show_error("暂无结果可导出。")
		return
	var json_archive = _export_last_result_json()
	var csv_archive = ""
	if last_result.get("type", "") == "batch":
		csv_archive = _export_batch_csv(last_result.get("results", []), last_result.get("summary", {}))
	elif last_result.get("type", "") == "strategy_compare":
		csv_archive = _export_compare_csv(last_result.get("summaries", []))
	else:
		csv_archive = _export_single_csv(last_result)
	status_label.text = "已导出 latest 与归档：\nJSON latest: %s\nJSON archive: %s\nCSV archive: %s" % [
		ProjectSettings.globalize_path(EXPORT_JSON),
		ProjectSettings.globalize_path(json_archive) if json_archive != "" else "无",
		ProjectSettings.globalize_path(csv_archive) if csv_archive != "" else "无"
	]


func _on_replay_button_pressed() -> void:
	_stop_replay()
	var replay_result = _load_replay_result()
	if replay_result.is_empty():
		_show_error("未找到可回放结果，请先运行一场单场模拟或导出 `last_result.json`。")
		return
	_begin_replay(replay_result)


func _load_replay_result() -> Dictionary:
	var source: Dictionary = last_result.duplicate(true) if not last_result.is_empty() else {}
	if source.is_empty():
		var file = FileAccess.open(EXPORT_JSON, FileAccess.READ)
		if file == null:
			return {}
		var parsed = JSON.parse_string(file.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			return {}
		source = parsed
	return _first_replayable_result(source)


func _first_replayable_result(source: Dictionary) -> Dictionary:
	if source.has("replay_events") and not source.get("replay_events", []).is_empty():
		return source
	if source.get("type", "") == "batch":
		for result in source.get("results", []):
			if typeof(result) == TYPE_DICTIONARY and not result.get("replay_events", []).is_empty():
				return result
	if source.get("type", "") == "strategy_compare":
		var results_by_strategy: Dictionary = source.get("results_by_strategy", {})
		for strategy_id in results_by_strategy.keys():
			for result in results_by_strategy[strategy_id]:
				if typeof(result) == TYPE_DICTIONARY and not result.get("replay_events", []).is_empty():
					return result
	return {}


func _sample_replay_events(events: Array) -> Array[Dictionary]:
	var picked: Array[Dictionary] = []
	var wanted = {"stage_start": true, "enemy_spawn": true, "damage": true, "monster_attack": true, "use_item": true, "room_reward": true, "battle_end": true}
	var seen = {}
	for event in events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var event_type = String(event.get("type", ""))
		if wanted.has(event_type) and not seen.has(event_type):
			picked.append(event)
			seen[event_type] = true
		if picked.size() >= wanted.size():
			break
	if picked.is_empty() and not events.is_empty() and typeof(events[0]) == TYPE_DICTIONARY:
		picked.append(events[0])
	return picked


func _begin_replay(result: Dictionary) -> void:
	replay_source = result.duplicate(true)
	replay_events = result.get("replay_events", []).duplicate(true)
	replay_index = 0
	replay_timer = 0.0
	replay_active = true
	replay_log_lines.clear()
	_hide_compare_chart()
	player_bar.max_value = max(1.0, float(result.get("player_max_hp", 1.0)))
	player_bar.value = player_bar.max_value
	player_label.text = "Replay 玩家 HP：%s / %s" % [_fmt(player_bar.value), _fmt(player_bar.max_value)]
	enemy_bar.max_value = 1.0
	enemy_bar.value = 0.0
	enemy_label.text = "Replay 敌人：等待登场"
	result_label.text = "Replay 播放中\n策略：%s\n模式：%s\nSeed：%s\n事件：0 / %s\n总伤害：%s\n承受伤害：%s" % [
		result.get("strategy_id", ""),
		"实时 Tick 制" if result.get("mode", "") == "realtime" else "回合制",
		result.get("seed", 0),
		replay_events.size(),
		_fmt(result.get("total_damage_done", 0.0)),
		_fmt(result.get("total_damage_taken", 0.0))
	]
	log_text.text = ""
	curve_graph.set_curve(result.get("damage_curve", []), "橙线累计 / 蓝柱单次：%s" % _fmt(result.get("total_damage_done", 0.0)))
	curve_text.text = _curve_to_text(result.get("damage_curve", []))
	damage_hint_label.text = "Replay：准备播放事件流。曲线表格包含 source、delta、total、target HP。"
	status_label.text = "Replay 播放中..."


func _stop_replay() -> void:
	replay_active = false


func _step_replay() -> void:
	if replay_index >= replay_events.size():
		replay_active = false
		status_label.text = "Replay 播放完成。"
		return
	var event: Dictionary = replay_events[replay_index]
	_apply_replay_event(event)
	replay_index += 1
	if replay_index >= replay_events.size():
		replay_active = false
		status_label.text = "Replay 播放完成。"
	else:
		status_label.text = "Replay 播放中：%s / %s" % [replay_index, replay_events.size()]


func _apply_replay_event(event: Dictionary) -> void:
	var payload: Dictionary = event.get("payload", {})
	var event_type = String(event.get("type", ""))
	match event_type:
		"stage_start":
			enemy_label.text = "Replay 房间：%s" % payload.get("stage_name", "")
		"enemy_spawn":
			var enemy_hp = float(payload.get("enemy_hp", 1.0))
			enemy_bar.max_value = max(1.0, float(payload.get("enemy_max_hp", enemy_hp)))
			enemy_bar.value = enemy_hp
			enemy_label.text = "Replay 敌人：%s HP %s / %s" % [payload.get("enemy_name", ""), _fmt(enemy_hp), _fmt(enemy_bar.max_value)]
		"damage":
			var enemy_hp_before = float(payload.get("enemy_hp_before", payload.get("enemy_hp", enemy_bar.value)))
			var enemy_hp_after = float(payload.get("enemy_hp", enemy_bar.value))
			enemy_bar.max_value = max(enemy_bar.max_value, float(payload.get("enemy_max_hp", enemy_hp_after)))
			enemy_bar.value = enemy_hp_after
			player_bar.value = float(payload.get("player_hp", player_bar.value))
			var source = String(payload.get("source", ""))
			var delta = float(payload.get("delta", payload.get("damage", 0.0)))
			var total_damage = float(payload.get("total_damage", payload.get("damage", 0.0)))
			var critical = bool(payload.get("critical", false))
			enemy_label.text = "Replay 敌人：%s HP %s / %s" % [payload.get("enemy_name", ""), _fmt(enemy_bar.value), _fmt(enemy_bar.max_value)]
			damage_hint_label.text = "Replay 伤害：%s%s，单次 %s，累计 %s，敌人 HP %s -> %s" % [
				source,
				" 暴击" if critical else "",
				_fmt(delta),
				_fmt(total_damage),
				_fmt(enemy_hp_before),
				_fmt(enemy_hp_after)
			]
			result_label.text = "Replay 事件 %s / %s\n来源：%s%s\n单次伤害：%s\n累计伤害：%s\n敌人 HP：%s -> %s" % [
				replay_index + 1,
				replay_events.size(),
				source,
				" 暴击" if critical else "",
				_fmt(delta),
				_fmt(total_damage),
				_fmt(enemy_hp_before),
				_fmt(enemy_hp_after)
			]
		"monster_attack":
			player_bar.value = float(payload.get("player_hp", player_bar.value))
			player_label.text = "Replay 玩家 HP：%s / %s" % [_fmt(player_bar.value), _fmt(player_bar.max_value)]
			damage_hint_label.text = "Replay 承伤：%s 造成 %s，玩家 HP %s" % [payload.get("enemy_name", ""), _fmt(payload.get("damage", 0.0)), _fmt(payload.get("player_hp", 0.0))]
			result_label.text = "Replay 事件 %s / %s\n来源：%s 普攻\n承伤：%s\n玩家 HP：%s" % [
				replay_index + 1,
				replay_events.size(),
				payload.get("enemy_name", ""),
				_fmt(payload.get("damage", 0.0)),
				_fmt(payload.get("player_hp", 0.0))
			]
		"use_item":
			damage_hint_label.text = "Replay 道具：%s，剩余 %s 次" % [payload.get("item_name", ""), payload.get("remaining_charges", 0)]
			result_label.text = "Replay 事件 %s / %s\n使用道具：%s\n剩余次数：%s" % [
				replay_index + 1,
				replay_events.size(),
				payload.get("item_name", ""),
				payload.get("remaining_charges", 0)
			]
		"room_reward":
			player_label.text = "Replay 获得：%s" % _item_detail_to_text(payload.get("picked_item_detail", {}))
			damage_hint_label.text = "Replay 奖励候选：%s" % " / ".join(payload.get("choices", []))
			result_label.text = "Replay 事件 %s / %s\n房间奖励：%s\n候选：%s" % [
				replay_index + 1,
				replay_events.size(),
				_item_detail_to_text(payload.get("picked_item_detail", {})),
				" / ".join(payload.get("choices", []))
			]
		"battle_end":
			player_bar.value = float(payload.get("player_hp", player_bar.value))
			result_label.text = "Replay 完成\n胜负：%s\n玩家 HP：%s\n总伤害：%s\n承受伤害：%s\nRooms Cleared：%s\n最终道具：%s" % [
				"胜利" if bool(payload.get("victory", false)) else "失败",
				_fmt(payload.get("player_hp", 0.0)),
				_fmt(payload.get("total_damage_done", 0.0)),
				_fmt(payload.get("total_damage_taken", 0.0)),
				payload.get("rooms_cleared", 0),
				"、".join(payload.get("player_items", []))
			]
	_append_replay_line(_event_to_replay_line(event))


func _append_replay_line(line: String) -> void:
	if line == "":
		return
	replay_log_lines.append(line)
	while replay_log_lines.size() > 90:
		replay_log_lines.pop_front()
	log_text.text = "\n".join(replay_log_lines)


func _event_to_replay_line(event: Dictionary) -> String:
	var payload: Dictionary = event.get("payload", {})
	var event_type = String(event.get("type", ""))
	var prefix = "[%03d time=%s turn=%s tick=%s room=%s] " % [
		int(event.get("index", 0)),
		_fmt(event.get("time", 0.0)),
		event.get("turn", 0),
		event.get("tick", 0),
		event.get("room_index", 0)
	]
	match event_type:
		"log":
			return prefix + String(payload.get("message", ""))
		"stage_start":
			return prefix + "进入房间：" + String(payload.get("stage_name", ""))
		"enemy_spawn":
			return prefix + "敌人登场：%s HP %s/%s" % [
				payload.get("enemy_name", ""),
				_fmt(payload.get("enemy_hp", 0.0)),
				_fmt(payload.get("enemy_max_hp", 0.0))
			]
		"cast_skill":
			return prefix + "释放技能：%s，能量 %s" % [payload.get("skill_name", ""), _fmt(payload.get("player_energy", 0.0))]
		"damage":
			return prefix + "%s%s -> %s，单次 %s，累计 %s，敌人 HP %s/%s" % [
				payload.get("source", ""),
				" 暴击" if bool(payload.get("critical", false)) else "",
				payload.get("enemy_name", ""),
				_fmt(payload.get("delta", payload.get("damage", 0.0))),
				_fmt(payload.get("total_damage", payload.get("damage", 0.0))),
				_fmt(payload.get("enemy_hp", 0.0)),
				_fmt(payload.get("enemy_max_hp", 0.0))
			]
		"monster_attack":
			return prefix + "%s 普攻，承伤 %s，玩家 HP %s" % [
				payload.get("enemy_name", ""),
				_fmt(payload.get("damage", 0.0)),
				_fmt(payload.get("player_hp", 0.0))
			]
		"use_item":
			return prefix + "使用道具：%s，剩余 %s" % [payload.get("item_name", ""), payload.get("remaining_charges", 0)]
		"room_reward":
			return prefix + "房间奖励：" + _item_detail_to_text(payload.get("picked_item_detail", {}))
		"battle_end":
			return prefix + "战斗结束：%s，总伤害 %s，承伤 %s" % [
				"胜利" if bool(payload.get("victory", false)) else "失败",
				_fmt(payload.get("total_damage_done", 0.0)),
				_fmt(payload.get("total_damage_taken", 0.0))
			]
		_:
			return prefix + event_type


func _export_last_result_json() -> String:
	# 结果文件保留完整复盘证据：
	# 日志、警告、伤害曲线、回放事件、最终道具和汇总数值都会写进去。
	last_result["export_meta"] = _make_export_meta("json")
	var file = FileAccess.open(EXPORT_JSON, FileAccess.WRITE)
	if file == null:
		_show_error("导出失败：" + error_string(FileAccess.get_open_error()))
		return ""
	file.store_string(JSON.stringify(last_result, "\t", false))
	file.flush()
	var archive_path = _archive_export_copy(EXPORT_JSON, "json")
	if archive_path != "":
		last_result["export_meta"]["json_archive_path"] = ProjectSettings.globalize_path(archive_path)
		file = FileAccess.open(EXPORT_JSON, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(last_result, "\t", false))
			file.flush()
	return archive_path


func _archive_export_copy(source_path: String, extension: String) -> String:
	# “最新结果”方便界面直接回放。
	# 归档副本会保存每次实验，避免多轮调参时互相覆盖。
	var dir = DirAccess.open("user://")
	if dir == null:
		return ""
	if not dir.dir_exists("exports"):
		var err = dir.make_dir("exports")
		if err != OK:
			return ""
	var archive_path = "%s/%s.%s" % [EXPORT_ARCHIVE_DIR, _export_file_stem(), extension]
	var bytes = FileAccess.get_file_as_bytes(source_path)
	if bytes.is_empty():
		return ""
	var out = FileAccess.open(archive_path, FileAccess.WRITE)
	if out == null:
		return ""
	out.store_buffer(bytes)
	out.flush()
	return archive_path


func _make_export_meta(kind: String) -> Dictionary:
	return {
		"kind": kind,
		"created_at": Time.get_datetime_string_from_system(false, true),
		"latest_json": ProjectSettings.globalize_path(EXPORT_JSON),
		"latest_single_csv": ProjectSettings.globalize_path(EXPORT_RESULT_CSV),
		"latest_batch_csv": ProjectSettings.globalize_path(EXPORT_BATCH_CSV),
		"latest_compare_csv": ProjectSettings.globalize_path(EXPORT_COMPARE_CSV),
		"archive_dir": ProjectSettings.globalize_path(EXPORT_ARCHIVE_DIR)
	}


func _export_file_stem() -> String:
	var stamp = Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")
	var result_type = String(last_result.get("type", "single"))
	var strategy_id = String(last_result.get("strategy_id", last_result.get("summary", {}).get("strategy_id", "compare")))
	var mode_text = String(last_result.get("mode", last_result.get("summary", {}).get("mode", selected_mode)))
	var seed_text = str(last_result.get("seed", last_result.get("base_seed", last_result.get("summary", {}).get("base_seed", 0))))
	var runs_text = str(last_result.get("runs_per_strategy", last_result.get("summary", {}).get("runs", 1)))
	return _safe_filename("%s_%s_%s_%s_seed%s_runs%s" % [stamp, result_type, strategy_id, mode_text, seed_text, runs_text])


func _safe_filename(text: String) -> String:
	var result = text
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " "]:
		result = result.replace(ch, "_")
	return result

func _update_selection() -> void:
	selected_strategy_id = String(strategy_option.get_selected_metadata())
	selected_mode = String(mode_option.get_selected_metadata())


func _handle_command_line() -> void:
	# 命令行参数让项目不依赖界面点击也能验证。
	# 这里和面板走同一条模拟器路径，所以冒烟测试和手动运行覆盖的是同一套核心实现。
	var args = _all_cmdline_args()
	var base_seed = _seed_from_args(args)
	if _has_flag(args, "--smoke-turn"):
		selected_mode = "turn_based"
		selected_strategy_id = "crit_strategy"
		last_result = _run_once(selected_strategy_id, selected_mode, base_seed)
		_render_result(last_result)
		_export_last_result_json()
		print("SMOKE turn_based seed=%s victory=%s turns=%s" % [last_result.get("seed", base_seed), last_result.get("victory", false), last_result.get("turns", 0)])
		return
	if _has_flag(args, "--smoke-tick"):
		selected_mode = "realtime"
		selected_strategy_id = "crit_strategy"
		last_result = _run_once(selected_strategy_id, selected_mode, base_seed)
		_render_result(last_result)
		_export_last_result_json()
		print("SMOKE realtime seed=%s victory=%s ticks=%s seconds=%s" % [last_result.get("seed", base_seed), last_result.get("victory", false), last_result.get("ticks", 0), _fmt(last_result.get("seconds", 0.0))])
		return
	if _has_flag(args, "--smoke-replay"):
		selected_mode = "turn_based"
		selected_strategy_id = "crit_strategy"
		last_result = _run_once(selected_strategy_id, selected_mode, base_seed)
		_export_last_result_json()
		var replay_result = _load_replay_result()
		if replay_result.is_empty():
			print("SMOKE replay ok=false events=0")
			return
		_begin_replay(replay_result)
		var sample_events = _sample_replay_events(replay_events)
		replay_log_lines.clear()
		for event in sample_events:
			_apply_replay_event(event)
		replay_active = false
		print("SMOKE replay ok=%s events=%s lines=%s" % [
			not sample_events.is_empty(),
			replay_events.size(),
			replay_log_lines.size()
		])
		return
	if _has_flag(args, "--single-sim"):
		selected_strategy_id = _normalize_strategy_id(_arg_value(args, "--strategy", "crit_strategy"))
		selected_mode = _normalize_mode(_arg_value(args, "--mode", "turn_based"))
		last_result = _run_once(selected_strategy_id, selected_mode, base_seed)
		_render_result(last_result)
		var csv_archive = _export_single_csv(last_result)
		if csv_archive != "":
			last_result["csv_archive_path"] = ProjectSettings.globalize_path(csv_archive)
		var json_archive = _export_last_result_json()
		print("SINGLE strategy=%s mode=%s seed=%s victory=%s time=%s hp=%s damage=%s csv=%s csv_archive=%s json=%s json_archive=%s" % [
			last_result.get("strategy_id", ""),
			last_result.get("mode", ""),
			last_result.get("seed", base_seed),
			last_result.get("victory", false),
			_fmt(_result_time(last_result)),
			_fmt(last_result.get("player_hp", 0.0)),
			_fmt(last_result.get("total_damage_done", 0.0)),
			ProjectSettings.globalize_path(EXPORT_RESULT_CSV),
			ProjectSettings.globalize_path(csv_archive) if csv_archive != "" else "",
			ProjectSettings.globalize_path(EXPORT_JSON),
			ProjectSettings.globalize_path(json_archive) if json_archive != "" else ""
		])
		return
	if _has_flag(args, "--batch-sim") or _has_flag(args, "--smoke-batch"):
		selected_strategy_id = _normalize_strategy_id(_arg_value(args, "--strategy", "crit_strategy"))
		selected_mode = _normalize_mode(_arg_value(args, "--mode", "turn_based"))
		var runs = int(_arg_value(args, "--runs", "30"))
		if _has_flag(args, "--smoke-batch"):
			runs = int(_arg_value(args, "--runs", "5"))
		runs = clamp(runs, 1, 1000)
		var result = _run_batch(runs, base_seed)
		var summary: Dictionary = result.get("summary", {})
		print("BATCH strategy=%s mode=%s base_seed=%s runs=%s wins=%s win_rate=%s average_time=%s average_hp=%s average_taken=%s elapsed_ms=%s runs_per_second=%s csv=%s json=%s" % [
			summary.get("strategy_id", ""),
			summary.get("mode", ""),
			summary.get("base_seed", base_seed),
			summary.get("runs", 0),
			summary.get("wins", 0),
			_fmt(summary.get("win_rate", 0.0)),
			_fmt(summary.get("average_time", 0.0)),
			_fmt(summary.get("average_player_hp", 0.0)),
			_fmt(summary.get("average_damage_taken", 0.0)),
			summary.get("elapsed_ms", 0),
			_fmt(summary.get("runs_per_second", 0.0)),
			ProjectSettings.globalize_path(EXPORT_BATCH_CSV),
			ProjectSettings.globalize_path(EXPORT_JSON)
		])
	if _has_flag(args, "--compare-strategies"):
		selected_mode = _normalize_mode(_arg_value(args, "--mode", "turn_based"))
		var compare_runs = clamp(int(_arg_value(args, "--runs", "30")), 1, 1000)
		var compare = _run_strategy_compare(compare_runs, base_seed)
		var parts: Array[String] = []
		for summary in compare.get("summaries", []):
			parts.append("%s win_rate=%s average_time=%s average_hp=%s average_taken=%s rps=%s" % [
				summary.get("strategy_id", ""),
				_fmt(summary.get("win_rate", 0.0)),
				_fmt(summary.get("average_time", 0.0)),
				_fmt(summary.get("average_player_hp", 0.0)),
				_fmt(summary.get("average_damage_taken", 0.0)),
				_fmt(summary.get("runs_per_second", 0.0))
			])
		print("COMPARE mode=%s base_seed=%s runs=%s elapsed_ms=%s runs_per_second=%s %s csv=%s json=%s" % [
			selected_mode,
			compare.get("base_seed", base_seed),
			compare_runs,
			compare.get("elapsed_ms", 0),
			_fmt(compare.get("runs_per_second", 0.0)),
			" | ".join(parts),
			ProjectSettings.globalize_path(EXPORT_COMPARE_CSV),
			ProjectSettings.globalize_path(EXPORT_JSON)
		])


func _all_cmdline_args() -> Array[String]:
	# 两类参数都要读取：
	# Godot 自己的启动参数，以及 `--` 后面的项目参数，会进入不同数组。
	var result: Array[String] = []
	for arg in OS.get_cmdline_args():
		result.append(String(arg))
	for arg in OS.get_cmdline_user_args():
		result.append(String(arg))
	return result


func _has_flag(args: Array[String], key: String) -> bool:
	for arg in args:
		var text = String(arg).strip_edges()
		if text == key or text.begins_with(key + "="):
			return true
		for part in text.split(" ", false):
			var token = String(part).strip_edges()
			if token == key or token.begins_with(key + "="):
				return true
	return false


func _arg_value(args: Array[String], key: String, default_value: String) -> String:
	var prefix = key + "="
	for arg in args:
		var text = String(arg).strip_edges()
		if text.begins_with(prefix):
			return text.substr(prefix.length())
		for part in text.split(" ", false):
			var token = String(part).strip_edges()
			if token.begins_with(prefix):
				return token.substr(prefix.length())
	return default_value


func _seed_from_args(args: Array[String]) -> int:
	var raw = _arg_value(args, "--seed", "")
	if raw == "":
		return Time.get_ticks_usec()
	if not raw.is_valid_int():
		push_warning("--seed 必须是整数，已回退为时间种子。")
		return Time.get_ticks_usec()
	return max(0, int(raw))


func _normalize_strategy_id(value: String) -> String:
	if strategy_scripts.has(value):
		return value
	match value:
		"crit", "crit_strategy":
			return "crit_strategy"
		"burn", "burn_strategy":
			return "burn_strategy"
		"summon", "summon_strategy":
			return "summon_strategy"
		_:
			return "crit_strategy"


func _normalize_mode(value: String) -> String:
	match value:
		"realtime", "tick":
			return "realtime"
		_:
			return "turn_based"


func _run_once(strategy_id: String, run_mode: String, seed_value: int) -> Dictionary:
	# 单场运行的边界很清楚：
	# 这里创建选中的策略对象，把它交给战斗模拟器；
	# 模拟器之后只通过公开的策略接口调用它。
	if not strategy_scripts.has(strategy_id):
		return {
			"strategy_id": strategy_id,
			"mode": run_mode,
			"victory": false,
			"error": "策略未注册：" + strategy_id,
			"logs": ["策略未注册：" + strategy_id],
			"warnings": ["策略未注册：" + strategy_id]
		}
	var strategy = strategy_scripts[strategy_id].new()
	var simulator = CombatSimulatorScript.new()
	simulator.setup(config, strategy, run_mode, seed_value)
	return simulator.run()


func _summarize_batch(results: Array[Dictionary]) -> Dictionary:
	# 这些统计字段就是设计问题的回答：
	# 不只看谁赢，还要看通关速度、生存能力、输出、承伤和复盘数据量。
	var wins = 0
	var total_time = 0.0
	var total_turns = 0.0
	var total_ticks = 0.0
	var total_seconds = 0.0
	var total_hp = 0.0
	var total_damage = 0.0
	var total_taken = 0.0
	var total_replay_events = 0.0
	for result in results:
		if bool(result.get("victory", false)):
			wins += 1
		total_time += _result_time(result)
		total_turns += float(result.get("turns", 0.0))
		total_ticks += float(result.get("ticks", 0.0))
		total_seconds += float(result.get("seconds", 0.0))
		total_hp += float(result.get("player_hp", 0.0))
		total_damage += float(result.get("total_damage_done", 0.0))
		total_taken += float(result.get("total_damage_taken", 0.0))
		total_replay_events += float(result.get("replay_events", []).size())
	var count = max(1, results.size())
	return {
		"strategy_id": selected_strategy_id,
		"mode": selected_mode,
		"runs": results.size(),
		"wins": wins,
		"win_rate": float(wins) / float(count),
		"average_time": total_time / float(count),
		"average_turns": total_turns / float(count),
		"average_ticks": total_ticks / float(count),
		"average_seconds": total_seconds / float(count),
		"average_player_hp": total_hp / float(count),
		"average_damage_done": total_damage / float(count),
		"average_damage_taken": total_taken / float(count),
		"average_replay_events": total_replay_events / float(count)
	}


func _attach_batch_metadata(summary: Dictionary, results: Array[Dictionary], base_seed: int, elapsed_ms: int) -> void:
	var count = results.size()
	summary["base_seed"] = base_seed
	summary["first_seed"] = base_seed
	summary["last_seed"] = base_seed
	if count > 0:
		summary["first_seed"] = results[0].get("seed", base_seed)
		summary["last_seed"] = results[count - 1].get("seed", base_seed)
	summary["elapsed_ms"] = elapsed_ms
	summary["runs_per_second"] = float(count) * 1000.0 / float(max(1, elapsed_ms))


func _render_result(result: Dictionary) -> void:
	_hide_compare_chart()
	_stop_replay()
	var player_hp = float(result.get("player_hp", 0.0))
	var player_max_hp = max(1.0, float(result.get("player_max_hp", 1.0)))
	player_bar.max_value = player_max_hp
	player_bar.value = player_hp
	player_label.text = "玩家 HP：%s / %s" % [_fmt(player_hp), _fmt(player_max_hp)]
	enemy_bar.max_value = 1
	enemy_bar.value = 0
	enemy_label.text = "敌人：本场已结束"
	result_label.text = "胜负：%s\n模式：%s\n回合数：%s\nTick 数：%s\n秒数：%s\n剩余 HP：%s\n总伤害：%s\n承受伤害：%s\n技能次数：%s\n道具次数：%s\n最终道具/词条：%s\nReplay 事件：%s" % [
		"胜利" if result.get("victory", false) else "失败",
		"实时 Tick 制" if result.get("mode", "") == "realtime" else "回合制",
		result.get("turns", 0),
		result.get("ticks", 0),
		_fmt(result.get("seconds", 0.0)),
		_fmt(player_hp),
		_fmt(result.get("total_damage_done", 0.0)),
		_fmt(result.get("total_damage_taken", 0.0)),
		str(result.get("skill_cast_counts", {})),
		str(result.get("item_use_counts", {})),
		_item_details_to_text(result.get("player_item_details", []), result.get("player_item_names", [])),
		result.get("replay_events", []).size()
	]
	log_text.text = "\n".join(result.get("logs", []))
	curve_graph.set_curve(result.get("damage_curve", []), "累计伤害：%s" % _fmt(result.get("total_damage_done", 0.0)))
	curve_text.text = _curve_to_text(result.get("damage_curve", []))
	damage_hint_label.text = _recent_damage_hint(result)
	status_label.text = "单场模拟完成。"


func _render_batch(summary: Dictionary, results: Array[Dictionary]) -> void:
	_hide_compare_chart()
	_stop_replay()
	player_bar.max_value = 1
	player_bar.value = summary.get("win_rate", 0.0)
	player_label.text = "批量胜率：%d%%" % int(float(summary.get("win_rate", 0.0)) * 100.0)
	enemy_bar.max_value = 1
	enemy_bar.value = 0
	enemy_label.text = "批量模拟"
	result_label.text = "批量模拟：%s 次\nBase Seed：%s\n胜场：%s\n胜率：%d%%\n平均耗时：%s\n平均回合/Tick/秒：%s / %s / %s\n平均剩余 HP：%s\n平均总伤害：%s\n平均承伤：%s\n平均 Replay 事件：%s\n模拟器耗时：%s ms\n吞吐：%s runs/s" % [
		summary.get("runs", 0),
		summary.get("base_seed", 0),
		summary.get("wins", 0),
		int(float(summary.get("win_rate", 0.0)) * 100.0),
		_fmt(summary.get("average_time", 0.0)),
		_fmt(summary.get("average_turns", 0.0)),
		_fmt(summary.get("average_ticks", 0.0)),
		_fmt(summary.get("average_seconds", 0.0)),
		_fmt(summary.get("average_player_hp", 0.0)),
		_fmt(summary.get("average_damage_done", 0.0)),
		_fmt(summary.get("average_damage_taken", 0.0)),
		_fmt(summary.get("average_replay_events", 0.0)),
		summary.get("elapsed_ms", 0),
		_fmt(summary.get("runs_per_second", 0.0))
	]
	var lines: Array[String] = []
	for i in range(min(20, results.size())):
		var result = results[i]
		lines.append("#%d seed=%s %s time=%s hp=%s dmg=%s" % [
			i + 1,
			result.get("seed", 0),
			"WIN" if result.get("victory", false) else "LOSE",
			_fmt(_result_time(result)),
			_fmt(result.get("player_hp", 0.0)),
			_fmt(result.get("total_damage_done", 0.0))
	])
	log_text.text = "\n".join(lines)
	curve_graph.clear_curve("批量模拟不绘制单场曲线")
	curve_text.text = "批量结果已导出 CSV：\n" + ProjectSettings.globalize_path(EXPORT_BATCH_CSV)
	damage_hint_label.text = "伤害提示：批量模拟完成，详见结果与 CSV。"
	status_label.text = "批量模拟完成。"


func _render_strategy_compare(summaries: Array[Dictionary], runs: int) -> void:
	# 图表故意做得很小，直接回答策划问题：
	# 哪个流派最快、最安全、最稳定？
	_stop_replay()
	player_bar.max_value = 1
	player_bar.value = 0
	enemy_bar.max_value = 1
	enemy_bar.value = 0
	player_label.text = "三流派对照"
	enemy_label.text = "同关卡 / 同种子序列"
	var base_seed = 0
	if not summaries.is_empty():
		base_seed = int(summaries[0].get("base_seed", 0))
	var lines: Array[String] = [
		"对照运行：每个流派 %d 次" % runs,
		"Base Seed：%s" % base_seed
	]
	var log_lines: Array[String] = []
	for summary in summaries:
		var line = "%s  胜率:%d%%  平均耗时:%s  平均HP:%s  平均伤害:%s  平均承伤:%s  吞吐:%s/s" % [
			_strategy_display_name(summary.get("strategy_id", "")),
			int(float(summary.get("win_rate", 0.0)) * 100.0),
			_fmt(summary.get("average_time", 0.0)),
			_fmt(summary.get("average_player_hp", 0.0)),
			_fmt(summary.get("average_damage_done", 0.0)),
			_fmt(summary.get("average_damage_taken", 0.0)),
			_fmt(summary.get("runs_per_second", 0.0))
		]
		lines.append(line)
		log_lines.append(line)
	result_label.text = "\n".join(lines)
	log_text.text = "\n".join(log_lines)
	_render_compare_chart(summaries)
	curve_graph.clear_curve("三流派对照不绘制单场曲线")
	curve_text.text = "三流派对照 CSV：\n" + ProjectSettings.globalize_path(EXPORT_COMPARE_CSV)
	damage_hint_label.text = "伤害提示：对照运行使用同一关卡和同一批随机种子。"
	status_label.text = "三流派对照完成。"


func _render_compare_chart(summaries: Array[Dictionary]) -> void:
	_clear_compare_chart()
	compare_chart_panel.visible = true
	var title = Label.new()
	title.text = "可视化对比：胜率 / 平均耗时 / 平均剩余 HP"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	compare_chart_box.add_child(title)
	var max_time = 1.0
	var max_hp = 1.0
	for summary in summaries:
		max_time = max(max_time, float(summary.get("average_time", 0.0)))
		max_hp = max(max_hp, float(summary.get("average_player_hp", 0.0)))
	for summary in summaries:
		var strategy_id = String(summary.get("strategy_id", ""))
		var color = _strategy_color(strategy_id)
		var name_label = Label.new()
		name_label.text = _strategy_display_name(strategy_id)
		compare_chart_box.add_child(name_label)
		compare_chart_box.add_child(_make_compare_bar("胜率", float(summary.get("win_rate", 0.0)), 1.0, "%d%%" % int(float(summary.get("win_rate", 0.0)) * 100.0), color))
		compare_chart_box.add_child(_make_compare_bar("耗时", float(summary.get("average_time", 0.0)), max_time, _fmt(summary.get("average_time", 0.0)), color))
		compare_chart_box.add_child(_make_compare_bar("HP", float(summary.get("average_player_hp", 0.0)), max_hp, _fmt(summary.get("average_player_hp", 0.0)), color))


func _make_compare_bar(label_text: String, value: float, max_value: float, value_text: String, color: Color) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	var label = Label.new()
	label.custom_minimum_size = Vector2(46, 0)
	label.text = label_text
	row.add_child(label)
	var bar_back = ColorRect.new()
	bar_back.custom_minimum_size = Vector2(150, 14)
	bar_back.color = Color(0.18, 0.19, 0.20)
	row.add_child(bar_back)
	var bar = ColorRect.new()
	var ratio = clamp(value / max(0.01, max_value), 0.0, 1.0)
	bar.custom_minimum_size = Vector2(max(4.0, 150.0 * ratio), 14)
	bar.size = bar.custom_minimum_size
	bar.color = color
	bar_back.add_child(bar)
	var value_label = Label.new()
	value_label.text = value_text
	row.add_child(value_label)
	return row


func _clear_compare_chart() -> void:
	for child in compare_chart_box.get_children():
		child.queue_free()


func _hide_compare_chart() -> void:
	if compare_chart_panel == null:
		return
	compare_chart_panel.visible = false
	_clear_compare_chart()


func _curve_to_text(curve: Array) -> String:
	if curve.is_empty():
		return "暂无伤害曲线。"
	var lines = ["index,time,source,delta,total_damage,crit,target,target_hp,turn,tick,room"]
	var step = max(1, int(ceil(float(curve.size()) / 48.0)))
	for i in range(0, curve.size(), step):
		var point: Dictionary = curve[i]
		lines.append("%s,%s,%s,%s,%s,%s,%s,%s/%s,%s,%s,%s" % [
			point.get("index", i + 1),
			_fmt(point.get("time", 0.0)),
			String(point.get("source", "")),
			_fmt(point.get("delta", point.get("damage_delta", 0.0))),
			_fmt(point.get("damage", point.get("total_damage", 0.0))),
			"Y" if bool(point.get("critical", false)) else "N",
			String(point.get("enemy_name", "")),
			_fmt(point.get("enemy_hp", 0.0)),
			_fmt(point.get("enemy_max_hp", 0.0)),
			point.get("turn", 0),
			point.get("tick", 0),
			point.get("room_index", 0)
		])
	if step > 1:
		lines.append("# sampled_every=%s,total_points=%s" % [step, curve.size()])
	return "\n".join(lines)


func _recent_damage_hint(result: Dictionary) -> String:
	var logs: Array = result.get("logs", [])
	var picked: Array[String] = []
	for i in range(logs.size() - 1, -1, -1):
		var line = String(logs[i])
		if line.find("造成") >= 0 or line.find("释放") >= 0 or line.find("暴击") >= 0:
			picked.push_front(line)
		if picked.size() >= 4:
			break
	if picked.is_empty():
		return "伤害提示：本场没有伤害记录。"
	return "伤害提示：\n" + "\n".join(picked)


func _export_batch_csv(results: Array[Dictionary], summary: Dictionary) -> String:
	var file = FileAccess.open(EXPORT_BATCH_CSV, FileAccess.WRITE)
	if file == null:
		status_label.text = "CSV 导出失败：" + error_string(FileAccess.get_open_error())
		return ""
	file.store_line("strategy_id,mode,base_seed,first_seed,last_seed,runs,wins,win_rate,average_time,average_turns,average_ticks,average_seconds,average_player_hp,average_damage_done,average_damage_taken,average_replay_events,elapsed_ms,runs_per_second")
	file.store_line("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s" % [
		summary.get("strategy_id", ""),
		summary.get("mode", ""),
		summary.get("base_seed", 0),
		summary.get("first_seed", 0),
		summary.get("last_seed", 0),
		summary.get("runs", 0),
		summary.get("wins", 0),
		_fmt(summary.get("win_rate", 0.0)),
		_fmt(summary.get("average_time", 0.0)),
		_fmt(summary.get("average_turns", 0.0)),
		_fmt(summary.get("average_ticks", 0.0)),
		_fmt(summary.get("average_seconds", 0.0)),
		_fmt(summary.get("average_player_hp", 0.0)),
		_fmt(summary.get("average_damage_done", 0.0)),
		_fmt(summary.get("average_damage_taken", 0.0)),
		_fmt(summary.get("average_replay_events", 0.0)),
		summary.get("elapsed_ms", 0),
		_fmt(summary.get("runs_per_second", 0.0))
	])
	file.store_line("")
	file.store_line("run,seed,victory,turns,ticks,seconds,time,player_hp,total_damage_done,total_damage_taken,skill_cast_counts,item_use_counts,final_item_details,replay_event_count")
	for i in range(results.size()):
		var result = results[i]
		file.store_line("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s" % [
			i + 1,
			result.get("seed", 0),
			result.get("victory", false),
			result.get("turns", 0),
			result.get("ticks", 0),
			_fmt(result.get("seconds", 0.0)),
			_fmt(_result_time(result)),
			_fmt(result.get("player_hp", 0.0)),
			_fmt(result.get("total_damage_done", 0.0)),
			_fmt(result.get("total_damage_taken", 0.0)),
			_csv_value(JSON.stringify(result.get("skill_cast_counts", {}))),
			_csv_value(JSON.stringify(result.get("item_use_counts", {}))),
			_csv_value(_item_details_to_text(result.get("player_item_details", []), result.get("player_item_names", []))),
			result.get("replay_events", []).size()
		])
	file.flush()
	return _archive_export_copy(EXPORT_BATCH_CSV, "csv")


func _export_compare_csv(summaries: Array) -> String:
	var file = FileAccess.open(EXPORT_COMPARE_CSV, FileAccess.WRITE)
	if file == null:
		status_label.text = "CSV 导出失败：" + error_string(FileAccess.get_open_error())
		return ""
	file.store_line("strategy_id,display_name,mode,base_seed,first_seed,last_seed,runs,wins,win_rate,average_time,average_turns,average_ticks,average_seconds,average_player_hp,average_damage_done,average_damage_taken,average_replay_events,elapsed_ms,runs_per_second")
	for summary in summaries:
		file.store_line("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s" % [
			summary.get("strategy_id", ""),
			_csv_value(_strategy_display_name(summary.get("strategy_id", ""))),
			summary.get("mode", ""),
			summary.get("base_seed", 0),
			summary.get("first_seed", 0),
			summary.get("last_seed", 0),
			summary.get("runs", 0),
			summary.get("wins", 0),
			_fmt(summary.get("win_rate", 0.0)),
			_fmt(summary.get("average_time", 0.0)),
			_fmt(summary.get("average_turns", 0.0)),
			_fmt(summary.get("average_ticks", 0.0)),
			_fmt(summary.get("average_seconds", 0.0)),
			_fmt(summary.get("average_player_hp", 0.0)),
			_fmt(summary.get("average_damage_done", 0.0)),
			_fmt(summary.get("average_damage_taken", 0.0)),
			_fmt(summary.get("average_replay_events", 0.0)),
			summary.get("elapsed_ms", 0),
			_fmt(summary.get("runs_per_second", 0.0))
		])
	file.flush()
	return _archive_export_copy(EXPORT_COMPARE_CSV, "csv")


func _export_single_csv(result: Dictionary) -> String:
	var file = FileAccess.open(EXPORT_RESULT_CSV, FileAccess.WRITE)
	if file == null:
		status_label.text = "CSV 导出失败：" + error_string(FileAccess.get_open_error())
		return ""
	file.store_line("section,key,value")
	file.store_line("summary,strategy_id,%s" % _csv_value(result.get("strategy_id", "")))
	file.store_line("summary,mode,%s" % _csv_value(result.get("mode", "")))
	file.store_line("summary,seed,%s" % result.get("seed", 0))
	file.store_line("summary,victory,%s" % result.get("victory", false))
	file.store_line("summary,turns,%s" % result.get("turns", 0))
	file.store_line("summary,ticks,%s" % result.get("ticks", 0))
	file.store_line("summary,seconds,%s" % _fmt(result.get("seconds", 0.0)))
	file.store_line("summary,player_hp,%s" % _fmt(result.get("player_hp", 0.0)))
	file.store_line("summary,rooms_cleared,%s" % result.get("rooms_cleared", 0))
	file.store_line("summary,total_damage_done,%s" % _fmt(result.get("total_damage_done", 0.0)))
	file.store_line("summary,total_damage_taken,%s" % _fmt(result.get("total_damage_taken", 0.0)))
	file.store_line("summary,final_item_details,%s" % _csv_value(_item_details_to_text(result.get("player_item_details", []), result.get("player_item_names", []))))
	file.store_line("summary,replay_event_count,%s" % result.get("replay_events", []).size())
	for skill_id in result.get("skill_cast_counts", {}).keys():
		file.store_line("skill_cast_counts,%s,%s" % [_csv_value(skill_id), result["skill_cast_counts"][skill_id]])
	for item_id in result.get("item_use_counts", {}).keys():
		file.store_line("item_use_counts,%s,%s" % [_csv_value(item_id), result["item_use_counts"][item_id]])
	for detail in result.get("player_item_details", []):
		if typeof(detail) == TYPE_DICTIONARY:
			file.store_line("item_details,%s,%s" % [_csv_value(detail.get("id", "")), _csv_value(_item_detail_to_text(detail))])
	file.store_line("")
	file.store_line("curve_index,time,turn,tick,room,source,critical,delta,total_damage,enemy_name,enemy_hp_before,enemy_hp,enemy_max_hp,player_hp")
	var curve: Array = result.get("damage_curve", [])
	for i in range(curve.size()):
		var point: Dictionary = curve[i]
		file.store_line("%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s" % [
			i + 1,
			_fmt(point.get("time", 0.0)),
			point.get("turn", 0),
			point.get("tick", 0),
			point.get("room_index", 0),
			_csv_value(point.get("source", "")),
			point.get("critical", false),
			_fmt(point.get("delta", point.get("damage_delta", 0.0))),
			_fmt(point.get("damage", point.get("total_damage", 0.0))),
			_csv_value(point.get("enemy_name", "")),
			_fmt(point.get("enemy_hp_before", 0.0)),
			_fmt(point.get("enemy_hp", 0.0)),
			_fmt(point.get("enemy_max_hp", 0.0)),
			_fmt(point.get("player_hp", 0.0))
		])
	file.flush()
	return _archive_export_copy(EXPORT_RESULT_CSV, "csv")


func _item_details_to_text(details: Array, fallback_names: Array = []) -> String:
	var parts: Array[String] = []
	for detail in details:
		if typeof(detail) == TYPE_DICTIONARY:
			parts.append(_item_detail_to_text(detail))
	if parts.is_empty():
		for item_name in fallback_names:
			parts.append(String(item_name))
	return "、".join(parts) if not parts.is_empty() else "无"


func _item_detail_to_text(detail: Dictionary) -> String:
	if detail.is_empty():
		return "无"
	var text = String(detail.get("name", detail.get("id", "")))
	var affix_names: Array[String] = []
	for affix in detail.get("affixes", []):
		if typeof(affix) != TYPE_DICTIONARY:
			continue
		var affix_name = String(affix.get("name", affix.get("id", "")))
		if affix_name != "":
			affix_names.append(affix_name)
	if not affix_names.is_empty():
		text += " [" + " / ".join(affix_names) + "]"
	return text


func _result_time(result: Dictionary) -> float:
	if result.get("mode", "") == "realtime":
		return float(result.get("seconds", 0.0))
	return float(result.get("turns", 0))


func _show_error(message: String) -> void:
	_hide_compare_chart()
	if curve_graph != null:
		curve_graph.clear_curve("暂无伤害曲线")
	status_label.text = message
	log_text.text = message
	result_label.text = "错误"


func _strategy_display_name(strategy_id: String) -> String:
	match strategy_id:
		"crit_strategy":
			return "裂芯暴击流"
		"burn_strategy":
			return "余火持续输出流"
		"summon_strategy":
			return "余烬召唤流"
		_:
			return strategy_id


func _strategy_color(strategy_id: String) -> Color:
	match strategy_id:
		"crit_strategy":
			return Color(0.95, 0.38, 0.20)
		"burn_strategy":
			return Color(0.95, 0.70, 0.18)
		"summon_strategy":
			return Color(0.20, 0.72, 0.90)
		_:
			return Color(0.70, 0.70, 0.70)


func _fmt(value: Variant) -> String:
	return "%.1f" % float(value)


func _csv_value(value: Variant) -> String:
	var text = String(value)
	if text.find(",") >= 0 or text.find("\"") >= 0 or text.find("\n") >= 0:
		return "\"" + text.replace("\"", "\"\"") + "\""
	return text


func _validate_unique_ids(entries: Array, label: String) -> String:
	var seen = {}
	for entry in entries:
		var entry_id = String(entry.get("id", ""))
		if entry_id == "":
			return label + " 中存在空 id"
		if seen.has(entry_id):
			return label + " 中存在重复 id: " + entry_id
		seen[entry_id] = true
	return ""


func _collect_ids(entries: Array) -> Dictionary:
	var ids = {}
	for entry in entries:
		ids[String(entry.get("id", ""))] = true
	return ids


func _validate_non_negative_numbers(values: Dictionary, path: String, skip_keys: Array) -> String:
	for key in values.keys():
		var key_name = String(key)
		if skip_keys.has(key_name):
			continue
		if typeof(values[key]) in [TYPE_INT, TYPE_FLOAT] and float(values[key]) < 0.0:
			return path + "." + key_name + " 不能为负数"
	return ""


func _sum_numeric_dict(values: Dictionary) -> float:
	var total = 0.0
	for key in values.keys():
		total += float(values.get(key, 0.0))
	return total


func _configured_compare_strategy_ids() -> Array[String]:
	var result: Array[String] = []
	var seen = {}
	for preset in config.get("build_presets", []):
		var strategy_id = String(preset.get("strategy_id", ""))
		if strategy_id == "" or seen.has(strategy_id) or not strategy_scripts.has(strategy_id):
			continue
		seen[strategy_id] = true
		result.append(strategy_id)
	if result.is_empty():
		result = ["crit_strategy", "burn_strategy", "summon_strategy"]
	return result
