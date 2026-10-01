extends Node
## 全局流程：场景切换（村庄 ↔ 战场）、任务状态、金钱、天数、**背包**、存档。
## 持久进度存在这里，玩家只是"当前会话里的执行者"；跨场景与存档都由本节点统一处理。
##
## 背包模型（v0.8 起）：
##   背包 = 固定 24 个格子，每格是一"堆"：{sid, id, count, dur}
##   - sid 是稳定编号，武器槽指向 sid（不是 id），所以"装的是哪一把短刀"不会认错
##   - 手里剑 / 苦无 / 兵粮丸 可堆叠（每组 16），堆叠物没有独立耐久
##   - 苦无的近战磨损算在"当前这一把"上：耐久归零 → 消耗 1 个 → 换下一把
##   - 短刀 / 长剑 不可堆叠（每组 1），每一把各自带耐久，用坏了就消失
##   投掷 = 直接从背包扣 1 个（真消耗品），战斗中不会自动补充

const SAVE_PATH := "user://pnv_save.json"
const DEFAULT_LOADOUT := ["blink", "fireball", "great_fireball", "thunder_dash", "shadow_clones"]

## 武器槽：主手 + 副手，Q 切换
const WEAPON_SLOT_COUNT := 2
## 背包格数（界面按 6 列 × 4 行摆）
const INV_SLOTS := 24
## 开局发的少量金钱（原始构想：降生时给一间公寓和少量钱）
const START_MONEY := 150
## 开局背包：8 把苦无 + 6 枚手里剑 + 3 颗兵粮丸，够打两趟 D 级任务
const DEFAULT_KIT := [
	{"id": "kunai", "count": 8},
	{"id": "shuriken", "count": 6},
	{"id": "hyorogan", "count": 3},
]

## ---------------------------------------------------------------- 时间
## 一天 24 小时 = DAY_REAL_SECONDS + NIGHT_REAL_SECONDS = 10 分钟现实时间。
## 06:00 是一天的起点，也是日界：跨过 06:00 就 day += 1。
const HOURS_PER_DAY := 24.0
const DAY_START_HOUR := 6.0
const NIGHT_START_HOUR := 18.0
const SHOP_CLOSE_HOUR := 20.0
const DAY_REAL_SECONDS := 480.0     ## 06:00 → 18:00
const NIGHT_REAL_SECONDS := 120.0   ## 18:00 → 次日 06:00
const DAY_SPAN_HOURS := NIGHT_START_HOUR - DAY_START_HOUR       ## 12
const NIGHT_SPAN_HOURS := HOURS_PER_DAY - DAY_SPAN_HOURS        ## 12

## 持久进度
var level := 1
var xp := 0
var money := 0
var day := 1
## 当前时刻（0.0 ~ 24.0）与"今天是否已经睡过"
var hour := DAY_START_HOUR
var slept_today := false
var loadout: Array[String] = []
## 背包格（每格 {sid, id, count, dur}）与自增编号
var inventory: Array = []
var inv_next_sid := 1
## 每个武器槽指向的背包格编号（-1 = 空槽）
var weapon_sids: Array[int] = []
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
	for id in Data.jutsu_list:
		unlocked_jutsu.append(String(id))
	_ensure_weapon_slots()
	if not load_save():
		## 全新存档：发开局的钱与装备
		money = START_MONEY
		grant_default_kit()
	_ensure_equipped_weapons()


func _ensure_weapon_slots() -> void:
	while weapon_sids.size() < WEAPON_SLOT_COUNT:
		weapon_sids.append(-1)


# ---------------------------------------------------------------- 时间

func is_night() -> bool:
	return hour >= NIGHT_START_HOUR or hour < DAY_START_HOUR


## 00:00 ~ 06:00：熬夜段（体力消耗加快，见 player.gd）
func is_late_night() -> bool:
	return hour < DAY_START_HOUR


## 20:00 打烊，次日 06:00 开门
func is_shop_closed() -> bool:
	return hour >= SHOP_CLOSE_HOUR or hour < DAY_START_HOUR


func can_sleep() -> bool:
	return not slept_today


func _hour_rate() -> float:
	## 白天 12 小时摊在 480 秒上（0.025 小时/秒），夜晚 12 小时摊在 120 秒上（0.1 小时/秒）
	return (NIGHT_SPAN_HOURS / NIGHT_REAL_SECONDS) if is_night() else (DAY_SPAN_HOURS / DAY_REAL_SECONDS)


