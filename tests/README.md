# System tests

Run the deterministic drone regression suite with Godot 4.6:

```sh
godot --headless --path . --script res://tests/drone_system_test.gd
godot --headless --path . --script res://tests/drone_runtime_integration_test.gd
godot --headless --path . --script res://tests/limb_kinematics_test.gd
godot --headless --path . --script res://tests/lobby_system_test.gd
godot --headless --path . --script res://tests/player_equipment_system_test.gd
godot --headless --path . --script res://tests/wrist_terminal_system_test.gd
godot --headless --path . --script res://tests/player_movement_test.gd
godot --headless --path . --script res://tests/player_procedural_leg_rig_test.gd
godot --headless --path . --script res://tests/grab_rotation_test.gd
godot --headless --path . --script res://tests/body_part_shop_system_test.gd
godot --headless --path . --script res://tests/ballistics_system_test.gd
godot --headless --path . --script res://tests/ballistics_runtime_integration_test.gd
godot --headless --path . --script res://tests/weapon_crafting_station_test.gd
godot --headless --path . --script res://tests/acoustic_propagation_test.gd
godot --headless --path . --script res://tests/acoustic_bake_system_test.gd
godot --headless --path . --script res://tests/acoustic_maze_world_test.gd
godot --headless --path . --script res://tests/forest_maze_dense_probe_test.gd
godot --headless --path . --script res://tests/acoustic_maze_forest_quarter_meter_test.gd
godot --headless --path . --script res://tests/acoustic_maze_forest_speed_probe_test.gd
godot --headless --path . --script res://tests/radio_system_test.gd
godot --headless --path . --script res://tests/speaker_cluster_system_test.gd
godot --headless --path . --script res://tests/bunker_exterior_speaker_probe.gd
godot --headless --path . --script res://tests/bunker_quarter_meter_mix_probe.gd
godot --headless --path . --script res://tests/industrial_environment_test.gd
godot --headless --path . --script res://tests/structure_collision_pipeline_test.gd
godot --headless --path . --script res://tests/level_editor_stage_one_test.gd
godot --headless --path . --script res://tests/acoustic_world_probe_test.gd
godot --headless --path . --script res://tests/tunnel_acoustic_dense_probe_test.gd
godot --headless --path . --script res://tests/tunnel_acoustic_centimeter_probe_test.gd
godot --headless --path . --script res://tests/tunnel_exit_cone_probe_test.gd
godot --headless --path . --script res://tests/audio_dsp_discontinuity_probe.gd
godot --headless --path . --script res://tests/reverb_return_normalization_probe.gd
godot --headless --path . --script res://tests/pa_four_speaker_render_probe.gd
godot --headless --path . --script res://tests/valve_bunker_pause_tail_render_probe.gd
godot --headless --path . --script res://tests/audio_tail_floor_render_probe.gd
godot --headless --path . --script res://tests/music_content_tail_render_probe.gd
godot --headless --path . --script res://tests/audio_prediction_system_test.gd
godot --headless --path . --script res://tests/jump_landing_audio_latency_test.gd
godot --headless --path . --script res://tests/asset_bundle_integration_test.gd
godot --headless --path . --script res://tests/drone_ml_pipeline_test.gd
godot --headless --path . --script res://tests/drone_training_policy_test.gd
godot --headless --path . --script res://tests/drone_training_obstacle_sensor_runtime_test.gd
godot --headless --path . --script res://tests/drone_training_loadout_config_test.gd
godot --headless --path . --script res://tests/drone_training_action_trace_test.gd
godot --headless --path . --script res://tests/model_action_trace_panel_test.gd
godot --headless --path . --script res://tests/drone_ppo_test.gd
godot --headless --path . --script res://tests/drone_sac_her_test.gd
godot --headless --path . --script res://tests/rl_implementation_guide_test.gd
godot --headless --path . --script res://tests/ml_evaluation_contract_test.gd
godot --headless --path . --script res://tests/generic_limb_test.gd
godot --headless --path . --script res://tests/ml_body_interface_test.gd
godot --headless --path . --script res://tests/four_limb_ml_test.gd
godot --headless --path . --script res://tests/four_limb_stability_test.gd
godot --headless --path . --script res://tests/turret_training_system_test.gd
godot --headless --path . --script res://tests/training_target_handler_test.gd
godot --headless --path . --script res://tests/training_target_room_integration_test.gd
godot --headless --path . --scene res://tests/variable_propeller_runtime_test.tscn
godot --headless --path . --scene res://tests/worker_preset_flow_test.tscn
```

