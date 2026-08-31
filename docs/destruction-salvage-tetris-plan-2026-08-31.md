# Destruction Salvage and Tetris Packing Plan

## Desired loop

1. Cut or shoot material out of a structure.
2. Detached SDF components become authoritative `DestructionFragment3D` bodies.
3. Carry or drag those bodies with the normal `E` grab controller to a vehicle, refinery, or payout
   intake.
4. Store raw irregular salvage inefficiently, sell it immediately, or refine it into a standardized
   polyomino cargo piece.
5. Pack refined pieces into a backpack/transport grid. Better packing carries more separate goods,
   while every removed voxel reduces the piece's value by the same material volume.

This should remain a material-and-geometry system. Concrete, steel, wood, future enemy tissue, and
other destruction textures use the same pipeline with authored value/density/refining rules.

## Foundation already present

- Detached pieces retain their source volume, destruction material ID, physical surface, measured
  occupied volume, physical mass, exact generated mesh, and a cropped fragment-local SDF. Players
  can keep cutting an oversized piece; each separated child inherits this same recursive contract.
- They use the ordinary authoritative rigid-body grab controller and the same physics-rate remote
  held-motion lane as normal items.
- `PlayerInventoryRules` already owns server-authoritative inventory serialization and backpacks;
  the cargo grid should extend that contract instead of creating a second inventory authority.
- The SDF field already gives a deterministic occupied-volume count. Value and refining yield should
  use that count rather than mesh bounds or a client-reported estimate.

## Data contracts

### World fragment

Keep `DestructionFragment3D` physical and short-lived. Add a durable `SalvageDescriptor` only when a
fragment enters a refinery, cargo intake, or persistence boundary:

```text
salvage_id                 server-issued stable ID
source_volume_id           audit/provenance only
material_texture_id        concrete, metal, wood, ...
original_occupied_units    integer SDF volume units at extraction
retained_occupied_units    integer units remaining after refining
quality_q16                optional contamination/heat/damage multiplier
raw_projection_mask        compact rows of occupied cargo cells
refined_shape_id           empty for raw chunks; explicit ID after refining
shape_rotation             0..3
thickness_class            standardized cargo-layer thickness
```

Use integer occupied units and fixed-point quality/value. Floating-point mesh volume must never be
the economic authority.

### Material economy

Add a small `SalvageMaterialDefinition` referenced by destruction texture ID:

- value per occupied unit;
- accepted thickness classes and cell scale;
- refining/cutting energy and time;
- contamination or heat rules;
- allowed output families (tetrominoes initially, smaller fallback shapes for low volume).

Authoritative value is:

```text
value = retained_occupied_units * material_unit_value * quality_q16
```

Refining changes only `retained_occupied_units` (and explicitly authored quality effects later).
If 18% of the occupied SDF volume is cut away, exactly 18% of the geometry-derived value is lost.
Do not add an unrelated random value penalty.

### Cargo grid

Keep the existing 1D selected-item hotbar for tools, guns, radios, and equipment. Add a cargo grid to
backpacks/vehicles for salvage and other packable goods. This avoids breaking weapon selection and
lets backpack definitions author grid width, height, and optional depth layers independently of the
current hotbar capacity.

Each cargo placement is only `{salvage_id, origin_cell, rotation}`. The server reconstructs its mask,
checks bounds and overlap, and commits the placement transactionally. The client may preview moves,
but never decides whether a placement or payout is valid.

## Refining rule

The refinery should operate on the fragment's SDF occupancy, not its render triangles:

1. Evaluate the three principal projection axes and four grid rotations.
2. Rasterize occupied voxels into the authored cargo cell scale and thickness class.
3. Enumerate only polyomino candidates that are fully contained in the occupied material after a
   small material-specific safety margin.
4. For each candidate, count retained occupied SDF units exactly and calculate value/yield.
5. Offer a small deterministic set: usually highest yield, easiest-to-pack, and one unusual shape.
6. On selection, subtract the rejected SDF cells, rebuild once through the existing chunk job, and
   serialize the resulting cargo piece. Removed cells are the value loss.

