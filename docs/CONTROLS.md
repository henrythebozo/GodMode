# Controls

All bindings can be changed in Settings → Controls (keyboard and mouse remapping, saved to
`user://settings.cfg`).

| Action | Default |
|---|---|
| Move | W A S D |
| Jump | Space |
| Crouch | Ctrl (toggle option in settings) |
| Walk (silent) | Shift (toggle option) |
| Fire / alt fire (zoom, heavy melee, underhand throw) | Mouse 1 / Mouse 2 |
| Reload | R |
| Use (plant / defuse / swap weapon on the ground) | E (hold) |
| Drop weapon | G |
| Inspect weapon | F |
| Primary / Secondary / Knife / Grenades / Charge | 1 / 2 / 3 / 4 / 5 (4 again cycles grenades) |
| Next / previous weapon | Mouse wheel |
| Quick switch (last weapon) | Q |
| Buy menu | B (only in a buy zone during buy time) |
| Scoreboard | Tab (hold) |
| Chat / team chat | Y / Shift+Y |
| Surrender vote yes / no | F1 / F2 |
| Pause menu | Esc |
| Developer console | ` (grave) |
| Spectator: next / previous / free camera | Mouse 1 / Mouse 2 / Space |

## Objective

* Attackers (Cinder Syndicate) carry a demolition charge. Select it (5), stand inside site A "Furnace"
  or B "Silo" and hold E for 3.2 s. It detonates after 40 s.
* Defenders (Aegis Directorate) hold E on the planted charge for 10 s (5 s with a defusal kit).
* Rounds: eliminate the enemy, run out the clock (defenders), detonate (attackers), defuse (defenders).
* First to 13 of 24 rounds wins; sides switch at halftime; ties go to 6-round overtime blocks.

## Console commands

`help`, `restart_round`, `start`, `end_round <team>`, `money <n> [all]`, `bot_add [team] [0-3]`,
`bot_kick`, `bot_difficulty <0-3>`, `noclip`, `god`, `give <weapon_id>`, `kill`, `map_reload`,
`net_sim <latency_ms> <loss> [jitter_ms]`, `timescale <x>`, `plant`, `tp <A|B|mid>`, `state`,
`validate_spawns`, `fps`, `quit`.
