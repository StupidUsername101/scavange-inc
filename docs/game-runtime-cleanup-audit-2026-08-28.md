# Game runtime cleanup audit — 2026-08-28

## Purpose

This is a cleanup plan for the game runtime that exists today. It is not a feature backlog and it
does not recommend replacing systems merely because they are large or unusual. The aim is to remove
proven dead paths, stop avoidable work and allocations, and create safer boundaries around the code
that is currently changing most often.

The audit is deliberately conservative around three recently stabilized areas:

- multiplayer admission, readiness, item motion, wrist-device replication, and audio ownership;
- the generic acoustic propagation, early-reflection, pressure, and late-return pipeline;
- procedural legs, whole-body pose, ragdoll recovery, and synchronized ocular expression.

Those are current architecture. Cleanup must characterize and preserve their behavior rather than
silently replacing it.

## Execution checkpoint — 2026-08-29

Passes 1 and 2 are implemented and characterized. The first Pass 3 seam was then implemented as a
separate checkpoint so class extraction did not share a commit with the multiplayer protocol change.

Completed work:

- removed the inactive player-ID missing-limb demos while preserving real missing-limb equipment;
- retired the garage-only room-response A/B switch while preserving its routing probes and all
  generic acoustic fields;
- guarded procedural-leg, body-pose, and ocular identity assignment against 20 Hz reseeding;
- added lifecycle-aware publication for projectiles, loose drone parts, enemies, and ropes;
- moved player inventory/equipment to a revisioned reliable stream while retaining realtime movement,
  expression, PBD, and vitals snapshots;
- replaced held-gun JSON visual signatures with a build signature stamped when the gun instance is
  created and retained across ammunition mutations;
- converted the generated visual music envelope table from 5,232 lines / 1,439,185 bytes of parsed
  GDScript into a 3,062-byte cached loader plus a 328,984-byte versioned binary artifact;
- made cleared client audio sessions release old compressed stream handles, and made the relevant
  audio fixtures explicitly release temporary renderers/services.

Pass 3 progress:

- `ServerReplicationService` now owns snapshot cadence and sequence numbers, grabbed-item motion
  sequence numbers, optional-stream lifecycle state, state collection, radio/listener publication,
  local prediction contexts, and reliable inventory publication;
- `server.gd` retains gameplay registries and admission authority, and exposes only the narrow
  `publish_states()` delegation point needed by existing runtime/tests;
- the service performs one validated bind to the autoload coordinator. This avoids a Godot circular
  script-type dependency without introducing per-tick reflection, context dictionaries, or copied
  registries;
- the parked drone integration obstacle is now placed across the live recovery command. It tests
  local context steering deterministically without accidentally demanding global path planning around
  an arbitrarily widened wall.

Player presentation, the wrist controller, top-level world layout, and registration adapters remain
the next isolated Pass 3 checkpoints.

Measured idle replication effect: the old empty world emitted one empty projectile replacement at
20 Hz and three empty bulk replacements at 10 Hz, or 50 redundant empty RPCs per second. Stable-empty
optional streams now emit none after their required lifecycle clear. A joining peer explicitly forces
one current publication per optional stream, including empty streams, so proxy deletion and late-join
state are preserved.

The inventory RPC changes the wire contract, so `LobbyRules.PROTOCOL_VERSION` is now `8`. Every host
and client in a multiplayer test must pull this checkpoint; mixed protocol 7/8 sessions are rejected
before transport admission.

Final focused verification completed with all required suites green, including lobby/admission,
movement, procedural legs, pose, eyes, equipment, PBD, proxy motion, grabbing, ballistics, crafting,
world collision/parity, local audio prediction, radio, speaker arrays, acoustic bake/propagation, and
the deterministic parked-drone integration scenario. The test processes now exit without the former
ObjectDB/resource-in-use diagnostics in the radio, speaker, acoustic-propagation, and ballistics
runtime fixtures. Steam transport timing and subjective audio continuity still require the documented
two-process playtest; headless tests cannot prove those.

## Current runtime map

The active authoritative world is `scenes/server/server_world.tscn`; the matching presentation world
is `scenes/proxy/world.tscn`. `Server`, `Client`, `GameState`, `ServerItemFactory`, and
`SceneController` persist as autoloads while the menu is hidden and the two runtime worlds are
created or destroyed.

The active world includes the warehouse and stations, test house, industrial acoustic complex,
speaker garage, acoustic maze, nature, player equipment, drones, items, weapons, and ropes. The dev
enemy zoo is not instantiated by either active world and is excluded from the game export. Its files
remain useful as a parked prototype.

## Invariants every cleanup pass must preserve

1. The server remains authoritative for player actions, ownership, inventory, damage, interactions,
   and admissible sound events. Local presentation prediction must not create a second authoritative
   outcome.