The suite checks shared arrival/position-hold control, moving-target feed-forward,
follow recovery and view independence, context obstacle steering, ORCA bounds,
all AI-chip contracts, and the complete hover-plus-fire power envelope of the
calibrated reference drone.

The limb-kinematics suite validates the allocation-light two-segment solver shared by
ML body authoring and runtime rigs: exact segment lengths, unreachable-target clamping,
bend-hemisphere continuity, finite degenerate poses, and orthonormal knee joint frames.
The retired deterministic enemy gait and its dev-zoo runtime no longer gate the learned
worker stack; the dormant zoo assets remain available for a future AI implementation.

The runtime integration test additionally uses the real Jolt rigid body, rotor-force,
battery, targeting, weapon, player-follow, and relocation-recovery paths. It checks
that the reference drone holds position while firing and returns upright to its follow
annulus after a large player teleport.

The lobby suite checks the four-player admission boundary, browser compatibility
filters, protocol isolation, full-lobby rejection, defensive lobby-count metadata,
functional card creation/removal/join IDs, member-versus-room callback isolation,
partial-search timeout preservation, Steam Join Game/rich presence, the invite overlay,
complete leave-session teardown, and sufficient SteamNetworkingSockets lanes for every
declared RPC channel so remote audio cannot silently collapse onto the world-state lane.
It also locks the latency contract: replaceable player/world snapshots must use loss-tolerant
transport, player poses and interactive items own independent lanes, late packets cannot rewind
newer state, actively grabbed items receive lightweight physics-rate deltas, and the 20 Hz full
realtime / 10 Hz secondary-physics / 2 Hz station schedule cannot silently regress into a single
reliable full-world queue.

The ML evaluation-contract suite checks deterministic benchmark scenario coverage, frozen
environment-contract hashing, task-routed scenario plans, cross-contract promotion rejection,
and stratified-bootstrap evaluation diagnostics.

The player-equipment suite checks the one-slot baseline, 3/6/9-slot backpacks,
generic equipment transactions, default and removable eyes and Fieldlinks, distinct
ocular shaders, quality-driven vision parameters, HUD/post-process draw order, and
the bounded monster-facing distortion contract. The wrist-terminal suite checks its
ordinary physical/equipped item paths, compact hover-hinted UI, lazily allocated 3D
screen, scanner-family CRT treatment, Tab access, public technical-interface opening,
local/remote arm-pose isolation, camera presentation, shared-gait bob inheritance,
critically damped heavy-arm hold sway, moving-screen pointer alignment, and gameplay input lockout.

The player-movement suite checks accelerated ground movement and braking,
momentum-preserving takeoff and airborne coasting, speed-neutral air steering,
stable ballistic gravity, wall sliding that removes only blocked velocity, and a
single distance-driven gait phase shared by footstep audio and camera motion. Hard landings also
probe both real biped supports on the authority, as do completed gait footfalls: a missing second
foothold must replicate one trip/ragdoll transition, while one-legged loadouts never fail a check
for a phantom foot. A compact server-owned torso carries the authoritative player through the fall,
recovers beside its final position, and waits when nearby geometry cannot fit the standing capsule.
These probes are event-driven rather than paid on every physics frame.

