class_name UpdateOverlay
extends CanvasLayer
## NATIVE-BOUNDARY FILE. Modal shown ONLY while a verified OTA is actually
## being activated. Styled to match the game's own panels (dark rounded panel,
## white outlined text). Indeterminate spinner: no fake percentages.

const MESSAGE := "Please wait, applying update"

var _root: Control
var _spinner: Control
var _label: Label

func _init() -> void:
	layer = 100
	visible = false

func _ready() -> void:
	_root = ColorRect.new()
	(_root as ColorRect).color = Color(0, 0, 0, 0.78)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # block all interaction underneath
	add_child(_root)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -110
	panel.offset_bottom = 110
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.92)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	_label = Label.new()
	_label.text = MESSAGE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 40)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 8)
	vb.add_child(_label)
	_spinner = Control.new()
	_spinner.custom_minimum_size = Vector2(64, 64)
	_spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_spinner.draw.connect(_draw_spinner)
	vb.add_child(_spinner)

func _draw_spinner() -> void:
	var t: float = Time.get_ticks_msec() * 0.006
	var c := Vector2(32, 32)
	_spinner.draw_arc(c, 24.0, t, t + 4.4, 32, Color(1.0, 0.92, 0.3), 6.0, true)

func _process(_dt: float) -> void:
	if visible and _spinner:
		_spinner.queue_redraw()

func show_overlay() -> void:
	visible = true

func hide_overlay() -> void:
	visible = false

func message() -> String:
	return MESSAGE