2. Host and remote clients follow the same snapshot and audio paths unless a path is explicitly
   local prediction. `call_local` behavior must remain covered.
3. Empty lifecycle snapshots matter: the first empty state after an entity stream was active removes
   stale proxies. An optimization may suppress later identical empty states, never the clearing one.
4. The PBD remains visible to other players, preserves its page/open state, accepts movement and RMB
   look, and uses the unified scanner target list.
5. Missing limbs remain valid. Procedural legs and body pose must degrade by capability rather than
   assuming a biped. Ragdoll recovery must keep its authoritative landing position.
6. Ocular expression stays generic across the three current eye resources. Pupil, eyelid, social
   gaze, and PBD gaze motion derives from replicated expression time and identity; it must not gain a
   per-frame network stream.
7. Acoustic geometry, direct sound, diffraction/propagation, early returns, pressure events, and
   optional shared late fields remain one generic system. No scene-name or bunker-position fixes may
   be introduced.

## Findings

### P0 — no new live correctness failure found in the static sweep

The reviewed paths parse and have focused regression coverage. The highest-value work below is
technical-debt and hot-path prevention, not a hidden emergency rewrite. Runtime profiling should be
captured before and after allocation-oriented changes so improvements are measured.

### P1 — retire the dead garage room-response experiment, not the acoustic field system

Evidence:

- `scripts/server/server_speaker_cluster_demo_facility.gd` exports
  `use_baked_room_response`, and `scenes/server/speaker_cluster_demo.tscn` sets it to `false`.
- There is no assignment that enables the switch anywhere in the project.
- Its only effects are `AcousticProbe3D.sample_reflections` and `reverb_scale` in that garage.
- `resources/world/garage_pressure_array.tres` also disables its shared late field.
- `resources/world/large_bunker_pressure_array.tres` and
  `resources/world/valve_reference_bunker_array.tres` actively enable the generic shared late field.

Decision:

- Delete the garage-only A/B export and scene property. Keep its routing probes, always disable their
  local sampled room response, and preserve the existing speaker-array resource.
- Do **not** remove `AcousticEnvironmentModel`, `AcousticPropagationField`, late-field resources,
  generic probe routing, early reflections, or pressure handling. They are active and tested.

Acceptance evidence:

- Garage probes still participate in routing and always have sampled reflections/reverb disabled.
- Large and Valve bunkers retain their resource-controlled shared late behavior.
- Radio, speaker-cluster, industrial-environment, and acoustic-propagation suites remain unchanged.

### P1 — remove stale missing-limb demo branches from the live server coordinator

`scripts/server/server.gd` still preloads the no-arms/no-legs loadouts and declares fixed demo player
IDs. The match branches that used them are commented out, so every joining player currently receives
the full-body loadout. The real equipment/body-loadout system already supports missing limbs.

Decision:

- Remove the two demo IDs, unused preloads, and commented match branches.
- Reduce `_get_starting_body_loadout` to its actual behavior. Do not delete the loadout resources or
  missing-limb support/tests.

This is dead source cleanup only; it must not alter any joining player's loadout.

### P1 — avoid reseeding presentation identity on every player snapshot

`PlayerProxy.apply_server_state()` writes `player_id` and calls `set_expression_identity()` on the
procedural leg, whole-body pose, and ocular controllers every 20 Hz snapshot. Identity normally
changes once, at proxy construction. The recent ocular layer adds a third redundant call but does not
otherwise introduce an expensive hot path.

Decision:

- Add one guarded `set_player_identity()` path and update the three controllers only when the ID
  changes. Keep replicated `expression_clock` updates at snapshot frequency.
- Add a regression proving a later snapshot advances expression time without resetting controller
  identity or phase.

### P1/P2 — the dormant enemy lane still consumes active-session work

The dev zoo is absent from both active worlds, but the server still:

- iterates `server_enemies_by_enemy_id` every physics tick;
- builds and broadcasts an enemy snapshot every 10 Hz bulk tick, normally empty.

The client still owns an enemy proxy registry and RPC receiver. The generic enemy rig and its gait
planner are used by the parked zoo and a runtime integration test, so deleting the subsystem would
discard useful future work.

Decision:

- Keep the zoo scenes/resources/scripts offline.
- First stop stable-empty network work through the lifecycle-aware stream policy described below.
- Keep enemy registration and replication functional when an enemy is explicitly instantiated. Do
  not add a scene-name special case or an `ENABLE_ENEMIES` constant that can drift from the world.

Acceptance evidence:

- An empty active world sends no repeating enemy payloads.
- Spawning one enemy starts the stream; removing the last enemy sends exactly one clearing snapshot;
  later stable-empty ticks send nothing.