The procedural player-leg suite checks reusable allocation-free two-bone presentation,
planted-foot query reuse, ordinary and detail-only ground roles, smooth movement guides with
discrete stair contacts, turn-safe foot ordering, forward walking knee drive, pose-preserving
takeoff, continuous asymmetric airborne correction, ground-relative landing preparation, and every
zero/one/two-leg availability combination. Touchdown contacts resolve independently, may arrive at
different times and heights, and drive a saturating whole-body yield instead of forcing both feet onto
one plane. The replicated trip presenter must construct physics only for installed limbs, keep its
torso converged on the server reference, move the local camera/listener with its physical head, and
restore the procedural body after recovery. A long high jump must remain tucked until its real ground
clearance closes without freezing into a mirrored pose. Nonlinear per-jump pose variation is keyed by
the server-owned jump sequence so every observer sees the same expressive choice, and a critically
damped per-foot response prevents those randomized targets from producing a post-takeoff shove;
missing limbs must not create hidden support, IK output, collision probes, or alternating gait slots.

The grab-rotation suite checks authored item hold poses, shortest-path orientation
errors, persistent player-relative targets, preserved three-dimensional hold anchors,
independent screen-space pitch/yaw, bounded input processing, and absolute mouse targets
that produce the same pose when an unreliable intermediate packet is dropped. It also
checks automatic centers of mass for offset shapes and a complete turn using the portable
radio's mass and collision geometry.

The body-parts shop suite checks recursive limb discovery and grouping behind
the flat department menu, one product per buyable limb, matching physical
delivery items, server-authoritative credit deduction, order-state transitions,
the kiosk and pickup-pad scene wiring, and preservation of the scanner cursor
indicator without its zoom-navigation presentation.

The ballistics suites check modular receiver/barrel/magazine/ammunition
compatibility, semi-auto versus server-paced held automatic fire, authoritative
ammunition and reload transactions, distinct pistol/rifle semantic reports,
shared drone and handheld projectile profiles, visible projectile replication,
continuous per-frame collision sweeps, and delayed impact damage instead of hitscan.

The weapon-crafting suite checks independent slot-machine reels, optional repeated
barrel mounts, caliber-gated payout, backward-compatible build serialization,
per-barrel mass/ammunition/projectile behavior, procedural multi-muzzle geometry,
server/client station replication, local rotating preview, input priority near the
machine, and physical pickup-ready payout through the ordinary inventory path.

The acoustic suite checks listener-centered wavefront routing, material-dependent
three-band transmission, graph-path selection, parallel direct/diffracted energy, physical arrival delay, apparent
doorway direction, modifier replication, packet validation, and scene-authored probe
and portal discovery, including continuous sub-meter distance updates from a cached field,
soft range fading, cached single-line endpoint obstruction, narrow-wall transmission, clear-path
bypass of unrelated probe barriers, mild short-panel diffraction, energy-domain indoor direct/diffuse
fields without outdoor gain, the authored acoustic test house, and the authoritative server-to-owning-client
RPC bridge. It also verifies rebuild-time pressure signatures, bounded multi-exit detonation arrivals,
strict packet validation, automatic response metadata on ordinary one-shots, explicit opt-out,
artifact-free room DSP without replaying ordinary recordings, dedicated pressure recordings, reverb-tail-safe voice
reuse, session-boundary DSP flushing, continuous-source cache cleanup, and reuse of the fixed
physical-delay voice pool.
Its explicit `A01..A26` contract also requires collision-derived forest scattering to differ from
the open field, independent sources to retain additive voices, and pistol/rifle reports to carry the
same authoritative indoor response. Rule A17 bounds spectral room bloom to sustained bright content
in reflective enclosures. The final two rules require generalized collision-visible source attachment
and keep continuous overload protection out of ordinary program dynamics. The final rules also expose one
bounded received-audio activity signal and forbid resizing a populated stereo-reverb delay network. A real placed trunk must remain
a partial aperture obstruction, and the speaker-cluster suite samples floor and crate-top bunker
positions so solid props cannot expose a baked room-field coverage hole. It also walks 482
ten-centimetre samples along the bunker rear and speaker-side walls using persistent listener IDs,
rejecting missing states and discontinuities in actual output level, spectrum, or hall response—not
merely changes in an internal occlusion flag. The suite fails when any listed rule lacks passing evidence.

