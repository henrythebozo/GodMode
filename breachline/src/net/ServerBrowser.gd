class_name ServerBrowser
extends Node
## LAN server discovery foundations: servers answer UDP broadcast probes with a small JSON info
## packet; clients list responders. Internet listing would plug in here (see docs/MULTIPLAYER.md).

const DISCOVERY_PORT := 27016
const PROBE := "BREACHLINE_PROBE"

var _udp := PacketPeerUDP.new()
var _is_server := false
var servers: Dictionary = {}     # "ip:port" -> info dict
var _refresh_timer := 0.0


func start_server_beacon() -> void:
	_is_server = true
	_udp.close()
	if _udp.bind(DISCOVERY_PORT, "*") != OK:
		push_warning("ServerBrowser: could not bind discovery port")
	set_process(true)


func start_client_discovery() -> void:
	_is_server = false
	_udp.close()
	_udp.bind(0, "*")
	_udp.set_broadcast_enabled(true)
	servers.clear()
	set_process(true)
	probe()


func probe() -> void:
	if _is_server:
		return
	_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_udp.put_packet(PROBE.to_utf8_buffer())
	_udp.set_dest_address("127.0.0.1", DISCOVERY_PORT)
	_udp.put_packet(PROBE.to_utf8_buffer())


func stop() -> void:
	_udp.close()
	set_process(false)


func _process(delta: float) -> void:
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var port := _udp.get_packet_port()
		if _is_server:
			if pkt.get_string_from_utf8() == PROBE:
				var info := Net.server_info()
				_udp.set_dest_address(ip, port)
				_udp.put_packet(JSON.stringify(info).to_utf8_buffer())
		else:
			var info = JSON.parse_string(pkt.get_string_from_utf8())
			if info is Dictionary:
				info["ip"] = ip
				servers["%s:%d" % [ip, info.get("port", 27015)]] = info
				Events.server_list_updated.emit(servers.values())
	if not _is_server:
		_refresh_timer += delta
		if _refresh_timer > 2.0:
			_refresh_timer = 0.0
			probe()
