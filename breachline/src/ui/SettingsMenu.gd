extends Control
## Settings: video, audio, controls (remapping), gameplay, accessibility, network, crosshair editor.

var tabs: TabContainer
var rebind_action := ""
var rebind_button: Button
var crosshair_preview: Control


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08, 0.96)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.offset_left = 60
	root.offset_top = 30
	root.offset_right = -60
	root.offset_bottom = -30
	add_child(root)
	var top := HBoxContainer.new()
	top.add_child(UIKit.title("SETTINGS"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(UIKit.button("BACK", func(): Events.open_menu.emit("back"), 120))
	root.add_child(top)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(tabs)
	_build_video()
	_build_audio()
	_build_controls()
	_build_gameplay()
	_build_accessibility()
	_build_network()
	_build_crosshair()


func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	tabs.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(vb)
	return vb


func _build_video() -> void:
	var v := _tab("Video")
	v.add_child(UIKit.slider("Field of view", 60, 120, 1, Settings.fov(), func(x): Settings.set_value("video", "fov", x)))
	v.add_child(UIKit.slider("Viewmodel FOV", 50, 90, 1, float(Settings.get_value("video", "viewmodel_fov", 68)), func(x): Settings.set_value("video", "viewmodel_fov", x)))
	v.add_child(UIKit.checkbox("Fullscreen", bool(Settings.get_value("video", "fullscreen", false)), func(x): Settings.set_value("video", "fullscreen", x)))
	v.add_child(UIKit.checkbox("V-Sync", bool(Settings.get_value("video", "vsync", true)), func(x): Settings.set_value("video", "vsync", x)))
	v.add_child(UIKit.slider("Max FPS", 30, 360, 10, float(Settings.get_value("video", "max_fps", 240)), func(x): Settings.set_value("video", "max_fps", int(x))))
	v.add_child(UIKit.option("Anti-aliasing (MSAA)", ["Off", "2x", "4x", "8x"], int(Settings.get_value("video", "msaa", 2)), func(i): Settings.set_value("video", "msaa", i)))
	v.add_child(UIKit.slider("Render scale", 0.5, 1.0, 0.05, float(Settings.get_value("video", "render_scale", 1.0)), func(x): Settings.set_value("video", "render_scale", x)))
	v.add_child(UIKit.checkbox("Reduced camera motion (no bob/sway)", bool(Settings.get_value("video", "reduced_motion", false)), func(x): Settings.set_value("video", "reduced_motion", x)))


func _build_audio() -> void:
	var v := _tab("Audio")
	for bus in ["master", "sfx", "music", "voice", "ui", "announcer"]:
		v.add_child(UIKit.slider(bus.capitalize() + " volume", 0, 1, 0.01, float(Settings.get_value("audio", bus, 1.0)), func(x): Settings.set_value("audio", bus, x)))
	v.add_child(UIKit.checkbox("Subtitles for announcer", bool(Settings.get_value("audio", "subtitles", true)), func(x): Settings.set_value("audio", "subtitles", x)))


func _build_controls() -> void:
	var v := _tab("Controls")
	v.add_child(UIKit.slider("Mouse sensitivity", 0.1, 5.0, 0.05, float(Settings.get_value("controls", "sensitivity", 1.0)), func(x): Settings.set_value("controls", "sensitivity", x)))
	v.add_child(UIKit.slider("Zoom sensitivity multiplier", 0.2, 1.5, 0.05, float(Settings.get_value("controls", "zoom_sensitivity", 0.8)), func(x): Settings.set_value("controls", "zoom_sensitivity", x)))
	v.add_child(UIKit.checkbox("Raw mouse input", bool(Settings.get_value("controls", "raw_input", true)), func(x): Settings.set_value("controls", "raw_input", x)))
	v.add_child(UIKit.checkbox("Invert vertical look", bool(Settings.get_value("controls", "invert_y", false)), func(x): Settings.set_value("controls", "invert_y", x)))
	v.add_child(UIKit.checkbox("Toggle crouch", bool(Settings.get_value("controls", "toggle_crouch", false)), func(x): Settings.set_value("controls", "toggle_crouch", x)))
	v.add_child(UIKit.checkbox("Toggle walk", bool(Settings.get_value("controls", "toggle_walk", false)), func(x): Settings.set_value("controls", "toggle_walk", x)))
	v.add_child(UIKit.hsep())
	v.add_child(UIKit.label("Key bindings — click a binding then press a key or mouse button (Esc cancels)", UIKit.DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	v.add_child(grid)
	for action in Settings.REMAPPABLE_ACTIONS:
		grid.add_child(UIKit.label(action.replace("_", " ").capitalize()))
		var b := Button.new()
		b.text = Settings.binding_label(action)
		b.custom_minimum_size.x = 160
		b.pressed.connect(func():
			rebind_action = action
			rebind_button = b
			b.text = "press a key...")
		grid.add_child(b)
		grid.add_child(UIKit.button("reset", func():
			Settings.reset_binding(action)
			b.text = Settings.binding_label(action), 80))


func _input(event: InputEvent) -> void:
	if rebind_action.is_empty():
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			rebind_button.text = Settings.binding_label(rebind_action)
		else:
			Settings.rebind(rebind_action, event)
			rebind_button.text = Settings.binding_label(rebind_action)
		rebind_action = ""
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		Settings.rebind(rebind_action, event)
		rebind_button.text = Settings.binding_label(rebind_action)
		rebind_action = ""
		get_viewport().set_input_as_handled()


func _build_gameplay() -> void:
	var v := _tab("Gameplay")
	v.add_child(UIKit.option("Match length (rounds)", [6, 12, 16, 24, 30], [6, 12, 16, 24, 30].find(int(Settings.get_value("gameplay", "max_rounds", 24))), func(i): Settings.set_value("gameplay", "max_rounds", [6, 12, 16, 24, 30][i])))
	v.add_child(UIKit.checkbox("Overtime when tied", bool(Settings.get_value("gameplay", "overtime", true)), func(x): Settings.set_value("gameplay", "overtime", x)))
	v.add_child(UIKit.checkbox("Friendly fire", bool(Settings.get_value("gameplay", "friendly_fire", false)), func(x): Settings.set_value("gameplay", "friendly_fire", x)))
	v.add_child(UIKit.option("Bot difficulty", ["Easy", "Normal", "Hard", "Expert"], int(Settings.get_value("gameplay", "bot_difficulty", 1)), func(i): Settings.set_value("gameplay", "bot_difficulty", i)))
	v.add_child(UIKit.slider("Bots per team (offline)", 0, 5, 1, float(Settings.get_value("gameplay", "bots_per_team", 4)), func(x): Settings.set_value("gameplay", "bots_per_team", int(x))))
	v.add_child(UIKit.checkbox("Show damage numbers", bool(Settings.get_value("gameplay", "damage_numbers", false)), func(x): Settings.set_value("gameplay", "damage_numbers", x)))
	v.add_child(UIKit.slider("Kill feed duration", 2, 12, 1, float(Settings.get_value("gameplay", "killfeed_time", 6)), func(x): Settings.set_value("gameplay", "killfeed_time", x), "s"))


func _build_accessibility() -> void:
	var v := _tab("Accessibility")
	var modes := ["none", "deuteranopia", "protanopia", "tritanopia"]
	v.add_child(UIKit.option("Colour vision mode", ["Default", "Deuteranopia", "Protanopia", "Tritanopia"], modes.find(str(Settings.get_value("accessibility", "colorblind", "none"))), func(i): Settings.set_value("accessibility", "colorblind", modes[i])))
	v.add_child(UIKit.slider("UI scale", 0.75, 1.75, 0.05, float(Settings.get_value("accessibility", "ui_scale", 1.0)), func(x): Settings.set_value("accessibility", "ui_scale", x); UIKit.reset_theme()))
	v.add_child(UIKit.checkbox("Large text", bool(Settings.get_value("accessibility", "large_text", false)), func(x): Settings.set_value("accessibility", "large_text", x); UIKit.reset_theme()))
	v.add_child(UIKit.checkbox("Blood effects", bool(Settings.get_value("accessibility", "blood", true)), func(x): Settings.set_value("accessibility", "blood", x)))
	v.add_child(UIKit.checkbox("High-contrast enemy outlines", bool(Settings.get_value("accessibility", "high_contrast_enemies", false)), func(x): Settings.set_value("accessibility", "high_contrast_enemies", x)))
	v.add_child(UIKit.slider("Screen shake", 0, 1, 0.05, float(Settings.get_value("accessibility", "screen_shake", 1.0)), func(x): Settings.set_value("accessibility", "screen_shake", x)))
	v.add_child(UIKit.slider("Flash intensity", 0.2, 1, 0.05, float(Settings.get_value("accessibility", "flash_intensity", 1.0)), func(x): Settings.set_value("accessibility", "flash_intensity", x)))
	v.add_child(UIKit.checkbox("Subtitles", bool(Settings.get_value("audio", "subtitles", true)), func(x): Settings.set_value("audio", "subtitles", x)))
	v.add_child(UIKit.checkbox("Reduced camera motion", bool(Settings.get_value("video", "reduced_motion", false)), func(x): Settings.set_value("video", "reduced_motion", x)))


func _build_network() -> void:
	var v := _tab("Network")
	v.add_child(UIKit.checkbox("Show latency in HUD", bool(Settings.get_value("network", "show_latency", true)), func(x): Settings.set_value("network", "show_latency", x)))
	v.add_child(UIKit.slider("Interpolation delay (snapshots)", 1, 6, 1, float(Settings.get_value("network", "interp_ticks", 2)), func(x): Settings.set_value("network", "interp_ticks", int(x))))
	v.add_child(UIKit.slider("Default port", 1024, 65535, 1, float(Settings.get_value("network", "port", 27015)), func(x): Settings.set_value("network", "port", int(x))))
	v.add_child(UIKit.hsep())
	v.add_child(UIKit.label("Network simulation (testing only)", UIKit.DIM))
	v.add_child(UIKit.slider("Simulated latency", 0, 400, 10, float(Settings.get_value("network", "sim_latency_ms", 0)), func(x): Settings.set_value("network", "sim_latency_ms", int(x)), "ms"))
	v.add_child(UIKit.slider("Simulated packet loss", 0, 0.5, 0.01, float(Settings.get_value("network", "sim_loss", 0.0)), func(x): Settings.set_value("network", "sim_loss", x)))
	v.add_child(UIKit.slider("Simulated jitter", 0, 200, 5, float(Settings.get_value("network", "sim_jitter_ms", 0)), func(x): Settings.set_value("network", "sim_jitter_ms", int(x)), "ms"))


func _build_crosshair() -> void:
	var v := _tab("Crosshair")
	var ch: Dictionary = Settings.get_value("player", "crosshair", {})
	var preview_panel := UIKit.panel(Vector2(200, 200))
	crosshair_preview = load("res://src/ui/Crosshair.gd").new()
	crosshair_preview.custom_minimum_size = Vector2(200, 200)
	crosshair_preview.preview = true
	preview_panel.add_child(crosshair_preview)
	v.add_child(preview_panel)
	var set_ch := func(k, val):
		ch[k] = val
		Settings.set_value("player", "crosshair", ch)
		crosshair_preview.queue_redraw()
	v.add_child(UIKit.slider("Size", 1, 20, 0.5, float(ch.get("size", 6)), func(x): set_ch.call("size", x)))
	v.add_child(UIKit.slider("Gap", 0, 15, 0.5, float(ch.get("gap", 3)), func(x): set_ch.call("gap", x)))
	v.add_child(UIKit.slider("Thickness", 1, 6, 0.5, float(ch.get("thickness", 2)), func(x): set_ch.call("thickness", x)))
	var colors := ["00ff66", "ffffff", "ff3355", "ffee33", "33ccff", "ff77ff"]
	v.add_child(UIKit.option("Colour", ["Green", "White", "Red", "Yellow", "Cyan", "Pink"], max(colors.find(str(ch.get("color", "00ff66"))), 0), func(i): set_ch.call("color", colors[i])))
	v.add_child(UIKit.checkbox("Outline", bool(ch.get("outline", true)), func(x): set_ch.call("outline", x)))
	v.add_child(UIKit.checkbox("Center dot", bool(ch.get("dot", false)), func(x): set_ch.call("dot", x)))
	v.add_child(UIKit.checkbox("Dynamic (expands with inaccuracy)", bool(ch.get("dynamic", true)), func(x): set_ch.call("dynamic", x)))
	v.add_child(UIKit.checkbox("T-style (no top line)", bool(ch.get("t_style", false)), func(x): set_ch.call("t_style", x)))