The focused tunnel field test deploys 10,961 evenly spaced quarter-metre listener probes around
the active south mouth and nearby house, plays the radio from the far tunnel end, serializes every
measurement to `tests/generated/tunnel_acoustic_dense_snapshot.json`, and rejects audible/silent
neighbor cliffs, silent-then-loud outdoor reappearances, excessive guided gain, and a falsely-near
far-end radio level.

The tunnel-exit cone regression places the portable radio near one end of the active comfort
tunnel, then samples 21,901 listeners on a 20 cm grid across the opposite exterior. It serializes
readable two-metre cross-sections plus the full compact field to
`tests/generated/tunnel_exit_cone_report.json` and `tunnel_exit_cone_field.bin`. The test rejects a
finite spill cutoff, any sudden centerline level change, or a half-strength footprint that fails to
widen at 2, 6, and 12 metres from the mouth.

The hard acoustic-maze acceptance field is intentionally separate from the fast regression suite:

```sh
godot --headless --path . --script res://tests/acoustic_maze_navigation_field_test.gd
```

It deterministically builds an enclosed 11-by-11 perfect maze from real collision shapes, asks the
ordinary world bake to recover its 121 probes and 120 openings, and places a loud source at the far
end of a 67-cell route. Every cell is measured through the production server service. The test then
tries to solve the maze independently from neighboring loudness and from apparent arrival direction,
including junctions whose geometrically closest source-side cell is behind a wall. A second graph-only
control distinguishes a bad bake from bad direct/routed mixing. The complete field, route, branch
margins, energy weights, navigation traces, and first failures are written to
`tests/generated/acoustic_maze_navigation_field.json`. The acceptance requires both volume-only and
apparent-direction navigators to follow all 67 route cells, including tempting branches and
behind-wall Euclidean shortcuts; weakening the maze or its assertions is not a propagation fix.

The same deterministic layout is instantiated in both active test-world scenes at `(150, 0.02,
-10)`, completely east of the generated forest. It has a walkable south entrance, matching
authoritative collision/client presentation, one acoustic probe per cell, and a fixed radio on its
marked farthest exit. Like every installed music source, that beacon starts silent and requires an
explicit interaction or Fieldlink command. A generated exterior perimeter follows the shell from the real entrance,
connects collision-visible outdoor air to the forest field, and receives reciprocal material-filtered
radiation from every adjacent wall cell plus an open entrance edge. Interior and exterior attachment
domains cannot auto-connect across the shell. Each interior cell also owns one overlapping,
continuously faded endpoint-influence volume; this admits both sides of a real cardinal opening near
their boundary but rejects probes seen only through a zero-width diagonal corner. This makes the
exterior wall an extended pressure source
without allowing a listener inside to leave through one wall and re-enter through another.
`acoustic_maze_world_test.gd` rejects missing world wiring, any nature
placement within a three-metre maze buffer, mismatched geometry, absent beacon registration, or a
beacon whose reach cannot cover the complete entrance-to-exit route. It also locks the temporary
three-times END capacity used while movement is still being finalized.

The forest/maze audit runs against the active production server world at 10 cm spacing. It serializes
168,336 static listener samples to `tests/generated/forest_maze_dense_probe_field.bin` and a readable
diagnostic report to `tests/generated/forest_maze_dense_probe_report.json`, then walks another 67,872
persistent-source samples east-to-west and west-to-east. The report ranks route, probe, wall-crossing,
occlusion, environment, and loudness discontinuities. The acceptance forbids a farther forest region
from becoming louder than the nearer maze clearing and bounds every real 10 cm movement step.

The combined quarter-metre acceptance runs the actual maze beacon through the complete production
world on a 98,553-position field covering the maze and its surrounding forest. In addition to the
compact binary field, it records every maze cell, the baked-only control wave, the rendered parallel
mix, apparent-direction navigation, branch margins, source/listener attachments, and persistent 25 cm
forest walks. Cell diagnostics include cumulative wall-crossing count and the nonlinear three-band
transmission response, so a real one-wall bass path is distinguishable from a multi-wall leak. It
rejects exterior graph shortcuts, inaudible corridor cells, unusable route levels, a false branch
more than the measured 1.5 dB broadband gain JND, renewed forest gain, and adjacent movement cliffs. Use
`SCAVANGE_MAZE_FOREST_AUDIT_MODE=cells` for the 121-cell setup/route check.

