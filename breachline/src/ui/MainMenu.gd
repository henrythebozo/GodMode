extends Control
## Original main menu: play offline with bots, host, join, dedicated hint, settings, quit.

var name_edit: LineEdit
var ip_edit: LineEdit
var port_edit: LineEdit
var status: Label
var browser_list: VBoxContainer


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var stripe := ColorRect.new()
	stripe.color = UIKit.ACCENT
	stripe.anchor_left = 0.0
	stripe.anchor_right = 0.0
	stripe.anchor_bottom = 1.0
	stripe.custom_minimum_size.x = 8
	stripe.size.x = 8
	add_child(stripe)
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 40)
	root.offset_left = 60
	root.offset_top = 40
	root.offset_right = -60
	root.offset_bottom = -40
	add_child(root)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)
	left.add_child(UIKit.title("BREACHLINE", 56))
	left.add_child(UIKit.label("Tactical 5v5 bomb defusal", UIKit.DIM))
	left.add_child(UIKit.hsep())
	var nrow := HBoxContainer.new()
	nrow.add_child(UIKit.label("Callsign"))
	name_edit = LineEdit.new()
	name_edit.text = str(Settings.get_value("player", "name", "Operator"))
	name_edit.custom_minimum_size.x = 200
	name_edit.max_length = 24
	name_edit.text_changed.connect(func(t): Settings.set_value("player", "name", t))
	nrow.add_child(name_edit)
	left.add_child(nrow)
	left.add_child(UIKit.button("PLAY WITH BOTS", _play_offline, 260))
	left.add_child(UIKit.button("HOST MATCH", _host, 260))
	left.add_child(UIKit.button("SETTINGS", func(): Events.open_menu.emit("settings"), 260))
	left.add_child(UIKit.button("QUIT", func(): get_tree().quit(), 260))
	status = UIKit.label("", UIKit.DIM)
	left.add_child(status)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	root.add_child(right)
	right.add_child(UIKit.title("JOIN", 28))
	var jrow := HBoxContainer.new()
	ip_edit = LineEdit.new()
	ip_edit.text = str(Settings.get_value("network", "last_ip", "127.0.0.1"))
	ip_edit.placeholder_text = "server ip"
	ip_edit.custom_minimum_size.x = 220
	jrow.add_child(ip_edit)
	port_edit = LineEdit.new()
	port_edit.text = str(Settings.get_value("network", "port", 27015))
	port_edit.custom_minimum_size.x = 90
	jrow.add_child(port_edit)
	jrow.add_child(UIKit.button("CONNECT", _join, 140))
	right.add_child(jrow)
	right.add_child(UIKit.label("LAN servers (auto-discovered)", UIKit.DIM))
	browser_list = VBoxContainer.new()
	right.add_child(browser_list)
	right.add_child(UIKit.hsep())
	var help := RichTextLabel.new()
	help.bbcode_enabled = true
	help.fit_content = true
	help.text = "[color=#999]Dedicated server:[/color] [code]godot --headless --path breachline -- --server --port 27015 --bots 8[/code]\n[color=#999]Docs:[/color] docs/SETUP.md, docs/CONTROLS.md, docs/MULTIPLAYER.md"
	right.add_child(help)
	Events.server_list_updated.connect(_on_servers)
	Events.connection_state_changed.connect(func(s, d): status.text = "%s: %s" % [s, d])
	Net.browser.start_client_discovery()
	Audio.play_music("ambient/menu_theme.wav")


func _exit_tree() -> void:
	Net.browser.stop()


func _on_servers(servers: Array) -> void:
	for c in browser_list.get_children():
		c.queue_free()
	for s in servers:
		var b := UIKit.button("%s  |  %s  |  %d/%d  |  %s" % [s.get("name", "?"), s.get("map", "?"), int(s.get("players", 0)), int(s.get("max", 10)), s.get("state", "")], func():
			ip_edit.text = s.ip
			port_edit.text = str(s.get("port", 27015))
			_join(), 400)
		browser_list.add_child(b)


func _play_offline() -> void:
	Audio.stop_music()
	Events.open_menu.emit("play_offline")


func _host() -> void:
	Audio.stop_music()
	Events.open_menu.emit("host")


func _join() -> void:
	Settings.set_value("network", "last_ip", ip_edit.text)
	Settings.set_value("network", "port", int(port_edit.text))
	Audio.stop_music()
	Events.open_menu.emit("join:%s:%s" % [ip_edit.text, port_edit.text])
