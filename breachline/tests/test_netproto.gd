extends TestCase


func test_input_cmd_roundtrip() -> void:
	var c := InputCmd.new()
	c.tick = 12345
	c.move = Vector2(0.5, -1.0)
	c.yaw = 1.2345
	c.pitch = -0.4
	c.buttons = InputCmd.BTN_FIRE | InputCmd.BTN_CROUCH
	c.weapon_slot = 3
	c.view_tick = 12000
	var buf := StreamPeerBuffer.new()
	c.pack(buf)
	buf.seek(0)
	var d := InputCmd.unpack(buf)
	assert_eq(d.tick, 12345)
	assert_near(d.move.x, 0.5, 0.01)
	assert_near(d.move.y, -1.0, 0.01)
	assert_near(d.yaw, 1.2345, 0.0001)
	assert_eq(d.buttons, c.buttons)
	assert_eq(d.weapon_slot, 3)
	assert_eq(d.view_tick, 12000)


func test_snapshot_roundtrip() -> void:
	var states := [{"id": -3, "tick": 77, "p": Vector3(1, 2, 3), "v": Vector3(0.5, 0, -1), "yaw": 0.3, "pitch": -0.1, "alive": true, "ladder": false, "floor": true,
		"reloading": true, "zoomed": false, "helmet": true, "kit": false, "bomb": true, "crouch": 0.5, "hp": 87, "armor": 40, "weapon": "corsair", "slot": 0,
		"plant": 0.25, "defuse": 0.0, "ammo": 17, "reserve": 60, "recoil": Vector2(0.5, 2.0)}]
	var ents := [{"id": 9, "type": 1, "p": Vector3(4, 5, 6), "v": Vector3(1, 1, 1), "weapon": "frag"}]
	var bytes := NetProtocol.pack_snapshot(500, states, ents)
	var snap := NetProtocol.unpack_snapshot(bytes)
	assert_eq(snap.tick, 500)
	var s: Dictionary = snap.players[0]
	assert_eq(s.id, -3, "negative bot ids survive")
	assert_eq(s.tick, 77)
	assert_eq(s.p, Vector3(1, 2, 3))
	assert_true(s.alive and s.reloading and s.helmet and s.bomb and not s.kit and not s.zoomed, "flags")
	assert_near(s.crouch, 0.5, 0.01)
	assert_eq(s.hp, 87)
	assert_eq(s.weapon, "corsair")
	assert_near(s.progress, 0.25, 0.01)
	assert_eq(s.ammo, 17)
	assert_near(s.recoil.y, 2.0, 0.001)
	assert_eq(snap.entities[0].weapon, "frag")
	assert_eq(snap.entities[0].p, Vector3(4, 5, 6))


func test_validation() -> void:
	var c := InputCmd.new()
	c.move = Vector2(5, 5)
	c.pitch = 9.0
	c.weapon_slot = 42
	c.view_tick = 1000
	assert_true(NetValidation.sanitize_cmd(c, 500))
	assert_true(c.move.length() <= 1.01, "move clamped")
	assert_true(abs(c.pitch) <= PI / 2.0, "pitch clamped")
	assert_eq(c.weapon_slot, -1, "bad slot reset")
	assert_eq(c.view_tick, 500, "view tick cannot be in the future")
	c.yaw = NAN
	assert_true(not NetValidation.sanitize_cmd(c, 500), "NaN rejected")
	assert_eq(NetValidation.sanitize_name("  [admin] Bob  "), "admin Bob")
	assert_eq(NetValidation.sanitize_name(""), "Operator")


func test_lag_compensation_rewind() -> void:
	var lc := LagCompensation.new()
	var p := Player.new()
	p.setup(5, "x", Teams.ATTACKERS, false)
	for t in range(1, 11):
		p.global_position = Vector3(t, 0, 0)
		lc.record(p, t)
	var r := lc.pose_at(5, 4, 10)
	assert_eq(r.pos, Vector3(4, 0, 0), "exact tick")
	var clamped := lc.pose_at(5, -50, 10)
	assert_true(clamped.pos.x >= 10 - LagCompensation.MAX_REWIND_TICKS, "rewind window clamped")
	assert_true(lc.pose_at(6, 3, 10).is_empty(), "unknown player")
	p.free()
