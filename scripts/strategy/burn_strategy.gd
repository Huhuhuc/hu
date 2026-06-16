class_name BurnStrategy
extends "res://scripts/strategy/strategy_base.gd"

# 持续输出策略：保持灼烧层数在线，
# 依靠持续伤害和更保守的道具选择提升长线稳定性。

func get_strategy_id() -> String:
	return "burn_strategy"


func choose_initial_build(context: Dictionary) -> Dictionary:
	return _initial_build_from_context(context, {
		"stat_points": {"speed": 3, "burn_power": 3},
		"item_ids": ["ember_hourglass", "fission_spark"],
		"notes": "余火持续输出流：尽早挂灼烧。"
	})


func choose_reward(context: Dictionary) -> Dictionary:
	return _pick_reward_by_priority(context, [
		"iron_heart",
		"ember_vial",
		"hot_coal",
		"battery_flask",
		"swift_boots",
		"ember_hourglass",
		"fission_spark"
	])


func decide_action(context: Dictionary) -> Dictionary:
	var target_id = String(context.get("current_target_id", ""))
	var enemies: Array = context.get("enemies", [])
	if enemies.is_empty():
		return {"type": "wait"}
	var player: Dictionary = context.get("player", {})
	# 灼烧流用时间换稳定，所以比暴击流更早使用回血道具。
	if float(player.get("hp", 0.0)) < float(player.get("max_hp", 1.0)) * 0.45 and _can_use_item(context, "ember_vial"):
		return {"type": "use_item", "item_id": "ember_vial", "target_id": target_id}
	var target: Dictionary = enemies[0]
	var burn = int(target.get("status", {}).get("burn", 0))
	# 第一优先级是维持足够灼烧层数，保证持续伤害稳定。
	if _can_cast(context, "ember_mark") and burn < 4:
		return {"type": "cast_skill", "skill_id": "ember_mark", "target_id": target_id}
	if _can_cast(context, "armor_pulse") and float(target.get("hp", 0.0)) > float(target.get("max_hp", 1.0)) * 0.5:
		return {"type": "cast_skill", "skill_id": "armor_pulse", "target_id": target_id}
	if _can_cast(context, "core_split"):
		return {"type": "cast_skill", "skill_id": "core_split", "target_id": target_id}
	return {"type": "basic_attack", "target_id": target_id}
