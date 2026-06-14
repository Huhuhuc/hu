extends Control

const CONFIG_PATH = "res://data/sample_config.json"
const RESULT_JSON = "user://play_result.json"
const RESULT_CSV = "user://play_result.csv"

var config: Dictionary = {}
var monsters_by_id: Dictionary = {}
var items_by_id: Dictionary = {}
var player_stats: Dictionary = {}
var player_hp = 1.0
var player_max_hp = 1.0
var player_energy = 0.0
var player_max_energy = 6.0
var player_speed = 240.0
var shoot_timer = 0.0
var core_timer = 0.0
var burn_timer = 0.0
var armor_timer = 0.0
var summon_timer = 0.0
var dash_timer = 0.0
var invincible_timer = 0.0
var wave_index = 0
var current_stage_index = 0
var enemy_queue: Array = []
var enemies: Array = []
var bullets: Array = []
var enemy_bullets: Array = []
var summons: Array = []
var float_texts: Array = []
var total_damage = 0.0
var total_taken = 0.0
var skill_cast_counts: Dictionary = {}
var damage_curve: Array = []
var elapsed = 0.0
var kills = 0
var room_state = "loading"
var selected_build = "balanced"
var player_items: Array = []
var offered_item_ids: Array = []
var summon_limit = 2
var crit_bonus_scale = 0.0
var burn_duration_bonus = 0.0
var burn_damage_multiplier = 1.0
var burn_explosion_scale = 0.0
var burn_explosion_required_stacks = 999
var burn_explosion_internal_cooldown = 0.0
var summon_energy_gain = 0.0

@onready var arena: ColorRect = %Arena
@onready var player_node: ColorRect = %Player
@onready var enemy_layer: Control = %EnemyLayer
@onready var enemy_bullet_layer: Control = %EnemyBulletLayer
@onready var bullet_layer: Control = %BulletLayer
@onready var summon_layer: Control = %SummonLayer
@onready var float_layer: Control = %FloatLayer
@onready var status_label: Label = %StatusLabel
@onready var hp_bar: ProgressBar = %HpBar
@onready var energy_bar: ProgressBar = %EnergyBar
@onready var skill_label: Label = %SkillLabel
@onready var wave_label: Label = %WaveLabel
@onready var log_label: Label = %LogLabel
@onready var stats_label: Label = %StatsLabel
@onready var upgrade_panel: PanelContainer = %UpgradePanel
@onready var upgrade_title: Label = %UpgradeTitle
@onready var crit_button: Button = %CritButton
@onready var burn_button: Button = %BurnButton
@onready var summon_button: Button = %SummonButton
@onready var result_panel: PanelContainer = %ResultPanel
@onready var result_label: Label = %ResultLabel


func _ready() -> void:
	_load_config()
	await get_tree().process_frame
	if room_state != "error":
		if OS.get_cmdline_args().has("--smoke-test"):
			_start_game("crit")
		else:
			_show_build_select()


func _process(delta: float) -> void:
	if room_state == "error":
		return
	if room_state == "playing":
		elapsed += delta
		_update_timers(delta)
		_handle_player(delta)
		_update_bullets(delta)
		_update_enemy_bullets(delta)
		_update_enemies(delta)
		_update_summons(delta)
		_update_status_effects(delta)
		_update_float_texts(delta)
		_check_wave_clear()
	_update_ui()


func _load_config() -> void:
	monsters_by_id.clear()
	items_by_id.clear()
	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		_fail_load("配置加载失败：" + error_string(FileAccess.get_open_error()))
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail_load("配置解析失败：JSON 顶层必须是 Object。")
		return
	config = parsed
	for key in ["characters", "skills", "items", "monsters", "stages"]:
		if not config.has(key):
			_fail_load("配置缺少字段：" + key)
			return
	for monster in config.get("monsters", []):
		monsters_by_id[monster.get("id", "")] = monster
	for item in config.get("items", []):
		items_by_id[item.get("id", "")] = item
	status_label.text = "配置加载成功"


func _fail_load(message: String) -> void:
	room_state = "error"
	status_label.text = message
	log_label.text = message


func _show_build_select() -> void:
	room_state = "build_select"
	result_panel.visible = false
	upgrade_panel.visible = true
	upgrade_title.text = "选择初始流派"
	crit_button.text = "暴击流\n攻击+3 / 暴击+3\n碎甲后裂芯斩爆发\n棱镜护符 + 锋刃齿轮"
	burn_button.text = "持续输出流\n速度+3 / 灼烧+3\n尽早挂燃烬印记\n余火沙漏 + 裂变火种"
	summon_button.text = "召唤流\n召唤+4 / 生命+2\n提前铺余烬仆从\n灰烬铃 + 共鸣核心"
	status_label.text = "选择一个流派开始探索"
	log_label.text = "WASD 移动，J/鼠标射击，K/L/U/I 释放技能，Space 冲刺。"
	stats_label.text = _base_stats_text()
	_clear_runtime_nodes()


