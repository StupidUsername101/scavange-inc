# Native SDF backend

This GDExtension accelerates allocation-sensitive mutation, structural mapping, chunk capture, and
contour construction while preserving the GDScript snapshot/result contract. Each volume keeps one
persistent dense sample lattice beside its authoritative sparse bricks. Hot remesh and local
connectivity queries copy directly from that lattice in C++ instead of traversing GDScript
dictionaries. Shared brick samples use the sparse field's positive-side ownership rule, and tests
require sample-identical native and portable captures so this cache cannot change topology.
Fragment extraction uses the same cache to fill bounded tile snapshots, and component erasure uses
reusable integer stamps plus complete touched-brick packets. The sparse bricks remain authoritative
and byte-identical to the portable path; the native lattice is updated incrementally rather than
being rebuilt after a large slab detaches.

Structural occupancy uses the minimum of each cell's eight SDF corners rather than their average.
Consequently every cell capable of producing zero-contour geometry also participates in the
connectivity flood; thin severed sheets cannot remain rendered merely because positive air samples
outweighed their negative matter sample. Connectivity crosses only shared voxel faces. Edge- or
corner-only contact has zero supporting area and therefore cannot pin tiny splinters to the source
wall after the surrounding material detaches.

Contour vertices retain analytic box-face constraints separately from cavity geometry. The worker
snaps constrained coordinates back to the exact authored planes and splits shell vertices per face
for hard axis normals; bullet channels and impact craters retain smooth surface-net normals. This
prevents a locally rebuilt chunk from rounding a straight wall edge or shading a dark bevel into an
untouched neighbour.

Mixed cells no longer force every crossing through one contour vertex. Their crossed cube edges are
partitioned into face-connected cycles first; four-crossing saddle faces use the bilinear asymptotic
decider, which gives neighboring cells and chunks the same topology decision. Each cycle receives
its own allocation-free centroid/normal accumulator. This prevents overlapping craters and grazing
hits from producing four-face branch edges, coincident sheets, or intermittent black shards.

The extension deliberately uses only Godot C++ bindings and standard C++; there are no platform
APIs, SIMD assumptions, compiler-specific packed structs, or native bytes in saved/network state.

The `godot-cpp.commit` file pins the binding revision used by supported builds. Build with the
repository helper:

```bash
python3 tools/build_sdf_native.py --godot-cpp /path/to/godot-cpp --target template_debug
python3 tools/build_sdf_native.py --godot-cpp /path/to/godot-cpp --target template_release
```

The editor/runtime discovers the resulting library through
`addons/scavange_sdf/scavange_sdf.gdextension`. If a platform binary is absent or incompatible,
`SdfChunkBuildJob` keeps using the deterministic GDScript implementation.
