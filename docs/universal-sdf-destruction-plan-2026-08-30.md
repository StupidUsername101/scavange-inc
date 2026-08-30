# Universal SDF Destruction Plan

Date: 2026-08-30
Status: Phase-1 reversible vertical slice implemented on `codex/universal-sdf-destruction`

## Implemented vertical slice

The current branch implements the shared contract and the isolated-wall gate without converting any
existing authored structure:

- deterministic, millimetre-quantized `DamageEvent` packets and material-specific destruction
  texture resources;
- copy-on-first-edit narrow-band bricks with signed 16-bit distance storage and a bounded optional
  fatigue channel;
- concrete/metal/wood/stone/soil profiles whose geometry operations differ, including brittle
  cracks, metal dents, penetration channels, and exit spall;
- uniform-grid Dual Contouring with bounded QEF vertices, per-chunk render/collision replacement,
  exterior/interior vertex color, and a one-ring seam policy;
- authoritative projectile routing, stale-collider rejection against the immediate SDF, reliable
  event replay, late-join/reconnect checkpoints, compressed integrity-checked save/load, and
  revision/checksum recovery;
- one broad-phase record spanning all spatial-hash cells of a volume, local acoustic cache
  invalidation, and an authored aperture threshold before topology rebuild;
- opt-in concrete and metal walls in a separate field-test area, plus mathematical and live runtime
  tests. Event/remesh time, queue depth, memory, and revision counters are exposed by `debug_state()`.

This does not silently claim the later rollout phases are finished. Imported-mesh baking, support
islands/debris, editor authoring, and the bone-local wound presenter remain Phase 2/3 work. Existing
structures, props, characters, ragdolls, and their collision path are intentionally untouched until
the isolated host/client field test has been played and accepted.

## Executive decision

Build one universal **damage and destruction contract**, backed by several purpose-built
geometry implementations:

1. **Static structure backend** — sparse, chunk-local signed-distance fields (SDFs), with
   remeshed visuals and static concave collision only for chunks that have changed.
2. **Movable prop/debris backend** — the same damage contract, but bounded convex collision and
   strict size/fragment budgets. Never turn arbitrary moving objects into dynamic concave meshes.
3. **Character wound backend** — the same impact events and material response resources, stored in
   bone-local space and rendered as wound cutouts/caps. Existing anatomical collision, limb health,
   missing-limb, and ragdoll systems remain authoritative.

This is universal at the part that should be universal—what happened, which material received it,
and how that material responds. It deliberately does **not** force a concrete bunker, a loose metal
radio, and an animated skinned torso through one unsuitable mesh/collision pipeline.

The runtime field must not cover the world. Destructible volumes are baked ahead of time into
immutable sparse bricks. A hit uses the existing authoritative spatial index to find nearby
destructible macro-chunks, copies only the touched bricks, edits only the brush AABB plus a one-sample
halo, and schedules only those chunks for regeneration.

## Why SDFs fit this game

SDF Boolean operations make local material removal robust: holes, tunnels, craters, severing cuts,
and unions do not require fragile triangle-to-triangle Boolean surgery. An SDF also gives a useful
gradient for surface normals and a signed inside/outside test for projectile and acoustic queries.

The zero surface is still converted into normal meshes. Godot and Jolt should render and collide
against polygons; raymarching the visible world or trying to create a custom SDF physics shape is
not the proposed design.

The important limitation is resolution. A 3 cm field cannot represent a clean 5 mm bullet hole.
The design therefore allows different resolution classes:

- structure shell: approximately 2–4 cm samples;
- thick terrain/large rock: approximately 4–8 cm samples;
- close character wounds: visual fields or analytic wound brushes at higher effective resolution;
- tiny ballistic marks below the geometry threshold: shader/decal damage only until they accumulate.

Those are initial experiment ranges, not constants to ship without measurement.

## Existing project seams

### Spatial broad phase

