class_name StrategyBase
extends RefCounted

func get_strategy_id() -> String:
	return "base"


func choose_initial_build(_context: Dictionary) -> Dictionary:
	return {"stat_points": {}, "item_ids": [], "notes": "base"}


func choose_reward(context: Dictionary) -> Dictionary:
	var choices: Array = context.get("choices", [])
	if choices.is_empty():
		return {"item_id": ""}
	return {"item_id": choices[0].get("id", ""), "reason": "fallback_first_choice"}


func decide_action(context: Dictionary) -> Dictionary:
	return {"type": "basic_attack", "target_id": context.get("current_target_id", "")}


func _can_cast(context: Dictionary, skill_id: String) -> bool:
	for action in context.get("available_actions", []):
		if action.get("type", "") == "cast_skill" and action.get("skill_id", "") == skill_id:
			return true
	return false


func _can_use_item(context: Dictionary, item_id: String) -> bool:
	for action in context.get("available_actions", []):
		if action.get("type", "") == "use_item" and action.get("item_id", "") == item_id:
			return true
	return false


func _pick_reward_by_priority(context: Dictionary, priority: Array) -> Dictionary:
	var choices: Array = context.get("choices", [])
	for preferred in priority:
		for item in choices:
			if String(item.get("id", "")) == String(preferred):
				return {"item_id": String(preferred), "reason": "priority_match"}
	if choices.is_empty():
		return {"item_id": ""}
	return {"item_id": choices[0].get("id", ""), "reason": "fallback_first_choice"}


func _initial_build_from_context(context: Dictionary, fallback: Dictionary) -> Dictionary:
	var build: Dictionary = fallback.duplicate(true)
	var preset = context.get("build_preset", {})
	if typeof(preset) == TYPE_DICTIONARY and not preset.is_empty():
		build["stat_points"] = preset.get("stat_points", {}).duplicate(true)
		build["item_ids"] = preset.get("item_ids", []).duplicate()
		build["notes"] = preset.get("synergy", build.get("notes", ""))
	return build