The focused moving-probe acceptance keeps one listener/source identity for 1,165 consecutive 25 cm
samples (a simulated 5 m/s at 20 Hz). It walks from the forest to the west shell, around the real
entrance, and through the generated maze route. Every sample serializes heard level/EQ/reverb,
direct baked wall crossings, the complete source-to-listener probe path, edge modifiers, bend count,
and expected versus applied deviation response to
`tests/generated/acoustic_maze_forest_speed_probe_report.json`. The test rejects any outdoor route
that crosses the shell somewhere other than a concrete boundary or the real entrance, any clean-EQ
many-corner route, missing wall-adjacent concrete coloration, and movement steps beyond the shared
level or spectral dezipper bounds.

The focused acoustic-bake suite round-trips graph topology, nonlinear edge modifiers, diffuse-room
links, environment responses, and the static-boundary broadphase through the versioned value-only
artifact. It verifies that overlapping modular wall pieces merge, separated walls accumulate, a
matching world reloads without visibility/environment rays, and a moved probe rejects stale data and
falls back to a normal rebuild. Run it with:

```sh
godot --headless --path . --script res://tests/acoustic_bake_system_test.gd
```

The exhaustive tunnel audit then evaluates 10,406,601 listener positions on a one-centimetre grid
across the active radio tunnel's south mouth and its full exterior approach. It writes a compact 16-byte binary record per
position plus ranked anomaly metadata, and separately walks both x directions at one-centimetre
resolution every 25 cm along z with persistent listener IDs. Static comparisons between independent
z-walk histories are retained as diagnostics but cannot masquerade as sideways movement. The audit
rejects same-regime level steps, farther-away hotspots, and discontinuities at probe ownership
changes. Set `SCAVANGE_TUNNEL_AUDIT_MODE=cross` for the focused cross-tunnel sweep or `setup` for a
fast parse/world-bake check.

