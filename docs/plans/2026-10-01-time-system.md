# 时间系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给游戏加一套"白天/夜晚"时钟：一天 10 分钟流过，夜里画面变暗、店铺 20:00 打烊、野外更危险，回公寓睡觉跳到次日早上。

**Architecture:** 时钟放在现成的 `Flow` 单例里（`hour: float` + `day: int` + `slept_today: bool`），提供 `advance(delta)` 与一组查询函数；两个场景在 `_process` 里推它。夜幕用独立静态模块 `NightFx` 画在两套 HUD 上。玩家侧的熬夜惩罚接进已有的体力/力竭系统，不另造惩罚。

**Tech Stack:** Godot 4.4 / GDScript、无头自检 `tests/selftest.tscn`、数据表 `data/strings.json`

**Spec:** `docs/specs/2026-10-01-time-system-design.md`

## Global Constraints

- 一天 24 游戏小时 = 10 分钟现实时间；白天 06:00–18:00（480 秒）、夜晚 18:00–次日 06:00（120 秒）
- 日界 = **06:00**（跨过 06:00 时 `day += 1` 并重置 `slept_today`）
- 店铺 20:00 打烊、次日 06:00 开门
- 熬夜 = `hour < 6.0`：动作体力消耗 **×1.5**，站立回复 **2.0/秒**（原 8.0）
- 夜间野外刷怪间隔 **×0.7**、精英权重 **×1.5**；村内保持绝对安全
- 睡觉只能回公寓；**每个游戏日一次**
- 所有界面打开时时间必须停（依赖现有 `get_tree().paused`，不得新增计时器绕过它）
- 老存档（无 `hour` 字段）必须能读，读成 `06:00`
- 自检入口：`godot --headless --path . --fixed-fps 60 --quit-after 40000 res://tests/selftest.tscn`，必须打印 `SELFTEST OK`
- 代码里不出现专有名词；文案进 `data/strings.json`

## Review Focus

1. **跨日边界的浮点误差**：`advance()` 一次传入很大 delta（例如测试里传 600 秒）时，必须正好跨过一次 06:00，不能吞掉或重复计一天。
2. **时间与暂停的交互**：打开任务看板 / 背包 / 商店时若时间仍在走，玩家会"看个背包天就黑了"——必须有测试证明菜单期间不推进。
3. **老存档**：缺 `hour` / `slept_today` 的旧存档读进来不能变成 `hour = 0`（会被判成熬夜）。
4. **熬夜惩罚的方向**：是"消耗变快"，不是"站着也掉血/掉体力"——站立仍然回复（只是更慢），玩家不该被卡死。
5. **夜幕下的可玩性**：压暗不是全黑，玩家周围要留可见范围；不能把 HUD 也一起压黑。

---

### Task 1: Flow 里的时钟核心 + 存档 + 睡觉

**Files:**
- Modify: `scripts/flow.gd`
- Test: `tests/selftest.gd`（新增 `_test_time()`，在 `_ready()` 里 `await` 调用）

**Interfaces:**
- Produces:
  - `Flow.hour: float`（0.0–24.0）、`Flow.slept_today: bool`
  - `Flow.advance(delta: float) -> void`
  - `Flow.is_night() -> bool`（`hour >= 18.0 or hour < 6.0`）
  - `Flow.is_late_night() -> bool`（`hour < 6.0`）
  - `Flow.is_shop_closed() -> bool`（`hour >= 20.0 or hour < 6.0`）
  - `Flow.can_sleep() -> bool`（`not slept_today`）
  - `Flow.sleep_until_morning() -> void`
  - `Flow.time_text() -> String`

- [ ] **Step 1: 写失败的测试** — 在 `tests/selftest.gd` 新增：

