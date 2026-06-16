class_name StrategyBase
extends RefCounted

# 策略脚本是“玩家怎么决策”的边界。
# 模拟器传入普通字典，策略也返回普通字典。
# 这样以后替换成生成式策略、远程策略或普通脚本策略都比较容易。

func get_strategy_id() -> String:
	return "base"


func choose_initial_build(_context: Dictionary) -> Dictionary:
	# 战斗开始前调用一次。返回属性点和初始道具；
	# 战斗模拟器会先校验，再真正应用。
	return {"stat_points": {}, "item_ids": [], "notes": "base"}


func choose_reward(context: Dictionary) -> Dictionary:
	# 清房后调用。基础策略故意保持简单安全，
	# 子类只需要覆写自己关心的行为。
	var choices: Array = context.get("choices", [])
	if choices.is_empty():
		return {"item_id": ""}
	return {"item_id": choices[0].get("id", ""), "reason": "fallback_first_choice"}


func decide_action(context: Dictionary) -> Dictionary:
	# 玩家可以行动时调用。上下文里包含所有可用动作，
	# 策略不用猜技能冷却、能量或道具次数是否合法。
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
	# 让策略代码更可读的共享工具：每个流派只定义优先级列表，
	# 这里负责扫描合法选项和兜底。
	var choices: Array = context.get("choices", [])
	for preferred in priority:
		for item in choices:
			if String(item.get("id", "")) == String(preferred):
				return {"item_id": String(preferred), "reason": "priority_match"}
	if choices.is_empty():
		return {"item_id": ""}
	return {"item_id": choices[0].get("id", ""), "reason": "fallback_first_choice"}


func _initial_build_from_context(context: Dictionary, fallback: Dictionary) -> Dictionary:
	# 优先使用配置里的构筑预设。
	# 如果测试只传入最小上下文、没有预设，也能用兜底配置跑起来。
	var build: Dictionary = fallback.duplicate(true)
	var preset = context.get("build_preset", {})
	if typeof(preset) == TYPE_DICTIONARY and not preset.is_empty():
		build["stat_points"] = preset.get("stat_points", {}).duplicate(true)
		build["item_ids"] = preset.get("item_ids", []).duplicate()
		build["notes"] = preset.get("synergy", build.get("notes", ""))
	return build
