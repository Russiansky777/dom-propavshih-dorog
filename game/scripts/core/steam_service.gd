extends Node
## Autoload `SteamService`: the game in Steam (Director 16.11: «так надо чтобы и достижения и оверлей и сохранения»).
##
## The bridge is GodotSteam (GDExtension, MIT — res://addons/godotsteam, only win64 and linux64 libraries; fetched by
## .github/workflows/fetch_godotsteam.yml). When the game is started by Steam the extension's `Steam` singleton
## starts the Steam API: the overlay (Shift+Tab) then works by itself — it only needs the API started, callbacks
## run every frame and the game drawing frames (no low-processor mode here); the achievements are set from here.
## Saves need no code: Steam Auto-Cloud copies user://saves (Docs/STEAM.md, «Auto-Cloud»).
##
## Without Steam nothing changes: the exe from the release (no libraries beside it — the extension does not load), the
## editor and tests without Steam running (the singleton is there, its start fails), headless runs (not even tried).
##
## Achievements are data: res://data/steam.json says which of the traces of choices (data/story/achievements.json —
## the end screen, FrameView.achieved()) are Steam achievements and under which API names (`ACH_<ID>` unless
## renamed; `skip` — not in Steam), plus `extra` — Steam-only ones that are no trace on the end screen (Director
## 17.11: the end of each day and of the game), each {id, if: [flags], any: [flags]} like a trace; each one is set
## the moment its flags hold — on every flag change and after a load (GameState's flag_changed "*"). Steam keeps an
## achievement once set; a repeated set (a load, the next game) does nothing.

const CONFIG := "res://data/steam.json"

signal achievement_set(api_name: String)

## The Steam singleton, or a test double (attach()); null — no Steam this run.
var backend: Object = null
var active: bool = false
## What steamInitEx answered ({status, verbal}); empty when it was not tried.
var init_result: Dictionary = {}
## API names already set this run (never sent twice).
var sent: Dictionary = {}
## Every call made to the backend this run: [method, args] (tests, the probe).
var calls: Array = []
var cfg: Dictionary = {}
var _pending: bool = false


func _ready() -> void:
	cfg = load_config()
	GameState.flag_changed.connect(_on_flag)
	if not _should_start():
		return
	var steam: Object = Engine.get_singleton("Steam")
	var app_id := int(cfg.get("app_id", 0))
	# app_id 0: Steam passes its own when it starts the game; a number lets a run outside Steam (Steam open) use it
	var res = steam.call("steamInitEx", app_id, false) if app_id > 0 else steam.call("steamInitEx")
	init_result = res if res is Dictionary else {"status": -1, "verbal": str(res)}
	if int(init_result.get("status", -1)) != 0:
		print("[steam] not started: %s" % str(init_result.get("verbal", init_result)))
		return
	attach(steam)
	print("[steam] started: app %s, overlay %s" % [str(_call("getAppID")), str(_call("isOverlayEnabled"))])


func _should_start() -> bool:
	if not bool(cfg.get("enabled", true)):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	return Engine.has_singleton("Steam")


## Use `b` as Steam from now on (the singleton after a good start; tests give a double with the same methods).
func attach(b: Object) -> void:
	backend = b
	active = b != null
	sent.clear()
	_queue()


func detach() -> void:
	backend = null
	active = false


func _process(_dt: float) -> void:
	if active and backend != null and backend.has_method("run_callbacks"):
		backend.call("run_callbacks")


func _exit_tree() -> void:
	if active and backend != null and backend.has_method("steamShutdown"):
		backend.call("steamShutdown")


static func load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	return d if d is Dictionary else {}


## The Steam API name of a trace of choices (an entry of achievements.json), "" — not a Steam achievement.
func api_name(entry: Dictionary) -> String:
	var id := String(entry.get("id", ""))
	if id == "" or id in cfg.get("skip", []):
		return ""
	var names: Dictionary = cfg.get("names", {})
	if names.has(id):
		return String(names[id])
	return String(cfg.get("prefix", "ACH_")) + id.to_upper()


## Every Steam achievement the game knows: the traces of achievements.json in their order, then `extra`:
## [{id, api}] (Docs/STEAM_ACHIEVEMENTS.md).
func all_api_names() -> Array:
	var out: Array = []
	var path := StoryData.DATA_DIR_RU + "/achievements.json"
	var doc = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var entries: Array = doc.get("achievements", []).duplicate() if doc is Dictionary else []
	entries.append_array(cfg.get("extra", []))
	for a in entries:
		var n := api_name(a)
		if n != "":
			out.append({"id": String(a.get("id", "")), "api": n})
	return out


## Do an entry's flags hold now: every one of `if`, and one of `any` when there is `any` (the rule of the end screen,
## FrameView.achieved()).
static func holds(entry: Dictionary) -> bool:
	for f in entry.get("if", []):
		if not GameState.has_flag(String(f)):
			return false
	if entry.has("any"):
		for f in entry["any"]:
			if GameState.has_flag(String(f)):
				return true
		return false
	return true


func _on_flag(_flag: String, _value: bool) -> void:
	if active:
		_queue()


## Flags change in bursts (one click sets several): one check at the end of the frame.
func _queue() -> void:
	if _pending:
		return
	_pending = true
	sync_achievements.call_deferred()


## Set every achievement whose flags hold now and was not set yet; one storeStats for the lot. Returns what it set.
func sync_achievements() -> Array:
	_pending = false
	var out: Array = []
	if not active or backend == null:
		return out
	var now: Array = FrameView.achieved()
	for e in cfg.get("extra", []):
		if e is Dictionary and holds(e):
			now.append(e)
	for a in now:
		var n := api_name(a)
		if n == "" or sent.has(n):
			continue
		sent[n] = true
		_call("setAchievement", [n])
		out.append(n)
		achievement_set.emit(n)
	if not out.is_empty():
		_call("storeStats")
	return out


func _call(method: String, args: Array = []):
	if backend == null or not backend.has_method(method):
		return null
	calls.append([method, args])
	return backend.callv(method, args)


## Tests and the web probe.
func probe() -> Dictionary:
	return {"active": active, "init": init_result, "sent": sent.keys(), "singleton": Engine.has_singleton("Steam")}