## 推进时间。支持一次传入很大的 delta（会按时段分段走完），
## 每到 06:00 算过一天，并重置"今天睡过了"。
func advance(delta: float) -> void:
	var left := maxf(delta, 0.0)
	var guard := 0
	while left > 0.0 and guard < 256:
		guard += 1
		var night := is_night()
		var rate := _hour_rate()
		var boundary := DAY_START_HOUR if night else NIGHT_START_HOUR
		var hours_to_boundary := fposmod(boundary - hour, HOURS_PER_DAY)
		if hours_to_boundary <= 0.0001:
			hours_to_boundary = HOURS_PER_DAY
		var real_to_boundary := hours_to_boundary / rate
		if left < real_to_boundary:
			hour = fposmod(hour + left * rate, HOURS_PER_DAY)
			left = 0.0
		else:
			hour = boundary
			left -= real_to_boundary
			if night:
				## 夜晚走到 06:00 = 过了一天
				day += 1
				slept_today = false


## 睡觉：跳到次日 06:00。调用方负责回满资源与提示。
func sleep_until_morning() -> void:
	day += 1
	hour = DAY_START_HOUR
	slept_today = true
	save_game()


func time_text() -> String:
	var h := int(floor(hour))
	var m := int(floor((hour - float(h)) * 60.0))
	return "%s · %02d:%02d" % [Data.s("hud.day") % day, h, m]


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


## 任务完成：发赏金、计次数、存盘。返回 {ryo, xp}。
## 注意：**不再凭空 +1 天**——时间由时钟负责，任务只是花掉了真实流过的那段时间。
func complete_mission() -> Dictionary:
	var ryo := int(mission_cfg.get("reward_ryo", 0))
	var r_xp := int(mission_cfg.get("reward_xp", 0))
	money += ryo
	missions_done[mission_id] = int(missions_done.get(mission_id, 0)) + 1
	save_game()
	return {"ryo": ryo, "xp": r_xp}


func mission_done_count(id: String) -> int:
	return int(missions_done.get(id, 0))


# ---------------------------------------------------------------- 背包

func _new_stack(id: String, count: int) -> Dictionary:
	var st := {
		"sid": inv_next_sid,
		"id": id,
		"count": count,
		## 耐久是"这一件"的，堆叠物按当前这一件算
		"dur": Data.item_durability(id),
	}
	inv_next_sid += 1
	return st


func inv_index(sid: int) -> int:
	for i in inventory.size():
		if int(inventory[i].get("sid", -1)) == sid:
			return i
	return -1


## 按 sid 取格子（返回的是字典引用，可以直接改）
func inv_find(sid: int) -> Dictionary:
	var i := inv_index(sid)
	return inventory[i] if i >= 0 else {}


func inv_used() -> int:
	return inventory.size()


func inv_free() -> int:
	return INV_SLOTS - inventory.size()


## 背包里某种东西的总数（不传 id 就返回所有格子数）
func inv_total(id := "") -> int:
	if id.is_empty():
		return inventory.size()
	var n := 0
	for st in inventory:
		if String(st["id"]) == id:
			n += int(st["count"])
	return n


## 背包里还有几个位置能放这种 id
func inv_space_for(id: String) -> int:
	var max_stack := Data.item_stack(id)
	var room := inv_free() * max_stack
	if max_stack > 1:
		for st in inventory:
			if String(st["id"]) == id:
				room += maxi(max_stack - int(st["count"]), 0)
	return room


## 放入物品，返回实际放进去的数量（背包满了就放不满）
func inv_add(id: String, count := 1) -> int:
	if not Data.has_item(id) or count <= 0:
		return 0
	var max_stack := Data.item_stack(id)
	var left := count
	if max_stack > 1:
		## 先填已有的同类未满堆
		for st in inventory:
			if left <= 0:
				break
			if String(st["id"]) != id:
				continue
			var room := max_stack - int(st["count"])
			if room <= 0:
				continue
			var put := mini(room, left)
			st["count"] = int(st["count"]) + put
			left -= put
	## 再开新格
	while left > 0 and inventory.size() < INV_SLOTS:
		var put2 := mini(max_stack, left)
		inventory.append(_new_stack(id, put2))
		left -= put2
	return count - left


## 从某个格子取出，返回实际取出的数量；取空了这个格子就消失
func inv_take(sid: int, count := 1) -> int:
	var idx := inv_index(sid)
	if idx < 0:
		return 0
	var st: Dictionary = inventory[idx]
	var take := mini(count, int(st["count"]))
	st["count"] = int(st["count"]) - take
	if int(st["count"]) <= 0:
		inventory.remove_at(idx)
		_unequip_sid(sid)
	return take


