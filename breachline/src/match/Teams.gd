class_name Teams
extends RefCounted

const NONE := 0
const ATTACKERS := 1
const DEFENDERS := 2
const SPECTATOR := 3


static func other(t: int) -> int:
	if t == ATTACKERS:
		return DEFENDERS
	if t == DEFENDERS:
		return ATTACKERS
	return t


static func team_name(t: int) -> String:
	match t:
		ATTACKERS: return "Cinder Syndicate"
		DEFENDERS: return "Aegis Directorate"
		SPECTATOR: return "Spectators"
	return "Unassigned"


static func short_name(t: int) -> String:
	match t:
		ATTACKERS: return "Attackers"
		DEFENDERS: return "Defenders"
		SPECTATOR: return "Spectators"
	return "None"


static func faction_model(t: int) -> String:
	return "res://assets/models/characters/cinder.glb" if t == ATTACKERS else "res://assets/models/characters/aegis.glb"