Candidate selection can have the gambling-machine presentation the project already likes, but the
server seed and all outcomes must be fixed before the UI animation starts. No reroll-by-disconnect and
no client-supplied result.

## Implementation phases

### Phase 1 — salvage identity and intake

- Introduce `SalvageDescriptor` plus a registry keyed by server-issued ID.
- Convert a fragment to a descriptor only inside an authoritative intake volume; reject fragments
  still supported by a structure or already claimed by another transaction.
- Add material value definitions and a simple sell-as-is intake.
- Persist provenance, occupied units, material, and quality; destroy the world fragment only after
  the transaction commits.
- Suspend debris expiry while grabbed or registered by an intake/refinery.

Completion test: cut a piece, carry it to intake, disconnect/rejoin, and receive exactly one payout
based on its measured occupied volume.

### Phase 2 — polyomino refinery

- Add the projection/candidate solver as a pure, deterministic module with no scene dependencies.
- Start with the five tetrominoes plus 1–3-cell fallbacks; reflections are shape definitions rather
  than implicit filesystem/order IDs.
- Preview the retained region and discarded region on the physical piece.
- Commit one SDF crop/rebuild and produce the descriptor's compact shape mask.
- Add heat/time/cooldown presentation only after the geometry/value transaction is correct.

Completion test: every offered mask fits the source occupancy, output volume never exceeds input,
and `input value - output value` equals the value of removed occupied units exactly.

### Phase 3 — backpack and vehicle packing

- Extend `BackpackDefinition` with cargo-grid dimensions while keeping existing hotbar capacity.
- Add server-authoritative place, rotate, move, and remove transactions with monotonic revisions.
- Put the packing UI on the PBD; mouse/keyboard manipulation is prediction-only until acknowledged.
- Materialize a packed piece back into a grabbable world body when dropped. Use its retained SDF mesh
  if available, otherwise a deterministic standardized shape mesh with the same mass/material/value.
- Reuse this container for carts, truck beds, warehouse payout trays, and future loot extraction.

Completion test: two peers concurrently moving the same piece cannot duplicate it, invalid overlaps
are rejected without disturbing the previous layout, and dropping/repacking preserves value exactly.

## Performance and networking boundaries

- Run expensive projection/refining only at a station or intake, never each physics tick.
- Cache occupancy projections by fragment geometry checksum and grid scale.
- Use packed row bitmasks for candidate fitting; a placement check becomes shifts plus bitwise AND.
- Keep world transform replication separate from economic state. Carried fragments use motion deltas;
  salvage descriptors and grid revisions use reliable transactions.
- Rebuild geometry once after the chosen refinement result, not once per candidate.
- Pool refinery preview meshes and never replicate preview SDF fields.

## Required regression coverage

- A detached fragment is grabbable through the normal `E` priority path and remains smooth remotely.
- Recutting a detached fragment updates its volume/mass, replaces its mesh on every peer, and gives
  every recursively detached child another valid cropped SDF.
- Held or intake-owned fragments do not expire.
- Volume/value conservation across every material and shape/orientation.
- Stable candidate results across native and scripted SDF backends.
- Grid rotations, boundary fits, holes, overlap rejection, and full-grid behavior.
- Transaction replay, duplicate request, disconnect during refinement, and late-join inventory state.
- World-to-descriptor-to-world round trip preserves material, mass within quantization tolerance, and
  retained economic value.

## Deliberate non-goals for the first pass

- Do not turn arbitrary raw chunks directly into ordinary `ItemDefinition` resources at runtime.
- Do not replace the current tool/weapon hotbar with the cargo grid.
- Do not use mesh AABB volume for payouts.
- Do not let cosmetic roulette alter the already committed server outcome.
- Do not make giant concrete slabs weightless. The existing grab force naturally permits carrying
  small pieces and dragging/cooperatively moving heavy ones; carts and powered tools can expand that
  later without a fragment-only physics exception.
