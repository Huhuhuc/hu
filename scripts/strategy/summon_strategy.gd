class_name SummonStrategy
extends "res://scripts/strategy/strategy_base.gd"

func get_strategy_id() -> String:
	return "summon_strategy"


func choose_initial_build(context: Dictionary) -> Dictionary:
	return _initial_build_from_context(context, {
		"stat_points": {"summon_power": 4, "max_hp": 2},
		"item_ids": ["ash_bell", "resonance_core"],
		"notes": "余烬召唤流：尽早铺场。"
	})


func choose_reward(context: Dictionary) -> Dictionary:
	return _pick_reward_by_priority(context, [
		"little_furnace",
		"battery_flask",
		"iron_heart",
		"ember_vial",
		"hot_coal",
		"ash_bell",
		"resonance_core"
	])


func decide_action(context: Dictionary) -> Dictionary:
	var target_id = String(context.get("current_target_id", ""))
	var enemies: Array = context.get("enemies", [])
	if enemies.is_empty():
		return {"type": "wait"}
	var player: Dictionary = context.get("player", {})
	if float(player.get("hp", 0.0)) < float(player.get("max_hp", 1.0)) * 0.40 and _can_use_item(context, "ember_vial"):
		return {"type": "use_item", "item_id": "ember_vial", "target_id": target_id}
	var summons: Array = player.get("summons", [])
	var summon_limit = int(player.get("summon_limit", 2))
	var target: Dictionary = enemies[0]
	if _can_cast(context, "ember_servant") and summons.size() < summon_limit:
		return {"type": "cast_skill", "skill_id": "ember_servant", "target_id": target_id}
	if _can_cast(context, "ember_mark") and float(target.get("hp", 0.0)) > float(target.get("max_hp", 1.0)) * 0.5:
		return {"type": "cast_skill", "skill_id": "ember_mark", "target_id": target_id}
	if _can_cast(context, "core_split"):
		return {"type": "cast_skill", "skill_id": "core_split", "target_id": target_id}
	return {"type": "basic_attack", "target_id": target_id}