`scripts/server/server_spatial_hash_3d.gd` already maintains an authoritative 8 m entity hash and
invalidates query caches when cell membership changes. Extend it with static AABB coverage rather
than introducing another unrelated world index:

- `register_bounds(key, bounds, kind, id, metadata)` inserts one volume or macro-chunk key into every
  covered 8 m cell;
- `update_bounds` changes membership only when its covered cell set changes;
- destruction queries use kind `destructible` and then perform exact local-brick intersection;
- never insert individual voxels into this hash;
- movable destructibles may keep the current position-based registration if they fit one cell.

The spatial hash answers **which volumes might be involved**. Each volume's brick map answers
**which samples are involved**.

### Structure collision bake

`scripts/world/static_structure_collision_builder.gd` already merges adjacent boxes only when their
union remains an exact box and preserves physical/acoustic material boundaries. Keep that behavior
for immutable structures. For destructible structures, add a bake mode that prevents a cluster from
crossing a destruction macro-chunk boundary.

At runtime:

- untouched macro-chunks keep their current cheap primitive collision and original visual mesh;
- the first destructive edit swaps only the affected macro-chunk to an SDF-generated visual mesh
  and one static concave collision shape;
- neighboring chunks are not rebuilt unless the edit plus halo reaches them;
- if a changed chunk returns to its exact baked state in an editor/debug operation, it can revert to
  the original primitive.

This avoids converting the whole warehouse or bunker into thousands of collision shapes at startup.

### Projectiles and damage

`scripts/server/server_projectile.gd` already performs swept authoritative ray hits, applies damage,
impulse, surface-specific impact sound, and resolves the projectile. Replace the destructive seam,
not the projectile solver:

- construct a normalized `DamageEvent` at the hit;
- route it to a `DamageReceiver3D`/destruction service when the collider is destructible;
- retain `apply_damage(float)` as a compatibility adapter for current players, enemies, drones, and
  turrets during migration;
- compare the mutable SDF hit with the Jolt ray result, because the SDF state changes immediately
  while an asynchronously rebuilt collision mesh may be one or two frames behind.

The projectile definition eventually needs mass/caliber or an authored impact-energy value,
penetration shape, heat, and damage tags. Its current scalar `damage` and `impact_impulse` are not
enough to distinguish a slow heavy strike from a fast narrow bullet.

### Physical and acoustic materials

`scripts/audio/physical_surface.gd` currently gives concrete, metal, wood, stone, and soil one
semantic name used by footsteps and impact audio. Keep this stable. Add a registry mapping that name
to a resource-backed `DestructionTextureDefinition` and an acoustic material; do not turn the audio
helper into a giant gameplay-material class.

### Networking

`scripts/network/server_replication_service.gd` already has scheduled, lifecycle-aware snapshot
streams. Destruction should add an event/checkpoint stream, not a full mesh snapshot stream:

- server validates and applies damage;
- reliable ordered batches replicate compact, quantized edit operations;
- each destructible volume has a monotonically increasing revision;
- late join and recovery use compressed changed-brick checkpoints plus a bake hash;
- clients build visual meshes locally from the same baked base and deterministic operations;
- the server remains authoritative for collision, penetration, support, and damage;
- the listen host consumes the same presentation path as a remote client.

### Acoustics

`scripts/audio/server_acoustic_service.gd` currently exposes a global `request_rebuild()`. Universal
destruction requires `invalidate_aabb(changed_bounds, revision)`:

- invalidate cached direct paths intersecting the changed bounds;
- recompute only affected probe graph edges/portal connectivity;
- do not treat every bullet divot as a new acoustic portal;
- accumulate exposed area per boundary patch and change topology only after an authored aperture
  threshold is crossed;
- crossfade between acoustic revisions so a newly opened wall never causes a hard sound cut.

## Runtime data model

### `DamageEvent`

A value object, with finite/range validation at construction:

