# Destruction artifact cleanup audit — 2026-08-31

## Status and scope

This document preserves the read-only forensic pass and the plan that preceded the cleanup. The
plan was executed later on 2026-08-31; the verified result is recorded below before the original
audit so future changes retain both the evidence and the reasoning.

## Execution result — 2026-08-31

The first corrupting production stage was the generated/base chunk seam mutation, not the native
contour extractor. A deterministic four-fixture stage trace starts with closed globally-owned raw
and analytic-shell meshes, then applies a test-local copy of the removed runtime mutation. Across
those fixtures the mutation creates 1,555–1,705 collapsed triangles and 23–65 open boundary edges.
The old sanitizer deletes the collapsed faces but still leaves 23–66 open edges. The production
path has zero degenerate, duplicate, boundary, non-manifold, or wrong-winding faces in all four
fixtures.

The production fix is architectural:

- the first accepted edit stages the complete finite-volume generated surface while the analytic
  boxes remain visible and collidable;
- render and collision switch atomically after every generated chunk is ready, so a frame can no
  longer mix independently-owned generated geometry with retained `BoxMesh` geometry;
- subsequent edits remain local and rebuild only the affected chunk neighborhood;
- no extracted vertex is moved onto a chunk boundary afterward, and the topology-changing
  sanitizer survives only as an explicitly named regression oracle;
- checkpoints preserve whether the generated surface is active, so listen hosts, event clients,
  and late-join clients reconstruct the same presentation state.

Exterior/fracture presentation now uses whole-polygon reference-surface classification. Vertices
shared by an exterior face and a fracture face are duplicated by semantic class without changing
their position or topology. Retained walls and detached fragments use the same classification, and
the runtime test rejects any triangle that interpolates between exterior and fracture colors. This
removes the remote dark-edge/material wedge caused by the old per-vertex distance band.

A Hermite/QEF placement experiment based on the cited Dual Contouring papers was tested in both
native and portable paths, but the constrained implementation made the current pathological cases
worse. It was reverted rather than shipped behind a plausible name. The cleanup therefore fixes
the proven ownership/mutation defect without silently replacing the stable extractor.

Verified gates:

- artifact pipeline: 8/8 assertions across four deterministic seeds;
- runtime destruction: 38/38, including final global manifold audit, atomic presentation,
  material-boundary polygons, host/client replay, and late checkpoints;
- fragmentation: 29/29; universal destruction: 24/24; plasma runtime: 10/10;
- native/script parity: all mutation, feature-point, topology, and fallback checks passed;
- ballistics: 58 assertions plus runtime integration; flute enemy: 27; death/respawn: 7;
- acoustic propagation: all 97 normative assertions still pass.

Linux debug performance after the cleanup: native capture plus mesh is about 0.11 ms median; an
ordinary continuous cutter pulse is about 1.4 ms median; the deliberate large structural
separation remains the exceptional roughly 30 ms pulse. The geometry oracle and OBJ trace writer
are test-only and allocate freely; neither is called by runtime code.

Reported symptom: visible mesh artifacts still occur after repeated ballistic/plasma edits despite
the current topology tests passing. Earlier captures included isolated wedges, blackened or rounded
box edges, small retained splinters, gaps between generated and retained geometry, and fragment
pieces that did not visually complement the remaining wall.

The goal of the next run is not to tune another tolerance. It is to capture one deterministic
failure, identify the first pipeline stage that creates invalid geometry, and correct that stage
using a published contouring rule or a maintained reference implementation.

## Verification performed in this audit

The following current tests were run without changing the repository:

- `universal_destruction_system_test.gd`: 24 assertions passed;
- `destruction_runtime_integration_test.gd`: 38 assertions passed;
- `destruction_fragmentation_test.gd`: 29 assertions passed;
- `sdf_native_backend_test.gd`: native/scripted mutation and meshing parity passed.

Passing these tests confirms deterministic replay, basic edge incidence, winding, bounded edge
lengths, some generated/base seam rays, fragment locality, native parity, and current multiplayer
state equivalence. It does **not** prove that the final presented triangle soup is free of every
visible artifact.