## 扣掉当前这一件的耐久；耐久归零就消耗掉它
## 返回 "ok"（还在用） / "broken"（这一件报废但堆里还有） / "gone"（格子空了）
func inv_wear(sid: int, amount := 1.0) -> String:
	var st := inv_find(sid)
	if st.is_empty():
		return "gone"
	var dur := float(st.get("dur", 0.0))
	if dur <= 0.0:
		return "ok"
	dur -= amount
	if dur > 0.0:
		st["dur"] = dur
		return "ok"
	st["dur"] = Data.item_durability(String(st["id"]))
	if inv_take(sid, 1) <= 0:
		return "gone"
	return "broken" if inv_index(sid) >= 0 else "gone"


## 开局那套基础装备（新档 / 老档迁移都用它）
func grant_default_kit() -> void:
	for entry in DEFAULT_KIT:
		inv_add(String(entry["id"]), int(entry["count"]))


# ---------------------------------------------------------------- 武器槽

func sid_of_slot(slot: int) -> int:
	if slot < 0 or slot >= weapon_sids.size():
		return -1
	return weapon_sids[slot]


## 武器槽指向某个背包格；同一个格子不会被两个槽同时指着
func equip_sid(slot: int, sid: int) -> bool:
	_ensure_weapon_slots()
	if slot < 0 or slot >= WEAPON_SLOT_COUNT:
		return false
	if sid >= 0:
		if inv_index(sid) < 0 or not Data.is_weapon(String(inv_find(sid)["id"])):
			return false
		for i in weapon_sids.size():
			if weapon_sids[i] == sid:
				weapon_sids[i] = -1
	weapon_sids[slot] = sid
	save_game()
	return true


## 武器 id → 背包里第一格该武器的 sid（找不到返回 -1）
func first_sid_of(id: String) -> int:
	for st in inventory:
		if String(st["id"]) == id:
			return int(st["sid"])
	return -1


func _unequip_sid(sid: int) -> void:
	for i in weapon_sids.size():
		if weapon_sids[i] == sid:
			weapon_sids[i] = -1


## 两个槽都空（或指向的格子没了）时，从背包里自动挑武器装上
func _ensure_equipped_weapons() -> void:
	_ensure_weapon_slots()
	for i in weapon_sids.size():
		if weapon_sids[i] >= 0 and inv_index(weapon_sids[i]) < 0:
			weapon_sids[i] = -1
	var used := {}
	for i in weapon_sids.size():
		if weapon_sids[i] >= 0:
			used[weapon_sids[i]] = true
	for i in weapon_sids.size():
		if weapon_sids[i] >= 0:
			continue
		for st in inventory:
			var sid := int(st["sid"])
			if used.has(sid) or not Data.is_weapon(String(st["id"])):
				continue
			weapon_sids[i] = sid
			used[sid] = true
			break


## 兼容旧接口：背包里有没有这件忍具
func owns_weapon(id: String) -> bool:
	return first_sid_of(id) >= 0


# ---------------------------------------------------------------- 忍具店

## 购买：qty 是想买几个，实际数量受赏金与背包空间限制
## 返回 {ok, reason, bought, want, cost, name}
## reason: ""（足量）/ "partial"（只买到一部分）/ "no_money" / "no_space" / "unknown"
func buy_item(id: String, qty := 1) -> Dictionary:
	var d: Dictionary = Data.item_def(id)
	var base := {"ok": false, "reason": "unknown", "bought": 0, "want": qty, "cost": 0, "name": id}
	if d.is_empty():
		return base
	var price := Data.item_price(id)
	var iname := Data.item_name(id)
	if price <= 0 or qty <= 0:
		base["name"] = iname
		return base
	var affordable := int(money / price)
	var space := inv_space_for(id)
	var want := mini(qty, mini(affordable, space))
	if want <= 0:
		base["reason"] = "no_money" if affordable <= 0 else "no_space"
		base["name"] = iname
		base["shortfall"] = maxi(price - money, 0)
		return base
	money -= want * price
	inv_add(id, want)
	## 买到武器时顺手补一个空武器槽，省得再进背包里点一次
	if Data.is_weapon(id):
		_auto_equip_new_weapon(id)
	save_game()
	return {
		"ok": true,
		"reason": "" if want >= qty else "partial",
		"bought": want,
		"want": qty,
		"cost": want * price,
		"name": iname,
	}


func _auto_equip_new_weapon(id: String) -> void:
	_ensure_weapon_slots()
	var sid := first_sid_of(id)
	if sid < 0:
		return
	for i in weapon_sids.size():
		if weapon_sids[i] == sid:
			return
	for i in weapon_sids.size():
		if weapon_sids[i] < 0:
			weapon_sids[i] = sid
			return


# ---------------------------------------------------------------- 与玩家的进度同步

func sync_from_player(p) -> void:
	level = int(p.level)
	xp = int(p.xp)
	loadout.clear()
	for id in p.jutsu_slots:
		loadout.append(String(id))
	weapon_sids.clear()
	for i in range(WEAPON_SLOT_COUNT):
		weapon_sids.append(int(p.weapon_sid_at(i)))
	save_game()


