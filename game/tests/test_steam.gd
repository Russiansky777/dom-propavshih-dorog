extends SceneTree
## Steam (Director 16.11: «так надо чтобы и достижения и оверлей и сохранения»): SteamService + GodotSteam.
##   godot --headless --audio-driver Dummy --path game -s res://tests/test_steam.gd
##   S16-1 Without Steam the game is the same: in a headless run SteamService does not even try to start Steam
##       (inactive, nothing sent, no calls), and the flags of an achievement change nothing but the story.
##   S16-2 Achievements are the traces of choices (data/story/achievements.json): with a Steam double attached, the
##       flags of one trace set exactly its API name (ACH_<ID>) and store once; another flag, a second set of the
##       same flag, a load (the resync "*") send nothing again. Self-check — a detached service sends nothing.
##   S16-3 The API names: every trace has one, unique, of the letters Steam takes (A–Z, 0–9, _), the same list as
##       Docs/STEAM_ACHIEVEMENTS.md; res://data/steam.json reads, its `skip` and `names` are obeyed. Self-check —
##       a name with a space or a lower-case letter is caught by the same rule.
##   S16-4 The library ships with its license: the «Лицензии» screen has a «Библиотеки игры» section with GodotSteam
##       under MIT and its full text (licenses.json ← addons/godotsteam/license.md); the Windows libraries the
##       export copies beside the exe are in the project.
##   S16-5 The extension itself (when its Linux library loads here): the `Steam` singleton has the calls SteamService
##       makes, with the arguments it passes (steamInitEx, run_callbacks, setAchievement, storeStats, getAppID,
##       isOverlayEnabled, steamShutdown) — an update of GodotSteam that renames one fails here, not in Steam.

const ACH := "res://data/story/achievements.json"
const NAME_RE := "^[A-Z0-9_]+$"
const LicensesText := preload("res://scripts/ui/licenses_text.gd")

var _results: Array = []
var _fails: Array[String] = []
var gs: Node
var ss: Node


class SteamDouble:
	extends RefCounted
	var log: Array = []
	func setAchievement(n: String) -> bool:
		log.append(["setAchievement", n])
		return true
	func storeStats() -> bool:
		log.append(["storeStats"])
		return true
	func run_callbacks() -> void:
		pass
	func getAppID() -> int:
		return 480
	func isOverlayEnabled() -> bool:
		return true
	func count(m: String) -> int:
		var c := 0
		for e in log:
			if e[0] == m:
				c += 1
		return c


func _initialize() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		_fails.append(message)


func _test(test_name: String, fn: Callable) -> void:
	_fails = []
	var started := Time.get_ticks_msec()
	await fn.call()
	var passed := _fails.is_empty()
	_results.append(passed)
	print(("PASS  " if passed else "FAIL  ") + test_name + "  (%d ms)" % (Time.get_ticks_msec() - started))
	for f in _fails:
		print("        - " + f)


func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	ss = root.get_node_or_null("SteamService")
	if ss == null:
		print("FAIL  SteamService is not an autoload")
		quit(1)
		return
	await _test("S16-1 without Steam: not started in a headless run, nothing sent, the flags of an achievement change only the story", _test_no_steam)
	await _test("S16-2 achievements: a trace's flags set its ACH_ name and store once; no repeats on another flag, a second set, a load; self-check — detached sends nothing", _test_achievements)
	await _test("S16-3 API names: one per trace, unique, A–Z 0–9 _, skip and names obeyed; self-check — a bad name is caught", _test_names)
	await _test("S16-4 the library's license is on the «Лицензии» screen (GodotSteam, MIT, full text); the Windows libraries are in the project", _test_license)
	await _test("S16-5 the GodotSteam extension has the calls SteamService makes (when its library loads here)", _test_extension_api)
	var failed := _results.count(false)
	print("==== steam 16.11: %d tests, %d passed, %d failed ====" % [_results.size(), _results.size() - failed, failed])
	quit(1 if failed > 0 else 0)


func _traces() -> Array:
	var d = JSON.parse_string(FileAccess.get_file_as_string(ACH))
	return d.get("achievements", []) if d is Dictionary else []


func _settle() -> void:
	await process_frame
	await process_frame


# --- S16-1 ---------------------------------------------------------------------------------------

