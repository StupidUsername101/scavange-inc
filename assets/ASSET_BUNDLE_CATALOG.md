# Asset bundle catalog

The local bundle currently contains roughly **8,600 files / 4.3 GiB**. Much of that size is the
same model repeated as GLB, FBX, OBJ/MTL, and DAE plus archived copies. The raw libraries stay in
ignored `.gdignore` source vaults; only assets selected for a real runtime use belong under
`assets/third_party/pizza_doggy`.

## Strong fits

- **PSX Tech** — terminals, panels, fuse boxes, radios, monitors, doors, and industrial fixtures.
  This is the best visual match for Scavange Inc.'s warehouse and training technology.
- **PSX Bunkers** — generators, machinery, storage, pipes, pallets, barrels, bunker structure, and
  military clutter. Useful for the acoustic annex, tunnels, future facilities, and scavenging maps.
- **PSX Mega Pack / Mega Pack II** — a broad reserve of streets, shops, apartments, sewers, and
  industrial pieces. Pull from it per level rather than importing it wholesale.
- **Rust & Blood - SFX Library** — strong physical gameplay coverage: footsteps, weapons, handling,
  impacts, debris, inventory actions, and player movement.
- **Echoes - Audio Super Kit** — electronics, switches, machinery, doors, UI, creatures, and general
  interaction sounds.
- **ROT - Horror Audio Bundle** — ambience, machinery, radio noise, entities, and tension layers.

## Situational reserves

- **PSX Nature** is useful once outdoor scavenging areas need authored terrain clutter and foliage.
- **Modular Retro FPS Kit** can supply stylized interior modules, but its pixel treatment should be
  used as a coherent room set rather than mixed randomly into every environment.
- **Brutal Skyboxes** are visually strong but much more specific than the current neutral outdoor
  lighting; choose one only when a level's art direction calls for it.

## Runtime selection in use

- The outdoor server scene uses one curated Brutal Skyboxes panorama and a deterministic,
  outward-densifying forest made from five PSX Nature models. Roughly 1,180 trees plus undergrowth
  remain five client MultiMesh batches; sampled trunks and rocks share two authoritative bodies and
  three baked convex shapes. Grass and ferns remain visual-only.
- The industrial annex uses nine curated GLB sources: eight prop types plus three parallel runs of
  the six-metre PSX Bunkers straight-tunnel module. Generated modular-structure resources own each
  run's measured bounds, scale, repeat count, and collision profile. Every eight-module run reduces
  from forty floor/wall/roof descriptors to five authoritative bodies, so all three hollow 48 m
  passages remain open without paying for one physics object per visible section.
- The wearable Fieldlink uses the compact partial-screen model from PSX Tech, with its actual display
  replaced by the live scanner-family session interface.
- Radio receiver static now uses a real multi-second loop from ROT.
- Concrete, metal, and wood footsteps, takeoffs, and landings use four randomized Rust & Blood
  contact variations each with cue-specific pitch and weight.
- Pistol reload-out/reload-in, item pickup/equip, and industrial station-button cues use the existing
  server-authoritative spatial audio route.
- Fieldlink uses paired Rust & Blood inventory movements for raising and lowering the arm unit, a
  short Echoes hover tick, and dark ROT click, confirmation, and warning cues. Every cue is a
  server-validated semantic event rendered by the shared pooled spatial/acoustic system, so nearby
  players hear device use through the same geometry and room response as other game sounds.
- The warehouse automatic rifle uses four curated Rust & Blood assault-rifle reports, matching
  magazine cues, and dedicated pressure transients instead of reusing the service pistol sound.

When adding more, prefer GLB for models and OGG for short/streamed game audio unless a WAV loop needs
sample-accurate control. Add one canonical source, keep collision authored server-side, and record the
source pack in the curated README.

Collision onboarding is now manifest-driven for untouched third-party GLBs. See
`res://tools/README.md`: the headless baker writes reusable Godot `Shape3D` resources, while modular
wall boxes go through exact structure clustering so adjacent art pieces do not become separate
physics shapes. Never convex-bake an entire hollow bunker; preserve its openings with simplified
`-colonly` source geometry or clustered wall/floor primitives.
