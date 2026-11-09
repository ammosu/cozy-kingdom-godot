extends Node
## 揮劍與命中音效：同類隨機挑一個（不連續重複）再微調音高，連打才不會單調。
## 音效播放不受遊戲停頓影響。

const GROUPS := {"whoosh": 4, "whoosh_heavy": 2, "hit_soft": 4, "hit_heavy": 2, "hit_hard": 3}
var streams := {}
var last := {}
var played := {}      # 自我測試用：各類播放次數
var pool: Array[AudioStreamPlayer] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 33
	for g in GROUPS:
		var list := []
		for i in GROUPS[g]:
			list.append(load("res://assets/sfx/%s_%d.wav" % [g, i]))
		streams[g] = list
		played[g] = 0
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)

func play(group: String, volume_db := 0.0, pitch_range := 0.07) -> void:
	var list: Array = streams[group]
	var i := rng.randi() % list.size()
	if list.size() > 1 and i == last.get(group, -1):
		i = (i + 1) % list.size()
	last[group] = i
	played[group] += 1
	for p in pool:
		if not p.playing:
			p.stream = list[i]
			p.volume_db = volume_db
			p.pitch_scale = 1.0 + rng.randf_range(-pitch_range, pitch_range)
			p.play()
			return
