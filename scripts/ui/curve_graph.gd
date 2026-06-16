class_name CurveGraph
extends Control

var points: Array = []
var caption = "暂无伤害曲线"


func set_curve(curve: Array, text: String = "累计伤害曲线") -> void:
	# 外部传入的是模拟器导出的普通字典数组。
	# 这里复制一份，避免 UI 绘制过程中反向修改结果数据。
	points = curve.duplicate(true)
	caption = text
	queue_redraw()


func clear_curve(text: String = "暂无伤害曲线") -> void:
	points.clear()
	caption = text
	queue_redraw()


func _draw() -> void:
	# Control 的绘制入口。Godot 会在 queue_redraw() 后调用这里，
	# 所以曲线刷新不需要额外创建或销毁节点。
	var rect = Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.12, 0.13, 0.14), true)
	draw_rect(rect, Color(0.30, 0.31, 0.32), false, 1.0)
	var font = get_theme_default_font()
	if font == null:
		return
	var font_size = 13
	draw_string(font, Vector2(10, 18), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.90, 0.90, 0.86))
	if points.is_empty():
		draw_string(font, Vector2(10, 44), "运行单场模拟后显示曲线：橙线=累计伤害，蓝柱=单次伤害。", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.62, 0.62, 0.62))
		return
	var plot = Rect2(Vector2(46, 30), Vector2(max(20.0, size.x - 64.0), max(20.0, size.y - 54.0)))
	var max_time = 0.0
	var max_total = 0.0
	var max_delta = 0.0
	for point in points:
		# 兼容单场、批量和旧字段名，避免导出结构小调整后图表直接空白。
		max_time = max(max_time, float(point.get("time", 0.0)))
		max_total = max(max_total, float(point.get("damage", point.get("total_damage", 0.0))))
		max_delta = max(max_delta, float(point.get("delta", point.get("damage_delta", point.get("damage", 0.0)))))
	max_time = max(1.0, max_time)
	max_total = max(1.0, max_total)
	max_delta = max(1.0, max_delta)
	_draw_grid(plot)
	_draw_legend(font, plot)
	var total_color = Color(1.0, 0.58, 0.18)
	var delta_color = Color(0.20, 0.72, 0.90, 0.45)
	# 蓝色竖线表示每个事件造成的单次伤害，橙色折线表示累计伤害。
	for point in points:
		var point_x = _time_to_x(point, plot, max_time)
		var delta_value = float(point.get("delta", point.get("damage_delta", 0.0)))
		var delta_ratio = clamp(delta_value / max_delta, 0.0, 1.0)
		var bar_top = plot.end.y - plot.size.y * delta_ratio
		draw_line(Vector2(point_x, plot.end.y), Vector2(point_x, bar_top), delta_color, 2.0)
	var previous = _total_point(points[0], plot, max_time, max_total)
	for i in range(1, points.size()):
		var current = _total_point(points[i], plot, max_time, max_total)
		draw_line(previous, current, total_color, 2.2)
		previous = current
	draw_circle(previous, 3.5, Color(1.0, 0.84, 0.22))
	draw_string(font, Vector2(8, plot.position.y + 4), "累计 " + _fmt(max_total), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.68, 0.68, 0.66))
	draw_string(font, Vector2(8, plot.end.y), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.68, 0.68, 0.66))
	draw_string(font, Vector2(plot.end.x - 34, size.y - 8), _fmt(max_time), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.68, 0.68, 0.66))
	draw_string(font, Vector2(plot.end.x - 114, plot.position.y + 4), "单次峰值 " + _fmt(max_delta), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.68, 0.68, 0.66))
	draw_string(font, Vector2(plot.position.x, size.y - 8), "time", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.68, 0.68, 0.66))


func _draw_grid(plot: Rect2) -> void:
	# 固定五等分网格，保证小尺寸面板也能快速读出趋势。
	for i in range(5):
		var t = float(i) / 4.0
		var y = plot.position.y + plot.size.y * t
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(0.23, 0.24, 0.25), 1.0)
	for i in range(5):
		var t = float(i) / 4.0
		var x = plot.position.x + plot.size.x * t
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(0.20, 0.21, 0.22), 1.0)


func _draw_legend(font: Font, plot: Rect2) -> void:
	var legend_x = plot.position.x + 6.0
	var legend_y = plot.position.y + 18.0
	draw_rect(Rect2(Vector2(legend_x, legend_y - 10.0), Vector2(10, 4)), Color(1.0, 0.58, 0.18), true)
	draw_string(font, Vector2(legend_x + 14.0, legend_y), "累计伤害", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.86, 0.86, 0.82))
	draw_rect(Rect2(Vector2(legend_x + 84.0, legend_y - 10.0), Vector2(10, 10)), Color(0.20, 0.72, 0.90, 0.60), true)
	draw_string(font, Vector2(legend_x + 98.0, legend_y), "单次伤害", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.86, 0.86, 0.82))


func _time_to_x(point: Dictionary, plot: Rect2, max_time: float) -> float:
	return plot.position.x + plot.size.x * clamp(float(point.get("time", 0.0)) / max_time, 0.0, 1.0)


func _total_point(point: Dictionary, plot: Rect2, max_time: float, max_total: float) -> Vector2:
	var x_ratio = clamp(float(point.get("time", 0.0)) / max_time, 0.0, 1.0)
	var y_ratio = clamp(float(point.get("damage", point.get("total_damage", 0.0))) / max_total, 0.0, 1.0)
	return Vector2(plot.position.x + plot.size.x * x_ratio, plot.end.y - plot.size.y * y_ratio)


func _fmt(value: float) -> String:
	if value >= 100.0:
		return str(int(round(value)))
	return "%.1f" % value