```gdscript
func _test_time() -> void:
	Flow.day = 1
	Flow.hour = 6.0
	Flow.slept_today = false
	Flow.advance(240.0)               ## 白天 0.025 小时/秒
	_check(is_equal_approx(Flow.hour, 12.0), "白天推进不对：%f" % Flow.hour)
	_check(not Flow.is_night(), "12:00 不该算夜晚")
	Flow.advance(240.0)
	_check(is_equal_approx(Flow.hour, 18.0), "到 18:00 不对：%f" % Flow.hour)
	_check(Flow.is_night(), "18:00 应算夜晚")
	Flow.advance(20.0)                ## 夜晚 0.1 小时/秒
	_check(is_equal_approx(Flow.hour, 20.0), "夜晚流速不对：%f" % Flow.hour)
	_check(Flow.is_shop_closed(), "20:00 应打烊")
	## 跨日：从 22:00 走 8 小时（夜晚 80 秒）
	Flow.hour = 22.0
	var d0: int = Flow.day
	Flow.advance(80.0)
	_check(Flow.day == d0 + 1, "跨过 06:00 应 +1 天：%d" % Flow.day)
	_check(is_equal_approx(Flow.hour, 6.0), "跨日后应停在 06:00：%f" % Flow.hour)
	## 一次性传很大的 delta（跨"白天→夜晚→次日"三段），不能吞掉或重复计一天
	Flow.hour = 6.0
	var d_big: int = Flow.day
	Flow.advance(600.0)              ## 480s 白天 + 120s 夜晚 = 正好一天
	_check(Flow.day == d_big + 1, "跨整天应恰好 +1 天：%d" % Flow.day)
	_check(is_equal_approx(Flow.hour, 6.0), "跨整天后应回到 06:00：%f" % Flow.hour)
	## 睡觉
	Flow.hour = 21.0
	Flow.slept_today = false
	var d1: int = Flow.day
	_check(Flow.can_sleep(), "白天/夜里应能睡")
	Flow.sleep_until_morning()
	_check(is_equal_approx(Flow.hour, 6.0), "睡觉后应是 06:00：%f" % Flow.hour)
	_check(Flow.day == d1 + 1, "睡觉应推进一天：%d" % Flow.day)
	_check(not Flow.can_sleep(), "同一天不该能睡第二次")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `godot --headless --path . --fixed-fps 60 --quit-after 40000 res://tests/selftest.tscn`
Expected: FAIL —— `Invalid call. Nonexistent function 'advance'`（或断言失败）

- [ ] **Step 3: 在 `scripts/flow.gd` 实现**

常量（放在文件顶部，与现有常量同级）：
```gdscript
const DAY_START_HOUR := 6.0
const NIGHT_START_HOUR := 18.0
const SHOP_CLOSE_HOUR := 20.0
const HOURS_PER_DAY := 24.0
const DAY_REAL_SECONDS := 480.0    ## 06:00→18:00
const NIGHT_REAL_SECONDS := 120.0  ## 18:00→06:00
```
字段：`var hour := DAY_START_HOUR`、`var slept_today := false`

关键实现点：
- `advance()`：按 `is_night()` 选速率（白天 `HOURS_PER_DAY/DAY_REAL_SECONDS`，夜晚 `HOURS_PER_DAY/NIGHT_REAL_SECONDS`），用 `fposmod` 绕圈；用私有 `_passed(before, after, mark)` 判断是否跨过 06:00，跨过则 `day += 1` 且 `slept_today = false`。**delta 必须支持一次跨多天**（用 while 或按比例分摊）。
- `sleep_until_morning()`：`day += 1`、`hour = DAY_START_HOUR`、`slept_today = true`、`save_game()`
- `time_text()`：`"%s · %02d:%02d" % [Data.s("hud.day") % day, int(hour), int((hour - floor(hour)) * 60.0)]`
- `save_game()` / `load_save()` 增加 `"hour"` 与 `"slept_today"`；`load_save()` 用 `float(parsed.get("hour", DAY_START_HOUR))`、`bool(parsed.get("slept_today", false))`
- `reset_save()` 把 `hour` 复位成 `DAY_START_HOUR`、`slept_today = false`
- `complete_mission()` 里**删掉** `day += 1`（时间改由时钟负责）
- **同时改既有用例**：`tests/selftest.gd:756` 现在是 `_check(Flow.day == 2, "任务完成未过天数：%d" % Flow.day)`，
  与新行为冲突。改成先记录 `var d_before: int = Flow.day`，任务结算后断言
  `_check(Flow.day == d_before, "任务完成不该凭空加一天：%d" % Flow.day)`