func _start_game(start_build: String) -> void:
	var character = config.get("characters", [])[0]
	player_stats = character.get("base_stats", {}).duplicate(true)
	_reset_build_modifiers()
	_apply_build(start_build)
	player_max_hp = float(player_stats.get("max_hp", 120.0))
	player_hp = player_max_hp
	player_energy = float(config.get("game", {}).get("starting_energy", 3.0))
	player_max_energy = float(config.get("game", {}).get("max_energy", 6.0))
	player_speed = 185.0 + float(player_stats.get("speed", 10.0)) * 5.0
	player_node.position = arena.size * 0.5 - player_node.size * 0.5
	current_stage_index = 0
	wave_index = 0
	total_damage = 0.0
	total_taken = 0.0
	skill_cast_counts = {
		"basic_attack": 0,
		"core_split": 0,
		"ember_mark": 0,
		"armor_pulse": 0,
		"ember_servant": 0
	}
	damage_curve.clear()
	kills = 0
	elapsed = 0.0
	room_state = "playing"
	result_panel.visible = false
	upgrade_panel.visible = false
	upgrade_title.text = "选择强化"
	_clear_runtime_nodes()
	_start_stage(current_stage_index)
	log_label.text = "战斗开始"
	_update_stats_panel()




func _reset_build_modifiers() -> void:
	player_items.clear()
	summon_limit = 2
	crit_bonus_scale = 0.0
	burn_duration_bonus = 0.0
	burn_damage_multiplier = 1.0
	burn_explosion_scale = 0.0
	burn_explosion_required_stacks = 999
	burn_explosion_internal_cooldown = 0.0
	summon_energy_gain = 0.0
	core_timer = 0.0
	burn_timer = 0.0
	armor_timer = 0.0
	summon_timer = 0.0
	shoot_timer = 0.0


func _apply_build(build_id: String) -> void:
	selected_build = build_id
	var preset = _get_build_preset(build_id)
	var growth = config.get("characters", [])[0].get("stat_growth", {})
	for stat_name in preset.get("stat_points", {}).keys():
		player_stats[stat_name] = float(player_stats.get(stat_name, 0.0)) + float(growth.get(stat_name, 0.0)) * float(preset["stat_points"][stat_name])
	for item_id in preset.get("item_ids", []):
		if not player_items.has(item_id):
			player_items.append(item_id)
			_apply_item(item_id)


func _get_build_preset(build_id: String) -> Dictionary:
	var preset_id = {
		"crit": "crit_build",
		"burn": "burn_build",
		"summon": "summon_build"
	}.get(build_id, "crit_build")
	for preset in config.get("build_presets", []):
		if preset.get("id", "") == preset_id:
			return preset
	return {}


func _apply_item(item_id: String) -> void:
	var item = items_by_id.get(item_id, {})
	for effect in item.get("effects", []):
		match effect.get("type", ""):
			"stat_add":
				var stat = String(effect.get("stat", ""))
				player_stats[stat] = float(player_stats.get(stat, 0.0)) + float(effect.get("value", 0.0))
			"on_crit_damage":
				crit_bonus_scale += float(effect.get("scale", 0.0))
			"burn_modify":
				burn_duration_bonus += float(effect.get("extra_duration", 0.0))
				burn_damage_multiplier *= float(effect.get("damage_multiplier", 1.0))
			"burn_explosion":
				burn_explosion_scale = max(burn_explosion_scale, float(effect.get("scale", 0.0)))
				burn_explosion_required_stacks = min(burn_explosion_required_stacks, int(effect.get("required_stacks", 999)))
				burn_explosion_internal_cooldown = max(burn_explosion_internal_cooldown, float(effect.get("internal_cooldown", 0.0)))
			"summon_limit_add":
				summon_limit += int(effect.get("value", 0))
			"on_summon_damage_energy":
				summon_energy_gain += float(effect.get("energy", 0.0))


func _refresh_player_derived_stats(heal_amount: float = 0.0) -> void:
	var old_max = player_max_hp
	player_max_hp = float(player_stats.get("max_hp", player_max_hp))
	player_speed = 185.0 + float(player_stats.get("speed", 10.0)) * 5.0
	if player_max_hp > old_max:
		player_hp += player_max_hp - old_max
	player_hp = min(player_max_hp, player_hp + heal_amount)


func _start_stage(stage_index: int) -> void:
	if stage_index >= config.get("stages", []).size():
		_win_game()
		return
	enemy_queue = _build_enemy_queue(config.get("stages", [])[stage_index])
	wave_index = 0
	player_node.position = arena.size * 0.5 - player_node.size * 0.5
	_clear_runtime_nodes()
	_spawn_next_wave()


func _build_enemy_queue(stage: Dictionary) -> Array:
	var queue = []
	for wave in stage.get("waves", []):
		var wave_enemies = []
		for i in range(int(wave.get("count", 0))):
			wave_enemies.append(String(wave.get("monster_id", "")))
		queue.append(wave_enemies)
	return queue