func apply_to_player(p) -> void:
	p.level = level
	p.xp = xp
	p.xp_next = 40 + (level - 1) * 26
	p.max_hp = p.MAX_HP_BASE + 12.0 * float(level - 1)
	p.max_chakra = p.MAX_CHAKRA_BASE + 10.0 * float(level - 1)
	p.max_stamina = p.MAX_STAMINA_BASE + 10.0 * float(level - 1)
	p.hp = p.max_hp
	p.chakra = p.max_chakra
	p.stamina = p.max_stamina
	p.exhausted = false
	p.jutsu_slots.clear()
	for id in loadout:
		p.jutsu_slots.append(String(id))
	_ensure_equipped_weapons()
	p.weapon_sids.clear()
	for i in range(WEAPON_SLOT_COUNT):
		p.weapon_sids.append(sid_of_slot(i))
	p.active_weapon = 0
	p.sync_active_weapon()


# ---------------------------------------------------------------- 存档

func save_game() -> void:
	var data := {
		"level": level,
		"xp": xp,
		"money": money,
		"day": day,
		"hour": hour,
		"slept_today": slept_today,
		"loadout": Array(loadout),
		"inventory": inventory,
		"inv_next_sid": inv_next_sid,
		"weapon_sids": Array(weapon_sids),
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
	## 老存档没有 hour：默认读成早上 06:00（不能变成 0，否则会被判成熬夜）
	hour = float(parsed.get("hour", DAY_START_HOUR))
	slept_today = bool(parsed.get("slept_today", false))
	var lo: Array = parsed.get("loadout", [])
	if lo.size() == 5:
		loadout.clear()
		for id in lo:
			loadout.append(String(id))
	_load_inventory(parsed)
	_load_weapon_sids(parsed)
	var md: Variant = parsed.get("missions_done", {})
	if md is Dictionary:
		missions_done = md
	return true


func _load_inventory(parsed: Dictionary) -> void:
	inventory.clear()
	## Data 表还没就绪时不做 id 校验，免得把存档读空
	var has_item_table := not Data.weapons.is_empty() or not Data.items.is_empty()
	var raw: Array = parsed.get("inventory", [])
	var max_sid := 0
	for e in raw:
		if not e is Dictionary:
			continue
		var iid := String(e.get("id", ""))
		if has_item_table and not Data.has_item(iid):
			continue
		var sid := int(e.get("sid", 0))
		var cnt := maxi(int(e.get("count", 1)), 1)
		var st := {
			"sid": sid,
			"id": iid,
			"count": cnt,
			"dur": float(e.get("dur", Data.item_durability(iid))),
		}
		inventory.append(st)
		max_sid = maxi(max_sid, sid)
	inv_next_sid = maxi(int(parsed.get("inv_next_sid", 1)), max_sid + 1)
	## 老存档（v0.7 及以前没有背包）迁移：把 owned_weapons 变成背包格
	if inventory.is_empty():
		var owned: Array = parsed.get("owned_weapons", [])
		if owned.is_empty():
			return
		for id in owned:
			var wid := String(id)
			if has_item_table and not Data.has_item(wid):
				continue
			## 投掷类给一小把，近战类给一把
			inv_add(wid, 4 if Data.item_stack(wid) > 1 else 1)


func _load_weapon_sids(parsed: Dictionary) -> void:
	_ensure_weapon_slots()
	for i in weapon_sids.size():
		weapon_sids[i] = -1
	var raw: Array = parsed.get("weapon_sids", [])
	if not raw.is_empty():
		for i in range(WEAPON_SLOT_COUNT):
			var sid := int(raw[i]) if i < raw.size() else -1
			if sid >= 0 and inv_index(sid) < 0:
				sid = -1
			weapon_sids[i] = sid
		return
	## v0.7 存档里 weapon_slots 存的是武器 id
	var old: Array = parsed.get("weapon_slots", [])
	for i in range(WEAPON_SLOT_COUNT):
		var wid := String(old[i]) if i < old.size() else ""
		weapon_sids[i] = first_sid_of(wid) if not wid.is_empty() else -1


func reset_save() -> void:
	level = 1
	xp = 0
	money = START_MONEY
	day = 1
	hour = DAY_START_HOUR
	slept_today = false
	loadout.clear()
	for id in DEFAULT_LOADOUT:
		loadout.append(String(id))
	inventory.clear()
	inv_next_sid = 1
	_ensure_weapon_slots()
	for i in range(WEAPON_SLOT_COUNT):
		weapon_sids[i] = -1
	grant_default_kit()
	_ensure_equipped_weapons()
	missions_done = {}
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