func _test_no_steam() -> void:
	gs.reset()
	await _settle()
	_check(not ss.active, "SteamService is active in a headless run")
	_check(ss.init_result.is_empty(), "steamInitEx was tried in a headless run: %s" % str(ss.init_result))
	_check(ss.calls.is_empty(), "calls were made to Steam without Steam: %s" % str(ss.calls))
	gs.set_flag("mitten_found_on_path")
	await _settle()
	_check(gs.has_flag("mitten_found_on_path"), "the flag itself did not hold")
	_check(ss.sent.is_empty() and ss.calls.is_empty(), "without Steam something was sent: %s" % str(ss.calls))
	var p: Dictionary = ss.probe()
	_check(p.has("active") and p.has("singleton"), "probe without its fields: %s" % str(p))
	gs.reset()


# --- S16-2 ---------------------------------------------------------------------------------------

func _test_achievements() -> void:
	gs.reset()
	var d := SteamDouble.new()
	ss.attach(d)
	await _settle()
	_check(d.count("setAchievement") == 0, "with no choices made something was set: %s" % str(d.log))
	gs.set_flag("mitten_found_on_path")
	await _settle()
	_check(d.log.has(["setAchievement", "ACH_MITTEN"]), "the mitten found did not set ACH_MITTEN: %s" % str(d.log))
	_check(d.count("setAchievement") == 1 and d.count("storeStats") == 1, "one trace — not one set and one store: %s" % str(d.log))
	# a trace with `if` + `any`: the board needs Mama's answer and one of the three places
	gs.set_flag("nina_answered_board")
	await _settle()
	_check(not d.log.has(["setAchievement", "ACH_BOARD"]), "ACH_BOARD set before any place was chosen")
	gs.set_flag("board_mama")
	await _settle()
	_check(d.log.has(["setAchievement", "ACH_BOARD"]), "ACH_BOARD not set once Mama answered and a place was chosen: %s" % str(d.log))
	var n := d.log.size()
	gs.set_flag("some_unrelated_flag_s16")
	gs.set_flag("mitten_found_on_path", false)
	gs.set_flag("mitten_found_on_path")
	gs.flag_changed.emit("*", true)   # what a load announces
	await _settle()
	_check(d.log.size() == n, "a repeat was sent: %s" % str(d.log.slice(n)))
	# self-check: a detached service sends nothing however the flags go
	ss.detach()
	gs.set_flag("ribbon_braided")
	await _settle()
	_check(not d.log.has(["setAchievement", "ACH_RIBBON"]), "self-check: a detached service still sent")
	ss.sent.clear()
	gs.reset()


# --- S16-3 ---------------------------------------------------------------------------------------

func _valid_names(names: Array) -> String:
	var re := RegEx.create_from_string(NAME_RE)
	var seen := {}
	for n in names:
		if re.search(String(n)) == null:
			return "name %s has a letter Steam does not take" % String(n)
		if seen.has(n):
			return "name %s twice" % String(n)
		seen[n] = true
	return ""


func _test_names() -> void:
	var cfg: Dictionary = ss.load_config()
	_check(not cfg.is_empty(), "res://data/steam.json does not read")
	_check(cfg.has("app_id") and cfg.has("prefix"), "steam.json without app_id/prefix: %s" % str(cfg.keys()))
	var traces := _traces()
	var all: Array = ss.all_api_names()
	_check(traces.size() >= 1 and all.size() == traces.size() - cfg.get("skip", []).size(),
		"%d traces, %d Steam names" % [traces.size(), all.size()])
	var names: Array = []
	for e in all:
		names.append(e["api"])
	var why := _valid_names(names)
	_check(why == "", why)
	# the same list as the document the Director's Steamworks page is filled from
	var doc := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../Docs/STEAM_ACHIEVEMENTS.md"))
	if doc != "":
		for e in all:
			_check(doc.contains("`%s`" % String(e["api"])), "Docs/STEAM_ACHIEVEMENTS.md has no row for %s" % String(e["api"]))
	# skip and names are obeyed
	var keep: Dictionary = ss.cfg
	ss.cfg = {"prefix": "ACH_", "skip": ["mitten"], "names": {"board": "BLACKBOARD_REPLY"}}
	_check(ss.api_name({"id": "mitten"}) == "", "skip not obeyed")
	_check(ss.api_name({"id": "board"}) == "BLACKBOARD_REPLY", "names not obeyed")
	_check(ss.api_name({"id": "q01"}) == "ACH_Q01", "prefix + upper not used: %s" % ss.api_name({"id": "q01"}))
	ss.cfg = keep
	# self-check: the rule catches a bad name and a twin
	_check(_valid_names(["ACH_OK", "ACH bad"]) != "" and _valid_names(["ACH_a"]) != "" and _valid_names(["A", "A"]) != "",
		"self-check: a bad or doubled name passed")


