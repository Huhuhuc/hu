extends Control


func _ready() -> void:
	# 无界面验证不需要停在菜单。
	# 如果启动参数要求运行模拟，就直接进入模拟器面板。
	var args = _all_cmdline_args()
	if args.has("--batch-sim") or args.has("--compare-strategies") or args.has("--single-sim") or args.has("--smoke-batch") or args.has("--smoke-turn") or args.has("--smoke-tick") or args.has("--smoke-replay"):
		_open_simulator_deferred.call_deferred()


func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/PlayableGame.tscn")


func _on_simulator_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _open_simulator_deferred() -> void:
	# 直接在 _ready 里切场景，可能和 Godot 场景树初始化冲突。
	# 所以先延后一帧调用，再在这里切换场景。
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _all_cmdline_args() -> Array[String]:
	# Godot 会把引擎参数和项目参数分开放。
	# `--` 后面的参数只会出现在 get_cmdline_user_args()，
	# 所以验证入口必须把两边都读出来。
	var result: Array[String] = []
	for arg in OS.get_cmdline_args():
		result.append(String(arg))
	for arg in OS.get_cmdline_user_args():
		result.append(String(arg))
	return result
