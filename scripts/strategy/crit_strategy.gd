class_name CritStrategy
extends "res://scripts/strategy/strategy_base.gd"

# 爆发策略：先上破甲，再趁目标脆弱时释放爆发技能。
# 这种打法理论上通关更快，但波动也更大。

func get_strategy_id() -> String:
	return "crit_strategy"


func choose_initial_build(context: Dictionary) -> Dictionary:
	return _initial_build_from_context(context, {
		"stat_points": {"attack": 3, "crit_rate": 3},
		"item_ids": ["prism_charm", "blade_gear"],
		"notes": "裂芯暴击流：先破甲再爆发。"
	})


func choose_reward(context: Dictionary) -> Dictionary:
	return _pick_reward_by_priority(context, [
		"blood_lens",
		"battery_flask",
		"swift_boots",
		"ember_vial",
		"hot_coal",
		"little_furnace",
		"prism_charm",
		"blade_gear",
		"iron_heart"
	])


func decide_action(context: Dictionary) -> Dictionary:
	var target_id = String(context.get("current_target_id", ""))
	var enemies: Array = context.get("enemies", [])
	if enemies.is_empty():
		return {"type": "wait"}
	var player: Dictionary = context.get("player", {})
	# 生存判断放在输出逻辑前面，因为再高的爆发，
	# 如果经常暴毙，批量稳定性也会很差。
	if float(player.get("hp", 0.0)) < float(player.get("max_hp", 1.0)) * 0.30 and _can_use_item(context, "ember_vial"):
		return {"type": "use_item", "item_id": "ember_vial", "target_id": target_id}
	var target: Dictionary = enemies[0]
	var armor_break = int(target.get("status", {}).get("armor_break", 0))
	# 理想爆发窗口：先制造 armor_break，
	# 再趁目标仍有 debuff 时使用 core_split。
	if _can_cast(context, "armor_pulse") and armor_break <= 0:
		return {"type": "cast_skill", "skill_id": "armor_pulse", "target_id": target_id}
	if _can_cast(context, "core_split") and armor_break > 0:
		return {"type": "cast_skill", "skill_id": "core_split", "target_id": target_id}
	return {"type": "basic_attack", "target_id": target_id}
