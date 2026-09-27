extends Node
## 全局流程：场景切换（村庄 ↔ 战场）、任务状态、金钱、天数、存档。
## 持久进度存在这里，玩家只是"当前会话里的执行者"；跨场景与存档都由本节点统一处理。

const SAVE_PATH := "user://pnv_save.json"
const DEFAULT_LOADOUT := ["blink", "fireball", "great_fireball", "thunder_dash", "shadow_clones"]
## 开局自带一件苦无（能近战能投掷，容错最高），其余忍具去忍具店买
const DEFAULT_OWNED_WEAPONS := ["kunai"]
const DEFAULT_WEAPON_SLOTS := ["kunai", ""]
const WEAPON_SLOT_COUNT := 2
## 开局给的少量金钱（原始构想：降生时给一间公寓和少量钱）
const START_MONEY := 150

## 持久进度
var level := 1
var xp := 0
var money := 0
var day := 1
var loadout: Array[String] = []
## 已购买的忍具（背包内容）与两个武器槽上的忍具
var owned_weapons: Array[String] = []
var weapon_slots: Array[String] = []
var missions_done := {}
var unlocked_jutsu: Array[String] = []

## 运行时任务状态
var mission_id := ""
var mission_cfg: Dictionary = {}
## 已在看板接取、但还没从村口大门出发的任务
var pending_mission := ""

## ---------------------------------------------------------------- 测试模式
## 打开后无视等级限制，5 个忍术槽全部可用（忍术本身没有等级门槛，从来都是 15 个全开）。
## 游戏内按 F1 随时切换；两套 HUD 左下角会显示当前状态。
## ⚠️ 正式发布前把这里改成 false，或删掉这个开关与 player.slots_unlocked() 里的分支。
var test_unlock_all := true


## 切换测试模式，返回切换后的状态（默认开 → 按一次变正式进度，再按回来）。
func toggle_test_mode() -> bool:
	test_unlock_all = not test_unlock_all
	return test_unlock_all


func _ready() -> void:
	for id in DEFAULT_LOADOUT:
		loadout.append(String(id))
	for id in DEFAULT_OWNED_WEAPONS:
		owned_weapons.append(String(id))
	for id in DEFAULT_WEAPON_SLOTS:
		weapon_slots.append(String(id))
	for id in Data.jutsu_list:
		unlocked_jutsu.append(String(id))
	if not load_save():
		## 全新存档：发开局的少量金钱
		money = START_MONEY


# ---------------------------------------------------------------- 场景与任务

func in_mission() -> bool:
	return mission_id != ""


## 看板接取：只登记待出发任务，玩家需走到村口大门出发
func accept_mission(id: String) -> void:
	pending_mission = id


## 村口大门出发：清空待出发，进入野外任务场景
func depart_mission() -> void:
	var id := pending_mission
	pending_mission = ""
	start_mission(id)


func start_mission(id: String) -> void:
	mission_id = id
	mission_cfg = Data.missions.get(id, {}).duplicate(true)
	get_tree().change_scene_to_file("res://scenes/wild.tscn")


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
	weapon_slots.clear()
	for i in range(WEAPON_SLOT_COUNT):
		weapon_slots.append(String(p.weapon_at(i)))
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
	p.weapon_slots.clear()
	for i in range(WEAPON_SLOT_COUNT):
		var wid := String(weapon_slots[i]) if i < weapon_slots.size() else ""
		## 存档里可能有已经不在商店里的忍具 id，这里兜底过滤掉
		if not wid.is_empty() and not Data.weapons.has(wid):
			wid = ""
		p.weapon_slots.append(wid)
	p.active_weapon = 0
	## 兜底：两个武器槽都空（老存档 / 极端情况）时发一把苦无，别让玩家完全没有攻击手段
	var has_any_weapon := false
	for wid in p.weapon_slots:
		if not String(wid).is_empty():
			has_any_weapon = true
			break
	if not has_any_weapon:
		p.weapon_slots[0] = "kunai"
	p._sync_active_weapon()


# ---------------------------------------------------------------- 忍具商店

func owns_weapon(id: String) -> bool:
	return owned_weapons.has(id)


## 购买忍具：返回 {ok, reason, price, shortfall, name}
## reason: "owned"（已拥有） / "no_money"（赏金不足） / "unknown"（没有这件忍具）
func buy_weapon(id: String) -> Dictionary:
	var w: Dictionary = Data.weapon(id)
	if w.is_empty():
		return {"ok": false, "reason": "unknown", "price": 0, "shortfall": 0, "name": id}
	var price := int(w.get("price", 0))
	var wname := Data.weapon_name(id)
	if owns_weapon(id):
		return {"ok": false, "reason": "owned", "price": price, "shortfall": 0, "name": wname}
	if money < price:
		return {"ok": false, "reason": "no_money", "price": price, "shortfall": price - money, "name": wname}
	money -= price
	owned_weapons.append(id)
	## 买到手就自动装进第一个空武器槽，省得再去界面里点一次
	for i in range(WEAPON_SLOT_COUNT):
		var cur := String(weapon_slots[i]) if i < weapon_slots.size() else ""
		if cur.is_empty():
			while weapon_slots.size() <= i:
				weapon_slots.append("")
			weapon_slots[i] = id
			break
	save_game()
	return {"ok": true, "reason": "", "price": price, "shortfall": 0, "name": wname}


# ---------------------------------------------------------------- 存档

func save_game() -> void:
	var data := {
		"level": level,
		"xp": xp,
		"money": money,
		"day": day,
		"loadout": Array(loadout),
		"owned_weapons": Array(owned_weapons),
		"weapon_slots": Array(weapon_slots),
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
	## Data.weapons 为空说明数据表还没就绪，此时不做 id 校验，避免把存档读空
	var has_weapon_table := not Data.weapons.is_empty()
	var ow: Array = parsed.get("owned_weapons", [])
	if not ow.is_empty():
		owned_weapons.clear()
		for id in ow:
			var wid := String(id)
			if (not has_weapon_table or Data.weapons.has(wid)) and not owned_weapons.has(wid):
				owned_weapons.append(wid)
	if owned_weapons.is_empty():
		for id in DEFAULT_OWNED_WEAPONS:
			owned_weapons.append(String(id))
	var ws: Array = parsed.get("weapon_slots", [])
	if not ws.is_empty():
		weapon_slots.clear()
		for i in range(WEAPON_SLOT_COUNT):
			var wid2 := String(ws[i]) if i < ws.size() else ""
			if has_weapon_table and not wid2.is_empty() and not Data.weapons.has(wid2):
				wid2 = ""
			weapon_slots.append(wid2)
	if weapon_slots.is_empty():
		for id in DEFAULT_WEAPON_SLOTS:
			weapon_slots.append(String(id))
	var md: Variant = parsed.get("missions_done", {})
	if md is Dictionary:
		missions_done = md
	return true


func reset_save() -> void:
	level = 1
	xp = 0
	money = START_MONEY
	day = 1
	loadout.clear()
	for id in DEFAULT_LOADOUT:
		loadout.append(String(id))
	owned_weapons.clear()
	for id in DEFAULT_OWNED_WEAPONS:
		owned_weapons.append(String(id))
	weapon_slots.clear()
	for id in DEFAULT_WEAPON_SLOTS:
		weapon_slots.append(String(id))
	missions_done = {}
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
