extends Node
## Global signal bus. Presentation listens here; gameplay/network emit here. Keeps UI decoupled.

# match
signal match_state_changed(state: int, time_left: float)
signal round_started(round_number: int)
signal round_ended(winner_team: int, reason: String)
signal score_changed(attackers: int, defenders: int)
signal halftime()
signal match_ended(winner_team: int)
signal bomb_planted(site: String, planter_id: int)
signal bomb_defused(defuser_id: int)
signal bomb_exploded()
signal bomb_dropped(position: Vector3)
signal bomb_picked_up(player_id: int)
signal plant_progress(progress: float)
signal defuse_progress(progress: float)
signal surrender_vote_started(team: int)
signal surrender_vote_updated(team: int, yes: int, needed: int)
signal announcer(event_name: String)

# players
signal player_joined(id: int, name: String, team: int)
signal player_left(id: int)
signal player_team_changed(id: int, team: int)
signal player_spawned(id: int)
signal player_damaged(victim_id: int, attacker_id: int, amount: int, zone: int, from_dir: Vector3, armor_hit: bool)
signal player_killed(victim_id: int, killer_id: int, weapon_id: String, headshot: bool, assist_id: int)
signal hit_confirmed(victim_id: int, amount: int, headshot: bool, killed: bool)
signal local_player_ready(player: Node)
signal local_player_died()
signal money_changed(id: int, money: int)
signal inventory_changed(id: int)
signal weapon_fired(id: int, weapon_id: String, origin: Vector3, direction: Vector3)
signal purchase_denied(reason: String)
signal purchase_ok(weapon_id: String)
signal footstep(id: int, position: Vector3, surface: String, loud: bool)
signal flashed(strength: float, duration: float)
signal chat_message(sender_id: int, team_only: bool, text: String)
signal spectating_changed(target_id: int, free_cam: bool)
signal callout_changed(name: String)

# net
signal connection_state_changed(state: String, detail: String)
signal lobby_updated()
signal latency_updated(ms: int)
signal server_list_updated(servers: Array)

# ui
signal open_menu(menu_name: String)
signal notification(text: String, seconds: float)
signal settings_changed()