func _spawn_next_wave() -> void:
	if enemy_queue.is_empty():
		_show_item_reward()
		return
	wave_index += 1
	var wave_enemies = enemy_queue.pop_front()
	for monster_id in wave_enemies:
		_spawn_enemy(monster_id)
	var stage = config.get("stages", [])[current_stage_index]
	wave_label.text = "房间 %d/%d：%s  波次 %d" % [current_stage_index + 1, config.get("stages", []).size(), stage.get("name", ""), wave_index]
	log_label.text = "新一波敌人出现"


func _spawn_enemy(monster_id: String) -> void:
	var monster = monsters_by_id.get(monster_id, {})
	var stats = monster.get("stats", {})
	var node = ColorRect.new()
	node.size = _monster_size(monster_id)
	node.color = _monster_color(monster_id)
	node.position = _random_edge_position(node.size)
	enemy_layer.add_child(node)
	var hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(0, -8)
	hp_bar.size = Vector2(node.size.x, 6)
	hp_bar.max_value = float(stats.get("max_hp", 50.0))
	hp_bar.value = hp_bar.max_value
	hp_bar.show_percentage = false
	node.add_child(hp_bar)
	enemies.append({
		"node": node,
		"hp_bar": hp_bar,
		"id": monster_id,
		"name": monster.get("name", monster_id),
		"hp": float(stats.get("max_hp", 50.0)),
		"max_hp": float(stats.get("max_hp", 50.0)),
		"attack": float(stats.get("attack", 8.0)),
		"defense": float(stats.get("defense", 0.0)),
		"speed": 65.0 + float(stats.get("speed", 8.0)) * 4.0,
		"behavior": monster.get("behavior", {}).get("type", "basic_attack"),
		"attack_timer": randf_range(0.2, 0.9),
		"move_phase": randf_range(0.0, 6.28),
		"burn": 0.0,
		"burn_stacks": 0,
		"burn_tick": 0.0,
		"burn_time": 0.0,
		"burn_explosion_cooldown": 0.0,
		"armor_break": 0,
		"armor_break_time": 0.0,
		"guarded": false,
		"action_count": 0
	})
	_spawn_float_text(node.position + Vector2(0, -18), _monster_trait_text(monster_id), node.color)


func _monster_size(monster_id: String) -> Vector2:
	match monster_id:
		"spark_bat":
			return Vector2(28, 28)
		"bone_turret":
			return Vector2(42, 42)
		"tar_slime":
			return Vector2(44, 44)
		"ember_mage":
			return Vector2(38, 38)
		"furnace_guard":
			return Vector2(54, 54)
		_:
			return Vector2(34, 34)


func _monster_color(monster_id: String) -> Color:
	match monster_id:
		"spark_bat":
			return Color(0.88, 0.74, 0.22)
		"bone_turret":
			return Color(0.62, 0.62, 0.70)
		"tar_slime":
			return Color(0.20, 0.16, 0.13)
		"ember_mage":
			return Color(0.58, 0.20, 0.78)
		"furnace_guard":
			return Color(0.78, 0.20, 0.10)
		_:
			return Color(0.55, 0.43, 0.32)


func _monster_trait_text(monster_id: String) -> String:
	match monster_id:
		"ash_crawler":
			return "普通追击"
		"spark_bat":
			return "高速突袭"
		"bone_turret":
			return "远程炮台"
		"tar_slime":
			return "重甲近战"
		"ember_mage":
			return "三连弹幕"
		"furnace_guard":
			return "精英护盾"
		_:
			return "未知怪物"


func _random_edge_position(size: Vector2) -> Vector2:
	var side = randi() % 4
	if side == 0:
		return Vector2(randf_range(10, arena.size.x - size.x - 10), 10)
	if side == 1:
		return Vector2(randf_range(10, arena.size.x - size.x - 10), arena.size.y - size.y - 10)
	if side == 2:
		return Vector2(10, randf_range(10, arena.size.y - size.y - 10))
	return Vector2(arena.size.x - size.x - 10, randf_range(10, arena.size.y - size.y - 10))


func _update_timers(delta: float) -> void:
	shoot_timer = max(0.0, shoot_timer - delta)
	core_timer = max(0.0, core_timer - delta)
	burn_timer = max(0.0, burn_timer - delta)
	armor_timer = max(0.0, armor_timer - delta)
	summon_timer = max(0.0, summon_timer - delta)
	dash_timer = max(0.0, dash_timer - delta)
	invincible_timer = max(0.0, invincible_timer - delta)
	player_energy = min(player_max_energy, player_energy + float(player_stats.get("energy_regen", 1.0)) * delta)


