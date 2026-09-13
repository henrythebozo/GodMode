extends Node
## Autoload: user settings persisted to user://settings.cfg. Every option in the settings menu maps
## to a key here; `Events.settings_changed` fires after any change so systems can re-read values.

const PATH := "user://settings.cfg"
const REMAPPABLE_ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right", "jump", "crouch", "walk", "fire", "alt_fire",
	"reload", "use", "drop", "inspect", "buy_menu", "scoreboard", "slot_primary", "slot_secondary", "slot_melee",
	"slot_grenade", "slot_bomb", "next_weapon", "prev_weapon", "quick_switch", "pause", "console", "chat",
]

var data := {
	"player": {"name": "Operator", "crosshair": {"size": 6.0, "gap": 3.0, "thickness": 2.0, "color": "00ff66", "outline": true, "dot": false, "dynamic": true, "t_style": false}},
	"controls": {"sensitivity": 1.0, "raw_input": true, "invert_y": false, "zoom_sensitivity": 0.8, "toggle_crouch": false, "toggle_walk": false, "toggle_zoom": false},
	"video": {"fov": 90.0, "fullscreen": false, "vsync": true, "max_fps": 240, "msaa": 2, "shadows": 2, "render_scale": 1.0, "reduced_motion": false, "viewmodel_fov": 68.0, "brightness": 1.0},
	"audio": {"master": 0.8, "sfx": 1.0, "music": 0.5, "voice": 1.0, "ui": 0.8, "announcer": 1.0, "subtitles": true},
	"accessibility": {"colorblind": "none", "ui_scale": 1.0, "blood": true, "screen_shake": 1.0, "high_contrast_enemies": false, "flash_intensity": 1.0, "large_text": false},
	"network": {"name_override": "", "last_ip": "127.0.0.1", "port": 27015, "interp_ticks": 2, "show_latency": true, "sim_latency_ms": 0, "sim_loss": 0.0, "sim_jitter_ms": 0},
	"gameplay": {"max_rounds": 24, "overtime": true, "bot_difficulty": 1, "bots_per_team": 4, "auto_reload_on_empty": true, "friendly_fire": false, "damage_numbers": false, "killfeed_time": 6.0},
	"keys": {},
}


func _ready() -> void:
	load_settings()
	apply_all()


func get_value(section: String, key: String, default = null):
	var s: Dictionary = data.get(section, {})
	return s.get(key, default)


func set_value(section: String, key: String, value) -> void:
	if not data.has(section):
		data[section] = {}
	data[section][key] = value
	apply_all()
	save_settings()
	Events.settings_changed.emit()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for section in cf.get_sections():
		if not data.has(section):
			data[section] = {}
		for key in cf.get_section_keys(section):
			data[section][key] = cf.get_value(section, key)


func save_settings() -> void:
	var cf := ConfigFile.new()
	for section in data:
		for key in data[section]:
			cf.set_value(section, key, data[section][key])
	cf.save(PATH)


func apply_all() -> void:
	_apply_video()
	_apply_audio()
	_apply_keys()


func _apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var v: Dictionary = data["video"]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if v.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(v.max_fps)
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = clampi(int(v.msaa), 0, 3) as Viewport.MSAA
		vp.scaling_3d_scale = clampf(float(v.render_scale), 0.5, 1.0)


func _apply_audio() -> void:
	var a: Dictionary = data["audio"]
	for bus in ["Master", "SFX", "Music", "Voice", "UI", "Announcer"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			var vol: float = float(a.get(bus.to_lower(), 1.0))
			AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(vol, 0.0001, 1.0)))
			AudioServer.set_bus_mute(idx, vol <= 0.001)


func _apply_keys() -> void:
	var keys: Dictionary = data["keys"]
	for action in keys:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		var ev := _event_from_string(str(keys[action]))
		if ev:
			InputMap.action_add_event(action, ev)


func rebind(action: String, event: InputEvent) -> void:
	data["keys"][action] = _event_to_string(event)
	_apply_keys()
	save_settings()
	Events.settings_changed.emit()


func reset_binding(action: String) -> void:
	data["keys"].erase(action)
	InputMap.load_from_project_settings()
	_apply_keys()
	save_settings()
	Events.settings_changed.emit()


func binding_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "unbound"
	var ev := events[0]
	if ev is InputEventKey:
		var kc: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(kc) if ev.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless" else kc)
	if ev is InputEventMouseButton:
		return "Mouse %d" % ev.button_index
	return ev.as_text()


static func _event_to_string(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return "key:%d" % (ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode)
	if ev is InputEventMouseButton:
		return "mouse:%d" % ev.button_index
	return ""


static func _event_from_string(s: String) -> InputEvent:
	var parts := s.split(":")
	if parts.size() != 2:
		return null
	if parts[0] == "key":
		var ev := InputEventKey.new()
		ev.physical_keycode = int(parts[1]) as Key
		return ev
	if parts[0] == "mouse":
		var ev := InputEventMouseButton.new()
		ev.button_index = int(parts[1]) as MouseButton
		return ev
	return null


func mouse_sensitivity() -> float:
	return float(get_value("controls", "sensitivity", 1.0)) * 0.0022


func fov() -> float:
	return float(get_value("video", "fov", 90.0))


func colorblind_palette() -> Dictionary:
	## Team colours adapt to the selected colour-vision mode.
	match str(get_value("accessibility", "colorblind", "none")):
		"deuteranopia", "protanopia":
			return {"enemy": Color(1.0, 0.55, 0.0), "friend": Color(0.2, 0.55, 1.0), "attackers": Color(1.0, 0.55, 0.0), "defenders": Color(0.2, 0.55, 1.0)}
		"tritanopia":
			return {"enemy": Color(1.0, 0.2, 0.3), "friend": Color(0.0, 0.85, 0.85), "attackers": Color(1.0, 0.2, 0.3), "defenders": Color(0.0, 0.85, 0.85)}
	return {"enemy": Color(1.0, 0.3, 0.25), "friend": Color(0.3, 0.8, 1.0), "attackers": Color(0.95, 0.45, 0.15), "defenders": Color(0.35, 0.65, 1.0)}