The radio suite checks music-folder discovery, specialized item spawning, authoritative
power/track/timeline state, restricted client resource loading, per-listener acoustic snapshots,
persistent distortion voice pooling, clear direct-path filtering, smooth DSP transitions, speaker
origin placement, pooled spectrum-envelope analysis, restrained speaker-cone motion, and replicated
power-light presentation. It also prevents ordinary snapshot jitter from hard-seeking a healthy
continuous stream, verifies bounded per-frame dB slew and missing-state fadeout, checks the
power-normalized room send, pre-reverb spectral bloom, shared predictive continuous-mix limiter, and calibrated
post-normalization speaker output, and requires every discovered track to have a peak-safe baked EBU
R128 loudness entry. It also locks the startup contract: portable radios, the maze beacon, and every
installed PA array must register silently until an explicit server-authoritative command. Synchronized speaker groups normally split authoritative energy into per-band
coherent spatial direct paths plus exactly one listener-space wet late field; per-cabinet reverbs are
forbidden for that group. The bunker currently exercises the reversible no-late-field A/B profile:
it keeps every baked routing probe and the coherent direct mix, but disables sampled environment
responses on those probes, returns reserved wet energy to the direct signal, and renders neither a
shared return nor four local reverbs. Because Godot's
reverb return is not output-energy normalized, groups that retain the shared return use one
deterministic correction derived from Godot's eight feedback combs, wet-output scale, room size, and
predelay feedback. It never follows program peaks or changes gain with a beat.
The separate 40-by-32-by-10-metre comparison bunker keeps that normalized shared return. Its four
wall-centred inward-facing cabinets share one timeline, while a two-height probe lattice supplies the
geometry-derived enclosure, room size, and RT60 instead of importing the garage response.
Both installations use the same `SpeakerArray3D` composition root. A variation supplies one shared
`SpeakerArrayDefinition` plus any number of recursively attached `SpeakerArrayEmitter3D` markers;
the server and client instance the same marker rig, so placement, ordering, IDs, collision, audio
origins, and cone animation cannot drift into layout-specific subclasses. The regression suite also
builds an asymmetric twelve-speaker array in reverse child order to guard this count-agnostic contract.
The rendered four-speaker guard walks the bunker entrance in both directions on the captured-audio
clock and bounds level, audible-band, stereo, correlation, derivative, and limiter movement.
The large-bunker lifecycle guard additionally instantiates the real client renderer and requires four
localized direct cabinet paths plus one live full-band shared Hall return. It crosses both a single
missing unreliable snapshot and a pause held through complete silence, then requires resume to clear
every tail filter/gain state without revealing a retired return.
The Valve-bunker pause-tail guard renders the real four-cabinet shared late field, verifies that a
clean PA never starts any receiver-static voice, pauses by removing the authoritative snapshot, and
requires every program decoder to stop while the populated room return decays monotonically to the
noise floor. This prevents a nominal `-60 dB` static layer from masquerading as silence beneath music.
Spectral steps already more than 24 dB beneath the program window are treated as masked;
overall waveform discontinuity and level checks still cover every sample/window.
The tail-floor render probe then isolates the shared production rack with a finite three-band tonal
source. It preserves the useful early room decay, finds the first undriven quarter-second window below
-50 dB, and requires the following residue to cross -88 dB within 750 ms and become fully inaudible
before Godot's default two-second below-threshold channel shutdown. Restoring the rack after silence
must also remain below -90 dB without new input. The untapered engine return fails
both the residue window and lifetime checks, covering the previously untested musical-tail to
noise-floor transition for footsteps and continuous program audio.
The music-content tail probe repeats that transition through the real four-speaker bunker renderer
with `Es geht alles vorüber es geht alles vorbei.mp3`. It keeps the recognizable first echo, then
requires the dry-to-diffuse handoff to continue falling instead of exposing a decorrelated Freeverb
plateau. This catches lossy, dense program residue that the clean three-tone source cannot excite.
The audio-prediction suite then guards the multiplayer presentation split: owner cues start with a
free-field fallback even before the first server-issued listener context, prediction keys are
disjoint for UI/gait/automatic shots, normalized pressure follows the cached room response,
host-speed and client-speed packet ordering reconcile to one voice, rejected future arrivals are
removed, authority-first host cues wait only within the bounded presentation-frame grace and safely
fall through when prediction is absent, and remote unkeyed events still play once. It also checks
that the replaceable context owns a valid dedicated GodotSteam lane and runs at the bounded 5 Hz
schedule rather than adding geometry work per input. Host and joining-client gait presentation both
advance from same-frame movement input through the authoritative acceleration solver, while delayed
snapshots are forbidden from dragging an already-predicted impact backward.
The jump-landing latency probe complements those semantic assertions with captured audio. It drives
a production `ServerPlayer` through a real ballistic jump and floor collision, then follows the
landing through `Server.emit_spatial_sound()`, the acoustic solve, local-host RPC, the production
renderer, and an `AudioEffectCapture` on Master. It prints the flight time separately from
contact-to-packet, physical travel, voice start, first audible sample, and Godot's reported output
latency. Headless runs measure the game path with the dummy driver's zero output latency. Run the
same script without `--headless` to include the active audio driver's buffer; Bluetooth codec/radio
latency remains downstream of Godot and therefore outside Master capture.
The separate reverb-return probe renders deterministic broadband noise through bunker- and
tunnel-sized wet-only racks, then measures their post-warmup RMS. It fails if the analytical return
normalization still leaves Godot's feedback network hot or crushes the return beyond its calibrated
window.

The industrial-environment suite verifies that the inactive zoo is absent from both live worlds,
server collision and client presentation share one three-storey/ramp/tunnel/large-bunker layout, every storey and
four-metre tunnel probe section participates in the acoustic graph, elongated tunnel geometry produces
a narrowed hall with a finite outdoor spill field, and the large bunker is at least eight garage
volumes with clear nature bounds, four symmetric speakers, and a sampled long-decay response. The multi-storey building uses dense per-floor probes
and physical ramp endpoints, turning the camera cannot orbit the acoustic listener, and the shared
semantic catalog registers both weapons' dry reports and dedicated pressure transients.