func _handle_player(delta: float) -> void:
	var dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir.length() > 0.0:
		dir = dir.normalized()
	var speed = player_speed
	if Input.is_key_pressed(KEY_SPACE) and dash_timer <= 0.0:
		speed *= 2.4
		dash_timer = 1.2
		invincible_timer = 0.25
	player_node.position += dir * speed * delta
	player_node.position = player_node.position.clamp(Vector2.ZERO, arena.size - player_node.size)

	if (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_J)) and shoot_timer <= 0.0:
		_record_skill_cast("basic_attack")
		_fire_bullet(false)
		shoot_timer = 0.22
	if Input.is_key_pressed(KEY_K) and core_timer <= 0.0 and player_energy >= 2.0:
		player_energy -= 2.0
		core_timer = 3.0
		_record_skill_cast("core_split")
		_fire_bullet(true)
		log_label.text = "释放裂芯斩"
	if Input.is_key_pressed(KEY_L) and burn_timer <= 0.0 and player_energy >= 2.0:
		player_energy -= 2.0
		burn_timer = 4.0
		_record_skill_cast("ember_mark")
		_cast_burn_mark()
	if Input.is_key_pressed(KEY_U) and armor_timer <= 0.0 and player_energy >= 3.0:
		player_energy -= 3.0
		armor_timer = 5.0
		_record_skill_cast("armor_pulse")
		_cast_armor_pulse()
	if Input.is_key_pressed(KEY_I) and summon_timer <= 0.0 and player_energy >= 3.0:
		player_energy -= 3.0
		summon_timer = 6.0
		_record_skill_cast("ember_servant")
		_summon_ember()


func _fire_bullet(big: bool) -> void:
	var dir = _aim_direction()
	var node = ColorRect.new()
	node.size = Vector2(18, 18) if big else Vector2(10, 10)
	node.color = Color(1.0, 0.38, 0.12) if big else Color(1.0, 0.78, 0.28)
	node.position = _player_center() - node.size * 0.5
	bullet_layer.add_child(node)
	var damage = float(player_stats.get("attack", 12.0)) * (2.2 if big else 1.0)
	bullets.append({"node": node, "dir": dir, "speed": 520.0, "damage": damage, "life": 1.2, "big": big})


func _aim_direction() -> Vector2:
	var mouse_dir = arena.get_local_mouse_position() - _player_center()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and mouse_dir.length() > 4.0:
		return mouse_dir.normalized()
	var target = _nearest_enemy()
	if target != null:
		return (_enemy_center(target) - _player_center()).normalized()
	return Vector2.RIGHT


func _cast_burn_mark() -> void:
	var target = _nearest_enemy()
	if target == null:
		return
	target["burn_stacks"] = 4
	target["burn"] = float(player_stats.get("burn_power", 4.0)) * 4.0
	target["burn_time"] = 4.0 + burn_duration_bonus
	target["burn_tick"] = 0.0
	_damage_enemy(target, float(player_stats.get("attack", 12.0)) * 0.8, "燃烬印记", false, true)
	if burn_explosion_scale > 0.0 and int(target.get("burn_stacks", 0)) >= burn_explosion_required_stacks and float(target.get("burn_explosion_cooldown", 0.0)) <= 0.0:
		_damage_enemy(target, float(player_stats.get("burn_power", 4.0)) * burn_explosion_scale, "裂变火种", false, false)
		target["burn_explosion_cooldown"] = burn_explosion_internal_cooldown
	log_label.text = "释放燃烬印记"


func _cast_armor_pulse() -> void:
	var target = _nearest_enemy()
	if target == null:
		return
	target["armor_break"] = int(target.get("armor_break", 0)) + 2
	target["armor_break_time"] = 3.0
	_damage_enemy(target, float(player_stats.get("attack", 12.0)), "碎甲脉冲", false, true)
	log_label.text = "释放碎甲脉冲"


func _summon_ember() -> void:
	if summons.size() >= summon_limit:
		log_label.text = "召唤物已达上限"
		return
	var node = ColorRect.new()
	node.size = Vector2(24, 24)
	node.color = Color(0.18, 0.78, 0.95)
	node.position = player_node.position + Vector2(randf_range(-32, 32), randf_range(-32, 32))
	summon_layer.add_child(node)
	summons.append({"node": node, "attack_timer": 0.0, "life": 8.0})
	log_label.text = "召唤余烬仆从"


func _update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var bullet = bullets[i]
		var node = bullet["node"]
		node.position += bullet["dir"] * float(bullet["speed"]) * delta
		bullet["life"] = float(bullet["life"]) - delta
		var removed = false
		for enemy in enemies:
			if _rects_overlap(node.position, node.size, enemy["node"].position, enemy["node"].size):
				var source = "裂芯斩" if bool(bullet.get("big", false)) else "余烬短击"
				_damage_enemy(enemy, float(bullet["damage"]), source, true, true)
				node.queue_free()
				bullets.remove_at(i)
				removed = true
				break
		if not removed and (float(bullet["life"]) <= 0.0 or not Rect2(Vector2.ZERO, arena.size).has_point(node.position)):
			node.queue_free()
			bullets.remove_at(i)


func _update_enemy_bullets(delta: float) -> void:
	for i in range(enemy_bullets.size() - 1, -1, -1):
		var bullet = enemy_bullets[i]
		var node = bullet["node"]
		node.position += bullet["dir"] * float(bullet["speed"]) * delta
		bullet["life"] = float(bullet["life"]) - delta
		if _rects_overlap(node.position, node.size, player_node.position, player_node.size):
			_take_damage(float(bullet["damage"]))
			node.queue_free()
			enemy_bullets.remove_at(i)
			continue
		if float(bullet["life"]) <= 0.0 or not Rect2(Vector2.ZERO, arena.size).has_point(node.position):
			node.queue_free()
			enemy_bullets.remove_at(i)


