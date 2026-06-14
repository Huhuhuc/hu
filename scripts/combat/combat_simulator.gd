class_name CombatSimulator
extends RefCounted

var config: Dictionary
var strategy
var mode = "turn_based"
var rng = RandomNumberGenerator.new()
var logs: Array[String] = []
var warnings: Array[String] = []
var damage_curve: Array = []
var player: Dictionary = {}
var current_enemy: Dictionary = {}
var enemy_queue: Array = []
var skills_by_id: Dictionary = {}
var items_by_id: Dictionary = {}
var monsters_by_id: Dictionary = {}
var skill_cast_counts: Dictionary = {}
var item_use_counts: Dictionary = {}
var replay_events: Array = []
var total_damage_done = 0.0
var total_damage_taken = 0.0
var elapsed = 0.0
var turn = 0
var tick = 0
var room_index = 0
var rooms_cleared = 0
var run_seed = 0


func setup(p_config: Dictionary, p_strategy: Object, p_mode: String, seed_value: int) -> void:
	config = p_config
	strategy = p_strategy
	mode = p_mode
	rng.seed = seed_value
	run_seed = seed_value
	logs.clear()
	warnings.clear()
	damage_curve.clear()
	replay_events.clear()
	skills_by_id = _index_by_id(config.get("skills", []))
	items_by_id = _index_by_id(config.get("items", []))
	monsters_by_id = _index_by_id(config.get("monsters", []))
	skill_cast_counts.clear()
	item_use_counts.clear()
	total_damage_done = 0.0
	total_damage_taken = 0.0
	elapsed = 0.0
	turn = 0
	tick = 0
	room_index = 0
	rooms_cleared = 0


func run() -> Dictionary:
	var characters: Array = config.get("characters", [])
	var stages: Array = config.get("stages", [])
	if characters.is_empty() or stages.is_empty():
		return _error_result("配置缺少角色或关卡。")
	var character: Dictionary = characters[0]
	var full_stage: Dictionary = _combine_stages(stages)
	var preset = _find_build_preset(strategy.get_strategy_id())
	var requested_build: Dictionary = {}
	if strategy.has_method("choose_initial_build"):
		requested_build = strategy.choose_initial_build({
		"schema_version": config.get("schema_version", "unknown"),
		"mode": mode,
		"character": character,
		"available_items": config.get("items", []),
		"stage": full_stage,
		"rules": config.get("game", {}),
		"build_preset": preset.duplicate(true)
	})
	var build = _resolve_initial_build(preset, requested_build)
	var build_error = _validate_initial_build(character, build)
	if build_error != "" and not preset.is_empty():
		_warn("策略返回的初始构筑非法，回退到配置 preset：" + build_error)
		build = _make_build_from_preset(preset)
		build_error = _validate_initial_build(character, build)
	if build_error != "":
		return _error_result("初始构筑非法：" + build_error)
	player = _make_player(character, build)
	_log("策略：" + strategy.get_strategy_id() + "；模式：" + mode)
	_log("初始构筑：" + str(build.get("stat_points", {})) + " / " + str(build.get("item_ids", [])))
	for i in range(stages.size()):
		if float(player.get("hp", 0.0)) <= 0.0:
			break
		room_index = i
		_start_stage(stages[i], i)
		if mode == "realtime":
			_run_realtime()
		else:
			_run_turn_based()
		if _battle_continues():
			_warn("房间未能在限制内完成：" + stages[i].get("name", str(i + 1)))
			break
		if float(player.get("hp", 0.0)) <= 0.0:
			break
		rooms_cleared += 1
		if i < stages.size() - 1:
			_claim_room_reward(i, stages[i])
	return _make_result()


func _combine_stages(stages: Array) -> Dictionary:
	var combined = {
		"id": "all_stages",
		"name": "全关卡",
		"waves": []
	}
	for stage in stages:
		for wave in stage.get("waves", []):
			combined["waves"].append(wave)
	return combined


func _start_stage(stage: Dictionary, index: int) -> void:
	enemy_queue = _expand_enemy_queue(stage)
	current_enemy = {}
	_log("进入房间 %d/%d：%s" % [index + 1, config.get("stages", []).size(), stage.get("name", "")])
	_record_event("stage_start", {"stage_name": stage.get("name", ""), "stage_index": index})
	_spawn_next_enemy()


func _run_turn_based() -> void:
	var max_turns = int(config.get("game", {}).get("max_turns", 80))
	var start_turn = turn
	while _battle_continues() and turn - start_turn < max_turns:
		turn += 1
		elapsed = float(turn)
		_log("--- 回合 " + str(turn) + " ---")
		_process_burn_damage()
		_tick_enemy_status(1.0)
		if not _battle_continues():
			break
		var player_first = float(player["stats"].get("speed", 0.0)) >= float(current_enemy["stats"].get("speed", 0.0))
		if player_first:
			_player_action()
			_summons_action()
			if _current_enemy_alive():
				_monster_action()
		else:
			_monster_action()
			if float(player["hp"]) > 0.0:
				_player_action()
				_summons_action()
		_tick_cooldowns(1.0)
		_tick_summon_duration(1.0)
		_spawn_next_enemy_if_needed()