The ML suites check variable propeller action shapes, creator layouts wider than four rotors,
dynamic server colliders/client visuals, worker-up-aligned default rotor placement, stable slot identity,
actuator clamping, rejection of malformed/non-finite actions, the intentionally
empty model boundary, quad-only baseline control, moving-target observation
features, independently switchable approach/radius/smoothness/obstacle/failure rewards, explicitly
named and normalized PPO tensors, compact dynamic-ray obstacle context, redundant-feature
removal, empirical correlation/rank auditing, bounded stochastic actions, checkpoint
fidelity and runtime deployment metadata, horizontal-only arena exits with unrestricted altitude, correct terminal versus time-limit bootstrapping, stable behavior-policy
sampling, reusable inference/backpropagation equivalence, sample-chunk equivalence, and
incremental finite clipped-PPO optimizer updates, plus SAC twin-critic replay updates, observation-dependent per-propeller exploration heads, hindsight relabelling, maze visitation memory, hover-relative action round-trips, worker-isolated structured warm-up, per-drone timed cell exploration rewards that reject short loops, SAC checkpoint/runtime compatibility, source-aware variable-width action traces with adaptive compaction across drone, four-limb, and turret workers, rolling checkpoint revisions that reject stale evaluator results, and persisted Model Library creation/training/last-used metadata. The PPO suite also checks that seeded relative
weight variation produces a distinct, reproducible, finite child policy and clears inherited
Adam momentum. The obstacle-sensor runtime test builds a real arena-layer wall and verifies
that floor clearance cannot mask horizontal wall clearance, that target-line occlusion reaches
the probe and the PPO actor tensor, and that a tagged wall contact is reported through the
training drone's rigid-body contact monitor. The loadout-configuration test verifies private
per-group part copies, linked battery/core/four-propeller power edits, physical lift summaries,
exact hardware and installed-chip checkpoint round-trips, and filtering to compatible four-slot
core presets.
The worker-preset scene checks the four requested **Worker Groups +** starts, complete equipped
quad/hex/humanoid/robo-dog anatomy, nonzero six-rotor lift, PPO/SAC compatibility gating, editable
creator loading, and the chooser-before-creator interaction in a normal project/autoload context.
The generic-limb suite builds one-, two-, and four-segment chains, verifies locked translations and Jolt angular-spring configuration, rejects duplicate action mappings, checks swing/twist round-trips, nonlinear passive hardening, damping, soft stops, and passive return to rest with all model actuator authority disabled.

The four-limb suite also checks the unified-room coordinator, separate rolling limb-model storage, fixed sixteen-output action contracts (twelve joints plus four grips), jump-contact anti-farming, qualified landing reward, sustained real-joint-limit punishment, dead-worker camera exclusion, reward-card checkpoint persistence, the generic four-chain/eight-segment adapter, load-bearing joint-axis alignment, and physical-body simulation. The focused stability test disables every model actuator, settles the real body for 240 Jolt physics frames, applies a chassis impulse, then checks another 180 frames of passive recovery. It fails if the chassis loses standing height, touches the floor, tips over, becomes non-finite, or folds its feet beneath the body.
The target-handler suite checks independent per-group navigation behaviour, deterministic semantic priority routing, survival-over-task ordering, nearest/urgent target selection, stable tie-breaking, and live target registration/removal without changing the model objective contract.
The target-room integration suite checks that the room-default evaluator/template marker stays hidden during ordinary per-group training, appears only for a live evaluator that consumes it, and that runtime worker dispatch repairs a missing group handler instead of aliasing workers back to the room-default objective.

The turret suite checks the three-output yaw/pitch/trigger contract, acceleration- and
braking-limited manual servos, authored pitch stops, fixed named observations, spatial-hash
target acquisition, shared drone/limb threat perception, finite-speed projectile hit ledgers,
aim/hit/discipline/damage rewards, rolling turret checkpoints, and dead-worker camera exclusion.