func _update_enemies(delta: float) -> void:
	for enemy in enemies:
		var node = enemy["node"]
		var to_player = _player_center() - _enemy_center(enemy)
		var behavior = String(enemy.get("behavior", "basic_attack"))
		_move_enemy(enemy, to_player, behavior, delta)
		enemy["attack_timer"] = float(enemy["attack_timer"]) - delta
		var in_melee = _rects_overlap(player_node.position, player_node.size, node.position, node.size)
		var distance = to_player.length()
		if enemy["attack_timer"] <= 0.0:
			enemy["action_count"] = int(enemy.get("action_count", 0)) + 1
			if behavior == "stationary_shooter" and distance < 430.0:
				enemy["attack_timer"] = 1.15
				_fire_enemy_projectile(enemy, to_player.normalized(), 260.0, Color(0.75, 0.80, 1.0), Vector2(12, 12), "炮台弹")
			elif behavior == "caster" and distance < 420.0:
				enemy["attack_timer"] = 1.6
				_fire_enemy_spread(enemy, to_player.normalized(), 3, 0.28, 220.0, Color(0.90, 0.34, 1.0), "法术弹幕")
			elif behavior == "basic_attack_with_guard":
				enemy["attack_timer"] = 1.05
				if int(enemy["action_count"]) % 3 == 0:
					enemy["guarded"] = true
					_spawn_float_text(_enemy_center(enemy), "精英护盾", Color(0.50, 0.78, 1.0))
					_fire_enemy_spread(enemy, Vector2.RIGHT, 8, TAU / 8.0, 180.0, Color(1.0, 0.24, 0.12), "精英环弹")
				elif in_melee:
					_take_damage(max(1.0, float(enemy["attack"]) - float(player_stats.get("defense", 0.0))))
				elif distance < 360.0:
					_fire_enemy_projectile(enemy, to_player.normalized(), 235.0, Color(1.0, 0.32, 0.16), Vector2(14, 14), "精英火弹")
			elif in_melee:
				enemy["attack_timer"] = 0.55 if behavior == "fast_chaser" else 0.9
				var damage_scale = 1.25 if behavior == "slow_brute" else 1.0
				_take_damage(max(1.0, float(enemy["attack"]) * damage_scale - float(player_stats.get("defense", 0.0))))


func _move_enemy(enemy: Dictionary, to_player: Vector2, behavior: String, delta: float) -> void:
	var node = enemy["node"]
	var distance = to_player.length()
	var dir = to_player.normalized() if distance > 0.1 else Vector2.ZERO
	match behavior:
		"stationary_shooter":
			return
		"caster":
			if distance < 170.0:
				node.position -= dir * float(enemy["speed"]) * 0.95 * delta
			elif distance > 260.0:
				node.position += dir * float(enemy["speed"]) * 0.65 * delta
		"fast_chaser":
			var side = dir.rotated(PI * 0.5) * sin(elapsed * 8.0 + float(enemy.get("move_phase", 0.0))) * 0.45
			node.position += (dir + side).normalized() * float(enemy["speed"]) * 1.25 * delta
		"slow_brute":
			if distance > 2.0:
				node.position += dir * float(enemy["speed"]) * 0.65 * delta
		_:
			if distance > 4.0:
				node.position += dir * float(enemy["speed"]) * delta
	node.position = node.position.clamp(Vector2.ZERO, arena.size - node.size)


func _fire_enemy_projectile(enemy: Dictionary, dir: Vector2, speed: float, color: Color, size: Vector2, label: String) -> void:
	if dir.length() <= 0.01:
		return
	var node = ColorRect.new()
	node.size = size
	node.color = color
	node.position = _enemy_center(enemy) - node.size * 0.5
	enemy_bullet_layer.add_child(node)
	enemy_bullets.append({
		"node": node,
		"dir": dir.normalized(),
		"speed": speed,
		"damage": max(1.0, float(enemy["attack"]) - float(player_stats.get("defense", 0.0))),
		"life": 3.0
	})
	if label != "":
		_spawn_float_text(_enemy_center(enemy), label, color)


func _fire_enemy_spread(enemy: Dictionary, base_dir: Vector2, count: int, angle_step: float, speed: float, color: Color, label: String) -> void:
	var start = -angle_step * float(count - 1) * 0.5
	for i in range(count):
		var dir = base_dir.rotated(start + angle_step * float(i))
		_fire_enemy_projectile(enemy, dir, speed, color, Vector2(11, 11), label if i == 0 else "")