func _run_realtime() -> void:
	var game: Dictionary = config.get("game", {})
	var tick_seconds = float(game.get("tick_seconds", 0.1))
	var max_seconds = float(game.get("max_seconds", 120.0))
	var start_elapsed = elapsed
	var player_interval = max(0.35, 10.0 / max(1.0, float(player["stats"].get("speed", 10.0))))
	var enemy_interval = 1.0
	var player_timer = 0.0
	var enemy_timer = 0.0
	var summon_timer = 0.0
	var burn_timer = 0.0
	while _battle_continues() and elapsed - start_elapsed < max_seconds:
		tick += 1
		elapsed += tick_seconds
		player_timer -= tick_seconds
		enemy_timer -= tick_seconds
		summon_timer -= tick_seconds
		burn_timer -= tick_seconds
		_tick_cooldowns(tick_seconds)
		_tick_summon_duration(tick_seconds)
		_tick_enemy_status(tick_seconds)
		if burn_timer <= 0.0:
			_process_burn_damage()
			burn_timer += 1.0
		if player_timer <= 0.0 and _battle_continues():
			_player_action()
			player_timer += player_interval
		if summon_timer <= 0.0 and _battle_continues():
			_summons_action()
			summon_timer += 1.0
		if enemy_timer <= 0.0 and _current_enemy_alive():
			_monster_action()
			enemy_interval = max(0.45, 10.0 / max(1.0, float(current_enemy["stats"].get("speed", 8.0))))
			enemy_timer += enemy_interval
		_spawn_next_enemy_if_needed()


func _make_player(character: Dictionary, build: Dictionary) -> Dictionary:
	var stats: Dictionary = character.get("base_stats", {}).duplicate(true)
	var growth: Dictionary = character.get("stat_growth", {})
	for stat_name in build.get("stat_points", {}).keys():
		stats[stat_name] = float(stats.get(stat_name, 0.0)) + float(growth.get(stat_name, 0.0)) * float(build["stat_points"][stat_name])
	var item_ids: Array = build.get("item_ids", []).duplicate()
	var summon_limit = 2
	var item_charges = {}
	var item_runtime = {}
	for item_id in item_ids:
		var runtime = _make_item_runtime(items_by_id.get(String(item_id), {}))
		item_runtime[String(item_id)] = runtime
		for effect in runtime.get("effects", []):
			match effect.get("type", ""):
				"stat_add":
					var stat = String(effect.get("stat", ""))
					stats[stat] = float(stats.get(stat, 0.0)) + float(effect.get("value", 0.0))
				"summon_limit_add":
					summon_limit += int(effect.get("value", 0))
		if _item_has_active_effect(runtime):
			item_charges[item_id] = int(runtime.get("charges", 1))
			item_use_counts[item_id] = 0
	var p = {
		"id": character.get("id", "player"),
		"name": character.get("name", "Player"),
		"hp": float(stats.get("max_hp", 100.0)),
		"max_hp": float(stats.get("max_hp", 100.0)),
		"energy": float(config.get("game", {}).get("starting_energy", 3)),
		"max_energy": float(config.get("game", {}).get("max_energy", 6)),
		"stats": stats,
		"skill_ids": character.get("skill_ids", []),
		"cooldowns": {},
		"items": item_ids,
		"item_runtime": item_runtime,
		"item_charges": item_charges,
		"summons": [],
		"summon_limit": summon_limit
	}
	for skill_id in p["skill_ids"]:
		if skill_id != "basic_attack":
			p["cooldowns"][skill_id] = 0.0
			skill_cast_counts[skill_id] = 0
	return p


func _expand_enemy_queue(stage: Dictionary) -> Array:
	var queue: Array = []
	var index = 0
	for wave in stage.get("waves", []):
		for _i in range(int(wave.get("count", 0))):
			index += 1
			var monster: Dictionary = monsters_by_id.get(wave.get("monster_id", ""), {})
			var stats: Dictionary = monster.get("stats", {}).duplicate(true)
			queue.append({
				"instance_id": "enemy_" + str(index),
				"monster_id": monster.get("id", wave.get("monster_id", "")),
				"name": monster.get("name", "Enemy"),
				"hp": float(stats.get("max_hp", 1.0)),
				"max_hp": float(stats.get("max_hp", 1.0)),
				"stats": stats,
				"behavior": monster.get("behavior", {}),
				"status": {
					"burn": 0,
					"burn_duration": 0.0,
					"burn_multiplier": 1.0,
					"armor_break": 0,
					"armor_break_duration": 0.0,
					"guarded": false,
					"burn_explosion_cooldown": 0.0
				},
				"action_count": 0
			})
	return queue


func _spawn_next_enemy() -> void:
	if enemy_queue.is_empty():
		current_enemy = {}
	else:
		current_enemy = enemy_queue.pop_front()
		_log("敌人登场：" + current_enemy.get("name", "") + " HP " + _fmt(current_enemy.get("hp", 0.0)))
		_record_event("enemy_spawn", {
			"enemy_id": current_enemy.get("id", ""),
			"enemy_name": current_enemy.get("name", ""),
			"enemy_hp": current_enemy.get("hp", 0.0),
			"enemy_max_hp": current_enemy.get("max_hp", current_enemy.get("hp", 0.0))
		})


