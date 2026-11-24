# Notes for Claude

## Models

Every model is built in code, and every new model or added detail must
follow the drawing-cost rules in `docs/models.md`: cache built meshes,
one surface per shared material, `MeshKit.commit_indexed`,
`ModelLod.finish` for automatic LODs, interiors and small parts in the
near-only detail mesh, near and far wheels, cheap flat quads for repeated
features. After changing a model, run

    godot --headless --path . --script res://tools/model_budget.gd

and keep it within budget (it fails the build otherwise). Check how it
looks with `tools/car_studio.gd` (vehicles) or `tools/cargo_studio.gd`
(loads).

## Godot

A new `class_name` script needs `godot --headless --path . --import`
before headless tools can see it.