func _update_summons(delta: float) -> void:
	for i in range(summons.size() - 1, -1, -1):
		var summon = summons[i]
		var node = summon["node"]
		summon["life"] = float(summon["life"]) - delta
		if float(summon["life"]) <= 0.0:
			node.queue_free()
			summons.remove_at(i)
			continue
		var target = _nearest_enemy_from(node.position + node.size * 0.5)
		if target != null:
			var desired = _enemy_center(target) - (node.position + node.size * 0.5)
			if desired.length() > 60.0:
				node.position += desired.normalized() * 150.0 * delta
			summon["attack_timer"] = float(summon["attack_timer"]) - delta
			if summon["attack_timer"] <= 0.0 and desired.length() <= 90.0:
				summon["attack_timer"] = 0.7
				_damage_enemy(target, float(player_stats.get("summon_power", 6.0)), "余烬仆从", false, false)
				player_energy = min(player_max_energy, player_energy + summon_energy_gain)


func _update_status_effects(delta: float) -> void:
	for enemy in enemies.duplicate():
		if float(enemy.get("burn_time", 0.0)) > 0.0:
			enemy["burn_time"] = float(enemy["burn_time"]) - delta
			enemy["burn_tick"] = float(enemy["burn_tick"]) - delta
			if enemy["burn_tick"] <= 0.0:
				enemy["burn_tick"] = 1.0
				_damage_enemy(enemy, float(enemy.get("burn", 0.0)) * burn_damage_multiplier, "灼烧", false, false)
			if float(enemy["burn_time"]) <= 0.0:
				enemy["burn_stacks"] = 0
		if float(enemy.get("burn_explosion_cooldown", 0.0)) > 0.0:
			enemy["burn_explosion_cooldown"] = max(0.0, float(enemy["burn_explosion_cooldown"]) - delta)
		if float(enemy.get("armor_break_time", 0.0)) > 0.0:
			enemy["armor_break_time"] = float(enemy["armor_break_time"]) - delta
			if float(enemy["armor_break_time"]) <= 0.0:
				enemy["armor_break"] = 0


func _damage_enemy(enemy: Dictionary, amount: float, source: String, can_crit: bool = true, direct_damage: bool = true) -> void:
	if enemy == null:
		return
	var damage = amount
	if can_crit and randf() < float(player_stats.get("crit_rate", 0.0)):
		damage *= float(player_stats.get("crit_damage", 1.8))
		damage += float(player_stats.get("attack", 12.0)) * crit_bonus_scale
		source += " 暴击"
	if direct_damage:
		damage *= 1.0 + int(enemy.get("armor_break", 0)) * 0.12
		if bool(enemy.get("guarded", false)):
			damage *= 0.7
			enemy["guarded"] = false
		damage = max(1.0, damage - float(enemy.get("defense", 0.0)))
	enemy["hp"] = float(enemy["hp"]) - damage
	var hp_bar = enemy.get("hp_bar", null)
	if hp_bar != null:
		hp_bar.value = max(0.0, float(enemy["hp"]))
	total_damage += damage
	damage_curve.append({"time": elapsed, "damage": total_damage})
	_spawn_float_text(_enemy_center(enemy), source + " -" + _fmt(damage), Color(1.0, 0.86, 0.22))
	if float(enemy["hp"]) <= 0.0:
		_kill_enemy(enemy)


func _kill_enemy(enemy: Dictionary) -> void:
	kills += 1
	var node = enemy["node"]
	node.queue_free()
	enemies.erase(enemy)
	_spawn_float_text(node.position, "击败", Color(0.60, 1.0, 0.55))


func _take_damage(amount: float) -> void:
	if invincible_timer > 0.0:
		return
	player_hp = max(0.0, player_hp - amount)
	total_taken += amount
	invincible_timer = 0.35
	_spawn_float_text(_player_center(), "-" + _fmt(amount), Color(1.0, 0.25, 0.20))
	if player_hp <= 0.0:
		_lose_game()


func _check_wave_clear() -> void:
	if room_state != "playing":
		return
	if enemies.is_empty():
		if not enemy_queue.is_empty():
			_spawn_next_wave()
		else:
			_show_item_reward()


func _on_crit_button_pressed() -> void:
	_pick_choice(0)


func _on_burn_button_pressed() -> void:
	_pick_choice(1)


func _on_summon_button_pressed() -> void:
	_pick_choice(2)


func _pick_choice(slot: int) -> void:
	if room_state == "build_select":
		var build_id = ["crit", "burn", "summon"][slot]
		_start_game(build_id)
		return
	if room_state != "item_reward" or slot >= offered_item_ids.size():
		return
	var item_id = offered_item_ids[slot]
	if not player_items.has(item_id):
		player_items.append(item_id)
	_apply_item(item_id)
	_refresh_player_derived_stats(16.0)
	upgrade_panel.visible = false
	room_state = "playing"
	current_stage_index += 1
	_start_stage(current_stage_index)