## Pre-execution geometry path (historical)

The visible wall is produced by several distinct transformations:

1. `SparseSdfVolumeData` samples the analytic box and applies CSG subtraction to touched samples.
2. `SdfNativeKernel::build_chunk_snapshot()` extracts per-chunk contour vertices and owned faces.
3. `SdfDualContouringMesher.finalize_box_shell()` snaps tagged vertices to the analytic box and
   duplicates selected vertices for hard shell normals.
4. `DestructibleVolume3D._snap_analytic_shell_to_chunk_bounds()` moves shell vertices again where a
   generated chunk meets a retained `BoxMesh` chunk.
5. `sanitize_after_vertex_edit()` collapses short edges, removes collapsed triangles, and rewinds
   faces after the seam movement.
6. `_surface_colors_for_result()` classifies vertices as exterior or interior from distance to the
   original box.
7. Fragmentation independently meshes a component before erasing its occupied cells and rebuilding
   the retained wall afterward.

The important consequence is that native/scripted extractor parity cannot detect a defect created
by stages 3–7.

## Confirmed findings

### P0 — the strongest topology test does not inspect the final runtime mesh

`_full_volume_topology()` in `universal_destruction_system_test.gd` calls
`SdfDualContouringMesher.build_chunk()` directly. It checks edge incidence after positional welding,
degenerate indices, winding, an intentionally broad edge-length limit, and SDF error at triangle
centroids.

It does not run the runtime chunk-boundary snap or runtime edge-collapse pass. It also does not test:

- triangle/triangle self-intersection;
- per-vertex SDF residual;
- exact pairwise equality of generated/generated and generated/base boundaries;
- normals after runtime vertex movement;
- disconnected components measured by surface area or enclosed volume;
- overlap or gaps between a detached fragment and the retained wall;
- fixed-camera rendered output, including material interpolation and back-face culling.

The runtime test checks triangle quality and winding per generated chunk and casts a sparse set of
seam rays. A closed or locally connected wedge can pass both checks and remain clearly visible.

### P0 — runtime seam repair changes topology after contour ownership is decided

`_snap_analytic_shell_to_chunk_bounds()` moves selected vertices by as much as `0.55 * voxel_size`
onto a chunk plane. `sanitize_after_vertex_edit()` then collapses the shortest edge of triangles
below a quality threshold. The collapse chooses an endpoint from valence but does not check the
topological link condition, self-intersection, surface error, material boundary, or whether the edge
belongs to a different contour component.

This is a confirmed architectural defect even before attributing a specific screenshot to it:
topology is first decided from sign-changing primal edges, then modified geometrically without
re-evaluating that topology. The current test suite does not audit manifoldness after this pass.

The next run must remove the need for this repair rather than make its tolerances more elaborate.

### P0 — normals become stale after runtime vertex edits

The seam snap moves positions. The sanitizer may merge two vertices. Neither operation recomputes
the sampled gradient, an angle-weighted normal, or an exact analytic face normal for every affected
triangle. The sanitizer only changes winding using the pre-edit normals.

This can produce dark or bright shading that resembles missing geometry even when index topology is
valid. It is a separate failure class from a real flap or crack and needs a normal-debug render mode.

### P1 — the extractor is not the QEF-based Dual Contouring described by its documentation

The original Dual Contouring method constructs Hermite constraints from edge intersection points
and normals and minimizes a quadratic error function (QEF). The current native and scripted paths
average the crossing points in each contour group. This is closer to a topology-clustered Surface
Nets vertex placement rule.

That mismatch does not by itself prove the reported artifacts, but it does explain why sharp box
features require later snapping and hardening passes. The published QEF/mass-point method exists
specifically to place vertices robustly for flat, sharp, and rank-deficient configurations.

Primary references:

- Tao Ju et al., [Dual Contouring of Hermite Data](https://people.eecs.berkeley.edu/~jrs/meshpapers/JuLosassoSchaeferWarren.pdf)
- Schaefer and Warren, [Dual Contouring: The Secret Sauce](https://www.cs.rice.edu/~jwarren/papers/techreport02408.pdf)
- Schaefer, Ju, and Warren, [Manifold Dual Contouring](https://people.engr.tamu.edu/schaefer/research/dualsimp_tvcg.pdf)

### P1 — exterior/interior presentation is inferred per vertex after meshing

The wall assigns white exterior modulation when a generated vertex lies within a `1.25 * voxel_size`
band of the original box, otherwise it assigns an interior modulation. A triangle may therefore
interpolate between classifications. Fragment meshes use a separate binary white/black vertex mask.

This is weaker than reference-surface polygon classification. OpenVDB's maintained fracture mesher
accepts the original unfractured SDF as a reference, uses it to eliminate seam lines, and tags
exterior and fracture-seam polygons for material/normal transfer:

- [OpenVDB `VolumeToMesh::setRefGrid`](https://www.openvdb.org/documentation/doxygen/structopenvdb_1_1v13__0_1_1tools_1_1VolumeToMesh.html)

Our next implementation should copy that rule conceptually: classify faces from the immutable base
field, split vertices at classification boundaries, and never blend an exterior color through an
interior fracture face merely because they share one contour vertex.

### P1 — fragments and retained walls are not generated as one proven complementary partition

A fragment is meshed from component membership against the pre-erasure field. Its cells are then
erased and the wall is meshed again from the changed field. Tests verify locality and absence of one
central remnant, but do not measure fragment/wall overlap, separation gaps, union volume, or matching
interface boundaries.

OpenVDB's reference-grid fracture path is a useful working model because it explicitly handles
fracture seam lines and exterior tagging. We should keep our lighter field representation, but adopt
the invariant that one component partition owns both outputs and that their interface is generated
from one shared set of boundary samples.

### P2 — repeated CSG edits are not audited for signed-distance quality

The field update uses `max(previous, -cutter)`. This preserves the desired inside/outside Boolean,
but min/max composition does not generally preserve an exact signed-distance function. The extractor
uses central-difference gradients from that field for normals and vertex constraints.

This is not yet proven to be the visible defect. The next trace must measure the local Eikonal
residual (`abs(length(gradient) - 1)`) and correlate it with failed triangles before any
re-distancing is added. OpenVDB likewise distinguishes arbitrary scalar volumes from level sets and
recomputes distance values when operations invalidate their level-set assumptions:

- [OpenVDB level-set documentation](https://github.com/AcademySoftwareFoundation/openvdb/blob/master/doc/doc.txt)

### P2 — face ambiguity is covered, but the full runtime topology space is not exhaustively proven

The extractor applies the asymptotic decider on ambiguous cube faces and clusters crossing edges
into multiple per-cell components. This is the right family of rule, but the tests use randomized
wall edits rather than an exhaustive sign/magnitude suite for ambiguous cells and their rotations.

Relevant primary references:

- Nielson and Hamann, [The Asymptotic Decider](https://escholarship.org/uc/item/17p025zk)
- Schaefer, Ju, and Warren, [Manifold Dual Contouring](https://people.engr.tamu.edu/schaefer/research/dualsimp_tvcg.pdf)

This must be proven by an exhaustive fixture before changing the grouping rule.

## Maintained working implementation to use as the chunking reference

Zylann's Godot Voxel Tools is a maintained C++ implementation used for editable, chunked smooth
voxel terrain in Godot. Its regular Transvoxel mesher uses explicit negative/positive sample padding,
boundary-aware vertex reuse, case tables, and a configurable interpolation edge margin. It does not
repair ordinary same-resolution chunk seams by moving an already-generated triangle soup afterward.

- [Godot Voxel Tools repository](https://github.com/Zylann/godot_voxel)
- [Transvoxel implementation](https://github.com/Zylann/godot_voxel/blob/master/meshers/transvoxel/transvoxel.cpp)
- [`edge_clamp_margin` documentation](https://github.com/Zylann/godot_voxel/blob/master/doc/source/api/VoxelMesherTransvoxel.md)

We should borrow its ownership/padding and near-corner interpolation discipline. We should not copy
the entire LOD system or silently replace our extractor until an A/B backend passes our destruction
and fragment contracts.

## Required next-run order

### 1. Build a deterministic artifact recorder before changing behavior

Add a developer-only recorder around one destructible volume. For every canonical damage event it
must retain:

- event packet, sequence, seed, material/profile signature, volume bake hash, and native version;
- pre/post field checksum and changed-brick packets;
- exact dirty/remeshed chunk coordinates;
- geometry after raw extraction, box-shell finalization, runtime seam handling, runtime sanitizing,
  surface classification, fragment extraction, and retained-wall rebuilding;
- timing and allocation metrics already available from the performance run.

On the first validator failure, write one compact JSON trace plus OBJ/PLY meshes for each stage. The
trace becomes a permanent regression fixture. This is the destruction equivalent of the serialized
probe walks that finally stabilized the audio system.

### 2. Add a real geometry oracle

Implement validation in the native test backend, not in the shipping hot path initially:

- finite coordinates and valid indices;
- zero-area, duplicate, reversed-duplicate, and extreme-aspect triangles;
- undirected edge incidence and vertex-link manifoldness;
- connected components with area, approximate volume, and bounding box;
- triangle/triangle self-intersection using a broad-phase grid/BVH and exact narrow-phase tests;
- per-vertex and sampled per-triangle distance to the authoritative zero surface;
- geometric-normal versus field-gradient agreement;
- exact shared boundary positions between every adjacent chunk pair;
- normal and surface-class agreement at shared positions;
- fragment/wall overlap and separation distance;
- pre-separation volume versus retained-plus-fragment volume.

Use CGAL's maintained triangle-soup self-intersection predicate as an offline CI oracle for dumped
fixtures; do not add CGAL to the game runtime:

- [CGAL triangle-soup self-intersection implementation](https://github.com/CGAL/cgal/blob/main/Polygon_mesh_processing/include/CGAL/Polygon_mesh_processing/self_intersections.h)

Add a fixed-camera Godot render fixture with debug materials for triangle ID, geometric normals,
sampled normals, shell mask, and exterior/interior class. Geometry validity and rendered shading are
different assertions and both are required.

### 3. Expand the fixture matrix until the current build fails reproducibly

The suite must cover:

- all 256 cell sign cases, rotations/reflections, and magnitude variants near the isovalue;
- ambiguous faces and internal multi-component cells;
- every chunk face, edge, and corner at both positive and negative sides;
- generated/generated and generated/retained boundaries;
- long plasma strokes at shallow, perpendicular, and diagonal angles;
- overlapping strokes, reversals, pauses, and repeated edits through old cuts;
- every shipped destruction profile and its maximum spatial warp;
- fragmentation immediately beside chunk boundaries and outer box edges;
- native and scripted output, host replay, client replay, and checkpoint restoration;
- deterministic stress seeds retained whenever a new failure is found.

Do not accept a random count alone. Every failure must shrink to the shortest event trace that still
reproduces it.

### 4. Locate the first corrupting stage with one trace and strict A/B gates

Replay the same failed trace and validate after every pipeline stage. Disable one stage at a time in
a developer backend only:

1. raw contour;
2. shell classification/hardening;
3. generated/base seam handling;
4. sliver sanitizer;
5. material/normal generation;
6. component extraction;
7. cell erasure and retained-wall rebuild.

The first transition from valid to invalid selects the correction path below. No production tuning
begins until this is known.

### 5A. If runtime seam handling is first to fail

Remove `_snap_analytic_shell_to_chunk_bounds()` and the unrestricted post-extraction edge collapse.
Replace mixed generated/base boundaries with deterministic extraction ownership:

- every chunk that consumes a changed halo uses the same global sample lattice and global cell IDs;
- boundary vertices are generated from the same samples and ownership rule on both sides;
- retain enough padding/transition-ring geometry that no generated triangle needs to be pulled onto
  a `BoxMesh` boundary;
- prevent near-corner slivers during interpolation, before topology is emitted, following the
  measured edge-margin approach in Godot Voxel Tools;
- if an edge collapse remains necessary for collision, require the manifold link condition and keep
  it out of the render mesh.

Normals and surface labels are generated only after final positions are known.

### 5B. If raw extraction is first to fail

Keep the current backend available behind a project flag and build a corrected experimental backend:

- use Hermite intersections and a numerically stable QEF with the published mass-point fallback;
- constrain or project the solution according to a documented cell rule;
- implement and exhaustively test Manifold Dual Contouring's multiple-component/vertex clustering
  invariant rather than adding new sign-case exceptions;
- compare it against the regular-cell Transvoxel output on the same fields.

If the maintained Transvoxel-style backend reaches all acceptance gates sooner and remains within
the performance budget, prefer it for ordinary structure chunks. Preserve special sharp/exterior
classification as a separate presentation concern.

### 5C. If the field is first to fail

Add local, sign-preserving re-distancing only within the edited narrow band. Gate it on measured
gradient/SDF error and compare the zero surface before and after. Do not globally blur, dilate, or
resample the volume, and do not add this step merely because repeated min/max composition can be
inexact in theory.

### 6. Replace vertex-band material guessing with reference-surface classification

Use the immutable baked/base field as the presentation reference:

- tag complete polygons as exterior, fracture interior, or fracture seam;
- split vertices where tags or hard-normal groups differ;
- transfer the original exterior material and normal only to exterior polygons;
- give fracture polygons an explicit interior/depth material coordinate;
- use the same classification for retained walls and rigid fragments.

This follows OpenVDB's proven reference-grid fracture contract without importing OpenVDB into the
shipping runtime.

### 7. Make fragment generation transactional and complementary

Generate retained and detached geometry from one component-label snapshot and one shared boundary
description. Before committing erasure:

- both meshes pass the full oracle;
- their interiors do not overlap;
- their shared cut interface agrees;
- retained plus detached volume stays within the field's discretization bound;
- every detached component either becomes a physics body or remains in the wall for a later retry.

If any gate fails, keep the authoritative wall unchanged for that detachment event and log the exact
fixture. Never erase material first and hope presentation succeeds afterward.

### 8. Re-run performance and multiplayer only after geometry is correct

Preserve the current ~1.5 ms ordinary plasma pulse and ~30 ms worst structural separation as the
baseline. Measure recorder/oracle code separately and keep it developer-only. The shipping backend
must retain allocation reuse, bounded chunk jobs, deterministic event/checkpoint replay, and equal
host/client geometry hashes.

## Acceptance gates

The cleanup is finished only when all of these hold:

- zero self-intersections, non-manifold edges/vertices, duplicate faces, and invalid winding in every
  permanent fixture;
- no connected render component exists without either structural ownership or a spawned fragment;
- adjacent chunk boundaries agree from the shared global ownership rule, without post-hoc snapping;
- sampled normals agree with final geometry and no exterior/interior material interpolation crosses
  an untagged boundary;
- fragment and retained-wall surfaces are complementary within a tolerance derived from voxel
  quantization, not an eyeballed constant;
- fixed-camera debug and normal-lit render captures contain no new wedges, black seams, missing
  faces, or unexpected changes outside the edited chunk/halo;
- native/scripted, host/client, event replay, and checkpoint replay remain deterministic;
- the current plasma/SDF performance budgets do not regress materially.

## Explicit non-solutions

Do not:

- increase the seam band or sliver threshold again;
- delete suspicious triangles without preserving a closed surface;
- hide the issue with two-sided materials, disabled back-face culling, darker cavity colors, or
  particle effects;
- lower spatial warp globally;
- increase voxel size until the artifact becomes too small to notice;
- run CGAL/OpenVDB repair in the shipping frame loop;
- add coordinates, material names, or wall-specific exceptions.
