extends Control


func _ready() -> void:
	var args = _all_cmdline_args()
	if args.has("--batch-sim") or args.has("--compare-strategies") or args.has("--single-sim") or args.has("--smoke-batch") or args.has("--smoke-turn") or args.has("--smoke-tick") or args.has("--smoke-replay"):
		_open_simulator_deferred.call_deferred()


func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/PlayableGame.tscn")


func _on_simulator_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _open_simulator_deferred() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _all_cmdline_args() -> Array[String]:
	var result: Array[String] = []
	for arg in OS.get_cmdline_args():
		result.append(String(arg))
	for arg in OS.get_cmdline_user_args():
		result.append(String(arg))
	return result