func _show_item_reward() -> void:
	if current_stage_index >= config.get("stages", []).size() - 1:
		_win_game()
		return
	room_state = "item_reward"
	upgrade_panel.visible = true
	upgrade_title.text = "房间清理完成：选择 1 件道具"
	offered_item_ids = _roll_item_choices()
	var buttons = [crit_button, burn_button, summon_button]
	for i in range(buttons.size()):
		var item_id = offered_item_ids[i]
		var item = items_by_id.get(item_id, {})
		buttons[i].text = item.get("name", item_id) + "\n" + _item_short_desc(item_id)
	log_label.text = "清房奖励：选择一个道具进入下一房间"
	_update_stats_panel()


func _roll_item_choices() -> Array:
	var pool: Array = []
	for item in config.get("items", []):
		var item_id = String(item.get("id", ""))
		if not player_items.has(item_id):
			pool.append(item_id)
	pool.shuffle()
	while pool.size() < 3:
		for item in config.get("items", []):
			pool.append(String(item.get("id", "")))
	return pool.slice(0, 3)


func _item_short_desc(item_id: String) -> String:
	match item_id:
		"prism_charm":
			return "暴击流核心：暴击率 +10%"
		"blade_gear":
			return "暴击流核心：暴击追加 attack*0.6"
		"ember_hourglass":
			return "持续输出核心：灼烧更久更痛"
		"fission_spark":
			return "持续输出核心：4 层灼烧爆炸"
		"ash_bell":
			return "召唤流核心：召唤上限 +1"
		"resonance_core":
			return "召唤流核心：召唤攻击回能"
		"blood_lens":
			return "暴击/通用：攻击与暴击提升"
		"iron_heart":
			return "生存通用：生命与防御提升"
		"swift_boots":
			return "持续/走位：移动速度提升"
		"hot_coal":
			return "持续输出：灼烧强度提升"
		"little_furnace":
			return "召唤流：召唤物攻击提升"
		"battery_flask":
			return "技能循环：能量恢复提升"
		_:
			return "未知道具"


func _base_stats_text() -> String:
	if config.is_empty() or config.get("characters", []).is_empty():
		return "属性：等待配置加载"
	var stats = config.get("characters", [])[0].get("base_stats", {})
	return "基础属性\nHP:%s  攻击:%s  防御:%s\n暴击:%d%%  暴伤:%s\n速度:%s  灼烧:%s  召唤:%s\n\n属性点机制：开局选择流派后自动分配 6 点。" % [
		_fmt(stats.get("max_hp", 0)),
		_fmt(stats.get("attack", 0)),
		_fmt(stats.get("defense", 0)),
		int(float(stats.get("crit_rate", 0.0)) * 100.0),
		_fmt(stats.get("crit_damage", 0)),
		_fmt(stats.get("speed", 0)),
		_fmt(stats.get("burn_power", 0)),
		_fmt(stats.get("summon_power", 0))
	]


func _update_stats_panel() -> void:
	if stats_label == null:
		return
	var item_names: Array[String] = []
	for item_id in player_items:
		item_names.append(items_by_id.get(item_id, {}).get("name", item_id))
	var items_text = "无" if item_names.is_empty() else "、".join(item_names)
	stats_label.text = "当前流派：%s\nHP:%s/%s  攻击:%s  防御:%s\n暴击:%d%%  暴伤:%s\n速度:%s  灼烧:%s  召唤:%s\n能量恢复:%s  召唤上限:%s\n\n已获得道具：%s" % [
		_build_display_name(selected_build),
		_fmt(player_hp),
		_fmt(player_max_hp),
		_fmt(player_stats.get("attack", 0)),
		_fmt(player_stats.get("defense", 0)),
		int(float(player_stats.get("crit_rate", 0.0)) * 100.0),
		_fmt(player_stats.get("crit_damage", 0)),
		_fmt(player_stats.get("speed", 0)),
		_fmt(player_stats.get("burn_power", 0)),
		_fmt(player_stats.get("summon_power", 0)),
		_fmt(player_stats.get("energy_regen", 0)),
		summon_limit,
		items_text
	]


func _win_game() -> void:
	room_state = "finished"
	_show_result(true)


func _lose_game() -> void:
	room_state = "finished"
	_show_result(false)


func _show_result(victory: bool) -> void:
	result_panel.visible = true
	result_label.text = "%s\n用时：%s 秒\n击败：%s\n剩余 HP：%s\n总伤害：%s\n承受伤害：%s\n技能次数：%s\n伤害曲线点：%s" % [
		"通关成功" if victory else "探索失败",
		_fmt(elapsed),
		kills,
		_fmt(player_hp),
		_fmt(total_damage),
		_fmt(total_taken),
		str(skill_cast_counts),
		damage_curve.size()
	]
	_export_result(victory)


func _on_restart_button_pressed() -> void:
	_show_build_select()


func _on_reload_config_button_pressed() -> void:
	_load_config()
	if room_state != "error":
		_show_build_select()


func _on_back_menu_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/LaunchMenu.tscn")


