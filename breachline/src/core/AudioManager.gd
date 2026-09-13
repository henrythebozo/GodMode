extends Node
## Autoload: pooled 2D/3D audio playback, bus setup, ambience and announcer hooks.
## All clips are procedurally generated originals in res://assets/audio (see tools/gen_audio.py).

const POOL_3D := 24
const POOL_2D := 12
const AUDIO_ROOT := "res://assets/audio/"

var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _ambience: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var headless := false


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	_setup_buses()
	if headless:
		return
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 80.0
		p.unit_size = 4.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		add_child(p)
		_pool_3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_pool_2d.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	Events.announcer.connect(_on_announcer)


func _setup_buses() -> void:
	for bus in ["SFX", "Music", "Voice", "UI", "Announcer"]:
		if AudioServer.get_bus_index(bus) < 0:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")


func stream(rel: String) -> AudioStream:
	if _cache.has(rel):
		return _cache[rel]
	var s: AudioStream = load(AUDIO_ROOT + rel) if ResourceLoader.exists(AUDIO_ROOT + rel) else null
	if s == null:
		push_warning("Audio: missing clip " + rel)
	_cache[rel] = s
	return s


func play_3d(rel: String, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0, max_distance: float = 80.0, bus: String = "SFX") -> void:
	if headless:
		return
	var s := stream(rel)
	if s == null:
		return
	for p in _pool_3d:
		if not p.playing:
			p.stream = s
			p.global_position = position
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.max_distance = max_distance
			p.bus = bus
			p.play()
			return


func play_2d(rel: String, volume_db: float = 0.0, pitch: float = 1.0, bus: String = "UI") -> void:
	if headless:
		return
	var s := stream(rel)
	if s == null:
		return
	for p in _pool_2d:
		if not p.playing:
			p.stream = s
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.bus = bus
			p.play()
			return


func play_random_3d(prefix: String, count: int, position: Vector3, volume_db: float = 0.0, max_distance: float = 40.0) -> void:
	play_3d("%s_%d.wav" % [prefix, randi() % count], position, volume_db, randf_range(0.94, 1.06), max_distance)


func start_ambience(clips: Array) -> void:
	stop_ambience()
	if headless:
		return
	for c in clips:
		var s := stream(c)
		if s == null:
			continue
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_end = s.data.size() / 2
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = "SFX"
		p.volume_db = -8.0
		add_child(p)
		p.play()
		_ambience.append(p)


func stop_ambience() -> void:
	for p in _ambience:
		p.queue_free()
	_ambience.clear()


func play_music(rel: String) -> void:
	if headless or _music == null:
		return
	var s := stream(rel)
	if s == null:
		return
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = s.data.size() / 2
	_music.stream = s
	_music.play()


func stop_music() -> void:
	if _music:
		_music.stop()


## Announcer hook: plays the stinger for the event; a voice line with the same name in
## assets/audio/announcer/vo/ overrides the stinger when present.
func _on_announcer(event_name: String) -> void:
	if ResourceLoader.exists(AUDIO_ROOT + "announcer/vo/%s.wav" % event_name):
		play_2d("announcer/vo/%s.wav" % event_name, 0.0, 1.0, "Announcer")
	else:
		play_2d("announcer/%s.wav" % event_name, -4.0, 1.0, "Announcer")
	if bool(Settings.get_value("audio", "subtitles", true)):
		Events.notification.emit("[Announcer] " + event_name.replace("_", " ").capitalize(), 3.0)