| Field | Purpose |
| --- | --- |
| `event_id`, `sequence` | Ordering, deduplication, deterministic replay |
| `source_kind`, `source_id` | Ownership, exclusions, analytics |
| `world_position`, `normal`, `direction` | Localize and orient the response |
| `brush_kind`, `radius`, `length` | Sphere, capsule, cone, crack sheet, or contact patch |
| `energy`, `impulse`, `penetration` | Separate removal, body response, and pass-through behavior |
| `heat` | Scorching, melting, ignition hooks |
| `damage_tags` | Bullet, blade, blunt, explosive, fire, acid, healing, etc. |
| `seed` | Cross-machine deterministic variation |
| `timestamp_tick` | Coalescing and replay window |

Inputs are quantized before replication. The deterministic seed is derived from volume ID, event
sequence, source ID, and the authored seed—not from per-client random state.

### `DestructionTextureDefinition`

“Texture” is the player-facing concept: it describes the spatial character of damage, not just a
color texture. Implement it as a `Resource` with curves and bounded ranges. Curves used by replicated
geometry should be baked to small lookup tables so results are reproducible.

#### Resistance

- density / energy absorption;
- surface hardness;
- fracture toughness;
- ductility/plasticity;
- penetration threshold and residual-energy loss;
- damage accumulation threshold and optional recovery;
- minimum surviving thickness/ligament;
- heat-softening and melt threshold.

#### Shape

- entry crater radius/depth;
- penetration-channel radius and taper;
- exit-spall cone angle and depth;
- dent radius/depth before perforation;
- brittle crack count, branching, length, and width;
- anisotropy/grain direction and strength;
- deterministic multi-octave spatial warp amplitude/frequency;
- minimum geometric feature size.

#### Fragmentation

- support role and detachment threshold;
- fragment size range;
- maximum physical fragment count per event/volume/world;
- convex simplification error;
- cosmetic chip/dust count and lifetime;
- mass/drag/restitution ranges.

#### Presentation and integration

- exterior and exposed-interior material palette;
- triplanar scale/roughness/metallic/scorch/blood parameters;
- fracture/impact sound family;
- acoustic transmission and topology aperture threshold;
- decal-only threshold below which no volume edit occurs;
- wound bleeding/healing/cauterization hooks.

Suggested first profiles:

| Material | Response |
| --- | --- |
| Concrete | Hard surface, rough shallow entry crater, brittle cracks, strong back-face spall, chunky detachment |
| Metal | High perforation threshold, damage accumulation, broad dent before removal, narrow torn opening, few fragments |
| Wood | Grain-aligned cracks, long splinters, moderate penetration, anisotropic toughness |
| Stone | Brittle chips/cracks with less concrete-style spall and little plastic response |
| Soil | Smooth excavation/compaction, no sharp fracture graph or rigid shard storm |
| Flesh | Soft wound channel, tearing/bleeding, bone-local visual field, anatomical collision retained |

Material differences must change the operation, not merely select a particle color. For example, a
low-energy event on metal may add plastic damage and a dent without changing the solid sign, while
the same event on concrete may remove a crater and seed cracks.

### `DestructibleVolume3D`

Owns immutable bake identity plus mutable chunk state:

- stable volume ID and bake-content hash;
- local transform and local bounds;
- destruction texture/material palette;
- brick size, voxel scale, narrow-band width;
- immutable base-brick provider;
- copy-on-write changed-brick map;
- macro-chunk revision table;
- dirty queues for render, collision, acoustics, support, save, and replication;
- hard budgets and feature flags.

Use a coarse optional damage/fatigue channel only for profiles that need accumulation. Do not pay for
it in every soil or rock brick.

## Sparse field representation

### Recommended first representation

Use fixed-size sparse narrow-band bricks, initially benchmarked at 16³ and 32³ samples:

- signed distance: quantized `int16`;
- material index: `uint8`;
- optional accumulated damage: `uint8` or `uint16`, allocated on first use;
- one-sample neighbor halo for watertight meshing and gradients;
- uniform inside/air bricks represented by a small constant record rather than an array;
- immutable base bricks shared by all clients and copied only when edited.

A raw 32³ brick costs 64 KiB for `int16` SDF plus 32 KiB for one material byte before halo and
optional channels. A 16³ brick costs 12 KiB for the same two channels. This is why allocation must be
surface- and edit-driven rather than global.

The field is clamped outside a narrow band. Exact distances far from the surface provide no useful
meshing information and make local edits nonlocal. Voxel Tools independently uses this same
clamping/quantization principle for editable smooth terrain.

### Boolean convention

Use negative values for solid and positive values for air:

```text
remove brush B from solid A:  phi' = max(phi_A, -phi_B)
add brush B to solid A:       phi' = min(phi_A,  phi_B)
```

Smooth min/max is a material response option for rounded dents, melted edges, flesh, or soil. It is
not the default for brittle cuts or industrial corners.

Repeated min/max edits preserve the zero surface but can corrupt true distance values away from it.
Run a bounded local re-distance pass after edits that exceed an error/gradient threshold. Fast
sweeping is linear in the number of samples processed; it should run only in the dirty narrow band,
never over the volume or map.

### Edit locality

For every accepted event:

1. Query the spatial hash for destructible volume/macro-chunk candidates.
2. Transform the event into each candidate's local space.
3. Compute the exact brush AABB expanded by narrow-band width and one halo sample.
4. Resolve material layers and energy at the first surface crossing.
5. Generate the material-specific operation list: dent, subtract, crack, heat, decal, fragments.
6. Copy and mutate only overlapping bricks.
7. Coalesce overlapping operations received in the same small tick window.
8. Increment revisions and queue dependent rebuilds.

No per-frame “destruction update” scans the world. No work occurs where no damage occurs.

## Surface extraction and visuals

Industrial structures need sharp edges. Benchmark two extractors in the spike:

- **Dual Contouring** with Hermite edge intersections, gradients, and a bounded/clamped QEF for sharp
  features;
- **Transvoxel/marching-cubes family** as a mature smooth, LOD-capable baseline.

Start with one resolution per neighboring macro-chunk. Transvoxel transition cells are only needed if
profiling proves that multi-resolution chunk LOD is necessary. They add seam and material complexity
that phase one does not need.

Watertight chunk rules:

- read a shared halo from neighbors;
- assign boundary vertex ownership deterministically;
- discard a job whose input revision is older than the current chunk revision;
- derive normals from the corrected field gradient;
- clamp Dual Contouring vertices to a safe cell region;
- select categorical material IDs from the surviving solid side rather than interpolating them;
- use local/world triplanar coordinates for newly exposed interiors, while preserving baked exterior
  material identity.

The ideal general asset bake partitions source visuals by macro-chunk and stores exterior material
provenance. An untouched chunk renders the original asset. Once edited, only that chunk swaps to the
generated surface plus its exposed-interior material. The first vertical slice can use a simple
triplanar concrete/metal test asset before solving arbitrary imported UV preservation.

## Collision and immediate hit correctness

Godot's current concave polygon collision is hollow and intended for static bodies. It is also its
slowest exact collision form, and collider acceleration-structure construction can cost more than
meshing. Therefore:

- one changed static macro-chunk becomes one `StaticBody3D` with one identity-transformed concave
  shape;
- never create dynamic concave debris;
- untouched structure chunks remain boxes/convex baked primitives;
- changed shapes are built with a strict main-thread time/commit budget;
- mesh and collision output are double-buffered and swapped atomically;
- fast projectiles continue using swept tests;
- current SDF state is queried for destructive projectile hits immediately, so stale Jolt collision
  during an async rebuild cannot re-block an already opened hole;
- movement collision may lag by a tightly bounded one or two physics frames in the initial version;
  if that is perceptible, prioritize chunks intersecting player swept AABBs.