func _export_result(victory: bool) -> void:
	var file = FileAccess.open(RESULT_JSON, FileAccess.WRITE)
	if file == null:
		return
	var result = {
		"victory": victory,
		"mode": "playable_realtime",
		"turns": 0,
		"ticks": 0,
		"seconds": elapsed,
		"kills": kills,
		"player_hp": player_hp,
		"player_max_hp": player_max_hp,
		"skill_cast_counts": skill_cast_counts,
		"total_damage": total_damage,
		"total_taken": total_taken,
		"damage_curve": damage_curve,
		"last_build": selected_build,
		"items": player_items
	}
	file.store_string(JSON.stringify(result, "\t", false))
	_export_result_csv(result)


func _export_result_csv(result: Dictionary) -> void:
	var file = FileAccess.open(RESULT_CSV, FileAccess.WRITE)
	if file == null:
		return
	file.store_line("section,key,value")
	file.store_line("summary,victory,%s" % result.get("victory", false))
	file.store_line("summary,mode,%s" % _csv_value(result.get("mode", "")))
	file.store_line("summary,turns,%s" % result.get("turns", 0))
	file.store_line("summary,ticks,%s" % result.get("ticks", 0))
	file.store_line("summary,seconds,%s" % _fmt(result.get("seconds", 0.0)))
	file.store_line("summary,player_hp,%s" % _fmt(result.get("player_hp", 0.0)))
	file.store_line("summary,total_damage,%s" % _fmt(result.get("total_damage", 0.0)))
	file.store_line("summary,total_taken,%s" % _fmt(result.get("total_taken", 0.0)))
	for skill_id in result.get("skill_cast_counts", {}).keys():
		file.store_line("skill_cast_counts,%s,%s" % [_csv_value(skill_id), result["skill_cast_counts"][skill_id]])
	file.store_line("")
	file.store_line("curve_index,time,total_damage")
	var curve: Array = result.get("damage_curve", [])
	for i in range(curve.size()):
		var point: Dictionary = curve[i]
		file.store_line("%s,%s,%s" % [i + 1, _fmt(point.get("time", 0.0)), _fmt(point.get("damage", 0.0))])


func _update_ui() -> void:
	hp_bar.max_value = player_max_hp
	hp_bar.value = player_hp
	energy_bar.max_value = player_max_energy
	energy_bar.value = player_energy
	skill_label.text = "J普攻  K裂芯:%s  L燃烬:%s\nU碎甲:%s  I召唤:%s" % [_fmt(core_timer), _fmt(burn_timer), _fmt(armor_timer), _fmt(summon_timer)]
	if room_state == "playing":
		status_label.text = "HP %s/%s  能量 %s/%s\n敌人 %s  道具 %s" % [_fmt(player_hp), _fmt(player_max_hp), _fmt(player_energy), _fmt(player_max_energy), enemies.size(), player_items.size()]
		_update_stats_panel()


func _nearest_enemy():
	return _nearest_enemy_from(_player_center())


func _nearest_enemy_from(pos: Vector2):
	var best = null
	var best_dist = 999999.0
	for enemy in enemies:
		var dist = pos.distance_squared_to(_enemy_center(enemy))
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best


func _player_center() -> Vector2:
	return player_node.position + player_node.size * 0.5


func _enemy_center(enemy: Dictionary) -> Vector2:
	var node = enemy["node"]
	return node.position + node.size * 0.5


func _rects_overlap(a_pos: Vector2, a_size: Vector2, b_pos: Vector2, b_size: Vector2) -> bool:
	return Rect2(a_pos, a_size).intersects(Rect2(b_pos, b_size))


func _spawn_float_text(pos: Vector2, text: String, color: Color) -> void:
	var label = Label.new()
	label.text = text
	label.position = pos
	label.modulate = color
	float_layer.add_child(label)
	float_texts.append({"node": label, "life": 0.8})


func _update_float_texts(delta: float) -> void:
	for i in range(float_texts.size() - 1, -1, -1):
		var item = float_texts[i]
		var node = item["node"]
		item["life"] = float(item["life"]) - delta
		node.position.y -= 28.0 * delta
		node.modulate.a = max(0.0, float(item["life"]) / 0.8)
		if float(item["life"]) <= 0.0:
			node.queue_free()
			float_texts.remove_at(i)


func _clear_runtime_nodes() -> void:
	for layer in [enemy_layer, bullet_layer, enemy_bullet_layer, summon_layer, float_layer]:
		for child in layer.get_children():
			child.queue_free()
	enemies.clear()
	bullets.clear()
	enemy_bullets.clear()
	summons.clear()
	float_texts.clear()


func _record_skill_cast(skill_id: String) -> void:
	skill_cast_counts[skill_id] = int(skill_cast_counts.get(skill_id, 0)) + 1


func _build_display_name(build_id: String) -> String:
	match build_id:
		"crit":
			return "裂芯暴击流"
		"burn":
			return "余火持续输出流"
		"summon":
			return "余烬召唤流"
		_:
			return "未选择"


func _fmt(value: Variant) -> String:
	return "%.1f" % float(value)


func _csv_value(value: Variant) -> String:
	var text = String(value)
	if text.find(",") >= 0 or text.find("\"") >= 0 or text.find("\n") >= 0:
		return "\"" + text.replace("\"", "\"\"") + "\""
	return text
