# Asset collision workflow

For an editable Blender/glTF source, prefer Godot's built-in import suffixes: use simplified
collision-only objects named with `-colonly` for static concave level geometry or `-convcolonly`
for a small convex prop. Primitive boxes remain the best choice for modular walls and floors.

For third-party GLBs that should stay untouched:

1. Copy one canonical runtime GLB beneath `assets/third_party/pizza_doggy/models/`.
2. Add an explicit entry to `asset_collision_manifest.json`. Use `convex` only for a genuinely
   convex prop/module. A whole hollow bunker must not be convex-baked because that seals its rooms.
3. Bake everything, or only the new stable manifest IDs:

   ```bash
   godot --headless --path . --script res://tools/generate_asset_collisions.gd
   godot --headless --path . --script res://tools/generate_asset_collisions.gd -- prop_generator
   ```

4. Reference the saved `Shape3D` resource from the authoritative structure script. Repeated
   unscaled placements share the resource without rebuilding a hull.

Modular structure collision should pass box descriptors to
`StaticStructureCollisionBuilder`. It merges only exact adjacent rectangular unions, preserves
openings/material boundaries, and emits one identity-transformed shape per `StaticBody3D`. The
custom server spatial hash is intentionally not involved: it is the interest index for moving
gameplay entities, while Godot Physics owns the static broad phase.

## Repeated modular structures

For a straight run of repeated art—tunnels are the first supported profile—create its baked
definition in one command:

```bash
godot --headless --path . --script res://tools/create_modular_structure_definition.gd -- \
  res://path/to/module.glb \
  res://resources/world/structures/my_tunnel.tres \
  8 arched_tunnel --scale=1.3,1.3,1.0
```

The command reuses the level editor's GLB loader and transformed-bounds calculation. The saved
definition contains the measured source bounds, optional non-uniform module scale, and cheap
collision-profile parameters, not the render scene itself, so a dedicated server can assemble and
cluster collision without loading mesh data. `ModularStructureAssembler` then produces both the
client module transforms and the matching server shell. Tune the generated shell thickness/profile
values only when the asset's interior requires it. Pass `--force` explicitly to replace an existing
definition.

Acoustic probes are intentionally not part of these resources. A later map-analysis bake should
derive their placement and influence volumes from the completed level geometry.