Godot/Jolt do not expose a drop-in custom SDF collision shape. A custom physics-server GDExtension
would be a separate engine project and is not justified for the first implementation.

## Structural support and fragments

An SDF says where matter exists; it does not say whether a disconnected wall chunk should fall.
Treat support as a distinct bounded system:

- bake support anchors (ground/foundation/explicit author tags);
- build adjacency between solid macro-cells or coarse support nodes;
- after removal crosses a face/support threshold, run connectivity only for the dirty component plus
  its one-ring neighborhood;
- keep anchored components static;
- detach only components above an authored volume threshold;
- approximate physical fragments with a small number of convex hulls or preauthored debris pieces;
- turn tiny components into client-side cosmetic chips/dust;
- enforce per-event, per-volume, and world fragment budgets.

Full finite-element fracture is out of scope. Material toughness, anisotropic cracks, support loss,
and bounded connectivity are controllable enough for the desired game behavior without making every
bullet solve a stress tensor over a bunker.

## Character wounds and limb loss

Do not voxelize and remesh the entire live skinned character in the first system. That would require
reconstructing stable skin weights, UVs, expression meshes, equipment masks, first-person visibility,
ragdoll bindings, and multiplayer state after every hit.

Instead:

1. Resolve armor/equipment and anatomical hit region first.
2. Store a bounded list of analytic sphere/capsule/cut brushes in bind-pose or dominant-bone local
   space.
3. Render them through a smooth wound clip/opacity field on the skin and add a small generated
   interior cap/tissue patch.
4. Replicate the same compact `DamageEvent`/wound operation used by world destruction.
5. Keep current capsule/limb collision and scalar/segment health authoritative.
6. When a sever threshold is crossed, invoke the existing missing-limb/loadout/ragdoll path and use
   an authored/generated stump cap at the cut socket.
7. Merge nearby wound brushes and retire healed/covered wounds to maintain a fixed slot budget.

This gives bullets and blades one coherent material response language while letting wounds follow
animation and ragdoll bones. A later prototype can test per-body-part SDF remeshing, but it must beat
this simpler backend visually before becoming a dependency.

## Scheduling and allocation policy

### Server

- enqueue validated events in physics order;
- cap events, touched samples, dirty chunks, and support jobs per tick;
- mutate/re-distance/mesh pure data on `WorkerThreadPool` or a native worker pool;
- never access scene nodes from worker tasks;
- commit `ArrayMesh`, physics shapes, and node changes on the main thread;
- reuse brick, brush, QEF, vertex, index, and query buffers;
- use free lists/slab pools instead of allocating dictionaries and arrays per voxel or triangle;
- prioritize collision near players/projectiles, then visible meshes, then remote/save work;
- discard stale output by revision rather than blocking for it.

### Client

- receive edits/checkpoints, mutate the same sparse bricks, and build presentation meshes locally;
- prioritize chunks near the local camera;
- show an immediate cheap impact decal/particle while the authoritative geometry job completes;
- optionally predict a local geometry edit only after deterministic reconciliation is proven;
- never send generated meshes over RPC.

### GPU policy

Godot compute shaders are a possible later client visual accelerator, but not the authoritative first
backend. Reading generated geometry back to the CPU introduces synchronization and GPU stalls;
Godot's own documentation warns that immediate `RenderingDevice.sync()` calls stall the CPU. Server
collision and deterministic checkpoints need CPU-visible data anyway.

If CPU profiling later identifies surface extraction as the bottleneck, a GPU path may produce only
render meshes while the server retains coarse CPU collision. It must use asynchronous multi-frame
readback and bounded dispatch sizes.

## Networking and persistence protocol

### Edit batch

```text
volume_id
base_bake_hash
from_revision -> to_revision
operation_count
quantized operations [position, direction, dimensions, energy, material response id, seed]
affected macro-chunk coordinates
checksum
```

Rules:

- reject nonfinite, out-of-bounds, oversized, unauthorized, stale, or duplicate operations;
- reliable ordered delivery for accepted topology edits;
- batch adjacent operations without hiding their deterministic sequence;
- request a changed-brick checkpoint on revision gap/checksum mismatch;
- checkpoint only dirty bricks, compressed and chunked below safe RPC payload sizes;
- compact the edit log once a checkpoint is durable;
- save bake hash, profile version, volume revisions, and changed bricks—not the unchanged world;
- include schema migrations because material tuning changes must not silently reinterpret old saves.

## Phased implementation

### Phase 0 — Reversible technical spike

No game-scene hookup.

- Create a standalone slab benchmark with concrete and metal profiles.
- Bake a box and an imported closed mesh into sparse narrow-band bricks.
- Compare 16³/32³ bricks and 2/3/4/6 cm sampling.
- Compare a minimal Dual Contouring extractor against Voxel Tools/Transvoxel as a reference backend.
- Apply spheres, oriented capsules, spall cones, dents, repeated cuts, and adjacent-chunk cuts.
- Measure mutation, re-distance, extraction, main-thread mesh upload, collision build/commit, memory,
  triangle count, seam error, and repeated-edit drift.
- Run the spike behind `destruction/backend = disabled|prototype|voxel_tools_reference`.
- Do not modify current structure collision or projectile behavior yet.

Gate: choose the storage/extractor only after it meets the budgets below and survives 10,000
deterministic edit/replay operations without a checksum or watertightness failure.

### Phase 1 — Core contract and isolated wall

- Add `DamageEvent`, `DestructionTextureDefinition`, registry, `DestructibleVolume3D`, sparse brick
  store, deterministic brush math, local re-distance, job scheduler, and debug inspector.
- Integrate one concrete wall and one metal plate in a separate field-test area.
- Add server-authoritative projectile routing and immediate SDF ray correctness.
- Generate visual meshes; add collision only after visual/replay tests pass.
- Add edit replication, late-join checkpoint, disconnect/reconnect recovery, and save/load for those
  two volumes.
- Keep all existing structures immutable.

Gate: two-player host/client session produces the same revision/checksum and no hitch exceeds the
frame/physics budgets.

### Phase 2 — World structure integration

- Extend level-editor/structure bake metadata with destructible, indestructible, resolution class,
  material profile, support anchor, and allowed damage tags.
- Partition destructible collision/visual sources on macro boundaries while preserving current exact
  clustering for immutable pieces.
- Add local acoustic invalidation and aperture thresholds.
- Add support connectivity, bounded convex debris, dust/chip pooling, and local navigation/foot
  contact invalidation if navigation is introduced.
- Roll out material profiles one at a time: concrete, metal, wood, stone, soil.

Gate: warehouse/bunker/tunnel tests preserve current movement and acoustics when untouched, and
damage never triggers a full-world rebuild.

### Phase 3 — Props and characters

- Add coarse destructible rigid props with convex fragment limits.
- Add the bone-local character wound backend, armor masking, wound merging, replicated presentation,
  and existing limb-sever integration.
- Verify first-person/full-body/ragdoll/missing-limb/PBD combinations and remote presentation.
- Keep character collision anatomical rather than SDF-derived.

Gate: wounds remain attached through procedural animation and ragdoll; late join sees the same wound
state; no unbounded per-character wound allocation exists.

### Phase 4 — Optional optimizations only when measured

- Move brick mutation/re-distance/extraction into a focused C++ GDExtension if the GDScript spike
  proves too slow.
- Add multi-resolution chunks and Transvoxel transition cells only if distant changed geometry is a
  measured rendering/memory cost.
- Add client GPU surface extraction only if asynchronous readback/visual-only use is a clear win.
- Investigate true skinned SDF remeshing only after the bone-local wound backend has a demonstrated
  visual limitation worth its cost.

## Initial budgets and degradation rules