- [ ] **Step 4: 再跑一次，确认通过**

Run: 同 Step 2（`SELFTEST OK`）

- [ ] **Step 5: 老存档兼容测试**（追加进 `_test_time()`）

```gdscript
	## 老存档：只有 day，没有 hour
	var f := FileAccess.open(Flow.SAVE_PATH, FileAccess.WRITE)
	f.store_string('{"day": 7, "level": 3}')
	f.close()
	Flow.hour = 2.0
	_check(Flow.load_save(), "老存档读取失败")
	_check(is_equal_approx(Flow.hour, 6.0), "老存档应读成 06:00：%f" % Flow.hour)
	_check(Flow.day == 7, "老存档天数应保留：%d" % Flow.day)
```

- [ ] **Step 6: 提交**

```bash
git add scripts/flow.gd tests/selftest.gd
git commit -m "feat(time): Flow 时钟核心、睡觉与存档（含老存档兼容）"
```

---

### Task 2: 场景推进时间

**Files:**
- Modify: `scripts/village.gd`（`_process` 或新增 `_process`）、`scripts/main.gd`（`_process`）
- Test: `tests/selftest.gd`

**Interfaces:**
- Consumes: `Flow.advance(delta)`
- Produces: 无新接口；两场景每帧推进一步

- [ ] **Step 1: 写失败的测试**

```gdscript
func _test_time_scene() -> void:
	## 村庄场景在跑，时间应当自己往前走
	_reset_flow()
	Flow.hour = 6.0
	var h0: float = Flow.hour
	await _frames(30)
	_check(Flow.hour > h0, "村庄里时间没有流逝：%f" % Flow.hour)
	## 界面打开（pause）时时间必须停
	game.toggle_board()
	await _frames(2)
	var h1: float = Flow.hour
	await _frames(30)
	_check(is_equal_approx(Flow.hour, h1), "看板打开时时间仍在走：%f → %f" % [h1, Flow.hour])
	game.close_board()
```

- [ ] **Step 2: 跑测试确认失败** → 报"村庄里时间没有流逝"

- [ ] **Step 3: 实现**

- `scripts/village.gd`：加 `func _process(delta: float) -> void: Flow.advance(delta)`（注意 `main.gd` 已有 `_process`，在里面加一行）
- `scripts/main.gd`：在已有 `_process` 开头加 `Flow.advance(delta)`（**放在 `mission_state != RUNNING` 的提前 return 之前**，否则任务结算后就停摆了）

- [ ] **Step 4: 跑测试确认通过**（`SELFTEST OK`）

- [ ] **Step 5: 提交**

```bash
git add scripts/village.gd scripts/main.gd tests/selftest.gd
git commit -m "feat(time): 村庄与野外每帧推进时钟（暂停时自动停）"
```

---

### Task 3: 右上角时钟

**Files:**
- Modify: `scripts/hud.gd`、`scripts/village_hud.gd`、`data/strings.json`
- Test: `tests/selftest.gd`

**Interfaces:**
- Consumes: `Flow.time_text()`
- Produces: 私有 `_draw_clock(font: Font)`；`Data.s("hud.time")` 文案键（如需）

- [ ] **Step 1: 写失败的测试**

```gdscript
	## 时钟文本（纯逻辑，便于断言）
	Flow.day = 3
	Flow.hour = 9.5
	var t1: String = Flow.time_text()
	_check(t1.find("3") >= 0 and t1.find("09:30") >= 0, "时钟文本不对：%s" % t1)
	Flow.hour = 21.0
	_check(Flow.time_text().find("21:00") >= 0, "夜晚时钟文本不对：%s" % Flow.time_text())
```

