extends Node
## 全局流程：场景切换（村庄 ↔ 战场）、任务状态、金钱、天数、存档。
## 持久进度存在这里，玩家只是"当前会话里的执行者"；跨场景与存档都由本节点统一处理。

const SAVE_PATH := "user://pnv_save.json"
const DEFAULT_LOADOUT := ["blink", "fireball", "great_fireball", "thunder_dash", "shadow_clones"]

## 持久进度
var level := 1
var xp := 0
var money := 0
var day := 1
var loadout: Array[String] = []
var missions_done := {}
var unlocked_jutsu: Array[String] = []

## 运行时任务状态
var mission_id := ""
var mission_cfg: Dictionary = {}


func _ready() -> void:
	for id in DEFAULT_LOADOUT:
		loadout.append(String(id))
	for id in Data.jutsu_list:
		unlocked_jutsu.append(String(id))
	load_save()


# ---------------------------------------------------------------- 场景与任务

func in_mission() -> bool:
	return mission_id != ""


func start_mission(id: String) -> void:
	mission_id = id
	mission_cfg = Data.missions.get(id, {}).duplicate(true)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func start_training() -> void:
	mission_id = ""
	mission_cfg = {}
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func back_to_village() -> void:
	mission_id = ""
	mission_cfg = {}
	save_game()
	get_tree().change_scene_to_file("res://scenes/village.tscn")


## 任务完成：发赏金、计次数、过一天、存盘。返回 {ryo, xp}。
func complete_mission() -> Dictionary:
	var ryo := int(mission_cfg.get("reward_ryo", 0))
	var r_xp := int(mission_cfg.get("reward_xp", 0))
	money += ryo
	missions_done[mission_id] = int(missions_done.get(mission_id, 0)) + 1
	day += 1
	save_game()
	return {"ryo": ryo, "xp": r_xp}


func mission_done_count(id: String) -> int:
	return int(missions_done.get(id, 0))


# ---------------------------------------------------------------- 与玩家的进度同步

func sync_from_player(p) -> void:
	level = int(p.level)
	xp = int(p.xp)
	loadout.clear()
	for id in p.jutsu_slots:
		loadout.append(String(id))
	save_game()


func apply_to_player(p) -> void:
	p.level = level
	p.xp = xp
	p.xp_next = 40 + (level - 1) * 26
	p.max_hp = p.MAX_HP_BASE + 12.0 * float(level - 1)
	p.max_chakra = p.MAX_CHAKRA_BASE + 10.0 * float(level - 1)
	p.hp = p.max_hp
	p.chakra = p.max_chakra
	p.jutsu_slots.clear()
	for id in loadout:
		p.jutsu_slots.append(String(id))


# ---------------------------------------------------------------- 存档

func save_game() -> void:
	var data := {
		"level": level,
		"xp": xp,
		"money": money,
		"day": day,
		"loadout": Array(loadout),
		"missions_done": missions_done,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()


func load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return false
	level = int(parsed.get("level", 1))
	xp = int(parsed.get("xp", 0))
	money = int(parsed.get("money", 0))
	day = int(parsed.get("day", 1))
	var lo: Array = parsed.get("loadout", [])
	if lo.size() == 5:
		loadout.clear()
		for id in lo:
			loadout.append(String(id))
	var md: Variant = parsed.get("missions_done", {})
	if md is Dictionary:
		missions_done = md
	return true


func reset_save() -> void:
	level = 1
	xp = 0
	money = 0
	day = 1
	loadout.clear()
	for id in DEFAULT_LOADOUT:
		loadout.append(String(id))
	missions_done = {}
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
