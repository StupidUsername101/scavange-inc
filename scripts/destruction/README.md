# Universal destruction vertical slice

The runtime is opt-in. Existing structures, props, characters, and collision are unchanged. Add a
`DestructibleVolume3D` only to a closed finite piece that is allowed to change, give it a stable
`volume_id`, and author `volume_size`, `voxel_size`, `brick_cells`, and a physical surface or custom
`DestructionTextureDefinition`.

## Ownership

- The server applies a canonical `DamageEvent` and owns field revision, collision, penetration,
  support (later phase), and material damage.
- Clients replay the same quantized event into matching visual-only volumes. A bake-hash, revision,
  or checksum mismatch requests a changed-brick checkpoint.
- The field is analytic until first edit. Only touched bricks allocate signed 16-bit distance data;
  sub-threshold fatigue allocates its byte channel only when used.
- Chunk sampling is snapshotted on the main thread. Dual Contouring runs through
  `WorkerThreadPool`; only `ArrayMesh` and static concave collision commits run on the main thread,
  under the per-frame commit budget.
- Immediate projectile checks query the SDF and reject stale Jolt triangles while a replacement
  chunk is pending.
- Small edits invalidate only intersecting acoustic caches. Newly opened projected cells are
  deduplicated; probe topology rebuild is reserved for the authored aperture threshold.

## Persistence and rollback

`DestructionCheckpointStore` stores only changed bricks, revisions, profile/bake compatibility, and
deduplicated acoustic aperture cells in a compressed SHA-256-checked file. Server helpers are
`create_destruction_snapshot`, `save_destruction_snapshot`, and `load_destruction_snapshot`.

The implementation is isolated on branch `codex/universal-sdf-destruction`. Revert its commits or
remove the two `DestructionFieldTest` scene instances to return to the immutable world path.

## Tests

```bash
godot --headless --path . --script res://tests/universal_destruction_system_test.gd
godot --headless --path . --script res://tests/destruction_runtime_integration_test.gd
godot --headless --path . --script res://tests/ballistics_system_test.gd
godot --headless --path . --script res://tests/acoustic_propagation_test.gd
```

`DestructibleVolume3D.debug_state()` exposes revision/checksum, sparse bytes, event time, worker
build time, queue depth/age, stale jobs, and generated render/collision counts. The GDScript event
mutation still exceeds the final sub-2-ms target in the headless stress impact; that fact is exposed,
not hidden. Do not batch-convert map structures until host/client playtesting and profiling justify
the Phase-2 authoring rollout or a focused native mutation backend.
