class_name JobPanel
extends PanelContainer
## The job under way (Jobs), top right under the money: who it's for, what
## it is, the stop you're heading to and what to do there, the clock
## against the estimate, the cargo's state (a job with `cargo`: "Food 87%")
## and what it pays if you finish now.

var _company: Label
var _title: Label
var _stop: Label
var _hint: Label
var _clock: Label
var _cargo: Label
var _pay: Label
var _timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.ACCENT))
	custom_minimum_size.x = 300
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	add_child(col)
	_company = HudStyle.label(14, true, HudStyle.ACCENT, false)
	col.add_child(_company)
	_title = HudStyle.label(18, false, Color.WHITE, false)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = 280
	col.add_child(_title)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.1)
	line.custom_minimum_size.y = 1
	col.add_child(line)
	_stop = HudStyle.label(20, true, Color.WHITE, false)
	col.add_child(_stop)
	_hint = HudStyle.label(15, false, HudStyle.DIM, false)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 280
	col.add_child(_hint)
	var foot := HBoxContainer.new()
	col.add_child(foot)
	_clock = HudStyle.label(16, true, HudStyle.DIM, false)
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_clock)
	_cargo = HudStyle.label(16, true, HudStyle.DIM, false)
	_cargo.custom_minimum_size.x = 96
	foot.add_child(_cargo)
	_pay = HudStyle.label(18, true, HudStyle.GOOD, false)
	foot.add_child(_pay)
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	position += Vector2(-24, 96)


func _process(delta: float) -> void:
	var jobs := Jobs.find(get_tree())
	visible = jobs != null and not jobs.active.is_empty()
	if not visible:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	var job := jobs.active
	_company.text = str(job.get("company", job.get("kind", "Job"))).to_upper()
	_title.text = str(job.get("title", ""))
	var s := jobs.stop()
	var n := (job["stops"] as Array).size()
	_stop.text = "%s  (%d of %d)" % [str(s.get("name", "")), jobs.index + 1, n] if n > 1 else str(s.get("name", ""))
	var parts: Array[String] = []
	if str(s.get("address", "")) != "":
		parts.append(str(s["address"]))
	if str(s.get("hint", "")) != "":
		parts.append(str(s["hint"]))
	_hint.text = "  ·  ".join(parts)
	_hint.visible = not parts.is_empty()
	var t := jobs.elapsed()
	var est := float(job.get("estimate", 300.0))
	_clock.text = "%d:%02d / %d:%02d" % [int(t) / 60, int(t) % 60, int(est) / 60, int(est) % 60]
	_clock.add_theme_color_override("font_color", HudStyle.WARN if t > est else HudStyle.DIM)
	var state: Variant = job.get("cargo_state")
	_cargo.visible = str(job.get("cargo", "")) != "" and state is Callable and (state as Callable).is_valid()
	if _cargo.visible:
		var c := clampf(float((state as Callable).call(job)), 0.0, 1.0)
		_cargo.text = "%s %d%%" % [str(job["cargo"]), roundi(c * 100.0)]
		_cargo.add_theme_color_override("font_color", HudStyle.GOOD if c > 0.85 else (HudStyle.DIM if c > 0.5 else HudStyle.WARN))
	_pay.text = CarModels.dollars(int(jobs.pay_now().get("pay", 0)))
	# Out of the wanted level's way: the money's top right, this under it.
	size = Vector2.ZERO
	position.x = get_viewport_rect().size.x - get_combined_minimum_size().x - 24.0
