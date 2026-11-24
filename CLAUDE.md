# Notes for Claude

## Models

Every model is built in code, and every new model or added detail must
follow the drawing-cost rules in `docs/models.md`: cache built meshes,
one surface per shared material, `MeshKit.commit_indexed`,
`ModelLod.finish_kits` for automatic LODs, interiors and small parts in the
near-only detail mesh, near and far wheels, cheap flat quads for repeated
features. After changing a model, run

    godot --headless --path . --script res://tools/model_budget.gd

and keep it within budget (it fails the build otherwise). Check how it
looks with `tools/car_studio.gd` (vehicles) or `tools/cargo_studio.gd`
(loads).

## The town

Everything placed in the world (buildings, props, trees, signs, placed
objects, textures) follows the art and drawing-cost rules in
`docs/world_art.md`: geometry only where it shows (close-up detail in the
facade mesh, repeated surface detail in shaders and texture arrays),
`ModelLod.finish_kits` (or `ModelLod.finish` at load time) on every mesh built once and drawn many times, shared
materials from `Materials.get_shared()` (never `StandardMaterial3D.new()`
in a prop or per chunk), repeats through `TiledMulti.add`, a draw distance
from size (`WorldLod.limit`), shadow stand-ins for detailed repeats, and
3D textures imported VRAM-compressed with mipmaps. After changing anything
in the world, run

    godot --headless --path . --script res://tools/world_budget.gd

and keep it within budget (it fails the build otherwise; `-- --verbose`
names what's costing what).

## Godot

A new `class_name` script needs `godot --headless --path . --import`
before headless tools can see it.