# --- S16-4 ---------------------------------------------------------------------------------------

func _test_license() -> void:
	var libs: Array = LicensesText.libraries()
	var gsl: Dictionary = {}
	for l in libs:
		if String(l.get("id", "")) == "godotsteam":
			gsl = l
	_check(not gsl.is_empty(), "licenses.json has no GodotSteam entry")
	_check(String(gsl.get("license", "")) == "MIT", "GodotSteam's license is not MIT: %s" % String(gsl.get("license", "")))
	_check(String(gsl.get("text", "")).contains("Permission is hereby granted"), "GodotSteam's license text is not the MIT text")
	var text: String = LicensesText.build({"libs": "Библиотеки игры"}, LicensesText.fonts(), libs)
	_check(text.contains("══ Библиотеки игры ══") and text.contains("GodotSteam — MIT"), "the screen's text has no libraries section")
	_check(not LicensesText.build({}, LicensesText.fonts()).contains("GodotSteam"), "self-check: without the list the section is still there")
	var ext := "res://addons/godotsteam/godotsteam.gdextension"
	_check(FileAccess.file_exists(ext), "no %s" % ext)
	var cf := ConfigFile.new()
	if cf.load(ext) == OK:
		for key in ["windows.release.x86_64", "windows.debug.x86_64"]:
			var p := String(cf.get_value("libraries", key, ""))
			_check(p != "" and FileAccess.file_exists(p), "the Windows library %s (%s) is not in the project" % [key, p])
		var deps_ok := false
		for key in cf.get_section_keys("dependencies") if cf.has_section("dependencies") else []:
			if String(key).begins_with("windows") and str(cf.get_value("dependencies", key)).contains("steam_api64.dll"):
				deps_ok = true
		_check(deps_ok or FileAccess.file_exists("res://addons/godotsteam/win64/steam_api64.dll"), "steam_api64.dll is not shipped with the Windows library")


# --- S16-5 ---------------------------------------------------------------------------------------

func _test_extension_api() -> void:
	if not Engine.has_singleton("Steam"):
		# the Linux library is in the project too; when it does not load here, say so (CI and the agent run Linux)
		_check(not FileAccess.file_exists("res://addons/godotsteam/linux64/libsteam_api.so"),
			"the Linux library is in the project but the Steam singleton is absent")
		print("        (no Steam singleton here — S16-5 checks nothing more)")
		return
	var steam: Object = Engine.get_singleton("Steam")
	var cls := steam.get_class()
	var want := {"steamInitEx": 2, "run_callbacks": 0, "setAchievement": 1, "storeStats": 0, "getAppID": 0,
		"isOverlayEnabled": 0, "steamShutdown": 0}
	var have := {}
	for m in ClassDB.class_get_method_list(cls, true):
		have[String(m["name"])] = m
	for name in want:
		if not have.has(name):
			_fails.append("Steam has no %s" % name)
			continue
		var m: Dictionary = have[name]
		var nargs: int = m["args"].size()
		var ndef: int = m.get("default_args", []).size()
		_check(nargs >= want[name] and nargs - ndef <= (0 if name == "steamInitEx" else want[name]),
			"Steam.%s takes %d args (%d defaulted), SteamService passes %d" % [name, nargs, ndef, want[name]])
	var init: Dictionary = have.get("steamInitEx", {})
	if not init.is_empty():
		var a: Array = init["args"]
		_check(a.size() >= 2 and int(a[0]["type"]) == TYPE_INT and int(a[1]["type"]) == TYPE_BOOL,
			"steamInitEx is not (app_id: int, embed_callbacks: bool): %s" % str(a))
