extends Node
## Звуки и музыка. Файлы лежат в res://assets/sfx/*.wav и res://assets/music/*.ogg|wav;
## если файла нет — просто тишина, игра не падает.

const POOL := 14

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache := {}
var _music: AudioStreamPlayer
var _music_name := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -9.0
	add_child(_music)


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[path] = s
	return s


func play(name: String, volume_db := 0.0, pitch_spread := 0.08) -> void:
	var s := _load("res://assets/sfx/%s.wav" % name)
	if s == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	p.play()


func music(name: String, fade := 1.0) -> void:
	if name == _music_name:
		return
	_music_name = name
	var s := _load("res://assets/music/%s.wav" % name)
	var tw := create_tween()
	if _music.playing:
		tw.tween_property(_music, "volume_db", -40.0, fade * 0.5)
	tw.tween_callback(func():
		_music.stop()
		if s:
			if s is AudioStreamWAV:
				(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
				(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
			_music.stream = s
			_music.volume_db = -40.0
			_music.play())
	tw.tween_property(_music, "volume_db", -9.0, fade)
