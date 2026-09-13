extends Node
## Gathers keyboard/mouse input for the local player and builds InputCmds. Mouse look uses raw
## relative motion (no OS acceleration) and is accumulated between physics ticks.

var player: Player
var yaw := 0.0
var pitch := 0.0
var mouse_accum := Vector2.ZERO
var pending_slot := -1
var pending_buttons := 0          # edge-triggered buttons pressed since the last tick
var ui_blocking := false           # menus that capture input (buy menu, pause, console, chat)
var toggle_crouch_state := false
var toggle_walk_state := false
var mouse_captured := false


func _ready() -> void:
	process_priority = -10
	set_process_input(true)


func attach(p: Player) -> void:
	player = p
	yaw = p.yaw
	pitch = p.pitch
	capture_mouse(true)


func capture_mouse(c: bool) -> void:
	mouse_captured = c and DisplayServer.get_name() != "headless"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.use_accumulated_input = not bool(Settings.get_value("controls", "raw_input", true))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured and not ui_blocking:
		mouse_accum += event.relative
	if ui_blocking or player == null:
		return
	if event.is_action_pressed("slot_primary"): pending_slot = Inventory.SLOT_PRIMARY
	elif event.is_action_pressed("slot_secondary"): pending_slot = Inventory.SLOT_SECONDARY
	elif event.is_action_pressed("slot_melee"): pending_slot = Inventory.SLOT_MELEE
	elif event.is_action_pressed("slot_grenade"):
		if player.active_slot == Inventory.SLOT_GRENADE and player.inventory.slots[Inventory.SLOT_GRENADE].size() > 1:
			player.inventory.grenade_index = (player.inventory.grenade_index + 1) % player.inventory.slots[Inventory.SLOT_GRENADE].size()
			var w := player.active_weapon()
			if w:
				w.on_equip()
		pending_slot = Inventory.SLOT_GRENADE
	elif event.is_action_pressed("slot_bomb"): pending_slot = Inventory.SLOT_BOMB
	elif event.is_action_pressed("next_weapon"): pending_slot = player.inventory.next_slot_with_weapon(player.active_slot, 1)
	elif event.is_action_pressed("prev_weapon"): pending_slot = player.inventory.next_slot_with_weapon(player.active_slot, -1)
	elif event.is_action_pressed("quick_switch"): pending_buttons |= InputCmd.BTN_QUICK_SWITCH
	elif event.is_action_pressed("reload"): pending_buttons |= InputCmd.BTN_RELOAD
	elif event.is_action_pressed("drop"): pending_buttons |= InputCmd.BTN_DROP
	elif event.is_action_pressed("inspect"): pending_buttons |= InputCmd.BTN_INSPECT
	elif event.is_action_pressed("fire"): pending_buttons |= InputCmd.BTN_FIRE
	elif event.is_action_pressed("alt_fire"): pending_buttons |= InputCmd.BTN_ALT_FIRE
	elif event.is_action_pressed("jump"): pending_buttons |= InputCmd.BTN_JUMP
	elif event.is_action_pressed("use"): pending_buttons |= InputCmd.BTN_USE
	elif event.is_action_pressed("crouch") and bool(Settings.get_value("controls", "toggle_crouch", false)):
		toggle_crouch_state = not toggle_crouch_state
	elif event.is_action_pressed("walk") and bool(Settings.get_value("controls", "toggle_walk", false)):
		toggle_walk_state = not toggle_walk_state


func build_cmd(tick: int, view_tick: int) -> InputCmd:
	var cmd := InputCmd.new()
	cmd.tick = tick
	cmd.view_tick = view_tick
	if player == null:
		return cmd
	if not ui_blocking and mouse_captured:
		var sens := Settings.mouse_sensitivity()
		if player.zoomed:
			sens *= float(Settings.get_value("controls", "zoom_sensitivity", 0.8))
		var invert := -1.0 if bool(Settings.get_value("controls", "invert_y", false)) else 1.0
		yaw -= mouse_accum.x * sens
		pitch -= mouse_accum.y * sens * invert
		pitch = clampf(pitch, -PI / 2.0 + 0.02, PI / 2.0 - 0.02)
		yaw = wrapf(yaw, -PI, PI)
	mouse_accum = Vector2.ZERO
	cmd.yaw = yaw
	cmd.pitch = pitch
	if ui_blocking:
		cmd.weapon_slot = -1
		pending_buttons = 0
		pending_slot = -1
		return cmd
	cmd.move = Vector2(Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"))
	var buttons := pending_buttons
	if Input.is_action_pressed("fire"): buttons |= InputCmd.BTN_FIRE
	if Input.is_action_pressed("alt_fire"): buttons |= InputCmd.BTN_ALT_FIRE
	if Input.is_action_pressed("jump"): buttons |= InputCmd.BTN_JUMP
	if Input.is_action_pressed("use"): buttons |= InputCmd.BTN_USE
	var crouch := Input.is_action_pressed("crouch")
	if bool(Settings.get_value("controls", "toggle_crouch", false)):
		crouch = toggle_crouch_state
	if crouch: buttons |= InputCmd.BTN_CROUCH
	var walk := Input.is_action_pressed("walk")
	if bool(Settings.get_value("controls", "toggle_walk", false)):
		walk = toggle_walk_state
	if walk: buttons |= InputCmd.BTN_WALK
	cmd.buttons = buttons
	cmd.weapon_slot = pending_slot
	pending_buttons = 0
	pending_slot = -1
	return cmd


func set_ui_blocking(b: bool) -> void:
	ui_blocking = b
	capture_mouse(not b)
