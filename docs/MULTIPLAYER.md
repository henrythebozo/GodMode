# Multiplayer

Breachline is **server-authoritative**. The server (dedicated, or the host of a listen server) is the
only writer of health, money, ammo, position, round state and objective state. Clients send intent.

## Status by system

| System | Status | Notes |
|---|---|---|
| ENet transport, host / join / dedicated server | Production-ready | `Net.host()`, `Net.join()`, `--server`. Verified with a headless client connecting to a dedicated server. |
| Lobby, team selection, ready check, bot fill | Production-ready | Lobby state broadcast via reliable RPC on every change. |
| Server-side simulation of inputs (`InputCmd` → `PlayerBody.simulate`) | Production-ready | 64 Hz. Redundant input packets (last 3 cmds) tolerate loss. |
| Snapshot replication (binary, 32 Hz) | Production-ready | `NetProtocol.pack_snapshot`, unit tested round trip. |
| Client-side prediction + reconciliation | Prototype | Local player predicts with the same simulation; corrected when the server state differs by > 6 cm, then replays pending inputs. Not yet tuned against high jitter. |
| Remote player interpolation | Prototype | 2 snapshots behind the newest; no extrapolation. |
| Lag compensation | Prototype | Analytic hurtbox rewind up to 20 ticks (~310 ms) using the client's reported view tick. Wall occlusion is checked against *current* world geometry (static, so equivalent). |
| Server-side validation | Basic | `NetValidation`: NaN/range checks on inputs, tick monotonicity, command rate cap, name/chat sanitising, weapon-id validation; buy rules, buy zone, money, alive-state and objective conditions are all evaluated on the server. |
| Anti-cheat | **Not implemented** | Only the sanity checks above. The design keeps every gameplay decision on the server so a dedicated anti-cheat (signature/behavioural) can be integrated at the `NetworkManager.rpc_*` boundary and in `_server_receive_input`. No claim of cheat resistance is made. |
| Reconnect | Prototype | Client keeps a session token; the server keeps a disconnected player's node for 60 s and reattaches the new peer id. Automatic retry with back-off (5 attempts). |
| Latency display | Production-ready | Ping RPC every second; shown in the HUD and scoreboard. |
| Network simulation | Production-ready (testing tool) | Settings → Network or console `net_sim`: inbound latency, jitter and loss on both sides. |
| Server browser | Foundation | LAN discovery over UDP broadcast (`ServerBrowser`), plus direct IP connect. No internet master server. |
| Match state sync | Production-ready | `Match.state_dict()` on every transition and every half second (timer). |
| Entities (grenades, pickups, smoke/fire areas) | Prototype | Server-simulated rigid bodies; positions mirrored in snapshots; effects via reliable entity events. |

## Trust model

Never trusted from the client: damage, money, ammunition, position, objective completion, team, ready
state or purchases. The client only sends `InputCmd` (move axes, view angles, buttons, weapon slot,
view tick) and menu requests (`rpc_buy`, `rpc_refund`, `rpc_set_team`, `rpc_ready`, `rpc_chat`,
`rpc_vote_surrender`). Console commands over the network are accepted only from the listen-server host.

## Testing locally

```
godot --headless --path breachline -- --server --port 27015 --bots 4 --fast
godot --path breachline -- --connect 127.0.0.1:27015
godot --path breachline                     # second instance: main menu → CONNECT
```
Settings → Network → simulated latency/loss lets you feel prediction and interpolation on one PC.