These are acceptance targets to validate on the real test scene, not promises derived from a toy
benchmark:

| Budget | Initial target | Degradation behavior |
| --- | ---: | --- |
| Server synchronous event validation/query | < 0.25 ms average, < 1 ms p95 | Queue lower-priority cosmetic damage |
| Worker mutation + local re-distance | < 2 ms per typical bullet edit | Split large explosions across bounded jobs |
| Worker surface extraction | < 4 ms per dirty macro-chunk | Lower remote priority, coalesce revisions |
| Main-thread render commit | < 0.5 ms per frame | Commit fewer chunks per frame |
| Main-thread collision commit | One bounded chunk/frame initially | Prioritize player/projectile swept bounds |
| Geometry response latency near player | <= 2 physics frames typical | Immediate decal plus authoritative SDF hit query |
| Physical fragments | Profile/world hard caps | Convert overflow to pooled cosmetic debris |
| Character wound slots | Fixed per body region/character | Merge nearest compatible wounds |
| Network topology events | Small reliable ordered batches | Send dirty-brick checkpoint on backlog/gap |

Every queue exposes counts, oldest age, discarded stale jobs, bytes, and timings in a debug panel.
There must be no silent quality collapse: when a budget is exceeded, counters explain exactly which
fallback occurred.

## Test plan

### Mathematical/unit tests

- analytic sphere/box/capsule SDF sign and distance;
- subtract/add identities and boundary cases;
- quantization error bounds;
- narrow-band re-distance gradient magnitude near the surface;
- deterministic fixed-input checksum across repeated runs;
- brush AABB touches only expected bricks and required halo;
- chunk seam has identical signs/vertices/normals on both sides;
- Dual Contouring QEF remains bounded and finite;
- material profile output stays within authored hard caps.

### Geometry/collision tests

- entry crater, through-hole, grazing hit, adjacent hits, thin wall, corner hit, and chunk-boundary hit;
- concrete spalls while equal-energy metal dents or narrowly perforates;
- no visual/collision hole disagreement after commit;
- swept projectile passes through an already removed region before collider rebuild completes;
- player cannot fall through a solid seam and can pass through a sufficiently large opening;
- debris is convex, bounded, reclaimable, and never dynamic concave collision;
- untouched structures retain the current primitive count and collision behavior.

### Structural/acoustic tests

- unsupported island detaches; anchored island remains;
- a small divot does not rebuild acoustic topology;
- an accumulated opening crosses the aperture threshold once and only invalidates local graph data;
- opening/closing revision transitions are lerped without a loudness/reverb step;
- tunnel/bunker propagation changes only where geometry actually changed.

### Multiplayer/persistence tests

- operation replay equals direct server state;
- duplicate/out-of-order batches are rejected or recovered;
- late join obtains the correct changed-brick checkpoint;
- temporary disconnect resumes from the last acknowledged revision;
- corrupted/mismatched bake hash requests a full volume checkpoint rather than applying bad edits;
- host and client see identical topology/material IDs;
- bandwidth remains bounded under automatic rifle fire and clustered explosions.

### Character tests

- wounds follow animation, flips, kicks, PBD pose, and ragdoll;
- armor intercepts the event before skin;
- missing limbs cannot receive/render wounds on absent geometry;
- severing invokes existing limb state and produces one stable cap;
- wound slots merge deterministically and remain bounded;
- remote and late-joining players receive the same wound state.

### Stress/fuzz tests

- thousands of random finite brushes with invariant checks;
- hostile NaN/infinite/extreme RPC inputs;
- repeated edits at world and brick-coordinate limits;
- 10,000 edits followed by save/load/checkpoint replay;
- multiple players firing different materials while acoustics and ragdolls run;
- strict allocation counters for the steady-state bullet path.

## Reversibility and rollout safety

- Default feature flag is disabled until Phase 1 gates pass.
- Immutable structure path remains intact and selectable per object.
- The new projectile router falls back to current `apply_damage` behavior when no destruction receiver
  exists.
