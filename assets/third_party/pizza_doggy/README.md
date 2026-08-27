# Curated Pizza Doggy assets

This directory contains the small runtime subset selected from the locally owned Pizza Doggy
bundle. The source vaults under `assets/environment` and `assets/sounds/effects` are intentionally
excluded from Godot imports and version control because they contain multiple source formats and
thousands of unused files.

## Provenance

- `models/bunkers`: selected GLB files from **PSX Bunkers**, including the modular straight tunnel.
  The tunnel deliberately has no convex manifest hull: one baked modular-structure definition
  drives its client instances and hollow server shell, which `StaticStructureCollisionBuilder`
  collapses into exact primitive clusters.
- `models/tech`: selected GLB files from **PSX Tech**.
- `models/nature`: selected GLB files from **PSX Nature**.
- `environment/skyboxes`: selected panoramas from **Brutal Skyboxes**.
- `audio/rust_and_blood`: selected OGG files from **Rust & Blood - SFX Library**. The rifle
  reports are trimmed mono runtime derivatives; their short pressure layers are filtered from the
  same licensed takes so the propagation system can author the actual room tail.
- `audio/echoes`: selected OGG files from **Echoes - Audio Super Kit**.
- `audio/rot`: selected WAV files from **ROT - Horror Audio Bundle**.

The included Game Asset License Agreements permit commercial and noncommercial game use and
modification. They prohibit redistributing the assets as standalone files, asset packs, templates,
or bundles. Keep additions here limited to files actually used by this game, and do not expose this
source-asset directory through a public repository; distribute it only as part of built game content.