func _spawn_next_enemy_if_needed() -> void:
	if not _current_enemy_alive() and not enemy_queue.is_empty():
		_spawn_next_enemy()


func _claim_room_reward(stage_index: int, stage: Dictionary) -> void:
	var choices = _roll_reward_choices(3)
	if choices.is_empty():
		_log("房间奖励：无可选道具。")
		return
	var picked_id = String(choices[0].get("id", ""))
	if strategy.has_method("choose_reward"):
		var decision = strategy.choose_reward({
			"mode": mode,
			"stage_index": stage_index,
			"stage": stage,
			"choices": choices,
			"player": player.duplicate(true),
			"history": {
				"rooms_cleared": rooms_cleared,
				"skill_cast_counts": skill_cast_counts.duplicate(true),
				"total_damage_done": total_damage_done,
				"total_damage_taken": total_damage_taken
			}
		})
		if typeof(decision) == TYPE_DICTIONARY:
			picked_id = String(decision.get("item_id", picked_id))
		elif typeof(decision) == TYPE_STRING:
			picked_id = String(decision)
	if not _reward_choices_have(choices, picked_id):
		_warn("非法奖励选择，回退：" + picked_id)
		picked_id = String(choices[0].get("id", ""))
	var picked_choice = _find_reward_choice(choices, picked_id)
	var picked_detail = _item_runtime_detail(picked_choice)
	_apply_item_to_player(picked_choice)
	var heal = float(config.get("game", {}).get("room_clear_heal", 18.0))
	player["hp"] = min(float(player.get("max_hp", 1.0)), float(player.get("hp", 0.0)) + heal)
	_log("房间奖励：" + String(picked_detail.get("name", _item_name(picked_id))) + "；恢复 " + _fmt(heal) + " HP。")
	_record_event("room_reward", {
		"picked_item_id": picked_id,
		"picked_item_name": picked_detail.get("name", _item_name(picked_id)),
		"picked_item_detail": picked_detail,
		"choices": _reward_choice_names(choices),
		"choice_details": _reward_choice_details(choices),
		"player_items": _player_item_names()
	})


func _roll_reward_choices(count: int) -> Array:
	var pool: Array = []
	for item in config.get("items", []):
		var item_id = String(item.get("id", ""))
		if item_id != "" and not player.get("items", []).has(item_id):
			pool.append(item)
	_shuffle_with_rng(pool)
	var result: Array = []
	for i in range(min(count, pool.size())):
		result.append(_make_reward_option(pool[i]))
	return result