- [ ] **Step 2: 跑测试确认失败**（`time_text` 未实现时在 Task 1 已补；此步验证格式）

- [ ] **Step 3: 实现**

- `scripts/hud.gd`：在 `_draw()` 里加 `_draw_clock(font)`。位置：**屏幕右上角最上面一行**（`x = size_v.x - 24`，右对齐，`y = 34`）；同时把现有的"击倒 N"（y=34）改成 y=58、"赏金 / 第 N 天"（y=56）改成 y=80，给时钟腾出一行
- 图标用**画的**，不用字体符号（避免缺字）：白天画一个 6px 黄色圆 + 8 条放射短线；夜晚画一个同尺寸淡蓝圆 + 两个小灰点
- `scripts/village_hud.gd`：同样在右上角加时钟（它右上角目前只有标题，时钟放标题上方一行）
- `data/strings.json`：若需要"第 %d 天"以外的文案（例如"打烊"），一并加上

- [ ] **Step 4: 跑测试**（`SELFTEST OK`；HUD 绘制在无头下不报错）

- [ ] **Step 5: 提交**

```bash
git add scripts/hud.gd scripts/village_hud.gd data/strings.json tests/selftest.gd
git commit -m "feat(time): 右上角时钟（第 N 天 + 太阳/月亮 + 时刻）"
```

---

### Task 4: 夜间压暗与玩家微光

**Files:**
- Create: `scripts/night_fx.gd`（`class_name NightFx`，静态绘制模块，风格对齐现有 `Fx` / `VillageArt`）
- Modify: `scripts/hud.gd`、`scripts/village_hud.gd`
- Test: `tests/selftest.gd`

**Interfaces:**
- Produces:
  - `NightFx.dark_alpha(hour: float) -> float`（含黄昏/黎明渐变，范围 0 ~ 0.35）
  - `NightFx.draw_overlay(c: CanvasItem, player_screen: Vector2, view_size: Vector2) -> void`

- [ ] **Step 1: 写失败的测试**

```gdscript
func _test_night_fx() -> void:
	_check(is_equal_approx(NightFx.dark_alpha(12.0), 0.0), "正午不该压暗")
	_check(NightFx.dark_alpha(21.0) > 0.3, "深夜应该明显压暗：%f" % NightFx.dark_alpha(21.0))
	var dusk := NightFx.dark_alpha(18.25)
	_check(dusk > 0.0 and dusk < 0.35, "18:15 应是渐变中间态：%f" % dusk)
	_check(is_equal_approx(NightFx.dark_alpha(18.0), 0.0), "18:00 整应还没变暗")
```

- [ ] **Step 2: 跑测试确认失败**

- [ ] **Step 3: 实现**

- `dark_alpha()`：18:00 起 0.5 游戏小时内线性升到 `0.35`，06:00 前 0.5 小时线性降回 0；其余夜晚保持 `0.35`
- `draw_overlay()`：以玩家屏幕坐标为圆心，用**一圈圈加粗的 `draw_arc`**（半径递增、宽度约 70、透明度随半径递增）近似径向渐变，避免引入 shader
- 两套 HUD 在 `_draw()` **最开头**调用（先压暗，再画 HUD 元素，保证 HUD 自己不被压暗）。玩家屏幕坐标：`get_viewport().get_camera_2d().get_canvas_transform() * player.global_position`

- [ ] **Step 4: 跑测试确认通过**

- [ ] **Step 5: 截图确认视觉效果**

Run: `godot --path . res://tools/shot_village.tscn`（工具里临时把 `Flow.hour` 设成 21.0 再截一张）
Expected: 画面明显变暗但不是全黑，玩家周围可见

- [ ] **Step 6: 提交**

```bash
git add scripts/night_fx.gd scripts/hud.gd scripts/village_hud.gd tests/selftest.gd
git commit -m "feat(time): 夜间压暗与玩家周围微光"
```