- Acoustic local invalidation is additive; global `request_rebuild()` remains a debug/fallback path.
- Every bake stores a version/hash; bad or obsolete bakes fail closed to immutable collision.
- The Voxel Tools reference spike lives behind an adapter and can be removed without changing
  `DamageEvent`, material definitions, networking, or tests.
- No current map is batch-converted until the isolated wall, multiplayer, collision, and acoustic
  gates pass.

## Research basis

- [Adaptively Sampled Distance Fields (Frisken et al., SIGGRAPH 2000)](https://graphics.stanford.edu/courses/cs468-03-fall/Papers/frisken00adaptively.pdf)
  shows adaptive sampling, spatial hierarchies, local sculpting, Boolean operations, and memory
  savings for detailed fields.
- [Kizamu: A System for Sculpting Digital Characters](https://www.ronaldperry.org/SIG2001_Kizamu.pdf)
  documents interactive ADF editing and specifically notes that min/max sculpting produces
  inaccurate remote distances that need correction.
- [Dual Contouring of Hermite Data](https://people.eecs.berkeley.edu/~jrs/meshpapers/JuLosassoSchaeferWarren.pdf)
  provides the sharp-feature-preserving octree/QEF extraction basis.
- [Transvoxel](https://transvoxel.org/) provides transition cells for stitching different voxel LOD
  levels and is intentionally deferred until LOD is justified.
- [OpenVDB](https://www.openvdb.org/about/) and its
  [sparse-volume paper](https://research.dreamworks.com/wp-content/uploads/2018/08/Museth_TOG13-Edited.pdf)
  establish the hierarchical sparse-volume model; the project should copy the sparse design
  principles, not embed a heavyweight film-volume dependency without evidence.
- [Voxel Tools for Godot](https://github.com/Zylann/godot_voxel) is a mature reference for editable,
  threaded, chunked SDF terrain and Transvoxel. Its
  [smooth-terrain documentation](https://github.com/Zylann/godot_voxel/blob/master/doc/source/smooth_terrain.md/)
  explains clamped narrow bands and 8/16-bit quantization. Its
  [performance documentation](https://voxel-tools.readthedocs.io/en/latest/performance/) also warns
  that collision acceleration-structure creation can cost several times the meshing work and is
  deferred to the main thread. Its multiplayer support is described as experimental, so it is a
  benchmark/reference backend rather than the universal architecture.
- [A Fast Sweeping Method for Eikonal Equations](https://www.math.uci.edu/~zhao/homepage/research_files/FSM.pdf)
  provides a simple linear-complexity distance correction method suitable for bounded dirty bands.
- [Godot collision-shape guidance](https://docs.godotengine.org/en/stable/tutorials/physics/collision_shapes_3d.html)
  supports keeping concave trimesh collision static and minimizing shape/body counts.
- [Godot compute-shader guidance](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html)
  documents storage-buffer compute and the cost of immediate CPU/GPU synchronization.
- [Graphical Modeling and Animation of Brittle Fracture](https://escholarship.org/uc/item/9r28g121)
  is evidence for stress/material-dependent fracture behavior, while also illustrating why full FEM
  fracture is much heavier than this game's bounded response profiles and support graph.

## Definition of done

The system is ready for broad map use only when:

- no update scans or stores a dense world field;
- concrete, metal, and wood visibly and mechanically respond differently to the same event;
- edits, collision, late join, reconnect, and saves agree by revision/checksum;
- current projectile, movement, item, character, ragdoll, and audio behavior is unchanged on
  non-destructible content;
- a changed structure locally and smoothly affects acoustics without a global rebuild;
- character wounds reuse the contract without replacing the proven limb/ragdoll collision rig;
- all queues, memory pools, fallbacks, and hard caps are observable and tested;
- the feature can still be disabled per object and globally without altering authored scenes.
