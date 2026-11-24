# Building it: single-player paint, wanted level and police

The plan is `docs/design.md` (sections 2, 3 and 7). This file is how the
first single-player slice is split up so the pieces can be built side by
side, and the interfaces between them. Everything here is single-player
(no networking), but written so the server can own it later: game
rules in plain nodes and data, not in the HUD or the camera.

## The pieces

| Piece | Owns | New code in |
|---|---|---|
| **A. Paint** | Firing the marker, paintballs in flight, hits, splats on the world, paint on cars and bodies, coverage and what it does to a car, hits and outs on people, wipers | `scripts/paint/` |
| **B. Autopilot** | A computer driver for any `Car`: follow a route on the street network, chase a target, box in, PIT | `scripts/ai/` |
| **C. Wanted** | Wanted levels, crimes, being seen, search circle, escape, the HUD for it, getting caught, Two Years Less a Day panels, fines, the car wash | `scripts/wanted/` |
| **D. Police** (after A–C) | The dispatcher, spawning police out of sight, roles, officers on foot, leaning out, paint strips, roadblocks, level 4 | `scripts/police/` |

## Interfaces

These are the seams. Each piece builds its side; stand-ins are fine
until the other side lands.

### Paint (A provides)
- `PaintShots` node (one, a child of Main, in group `"paint_shots"`):
  - `fire(origin: Vector3, dir: Vector3, shooter: Node, weapon: Dictionary) -> void`
    (weapon: speed, spread, hit value, colour, splash radius; the
    Islander's numbers are in design.md section 2).
  - `signal hit(info: Dictionary)` with `target` (the Node hit, or
    null for the world), `point`, `normal`, `shooter`, `value`,
    `colour`, `kind` ("car", "person", "world").
- Anything that can be painted out implements
  `take_paint_hit(value: int, shooter: Node, point: Vector3) -> void`
  and has `is_out() -> bool` and `signal went_out(by: Node)`.
  The player does; officers (D) will.
- `PaintCoverage` (a child node of each `Car`, made on demand):
  `coverage: float` (0–1), `add_hit(local_point, colour, size, police: bool)`,
  `clear()` (car wash), `signal changed(coverage)`. Police hits apply
  the coverage table in design.md section 7 to the car
  (`Car.power_factor`, `Car.stalled`); player hits only paint.

- `PassengerSeat` (`scripts/paint/passenger_seat.gd`), for officers who
  lean out and paint you (design.md section 7, level 3): the front
  passenger seat of any `Car`, made on demand with `PassengerSeat.of(car)`.
  It does the lean, the pose (`HumanoidModel.seated_lean`, up on the
  window sill and turned to the aim) and the fire rules (0.5x the fire
  rate, twice the spread and wider with speed, only out of the window,
  never across the roof). An officer node with a `HumanoidModel` and a
  `PaintMarker` (whose `shooter` is the officer) uses it like this:
  `seat.sit(officer, model, marker)`, then every physics step set
  `seat.wants_lean`, `seat.aim_at` (a world point) and `seat.trigger`
  (`seat.ready_to_fire()` says a shot would go now); `seat.leave()` and
  reparent the officer to get out. The driver's seat never shoots.
  `tools/loadout_check.gd` drives one this way.
- Weapons owned: `GameState.owned_weapons`, `owns_weapon(id)`,
  `unlock_weapon(id)` (saved). The weapon wheel (hold Tab / RB) switches
  among them; until there's a shop, F7 in the game owns them all and
  fills every hopper and jar (a debug key).

### Autopilot (B provides)
- `Car` gets a seam for a computer driver: `var ai_controls: Object`
  (null = player or parked). When set, `_read_controls` takes throttle,
  brake, steer and handbrake from it instead of Input.
- `CarAutopilot` (a Node, child of the car):
  `drive_to(point: Vector3)`, `follow(target: Node3D)` (chase),
  `box_in(target: Car)`, `pit(target: Car)`, `stop()`,
  `cruise_speed_kmh`, `signal arrived`. Routes from `RoadNetwork.route`.

### Wanted (C provides)
- `Wanted` autoload:
  - `level: int` (0–4), `signal level_changed(level)`,
  - `report_crime(kind: String, at: Vector3)` (kinds: "paint_bystander",
    "paint_car", "paint_police", "paint_fip", "flee", "car_meet",
    "take_car": a traffic car taken from its driver),
  - `police_saw_player(at: Vector3)` (D calls it while any officer can
    see the player), `last_known_position`, `search_radius`,
  - `caught()` (D calls it: plays the jail panels, fines, clears),
  - `signal crackdown_changed(on)` (single player: unused for now).
- The minimap (`scripts/ui/minimap.gd`, on the HUD, bottom left):
  `Minimap.find(get_tree())`, then `track(unit, "police")` (or `"fip"`)
  for each police vehicle or officer on the map (dropped when the node
  goes), `set_marker(id, kind, at)` / `remove_marker(id)` for fixed
  places (`"car_wash"` and `"police_station"` are already on it, shown on
  the rim when off the map). WantedHud keeps the search circle on it
  (`set_search_circle`, `clear_search_circle`) and the rim goes red while
  wanted. `tools/minimap_check.gd` checks it.
- The car wash: a placed spot that clears coverage and, if no officer
  saw you go in, the wanted level. C asks D "was the player seen in the
  last moment" through `Wanted.seen_recently()`.

## Rules for every piece
- `CLAUDE.md`, `docs/models.md` and `docs/world_art.md` apply: cached
  meshes, shared materials, `ModelLod.finish_kits`, budgets.
  `tools/model_budget.gd` and `tools/world_budget.gd` must pass.
- New `class_name` scripts need `godot --headless --path . --import`.
- Each piece has a headless check in `tools/` that exercises it and
  exits non-zero on failure.
- Numbers come from design.md and are `@export`ed or constants with a
  comment, ready to tune.
