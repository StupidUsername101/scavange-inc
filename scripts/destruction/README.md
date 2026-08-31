# Universal destruction vertical slice

The runtime is opt-in. Existing structures, props, characters, and collision are unchanged. Add a
`DestructibleVolume3D` only to a closed finite piece that is allowed to change, give it a stable
`volume_id`, and author `volume_size`, `voxel_size`, `brick_cells`, and a physical surface or custom
`DestructionTextureDefinition`.

## Ownership

- The server applies a canonical `DamageEvent` and owns field revision, collision, penetration,
  structural support, detached rigid bodies, and material damage.
- Clients replay the same quantized event into matching visual-only volumes. A bake-hash, revision,
  or checksum mismatch requests a changed-brick checkpoint.
- Destruction events and checkpoints use the same reliable RPC channel and render through
  `call_local`, so the listen host and remote peers run the identical proxy path. Client revisions
  are monotonic: covered events and stale checkpoints are ignored, while a checksum disagreement
  requests authority recovery. Applying recovery discards old worker output and rebuilds visible
  topology from the checkpoint instead of only replacing field bytes.
- The field is analytic until first edit. Only touched bricks allocate signed 16-bit distance data;
  sub-threshold fatigue allocates its byte channel only when used.
- Chunk sampling is captured from the per-volume native lattice when available (or the portable
  sparse field otherwise). Dual Contouring and analytic shell finalization run through
  `WorkerThreadPool`; only `ArrayMesh` and static concave collision commits run on the main thread,
  under the per-frame commit budget.
- Mutation owns fixed-capacity brush, chunk-stamp, and smooth-noise scratch buffers. Worker jobs,
  sample snapshots, contour lookup/output arrays, colors, and collision faces are pooled per volume.
  First-touch brick bytes and the stable result/replication packet are intentional persistent/API
  allocations; hot sample, brush, topology-compaction, and worker polling loops must not create
  Dictionaries or variable-length scratch arrays.
- When a matching `addons/scavange_sdf` GDExtension binary is present, packed-brick boolean
  mutation, native-lattice chunk capture, localized structural component mapping, and dual-contour
  topology with stable surface-net feature points run in a per-volume/per-worker C++ kernel with
  persistent standard-library scratch. The boundary is the same packed snapshot/checkpoint
  contract; source-only checkouts and unsupported platforms resolve through `ClassDB` and retain
  the byte-identical GDScript implementation rather than failing project load.
- Continuous cuts reuse native fragment-tile capture buffers and a stamped dense-field erasure
  scratchpad. Detaching a component updates only its touched sparse bricks instead of hashing
  `Vector3i` samples in GDScript and resynchronizing the complete finite volume. Runtime chunk
  publication updates existing ArrayMesh, collision-face, and Jolt shape objects in place; a body
  currently forwarding a synchronous damage call is the sole physics-safe replacement case.
  The server also retains one ray-query object and exclusion buffer per cutter owner; aiming every
  physics tick no longer allocates query state between the lower-frequency SDF mutation pulses.
- Material warp is deterministic, spatially smooth value noise. Contour quads maximize their worst
  triangle quality and every surviving triangle is wound from the sampled SDF normal. The first
  edit stages one globally-owned contour before atomically replacing the analytic boxes; extracted
  vertices are never pushed onto chunk seams afterward. Increasing a material's destructiveness
  must not create disconnected sheets or back-face holes.
- Analytic shell intersections carry exact box-face constraints through contour extraction. Shell
  coordinates snap to authored planes and split per face for hard normals, while impact cavities
  keep smooth normals. Remeshing beside damage therefore cannot round or darken a straight retained
  wall corner.
- Immediate projectile checks query the SDF and reject stale Jolt triangles while a replacement
  chunk is pending.