---

### Task 5: 熬夜惩罚（接进体力系统）

**Files:**
- Modify: `scripts/player.gd`
- Test: `tests/selftest.gd`

**Interfaces:**
- Consumes: `Flow.is_late_night()`
- Produces: 常量 `LATE_NIGHT_DRAIN_MULT := 1.5`、`LATE_NIGHT_IDLE_REGEN := 2.0`

- [ ] **Step 1: 写失败的测试**

```gdscript
func _test_late_night_stamina() -> void:
	player.stamina = 100.0
	player.exhausted = false
	Flow.hour = 12.0
	player._spend_stamina(10.0)
	_check(is_equal_approx(player.stamina, 90.0), "白天消耗不对：%f" % player.stamina)
	Flow.hour = 1.0
	player.stamina = 100.0
	player._spend_stamina(10.0)
	_check(is_equal_approx(player.stamina, 85.0), "熬夜消耗应为 1.5 倍：%f" % player.stamina)
	## 熬夜时站立回复变慢，但仍然回复（不卡死）
	player.stamina = 10.0
	Flow.hour = 1.0
	player._tick_stamina(1.0, false, true)
	_check(is_equal_approx(player.stamina, 12.0), "熬夜站立回复应为 2/秒：%f" % player.stamina)
	Flow.hour = 12.0
	player.stamina = 10.0
	player._tick_stamina(1.0, false, true)
	_check(is_equal_approx(player.stamina, 18.0), "白天站立回复应为 8/秒：%f" % player.stamina)
```

- [ ] **Step 2: 跑测试确认失败**

- [ ] **Step 3: 实现**

- `_spend_stamina()` 内：`if Flow.is_late_night(): amount *= LATE_NIGHT_DRAIN_MULT`
- `_tick_stamina()` 的 idle 分支：`var regen := LATE_NIGHT_IDLE_REGEN if Flow.is_late_night() else STAMINA_REGEN_IDLE`

- [ ] **Step 4: 跑测试确认通过**

- [ ] **Step 5: 提交**

```bash
git add scripts/player.gd tests/selftest.gd
git commit -m "feat(time): 熬夜体力消耗 ×1.5、站立回复降到 2/秒"
```

---

### Task 6: 店铺打烊 + 夜间野外更危险 + 公寓睡觉

**Files:**
- Modify: `scripts/village.gd`、`scripts/main.gd`、`data/strings.json`
- Test: `tests/selftest.gd`

**Interfaces:**
- Consumes: `Flow.is_shop_closed()`、`Flow.is_night()`、`Flow.can_sleep()`、`Flow.sleep_until_morning()`
- Produces: 常量 `NIGHT_SPAWN_INTERVAL_MULT := 0.7`、`NIGHT_ELITE_WEIGHT_MULT := 1.5`（`main.gd`）

- [ ] **Step 1: 写失败的测试**

```gdscript
func _test_time_gates() -> void:
	## 注意：本用例需要**村庄场景**（睡觉是村庄功能），放在 _test_ui_clicks 之后跑
	_reset_flow()
	## 打烊
	Flow.hour = 21.0
	_check(Flow.is_shop_closed(), "21:00 应打烊")
	Flow.hour = 12.0
	_check(not Flow.is_shop_closed(), "中午不该打烊")
	## 睡觉：第一次成功、第二次被拒
	Flow.hour = 12.0
	Flow.slept_today = false
	player.hp = 10.0
	game.sleep_here()              ## 村庄的睡觉入口，见 Step 3
	_check(is_equal_approx(Flow.hour, 6.0), "睡觉后应是 06:00：%f" % Flow.hour)
	_check(player.hp >= player.max_hp, "睡觉应回满生命：%f" % player.hp)
	_check(not Flow.can_sleep(), "同一天不该能睡第二次")
```

夜间刷怪是**战场**（`main.gd`）的功能，不能在村庄场景里测，单独一个用例放在战斗场景中：

