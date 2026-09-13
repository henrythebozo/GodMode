class_name InputCmd
extends RefCounted
## One tick of player intent. Produced by LocalController (humans) or BotBrain (bots), consumed by
## PlayerBody.simulate() on both client (prediction) and server (authority).

const BTN_JUMP := 1
const BTN_CROUCH := 2
const BTN_WALK := 4
const BTN_FIRE := 8
const BTN_ALT_FIRE := 16
const BTN_RELOAD := 32
const BTN_USE := 64
const BTN_DROP := 128
const BTN_INSPECT := 256
const BTN_QUICK_SWITCH := 512

var tick: int = 0
var move: Vector2 = Vector2.ZERO      # x = strafe (-1..1), y = forward (-1..1)
var yaw: float = 0.0                  # radians
var pitch: float = 0.0
var buttons: int = 0
var weapon_slot: int = -1             # -1 = keep current; otherwise Inventory slot index
var view_tick: int = 0                # server tick the client was rendering (lag compensation)


func has(btn: int) -> bool:
	return (buttons & btn) != 0


func pack(buf: StreamPeerBuffer) -> void:
	buf.put_u32(tick)
	buf.put_8(int(clampf(move.x, -1, 1) * 127))
	buf.put_8(int(clampf(move.y, -1, 1) * 127))
	buf.put_float(yaw)
	buf.put_float(pitch)
	buf.put_u16(buttons)
	buf.put_8(weapon_slot)
	buf.put_u32(view_tick)


static func unpack(buf: StreamPeerBuffer) -> InputCmd:
	var c := InputCmd.new()
	c.tick = buf.get_u32()
	c.move = Vector2(buf.get_8() / 127.0, buf.get_8() / 127.0)
	c.yaw = buf.get_float()
	c.pitch = buf.get_float()
	c.buttons = buf.get_u16()
	c.weapon_slot = buf.get_8()
	c.view_tick = buf.get_u32()
	return c


func duplicate_cmd() -> InputCmd:
	var c := InputCmd.new()
	c.tick = tick
	c.move = move
	c.yaw = yaw
	c.pitch = pitch
	c.buttons = buttons
	c.weapon_slot = weapon_slot
	c.view_tick = view_tick
	return c