- A late join while enemies exist still receives the complete current state.

### P2 — lifecycle snapshot streams repeat stable-empty payloads

`Server.publish_states()` builds and RPCs multiple full dictionaries on fixed intervals. Some streams
are usually active (players/items), while projectiles, drone parts, enemies, ropes, and previews can
remain empty for long periods. Simply skipping every empty dictionary would be incorrect because the
client treats the first empty full snapshot as deletion of all proxies.

Decision:

- Add a small per-stream activity tracker to the replication schedule:
  - non-empty full snapshots are sent normally;
  - an active-to-empty transition sends one empty clearing snapshot;
  - stable-empty intervals send nothing;
  - a late-joining peer receives an explicit current full snapshot for every relevant stream.
- Do not apply this policy to delta-only grabbed-item motion, reliable spawn/despawn transactions, or
  per-listener radio/audio packets without separate lifecycle proof.

Tests must cover loss-tolerant sequence ordering, final clear, stable-empty suppression, reactivation,
late join, host `call_local`, and reset/reconnect.

### P2 — inventory presentation is rebuilt from a full public inventory at 20 Hz

Every player snapshot constructs a fresh public inventory on the server. Every proxy then sanitizes
that full dictionary; the held-gun path also serializes its build dictionary to JSON to derive a
signature. Equipment visuals avoid rebuilding when paths match, but the copies, sanitization, and JSON
signature are still paid for each player at movement snapshot frequency.

Decision:

- Give authoritative inventory/equipment state a monotonically increasing revision.
- Keep movement and expression data in the existing realtime player snapshot, but only include or
  apply full inventory data when the revision changes. A newly admitted peer must receive the current
  inventory regardless of revision history.
- Replace JSON signature construction with an explicit stable build revision/hash produced when a
  crafted instance changes.
- Preserve HUD immediacy by sending inventory mutations reliably or forcing the next realtime
  snapshot; do not wait on a slow station cadence.

Measure allocations and packet bytes before and after. Do not combine this protocol change with the
larger class extractions below.

### P2 — generated music envelopes should be data, not 5,232 lines of source

`scripts/audio/music_visual_envelope_catalog.gd` embeds every music track's sampled visual envelope as
GDScript `PackedByteArray` literals. It is generated by `tools/generate_music_loudness_catalog.py` and
used for speaker-disc animation, not acoustic propagation. With each new track it increases parser,
editor, source-diff, and script-cache cost.

Decision:

- Change the generator to emit an imported binary/resource artifact containing a version, normalized
  track key, sample rate, and packed bytes.
- Keep a tiny cached loader with the current lookup/sample API so `RadioAudioRenderer` does not change
  behavior or allocate per frame.
- Test deterministic generation, catalog completeness, unknown-track fallback, duration/sample
  boundaries, and export inclusion.

This is a representation change only. It must not alter audio level, track synchronization, or the
speaker pulse response.

### P3 — server and player proxy have accumulated too many unrelated responsibilities

Current sizes are useful warning signals, not proof by themselves:

- `scripts/server/server.gd`: 4,281 lines;
- `scripts/client/player_proxy.gd`: 1,741 lines;
- `scripts/server/server_player.gd`: 1,657 lines;
- `scripts/client/client.gd`: 1,280 lines.

The actual problem is change coupling. Lobby admission, entity registries, interactions, stations,
weapons, grabbing, and snapshot publication share one coordinator. Player input/camera, PBD, equipment,
audio prediction, body presentation, oculars, and ragdoll presentation share one proxy.

Decision: extract only across already-visible seams, in small commits with characterization tests:

1. `PlayerPresentationRig`: owns procedural legs, whole-body pose, ocular expression, equipment/body
   mounts, and ragdoll visual state. It consumes one sanitized presentation snapshot and does not send
   RPCs. The existing `PlayerCharacterPoseController`, `PlayerProceduralLegRig`, and
   `PlayerOcularExpressionController` remain subcomponents.
2. `PlayerWristInterfaceController`: owns PBD input mode, page/open state, scanner/control refresh, and
   local/remote display presentation. It delegates network requests through the client coordinator.
3. `ServerReplicationService`: owns snapshot sequence, schedule, stream lifecycle tracker, and
   publication. It reads registries but does not own gameplay entities.
4. Only after those settle, separate session/admission and interaction routing from `server.gd`.

Do not perform a wholesale rewrite, rename RPC methods during extraction, or move audio math merely to
make file sizes smaller.

### P3 — top-level server/client world placement is duplicated

The industrial complex, maze, and garage already use shared internal layout definitions, but the two
top-level world scenes manually repeat which areas/stations exist and where their server/client
representations are placed. This is a multiplayer drift risk.

Decision:

- Introduce a shared top-level world-layout resource containing stable IDs and transforms, plus paired
  authoritative/presentation scene paths.
- Keep server-only collision and client-only sky/visual concerns separate.
- Migrate one area at a time and add a parity test for stable ID and transform before removing its two
  manual scene entries.

This should follow, not precede, the replication cleanup because world migration and protocol changes
in the same pass would make regressions difficult to localize.

### P3 — dynamic method calls need boundaries, not blanket replacement

The game intentionally supports different fieldlink devices, items, and stations through
`has_method()`/`call()` contracts. Other dynamic calls merely reach known autoload methods and hide
breakage until runtime.

Decision:

- Keep duck typing at genuinely extensible device/item boundaries, but formalize each contract in one
  adapter/component with validation at registration time.
- Replace dynamic calls to known `Server`/`Client` methods with typed references as code moves into
  the services above.
- Do not convert every call in one mechanical pass; that would produce churn without improving a
  runtime boundary.

## Execution order

### Pass 1 — dead paths and characterization (lowest risk)

1. Add active-world and acoustic-boundary characterization tests.
2. Remove the unused no-arms/no-legs demo constants, preloads, and commented branches.
3. Retire the garage-only baked-room switch while preserving routing probes.
4. Guard presentation identity assignment so snapshots cannot reseed it.
5. Record packet counts for an idle host with one local player as the baseline for Pass 2.

Rollback is file-local for every change in this pass.

### Pass 2 — measured replication/allocation cleanup

1. Implement and test lifecycle-aware stable-empty stream suppression.
2. Apply it first to enemies, then projectiles/drone parts/ropes one stream per commit.
3. Add inventory/equipment/build revisions and remove repeated sanitize/JSON work.
4. Convert music envelope source literals to a generated data artifact.
5. Compare idle packet counts, bytes, script-load time, and frame allocations with the Pass 1 baseline.

Each stream/protocol change must be independently revertible. Do not batch audio behavior changes into
this pass.

### Pass 3 — structural seams

1. Extract player presentation without changing its input snapshot.
2. Extract the wrist controller without changing RPC names/channels.
3. Extract replication scheduling/publication from the server coordinator.
4. Migrate top-level world placement to shared descriptors one area at a time.
5. Formalize dynamic registration contracts at the boundaries exposed by those moves.

## Required regression matrix

At minimum, run these focused suites after each relevant pass:

- lobby/admission: `lobby_system_test.gd`;
- player authority/presentation: `player_movement_test.gd`,
  `player_procedural_leg_rig_test.gd`, `player_character_pose_system_test.gd`,
  `player_ocular_expression_system_test.gd`, and `client_proxy_motion_test.gd`;
- equipment/PBD: `player_equipment_system_test.gd`, `wrist_terminal_system_test.gd`;
- interaction physics: `grab_rotation_test.gd`, `ballistics_system_test.gd`;
- world parity/collision: `industrial_environment_test.gd`,
  `structure_collision_pipeline_test.gd`, `movement_parkour_area_test.gd`;
- audio invariants: `audio_prediction_system_test.gd`, `radio_system_test.gd`,
  `speaker_cluster_system_test.gd`, and the acoustic propagation/bake suites;
- parked enemy capability when its lane changes: `drone_runtime_integration_test.gd` plus a dedicated
  enemy stream lifecycle test.

Also perform a two-process host/client smoke test for join/readiness, remote PBD visibility, item grab
motion, radio control/position response, footsteps, ragdoll recovery, and remote ocular expression.
Headless unit tests cannot prove Steam transport timing or perceived audio continuity by themselves.

## Audit baseline

On 2026-08-28, the focused suites listed above completed with 683 passing assertions/checks and no
test failure. This includes lobby, player movement, procedural legs, whole-body pose, ocular
expression, equipment, PBD, client proxy motion, grabbing, ballistics, industrial world, clustered
collision, parkour, local audio prediction, radio, speaker cluster, and acoustic bake coverage.

At the original baseline, `radio_system_test.gd` and `speaker_cluster_system_test.gd` printed
ObjectDB/resource-in-use warnings during process shutdown. The execution pass traced those fixture
ownership gaps, released the temporary renderers, and also cleaned equivalent temporary-service and
active-playback residue in the acoustic-propagation and ballistics runtime suites. Their verbose exits
are now clean, so future ownership warnings should be treated as regressions rather than familiar
noise.

## Explicitly deferred

- New enemies or reactivation of the zoo.
- Music-derived emotion and emotes.
- New acoustic math, room tuning, or bunker-specific correction.
- A redesign of the ML room or level editor.
- Deleting the parked enemy gait/physical-rig implementation.

Those may become future work, but they are not cleanup defects in the active game runtime.