```gdscript
func _test_night_spawn() -> void:
	## 战场场景（_test_mission_hunt 之后跑）
	Flow.hour = 12.0
	var day_i: float = game._spawn_interval()
	Flow.hour = 22.0
	var night_i: float = game._spawn_interval()
	_check(night_i < day_i, "夜间刷怪间隔应更短：%f vs %f" % [night_i, day_i])
	## 精英权重只在夜间放大
	var mix := {"chaser": 10.0, "elite": 1.0}
	var night_mix: Dictionary = game._night_mix(mix)
	_check(float(night_mix["elite"]) > float(mix["elite"]), "夜间精英权重应提高")
	Flow.hour = 12.0
	_check(float(game._night_mix(mix)["elite"]) == 1.0, "白天不该改精英权重")
```

两个用例的挂载位置（`_ready()` 里）：
- `await _test_time_gates()` → 跟在 `await _test_shop()` 后面（此时村庄场景已加载）
- `await _test_night_spawn()` → 跟在 `await _test_mission_hunt()` 后面（此时是战场场景）

- [ ] **Step 2: 跑测试确认失败**

- [ ] **Step 3: 实现**

- `scripts/village.gd`：交互点 `shrine`（公寓）的 `hint` 与 `on_interact()` 改成睡觉：
  - `if not Flow.can_sleep()` → `hud.show_notice(Data.s("village.cant_sleep"))`，return
  - 否则 `Flow.sync_from_player(player)` → `Flow.sleep_until_morning()` → 回满 `hp/chakra/stamina` → `hud.show_notice(Data.s("village.slept"))`
  - 新增 `func sleep_here() -> void` 作为入口（测试与交互都调它）
- `scripts/village.gd`：`toggle_shop(mode)` 开头加打烊判定 → 提示 `Data.s("shop.closed")` 并 return；交互提示在打烊时也显示"已打烊"
- `scripts/main.gd`：抽出 `func _spawn_interval() -> float`（返回当前生效的刷怪间隔，夜晚 ×0.7），`_process` 里用它；`_pick_from_mix()` 前把 `mix["elite"]` ×1.5（仅夜间）
- `scripts/main.gd`：新增 `func _night_mix(mix: Dictionary) -> Dictionary`（夜间返回复制并把 `elite` ×1.5，白天原样返回）
- `data/strings.json`：加 `village.slept`、`village.cant_sleep`、`shop.closed`
- `tests/selftest.gd`：`_reset_flow()` 里补 `Flow.hour = Flow.DAY_START_HOUR` 与 `Flow.slept_today = false`，避免用例之间互相污染

- [ ] **Step 4: 跑测试确认通过**

- [ ] **Step 5: 提交**

```bash
git add scripts/village.gd scripts/main.gd data/strings.json tests/selftest.gd
git commit -m "feat(time): 店铺 20:00 打烊、夜间野外更危险、公寓睡觉"
```

---

### Task 7: 文档收尾

**Files:**
- Modify: `README.md`、`../设计基线.md`（仓库外，同步即可）

**Interfaces:** 无

- [ ] **Step 1: 更新 README**：状态版本 → v0.11，新增「v0.10 → v0.11」变更块（一天 10 分钟、睡觉、打烊、夜间野外、熬夜惩罚、右上角时钟）
- [ ] **Step 2: 更新 `设计基线.md`**：加 v0.11 规格（常量表照抄 spec 第 8 节）+ 待办勾选
- [ ] **Step 3: 提交**

```bash
git add README.md
git commit -m "docs v0.11：时间系统落地说明"
```

---

## 交付后自检清单

- [ ] `SELFTEST OK`（含 Task 1–6 新增的全部用例）
- [ ] 手动跑一次游戏：站着看时钟走、18:00 变暗、20:00 店铺打烊、回公寓睡觉跳到次日 06:00
- [ ] 截图留档（白天 / 夜晚各一张）
- [ ] 老存档可读（`hour` 缺失 → 06:00）
