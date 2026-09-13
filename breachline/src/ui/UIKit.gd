class_name UIKit
extends RefCounted
## Shared theme + small builders so every menu looks like one game. Honours UI scale / large text.

const BG := Color(0.07, 0.08, 0.1)
const PANEL := Color(0.11, 0.12, 0.15, 0.94)
const ACCENT := Color(1.0, 0.48, 0.1)
const ACCENT2 := Color(0.3, 0.7, 1.0)
const TEXT := Color(0.92, 0.92, 0.9)
const DIM := Color(0.6, 0.62, 0.66)
const OK := Color(0.35, 0.85, 0.45)
const BAD := Color(0.95, 0.3, 0.25)

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	var scale := float(Settings.get_value("accessibility", "ui_scale", 1.0))
	var large := bool(Settings.get_value("accessibility", "large_text", false))
	var base := int(16 * scale * (1.25 if large else 1.0))
	t.default_font_size = base
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.corner_radius_top_left = 6
	panel.corner_radius_top_right = 6
	panel.corner_radius_bottom_left = 6
	panel.corner_radius_bottom_right = 6
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	t.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.18, 0.2, 0.24)
	btn.corner_radius_top_left = 4
	btn.corner_radius_top_right = 4
	btn.corner_radius_bottom_left = 4
	btn.corner_radius_bottom_right = 4
	btn.content_margin_left = 14
	btn.content_margin_right = 14
	btn.content_margin_top = 8
	btn.content_margin_bottom = 8
	t.set_stylebox("normal", "Button", btn)
	var hover := btn.duplicate()
	hover.bg_color = Color(0.26, 0.28, 0.33)
	t.set_stylebox("hover", "Button", hover)
	var pressed := btn.duplicate()
	pressed.bg_color = ACCENT.darkened(0.3)
	t.set_stylebox("pressed", "Button", pressed)
	var focus := btn.duplicate()
	focus.bg_color = Color(0.26, 0.28, 0.33)
	focus.border_color = ACCENT
	focus.border_width_bottom = 2
	t.set_stylebox("focus", "Button", focus)
	var disabled := btn.duplicate()
	disabled.bg_color = Color(0.12, 0.13, 0.15)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	var le := btn.duplicate()
	le.bg_color = Color(0.05, 0.06, 0.08)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_stylebox("panel", "TabContainer", panel)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_stylebox("normal", "OptionButton", btn)
	t.set_stylebox("hover", "OptionButton", hover)
	t.set_stylebox("pressed", "OptionButton", pressed)
	t.set_stylebox("focus", "OptionButton", focus)
	_theme = t
	return t


static func reset_theme() -> void:
	_theme = null


static func title(text: String, size: int = 34) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(size * float(Settings.get_value("accessibility", "ui_scale", 1.0))))
	l.add_theme_color_override("font_color", ACCENT)
	return l


static func label(text: String, color: Color = TEXT, size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if size > 0:
		l.add_theme_font_size_override("font_size", int(size * float(Settings.get_value("accessibility", "ui_scale", 1.0))))
	return l


static func button(text: String, cb: Callable, min_width: int = 220) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.x = min_width
	b.pressed.connect(cb)
	b.pressed.connect(func(): Audio.play_2d("ui/click.wav", -12.0))
	b.mouse_entered.connect(func(): Audio.play_2d("ui/hover.wav", -18.0))
	return b


static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	return p


static func centered(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(child)
	return c


static func hsep() -> HSeparator:
	return HSeparator.new()


static func row(children: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	for c in children:
		h.add_child(c)
	return h


static func slider(label_text: String, min_v: float, max_v: float, step: float, value: float, cb: Callable, suffix: String = "") -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := label(label_text)
	l.custom_minimum_size.x = 240
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size.x = 260
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(s)
	var v := label(("%.2f" if step < 1.0 else "%d") % value + suffix, DIM)
	v.custom_minimum_size.x = 70
	h.add_child(v)
	s.value_changed.connect(func(val):
		v.text = (("%.2f" if step < 1.0 else "%d") % val) + suffix
		cb.call(val))
	return h


static func checkbox(label_text: String, value: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = label_text
	c.button_pressed = value
	c.toggled.connect(cb)
	return c


static func option(label_text: String, options: Array, selected: int, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := label(label_text)
	l.custom_minimum_size.x = 240
	h.add_child(l)
	var o := OptionButton.new()
	for opt in options:
		o.add_item(str(opt))
	o.selected = clampi(selected, 0, options.size() - 1)
	o.item_selected.connect(cb)
	o.custom_minimum_size.x = 260
	h.add_child(o)
	return h


static func team_color(team: int) -> Color:
	var pal := Settings.colorblind_palette()
	return pal.attackers if team == Teams.ATTACKERS else (pal.defenders if team == Teams.DEFENDERS else DIM)


static func fmt_time(t: float) -> String:
	var s := int(ceil(max(t, 0.0)))
	return "%d:%02d" % [s / 60, s % 60]