func _shuffle_with_rng(items: Array) -> void:
	if items.size() <= 1:
		return
	for i in range(items.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


func _reward_choices_have(choices: Array, item_id: String) -> bool:
	for item in choices:
		if String(item.get("id", "")) == item_id:
			return true
	return false


func _find_reward_choice(choices: Array, item_id: String) -> Dictionary:
	for item in choices:
		if String(item.get("id", "")) == item_id:
			return item
	return choices[0] if not choices.is_empty() else {}


func _apply_item_to_player(item_source: Variant) -> void:
	var runtime: Dictionary = {}
	if typeof(item_source) == TYPE_DICTIONARY:
		runtime = item_source.duplicate(true)
	else:
		runtime = _make_item_runtime(items_by_id.get(String(item_source), {}))
	var item_id = String(runtime.get("id", ""))
	if item_id == "" or player.get("items", []).has(item_id):
		return
	if runtime.is_empty():
		_warn("奖励道具不存在：" + item_id)
		return
	var old_max_hp = float(player.get("max_hp", 1.0))
	player["items"].append(item_id)
	player["item_runtime"][item_id] = runtime
	for effect in runtime.get("effects", []):
		match effect.get("type", ""):
			"stat_add":
				var stat = String(effect.get("stat", ""))
				player["stats"][stat] = float(player["stats"].get(stat, 0.0)) + float(effect.get("value", 0.0))
			"summon_limit_add":
				player["summon_limit"] = int(player.get("summon_limit", 2)) + int(effect.get("value", 0))
	if _item_has_active_effect(runtime):
		player["item_charges"][item_id] = int(runtime.get("charges", 1))
		item_use_counts[item_id] = 0
	player["max_hp"] = float(player["stats"].get("max_hp", player.get("max_hp", 1.0)))
	if float(player["max_hp"]) > old_max_hp:
		player["hp"] = float(player.get("hp", 0.0)) + float(player["max_hp"]) - old_max_hp


func _player_action() -> void:
	player["energy"] = min(float(player["max_energy"]), float(player["energy"]) + float(player["stats"].get("energy_regen", 0.0)))
	var context = _make_context()
	var action = _sanitize_action(strategy.decide_action(context), context)
	match action.get("type", ""):
		"cast_skill":
			_cast_skill(String(action.get("skill_id", "")))
		"use_item":
			_use_item(String(action.get("item_id", "")))
		"wait":
			_log("玩家等待。")
		_:
			_cast_basic_attack()


func _cast_basic_attack() -> void:
	_log("玩家使用余烬短击。")
	_deal_damage(current_enemy, float(player["stats"].get("attack", 1.0)), true, true, "basic_attack")


func _cast_skill(skill_id: String) -> void:
	var skill: Dictionary = skills_by_id.get(skill_id, {})
	if skill.is_empty():
		_warn("技能不存在：" + skill_id)
		_cast_basic_attack()
		return
	player["energy"] = float(player["energy"]) - float(skill.get("energy_cost", 0.0))
	player["cooldowns"][skill_id] = float(skill.get("cooldown", 0.0))
	skill_cast_counts[skill_id] = int(skill_cast_counts.get(skill_id, 0)) + 1
	_log("玩家释放：" + skill.get("name", skill_id))
	_record_event("cast_skill", {
		"skill_id": skill_id,
		"skill_name": skill.get("name", skill_id),
		"player_energy": player["energy"]
	})
	match String(skill.get("kind", "")):
		"direct_damage":
			var damage = float(player["stats"].get("attack", 1.0)) * float(skill.get("power", 1.0))
			for effect in skill.get("effects", []):
				if effect.get("type", "") == "bonus_vs_debuff" and int(current_enemy["status"].get(effect.get("debuff", ""), 0)) > 0:
					damage *= float(effect.get("damage_multiplier", 1.0))
			_deal_damage(current_enemy, damage, true, bool(skill.get("can_crit", false)), skill_id)
		"dot":
			_deal_damage(current_enemy, float(player["stats"].get("attack", 1.0)) * float(skill.get("power", 1.0)), true, false, skill_id)
			for effect in skill.get("effects", []):
				if effect.get("type", "") == "burn":
					_apply_burn(effect)
		"debuff":
			_deal_damage(current_enemy, float(player["stats"].get("attack", 1.0)) * float(skill.get("power", 1.0)), true, false, skill_id)
			for effect in skill.get("effects", []):
				if effect.get("type", "") == "armor_break":
					current_enemy["status"]["armor_break"] = int(current_enemy["status"].get("armor_break", 0)) + int(effect.get("stacks", 0))
					current_enemy["status"]["armor_break_duration"] = max(float(current_enemy["status"].get("armor_break_duration", 0.0)), float(effect.get("duration", 0.0)))
					_log("目标获得破甲 x" + str(current_enemy["status"]["armor_break"]))
		"summon":
			_summon_servant(skill)
		_:
			_cast_basic_attack()


func _use_item(item_id: String) -> void:
	var item = _player_item_runtime(item_id)
	if item.is_empty():
		_warn("道具不存在：" + item_id)
		_cast_basic_attack()
		return
	if int(player.get("item_charges", {}).get(item_id, 0)) <= 0:
		_warn("道具次数不足：" + item_id)
		_cast_basic_attack()
		return
	player["item_charges"][item_id] = int(player["item_charges"].get(item_id, 0)) - 1
	item_use_counts[item_id] = int(item_use_counts.get(item_id, 0)) + 1
	_log("玩家使用道具：" + item.get("name", item_id))
	_record_event("use_item", {
		"item_id": item_id,
		"item_name": item.get("name", item_id),
		"item_detail": _item_runtime_detail(item),
		"remaining_charges": player["item_charges"][item_id]
	})
	for effect in item.get("effects", []):
		match effect.get("type", ""):
			"active_heal":
				var heal = float(effect.get("value", 0.0)) + float(player.get("max_hp", 0.0)) * float(effect.get("max_hp_ratio", 0.0))
				var before = float(player.get("hp", 0.0))
				player["hp"] = min(float(player.get("max_hp", 1.0)), before + heal)
				_log(item.get("name", item_id) + " 恢复 " + _fmt(float(player["hp"]) - before) + " HP。")
			"active_energy":
				var before_energy = float(player.get("energy", 0.0))
				player["energy"] = min(float(player.get("max_energy", 1.0)), before_energy + float(effect.get("value", 0.0)))
				_log(item.get("name", item_id) + " 恢复 " + _fmt(float(player["energy"]) - before_energy) + " 能量。")
			"active_damage":
				var damage = float(effect.get("value", 0.0))
				var scale_stat = String(effect.get("scale_stat", ""))
				if scale_stat != "":
					damage += float(player["stats"].get(scale_stat, 0.0)) * float(effect.get("scale", 0.0))
				_deal_damage(current_enemy, damage, bool(effect.get("direct", true)), bool(effect.get("can_crit", false)), item_id)


func _apply_burn(effect: Dictionary) -> void:
	var extra_duration = 0
	var multiplier = 1.0
	for item_id in player.get("items", []):
		for item_effect in _player_item_effects(String(item_id)):
			if item_effect.get("type", "") == "burn_modify":
				extra_duration += int(item_effect.get("extra_duration", 0))
				multiplier *= float(item_effect.get("damage_multiplier", 1.0))
	current_enemy["status"]["burn"] = int(current_enemy["status"].get("burn", 0)) + int(effect.get("stacks", 0))
	current_enemy["status"]["burn_duration"] = max(float(current_enemy["status"].get("burn_duration", 0.0)), float(effect.get("duration", 0.0)) + extra_duration)
	current_enemy["status"]["burn_multiplier"] = multiplier
	_log("目标获得灼烧 x" + str(current_enemy["status"]["burn"]))
	for item_id in player.get("items", []):
		for item_effect in _player_item_effects(String(item_id)):
			if item_effect.get("type", "") != "burn_explosion":
				continue
			var required_stacks = int(item_effect.get("required_stacks", 999))
			var cooldown_left = float(current_enemy["status"].get("burn_explosion_cooldown", 0.0))
			if int(current_enemy["status"]["burn"]) < required_stacks or cooldown_left > 0.0:
				continue
			_deal_damage(current_enemy, float(player["stats"].get(item_effect.get("scale_stat", "burn_power"), 0.0)) * float(item_effect.get("scale", 1.0)), false, false, "burn_explosion")
			current_enemy["status"]["burn_explosion_cooldown"] = float(item_effect.get("internal_cooldown", 0.0))


func _summon_servant(skill: Dictionary) -> void:
	if player["summons"].size() >= int(player.get("summon_limit", 2)):
		_log("召唤物已达上限。")
		return
	var effect: Dictionary = {}
	for e in skill.get("effects", []):
		if e.get("type", "") == "summon":
			effect = e
	var duration = float(effect.get("duration_seconds", 8)) if mode == "realtime" else float(effect.get("duration_turns", 5))
	player["summons"].append({"duration": duration, "attack_stat": effect.get("attack_stat", "summon_power")})
	_log("召唤余烬仆从，当前数量：" + str(player["summons"].size()))
	_record_event("summon", {"count": player["summons"].size(), "duration": duration})


func _summons_action() -> void:
	for summon in player.get("summons", []):
		if not _current_enemy_alive():
			return
		_deal_damage(current_enemy, float(player["stats"].get(summon.get("attack_stat", "summon_power"), 0.0)), false, false, "summon")
		for item_id in player.get("items", []):
			for effect in _player_item_effects(String(item_id)):
				if effect.get("type", "") == "on_summon_damage_energy":
					player["energy"] = min(float(player["max_energy"]), float(player["energy"]) + float(effect.get("energy", 0.0)))


func _monster_action() -> void:
	var damage = max(1.0, float(current_enemy["stats"].get("attack", 1.0)) - float(player["stats"].get("defense", 0.0)))
	player["hp"] = max(0.0, float(player["hp"]) - damage)
	total_damage_taken += damage
	current_enemy["action_count"] = int(current_enemy.get("action_count", 0)) + 1
	_log(current_enemy.get("name", "敌人") + " 普攻，造成 " + _fmt(damage) + " 伤害。")
	_record_event("monster_attack", {
		"enemy_name": current_enemy.get("name", "敌人"),
		"damage": damage,
		"player_hp": player["hp"]
	})
	var behavior: Dictionary = current_enemy.get("behavior", {})
	if behavior.get("type", "") == "basic_attack_with_guard" and int(behavior.get("guard_every_actions", 0)) > 0:
		if int(current_enemy["action_count"]) % int(behavior["guard_every_actions"]) == 0:
			current_enemy["status"]["guarded"] = true
			_log(current_enemy.get("name", "敌人") + " 进入 guarded 状态。")


func _deal_damage(enemy: Dictionary, amount: float, direct: bool, can_crit: bool, source: String) -> void:
	if enemy.is_empty() or float(enemy.get("hp", 0.0)) <= 0.0:
		return
	var hp_before = float(enemy.get("hp", 0.0))
	var damage = amount
	var is_crit = false
	if can_crit and rng.randf() < float(player["stats"].get("crit_rate", 0.0)):
		is_crit = true
		damage *= float(player["stats"].get("crit_damage", 1.5))
		damage += _crit_bonus_damage()
	if direct:
		damage *= 1.0 + int(enemy["status"].get("armor_break", 0)) * 0.12
		if bool(enemy["status"].get("guarded", false)):
			damage *= 1.0 - float(enemy.get("behavior", {}).get("guard_damage_reduction", 0.3))
			enemy["status"]["guarded"] = false
		damage = max(1.0, damage - float(enemy["stats"].get("defense", 0.0)))
	enemy["hp"] = max(0.0, hp_before - damage)
	total_damage_done += damage
	var curve_point = {
		"index": damage_curve.size() + 1,
		"time": elapsed,
		"turn": turn,
		"tick": tick,
		"room_index": room_index,
		"source": source,
		"critical": is_crit,
		"delta": damage,
		"damage_delta": damage,
		"damage": total_damage_done,
		"total_damage": total_damage_done,
		"enemy_id": enemy.get("id", enemy.get("monster_id", "")),
		"enemy_name": enemy.get("name", "敌人"),
		"enemy_hp_before": hp_before,
		"enemy_hp": enemy["hp"],
		"enemy_max_hp": enemy.get("max_hp", enemy["hp"]),
		"player_hp": player.get("hp", 0.0)
	}
	damage_curve.append(curve_point)
	_log(source + (" 暴击" if is_crit else "") + " 造成 " + _fmt(damage) + "；目标 HP " + _fmt(enemy["hp"]) + "/" + _fmt(enemy["max_hp"]))
	_record_event("damage", curve_point.duplicate(true))
	if float(enemy["hp"]) <= 0.0:
		_log(enemy.get("name", "敌人") + " 被击败。")


func _crit_bonus_damage() -> float:
	var bonus = 0.0
	for item_id in player.get("items", []):
		for effect in _player_item_effects(String(item_id)):
			if effect.get("type", "") == "on_crit_damage":
				bonus += float(player["stats"].get(effect.get("scale_stat", "attack"), 0.0)) * float(effect.get("scale", 0.0))
	return bonus


func _process_burn_damage() -> void:
	if not _current_enemy_alive():
		return
	var status: Dictionary = current_enemy.get("status", {})
	if int(status.get("burn", 0)) > 0 and float(status.get("burn_duration", 0.0)) > 0.0:
		var damage = int(status["burn"]) * float(player["stats"].get("burn_power", 0.0)) * float(status.get("burn_multiplier", 1.0))
		_deal_damage(current_enemy, damage, false, false, "burn")


func _tick_enemy_status(step: float) -> void:
	if current_enemy.is_empty():
		return
	for pair in [["burn_duration", "burn"], ["armor_break_duration", "armor_break"]]:
		var duration_key = String(pair[0])
		var stack_key = String(pair[1])
		if float(current_enemy["status"].get(duration_key, 0.0)) > 0.0:
			current_enemy["status"][duration_key] = max(0.0, float(current_enemy["status"][duration_key]) - step)
			if float(current_enemy["status"][duration_key]) <= 0.0:
				current_enemy["status"][stack_key] = 0
	if float(current_enemy["status"].get("burn_explosion_cooldown", 0.0)) > 0.0:
		current_enemy["status"]["burn_explosion_cooldown"] = max(0.0, float(current_enemy["status"]["burn_explosion_cooldown"]) - step)


func _tick_cooldowns(step: float) -> void:
	for skill_id in player.get("cooldowns", {}).keys():
		player["cooldowns"][skill_id] = max(0.0, float(player["cooldowns"][skill_id]) - step)


func _tick_summon_duration(step: float) -> void:
	var kept: Array = []
	for summon in player.get("summons", []):
		summon["duration"] = float(summon.get("duration", 0.0)) - step
		if float(summon["duration"]) > 0.0:
			kept.append(summon)
	player["summons"] = kept


func _make_context() -> Dictionary:
	var enemies: Array = []
	if _current_enemy_alive():
		enemies.append({
			"instance_id": current_enemy.get("instance_id", ""),
			"monster_id": current_enemy.get("monster_id", ""),
			"name": current_enemy.get("name", ""),
			"hp": current_enemy.get("hp", 0.0),
			"max_hp": current_enemy.get("max_hp", 0.0),
			"status": current_enemy.get("status", {}).duplicate(true)
		})
	return {
		"mode": mode,
		"time": {"turn": turn, "tick": tick, "seconds": elapsed},
		"player": player.duplicate(true),
		"current_target_id": current_enemy.get("instance_id", ""),
		"enemies": enemies,
		"available_actions": _available_actions(),
		"history": {"skill_cast_counts": skill_cast_counts.duplicate(true), "total_damage_done": total_damage_done, "total_damage_taken": total_damage_taken}
	}


func _available_actions() -> Array:
	var actions: Array = []
	if not _current_enemy_alive():
		return [{"type": "wait"}]
	var target_id = String(current_enemy.get("instance_id", ""))
	actions.append({"type": "basic_attack", "target_id": target_id})
	for skill_id in player.get("skill_ids", []):
		if skill_id == "basic_attack":
			continue
		var skill: Dictionary = skills_by_id.get(skill_id, {})
		if float(player["cooldowns"].get(skill_id, 0.0)) <= 0.0 and float(player["energy"]) >= float(skill.get("energy_cost", 0.0)):
			actions.append({"type": "cast_skill", "skill_id": skill_id, "target_id": target_id})
	for item_id in player.get("items", []):
		if _item_has_active_effect(_player_item_runtime(String(item_id))) and int(player.get("item_charges", {}).get(item_id, 0)) > 0:
			actions.append({"type": "use_item", "item_id": item_id, "target_id": target_id})
	actions.append({"type": "wait"})
	return actions


func _sanitize_action(action: Dictionary, context: Dictionary) -> Dictionary:
	for available in context.get("available_actions", []):
		if available.get("type", "") == action.get("type", ""):
			if action.get("type", "") == "cast_skill" and available.get("skill_id", "") != action.get("skill_id", ""):
				continue
			if action.get("type", "") == "use_item" and available.get("item_id", "") != action.get("item_id", ""):
				continue
			return action
	_warn("非法动作，回退：" + str(action))
	for available in context.get("available_actions", []):
		if available.get("type", "") == "basic_attack":
			return available
	return {"type": "wait"}


func _battle_continues() -> bool:
	return float(player.get("hp", 0.0)) > 0.0 and (_current_enemy_alive() or not enemy_queue.is_empty())


func _current_enemy_alive() -> bool:
	return not current_enemy.is_empty() and float(current_enemy.get("hp", 0.0)) > 0.0


func _make_result() -> Dictionary:
	var victory = float(player.get("hp", 0.0)) > 0.0 and not _current_enemy_alive() and enemy_queue.is_empty()
	_record_event("battle_end", {
		"victory": victory,
		"player_hp": player.get("hp", 0.0),
		"player_items": _player_item_names(),
		"player_item_details": _player_item_details(),
		"rooms_cleared": rooms_cleared,
		"total_damage_done": total_damage_done,
		"total_damage_taken": total_damage_taken
	})
	return {
		"strategy_id": strategy.get_strategy_id(),
		"mode": mode,
		"seed": run_seed,
		"victory": victory,
		"turns": turn,
		"ticks": tick,
		"seconds": elapsed,
		"player_hp": player.get("hp", 0.0),
		"player_max_hp": player.get("max_hp", 0.0),
		"rooms_cleared": rooms_cleared,
		"player_items": player.get("items", []).duplicate(),
		"player_item_names": _player_item_names(),
		"player_item_details": _player_item_details(),
		"item_charges": player.get("item_charges", {}).duplicate(true),
		"skill_cast_counts": skill_cast_counts.duplicate(true),
		"item_use_counts": item_use_counts.duplicate(true),
		"total_damage_done": total_damage_done,
		"total_damage_taken": total_damage_taken,
		"damage_curve": damage_curve.duplicate(true),
		"replay_events": replay_events.duplicate(true),
		"logs": logs.duplicate(),
		"warnings": warnings.duplicate()
	}


func _error_result(message: String) -> Dictionary:
	return {"strategy_id": "unknown", "mode": mode, "victory": false, "error": message, "logs": [message], "warnings": [message]}


func _index_by_id(items: Array) -> Dictionary:
	var result = {}
	for item in items:
		result[item.get("id", "")] = item
	return result


func _find_build_preset(strategy_id: String) -> Dictionary:
	for preset in config.get("build_presets", []):
		if String(preset.get("strategy_id", "")) == strategy_id:
			return preset
	return {}


func _make_build_from_preset(preset: Dictionary) -> Dictionary:
	return {
		"stat_points": preset.get("stat_points", {}).duplicate(true),
		"item_ids": preset.get("item_ids", []).duplicate(),
		"notes": preset.get("synergy", preset.get("name", ""))
	}


func _resolve_initial_build(preset: Dictionary, requested_build: Dictionary) -> Dictionary:
	var build = _make_build_from_preset(preset)
	if typeof(requested_build) != TYPE_DICTIONARY:
		return build
	if requested_build.has("stat_points"):
		build["stat_points"] = requested_build.get("stat_points", {}).duplicate(true)
	if requested_build.has("item_ids"):
		build["item_ids"] = requested_build.get("item_ids", []).duplicate()
	if String(requested_build.get("notes", "")) != "":
		build["notes"] = String(requested_build.get("notes", ""))
	return build


func _validate_initial_build(character: Dictionary, build: Dictionary) -> String:
	var rules: Dictionary = config.get("game", {})
	var stat_points: Dictionary = build.get("stat_points", {})
	var growth: Dictionary = character.get("stat_growth", {})
	for stat_name in stat_points.keys():
		if not growth.has(stat_name):
			return "未知属性点字段：" + String(stat_name)
		if float(stat_points.get(stat_name, 0.0)) < 0.0:
			return "属性点不能为负数：" + String(stat_name)
	if int(round(_sum_numeric_values(stat_points))) != int(rules.get("starting_stat_points", 0)):
		return "属性点总和必须等于 starting_stat_points"
	var item_ids: Array = build.get("item_ids", [])
	if item_ids.size() > int(rules.get("item_slots", 0)):
		return "初始道具数量超过 item_slots"
	var seen_items = {}
	for item_id in item_ids:
		var normalized = String(item_id)
		if normalized == "":
			return "初始道具 ID 不能为空"
		if seen_items.has(normalized):
			return "初始道具重复：" + normalized
		seen_items[normalized] = true
		if not items_by_id.has(normalized):
			return "初始道具不存在：" + normalized
	return ""


func _sum_numeric_values(values: Dictionary) -> float:
	var total = 0.0
	for key in values.keys():
		total += float(values.get(key, 0.0))
	return total


func _make_reward_option(base_item: Dictionary) -> Dictionary:
	return _make_item_runtime(base_item, _roll_affix_for_item(base_item))


func _make_item_runtime(base_item: Dictionary, affix: Dictionary = {}) -> Dictionary:
	if base_item.is_empty():
		return {}
	var base_name = String(base_item.get("name", base_item.get("id", "")))
	var prefix = String(affix.get("name_prefix", ""))
	var suffix = String(affix.get("name_suffix", ""))
	var display_name = (prefix + base_name + suffix).strip_edges()
	if display_name == "":
		display_name = base_name
	return {
		"id": String(base_item.get("id", "")),
		"base_item_id": String(base_item.get("id", "")),
		"name": display_name,
		"base_name": base_name,
		"charges": int(base_item.get("charges", 0)),
		"tags": _merge_string_arrays(base_item.get("tags", []), affix.get("tags", [])),
		"effects": _clone_effects(base_item.get("effects", [])) + _clone_effects(affix.get("effects", [])),
		"affixes": [] if affix.is_empty() else [_affix_summary(affix)]
	}


func _roll_affix_for_item(base_item: Dictionary) -> Dictionary:
	var affixes: Array = config.get("item_affixes", [])
	var chance = float(config.get("game", {}).get("reward_affix_chance", 0.0))
	if affixes.is_empty() or rng.randf() > chance:
		return {}
	var candidates: Array = []
	var item_tags: Array = base_item.get("tags", [])
	for affix in affixes:
		var applicable_tags: Array = affix.get("applicable_tags", [])
		if applicable_tags.is_empty() or _arrays_overlap(item_tags, applicable_tags):
			candidates.append(affix)
	if candidates.is_empty():
		return {}
	var total_weight = 0.0
	for affix in candidates:
		total_weight += float(affix.get("weight", 1.0))
	var roll = rng.randf() * max(0.001, total_weight)
	var cursor = 0.0
	for affix in candidates:
		cursor += float(affix.get("weight", 1.0))
		if roll <= cursor:
			return affix.duplicate(true)
	return candidates[0].duplicate(true)


func _affix_summary(affix: Dictionary) -> Dictionary:
	return {
		"id": String(affix.get("id", "")),
		"name": String(affix.get("display_name", affix.get("name_prefix", "") + affix.get("name_suffix", ""))).strip_edges(),
		"description": String(affix.get("description", ""))
	}


func _clone_effects(effects: Array) -> Array:
	var result: Array = []
	for effect in effects:
		result.append(effect.duplicate(true))
	return result


func _merge_string_arrays(left: Array, right: Array) -> Array:
	var result: Array = []
	var seen = {}
	for value in left + right:
		var text = String(value)
		if seen.has(text):
			continue
		seen[text] = true
		result.append(text)
	return result


func _arrays_overlap(left: Array, right: Array) -> bool:
	var right_lookup = {}
	for value in right:
		right_lookup[String(value)] = true
	for value in left:
		if right_lookup.has(String(value)):
			return true
	return false


func _player_item_runtime(item_id: String) -> Dictionary:
	return player.get("item_runtime", {}).get(item_id, _make_item_runtime(items_by_id.get(item_id, {})))


func _player_item_effects(item_id: String) -> Array:
	return _player_item_runtime(item_id).get("effects", [])


func _player_item_names() -> Array[String]:
	var names: Array[String] = []
	for item_id in player.get("items", []):
		names.append(_item_name(String(item_id)))
	return names


func _player_item_details() -> Array:
	var details: Array = []
	for item_id in player.get("items", []):
		var runtime = _player_item_runtime(String(item_id))
		details.append(_item_runtime_detail(runtime))
	return details


func _reward_choice_details(choices: Array) -> Array:
	var details: Array = []
	for choice in choices:
		if typeof(choice) == TYPE_DICTIONARY:
			details.append(_item_runtime_detail(choice))
	return details


func _item_runtime_detail(runtime: Dictionary) -> Dictionary:
	return {
		"id": runtime.get("id", ""),
		"name": runtime.get("name", ""),
		"base_name": runtime.get("base_name", ""),
		"tags": runtime.get("tags", []).duplicate(),
		"affixes": runtime.get("affixes", []).duplicate(true)
	}


func _reward_choice_names(choices: Array) -> Array[String]:
	var names: Array[String] = []
	for choice in choices:
		names.append(String(choice.get("name", choice.get("id", ""))))
	return names


func _item_name(item_id: String) -> String:
	return _player_item_runtime(item_id).get("name", items_by_id.get(item_id, {}).get("name", item_id))


func _item_has_active_effect(item_source: Variant) -> bool:
	var runtime: Dictionary = item_source if typeof(item_source) == TYPE_DICTIONARY else _player_item_runtime(String(item_source))
	for effect in runtime.get("effects", []):
		if String(effect.get("type", "")).begins_with("active_"):
			return true
	return false


func _fmt(value: Variant) -> String:
	return "%.1f" % float(value)


func _log(message: String) -> void:
	if logs.size() < 260:
		logs.append(message)
	_record_event("log", {"message": message})


func _warn(message: String) -> void:
	warnings.append(message)
	_log("WARNING: " + message)


func _record_event(event_type: String, payload: Dictionary = {}) -> void:
	if replay_events.size() >= 2500:
		return
	var event = {
		"index": replay_events.size(),
		"type": event_type,
		"time": elapsed,
		"turn": turn,
		"tick": tick,
		"room_index": room_index,
		"payload": payload
	}
	replay_events.append(event)