- Nearby damage bounds are merged into sparse structural regions. After each geometry edit, every
  cell containing a negative SDF sample enters a six-neighbour, shared-face graph, so zero-area
  edge/corner contact cannot preserve detached splinters. Connectivity is not support by itself:
  a one-cell morphological core partitions thick matter into regions, and the original cells
  between those regions become bonds whose capacity is their shared voxel-face area. Required bond
  area grows with `cell_count^(2/3)` and is scaled by the destruction texture's support strength,
  fracture toughness, and ductility. A hidden one/two-edge ligament can therefore no longer carry
  an arbitrarily large slab, while a broad bridge and a genuinely strong material remain valid.
  Matter reaching an interior scan edge is provisionally supported. If a weak neck or multiple
  face-disconnected regions make that local answer ambiguous, the native path reruns once against
  the complete finite volume (within the hard structural-cell budget) instead of treating both scan
  exits as anchors. `DestructibleVolume3D.structural_anchor_faces` authors real attachment in local
  space; standing volumes default to the negative-Y/ground face, while ceiling- and side-mounted
  pieces can select their actual faces. Support always outranks component size, so a larger upper
  slab cannot remain floating after it is severed from a smaller grounded base. The largest-region
  fallback is used only when a full-volume graph has no authored attachment. Detached components
  are removed from the wall field. Wide, thin regions are extracted through bounded cubic tiles
  and merged into one rigid descriptor, so their longest axis cannot silently exceed a meshing
  cutoff or force a mostly-empty cubic allocation. Removal is transactional for physical debris:
  if a qualifying fragment cannot produce valid geometry, its cells remain for a later structural
  retry instead of disappearing.
  Components above the material's physical-volume threshold are
  reconstructed as centred indexed meshes with convex Jolt collision; smaller/excess pieces
  become dust rather than leaving duplicate floating wall triangles. The server synchronously
  crosses the existing chunk-rebuild barrier only when a body detaches, then publishes reliable
  geometry/material manifests and unreliable authoritative rigid-state snapshots. Listen hosts,
  remote clients, and late joiners therefore see the same removed SDF matter and moving debris.
  A hit collision adapter can therefore rebuild its own chunk before its damage call returns;
  generated bodies leave volume ownership immediately but disable and free through SceneTree's
  deferred physics-safe path instead of attempting a re-entrant `Object.free()`.
  A physical fragment also retains a tightly cropped, fully populated copy of its component SDF.
  It therefore implements the same `apply_damage_event` and stale-collider rejection contract as
  the source volume. Further bullets or cutter strokes mutate that field, replace the fragment's
  convex presentation/collision, retain the largest connected remainder in the current body, and
  recursively spawn every qualifying separated component with inherited linear/angular velocity.
  Remeshing is deferred and coalesced per frame so continuous cutting never rebuilds one fragment
  more than once per rendered frame. Remote peers receive reliable replacement geometry/removal
  packets while ordinary rigid motion stays on its existing unreliable stream; late join manifests
  always contain the latest recursively cut geometry. Fragment fields materialize their positive
  padding bricks once, preventing either native or portable mutation from falling back to an
  analytic box and resurrecting matter outside the extracted island.
  Density, per-event body cap, minimum physical volume, and lifetime live in the destruction
  texture. Debris is transient; the removed wall state remains checkpointed.
- Small edits invalidate only intersecting acoustic caches. Newly opened projected cells are
  deduplicated; probe topology rebuild is reserved for the authored aperture threshold.
- Geometry events tagged with both `blade` and `heat` (and never `ballistic`) add bounded local
  thermal imprints to a transient second material pass. The cut walls cool from white-yellow to a
  dim red glow, then detach the pass completely; ordinary gun damage has no thermal shader or extra
  draw cost. Live replication, checkpoints, and detached-fragment manifests preserve remaining heat.
- Animated humanoids reuse canonical `DamageEvent`, `SparseSdfVolumeData`, destruction textures, and
  `SdfDualContouringMesher` through compact anatomical fields rather than inventing actor-only wound
  geometry. Server snapshots carry exact part-local SDF edits alongside bounded shell apertures and
  limb availability. Clients replay those edits byte-identically, aperture-clip only the imported
  skinned shell, and extract the newly exposed tissue faces through `SdfInteriorSurfaceBuilder`.
  Primitive cavity meshes and their discard shader are forbidden: they previously recreated the same
  detached flaps and red-ball artifacts already removed from wall destruction. A destruction texture
  may keep a flat interior color or blend from `interior_color` to `deep_interior_color` over
  `interior_color_depth` without changing topology.

## Persistence and rollback

`DestructionCheckpointStore` stores only changed bricks, revisions, profile/bake compatibility, and
deduplicated acoustic aperture cells in a compressed SHA-256-checked file. Server helpers are
`create_destruction_snapshot`, `save_destruction_snapshot`, and `load_destruction_snapshot`.

The implementation is isolated on branch `codex/universal-sdf-destruction`. Revert its commits or
remove the two `DestructionFieldTest` scene instances to return to the immutable world path.

## Tests

```bash
godot --headless --path . --script res://tests/universal_destruction_system_test.gd
godot --headless --path . --script res://tests/destruction_artifact_pipeline_test.gd
godot --headless --path . --script res://tests/destruction_runtime_integration_test.gd
godot --headless --path . --script res://tests/destruction_fragmentation_test.gd
godot --headless --path . --script res://tests/ballistics_system_test.gd
godot --headless --path . --script res://tests/flute_runner_system_test.gd
godot --headless --path . --script res://tests/acoustic_propagation_test.gd
godot --headless --path . --script res://tests/sdf_native_backend_test.gd
godot --headless --path . --script res://tests/sdf_performance_benchmark.gd
```

`DestructibleVolume3D.debug_state()` exposes revision/checksum, sparse bytes, event time, worker
build time, queue depth/age, stale jobs, and generated render/collision counts.
`sdf_performance_benchmark.gd` reports cold/warm native mutation, snapshot capture, reference/native
meshing, and pooled capture+mesh separately and fails if fixed scratch starts growing per impact.

`tests/helpers/destruction_impact_audit.gd` is the black-box geometric oracle. Given any pristine
Godot `Mesh`, its matching `DestructibleVolume3D`, and world-space gun rays, it fires real damage
events and reports field/ArrayMesh modification, impact centroid, forward/backward extent,
direction/yaw/pitch error, opened-ray continuity, deformation locality, and neighboring intact
surface. `destruction_mesh_deformation_test.gd` exercises several impacts, rotated targets, generic
`ArrayMesh` input, a deliberately wrong-yaw control, and a subthreshold no-deformation control.
On the initial Linux debug benchmark, median mutation is about 0.9 ms and native contour extraction
about 0.08 ms versus about 5.8 ms in the reference implementation. Timings remain diagnostic rather
than hardware-dependent assertions. Build reproducibility is pinned by
`native/sdf_backend/godot-cpp.commit`; Linux and Windows compile in the native-backend workflow.
