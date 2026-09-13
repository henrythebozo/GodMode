extends Control
## Buy menu: categories on the left, items with prices, armour/kit, refund list, team restrictions.

var money_lbl: Label
var items_box: VBoxContainer
var refund_box: VBoxContainer
var msg_lbl: Label
var current_cat := "pistol"
const CATS := [["pistol", "Pistols"], ["smg", "SMGs"], ["shotgun", "Shotguns"], ["rifle", "Rifles"], ["sniper", "Snipers"], ["lmg", "Machine guns"], ["grenade", "Grenades"], ["gear", "Gear"]]


func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var panel := UIKit.panel(Vector2(900, 520))
	add_child(UIKit.centered(panel))
	var root := VBoxContainer.new()
	panel.add_child(root)
	var top := HBoxContainer.new()
	top.add_child(UIKit.title("BUY", 28))
	var sp := Control.new()
	sp.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(sp)
	money_lbl = UIKit.label("$0", UIKit.OK, 24)
	top.add_child(money_lbl)
	top.add_child(UIKit.button("CLOSE (B)", func(): Events.open_menu.emit("close_buy"), 120))
	root.add_child(top)
	msg_lbl = UIKit.label("", UIKit.DIM)
	root.add_child(msg_lbl)
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)
	var cats := VBoxContainer.new()
	body.add_child(cats)
	for c in CATS:
		cats.add_child(UIKit.button(c[1], func(): current_cat = c[0]; _refresh(), 170))
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	items_box = VBoxContainer.new()
	items_box.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(items_box)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 220
	body.add_child(right)
	right.add_child(UIKit.label("Bought this round (click to refund)", UIKit.DIM, 13))
	refund_box = VBoxContainer.new()
	right.add_child(refund_box)
	Events.purchase_denied.connect(func(r): msg_lbl.text = r; msg_lbl.add_theme_color_override("font_color", UIKit.BAD))
	Events.purchase_ok.connect(func(id): msg_lbl.text = "Purchased " + id.replace("refund:", "refunded "); msg_lbl.add_theme_color_override("font_color", UIKit.OK); _refresh())
	Events.inventory_changed.connect(func(_id): _refresh())
	Events.money_changed.connect(func(_id, _m): _refresh())
	_refresh()


func _buy(id: String) -> void:
	if Net.is_server():
		Match.server_buy(Net.local_id, id)
	else:
		Net.rpc_id(1, "rpc_buy", id)


func _refund(id: String) -> void:
	if Net.is_server():
		Match.server_refund(Net.local_id, id)
	else:
		Net.rpc_id(1, "rpc_refund", id)


func _refresh() -> void:
	var lp := Net.local_player()
	if lp == null:
		return
	money_lbl.text = "$%d" % lp.money
	for c in items_box.get_children():
		c.queue_free()
	for c in refund_box.get_children():
		c.queue_free()
	var team_name := "attackers" if lp.team == Teams.ATTACKERS else "defenders"
	if current_cat == "gear":
		var ec := Match.economy_cfg
		_item("Body armor", ec.armor_price, "armor", lp.money >= ec.armor_price and lp.armor < Match.rules.max_armor, "100 armor. Reduces body damage from most weapons.")
		var hp := ec.helmet_upgrade_price if lp.armor > 0 else ec.armor_price + ec.helmet_price
		_item("Armor + helmet", hp, "helmet", lp.money >= hp and not lp.has_helmet, "Adds head protection.")
		if lp.team == Teams.DEFENDERS:
			_item("Defusal kit", ec.defuse_kit_price, "defuse_kit", lp.money >= ec.defuse_kit_price and not lp.inventory.has_kit, "Defuse in 5 s instead of 10 s.")
	else:
		for w in WeaponDB.by_category.get(current_cat, []):
			if w.price <= 0 or (w.team != "both" and w.team != team_name):
				continue
			var desc := ""
			if w.is_firearm():
				desc = "dmg %d  |  %d rpm  |  %d/%d  |  pen %.0f%%  |  $%d kill" % [int(w.damage), int(w.fire_rate_rpm), w.mag_size, w.reserve_ammo, w.armor_penetration * 100, w.kill_reward]
			elif w.is_grenade():
				desc = "carry up to %d" % w.max_carry
			var owned := lp.inventory.has_weapon(w.id)
			_item(w.display_name, w.price, w.id, lp.money >= w.price and not (owned and w.slot != "grenade"), desc + ("  (owned)" if owned else ""))
	for id in lp.inventory.purchases_this_round:
		var nm: String = WeaponDB.get_config(id).display_name if WeaponDB.has(id) else id.capitalize()
		refund_box.add_child(UIKit.button("↩ " + nm, func(): _refund(id), 200))


func _item(name: String, price: int, id: String, enabled: bool, desc: String) -> void:
	var row := HBoxContainer.new()
	var b := UIKit.button("%s   $%d" % [name, price], func(): _buy(id), 300)
	b.disabled = not enabled
	row.add_child(b)
	var l := UIKit.label(desc, UIKit.DIM, 13)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(l)
	items_box.add_child(row)
