# System tests

Run the deterministic drone regression suite with Godot 4.6:

```sh
godot --headless --path . --script res://tests/drone_system_test.gd
godot --headless --path . --script res://tests/drone_runtime_integration_test.gd
godot --headless --path . --script res://tests/enemy_system_test.gd
godot --headless --path . --script res://tests/enemy_runtime_integration_test.gd
godot --headless --path . --script res://tests/lobby_system_test.gd
godot --headless --path . --script res://tests/player_equipment_system_test.gd
godot --headless --path . --script res://tests/body_part_shop_system_test.gd
godot --headless --path . --script res://tests/ballistics_system_test.gd
godot --headless --path . --script res://tests/ballistics_runtime_integration_test.gd
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
```

The suite checks shared arrival/position-hold control, moving-target feed-forward,
follow recovery and view independence, context obstacle steering, ORCA bounds,
all AI-chip contracts, and the complete hover-plus-fire power envelope of the
calibrated reference drone.

The enemy suites validate the resource-driven behavior/anatomy contracts,
two-bone reach solver, alternating gait, dev-zoo discovery, and procedural
visual geometry. The runtime suite instantiates the real Jolt-backed spider and
four-legged block creature. It verifies that the complete skeleton exists
before `PhysicalBoneSimulator3D` binds every unique limb body. One fixed
physical root must follow the authoritative chassis, each upper segment must be
parented to that root, each lower segment must be parented to its matching upper
segment, and every joint frame must sit at the segment's proximal endpoint.
Sustained chase assertions measure chassis tracking, root lag, attachment error,
segment length, and physical knee-side polarity, so detached hips, inverted
knees, and knee-only pivots fail explicitly. The deterministic suite also
checks the spider's exact alternating tetrapod sets, strict group alternation,
and the brief eight-foot support transfer between swing phases. The suite also
verifies finite replicated joints and confirms that hits on a physical leg
forward damage to the owning enemy.

The runtime integration test additionally uses the real Jolt rigid body, rotor-force,
battery, targeting, weapon, player-follow, and relocation-recovery paths. It checks
that the reference drone holds position while firing and returns upright to its follow
annulus after a large player teleport.

The lobby suite checks the four-player admission boundary, browser compatibility
filters, protocol isolation, full-lobby rejection, and defensive lobby-count
metadata parsing.

The ML evaluation-contract suite checks deterministic benchmark scenario coverage, frozen
environment-contract hashing, task-routed scenario plans, cross-contract promotion rejection,
and stratified-bootstrap evaluation diagnostics.

The player-equipment suite checks the one-slot baseline, 3/6/9-slot backpacks,
generic equipment transactions, default and removable eyes, distinct ocular
shaders, quality-driven vision parameters, HUD/post-process draw order, and the
bounded monster-facing distortion contract.

The body-parts shop suite checks recursive limb discovery and grouping behind
the flat department menu, one product per buyable limb, matching physical
delivery items, server-authoritative credit deduction, order-state transitions,
the kiosk and pickup-pad scene wiring, and preservation of the scanner cursor
indicator without its zoom-navigation presentation.

The ballistics suites check modular receiver/barrel/magazine/ammunition
compatibility, authoritative ammunition and reload transactions, shared drone
and handheld projectile profiles, visible projectile replication, continuous
per-frame collision sweeps, and delayed impact damage instead of hitscan.

The ML suites check variable propeller action shapes, stable slot identity,
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
The generic-limb suite builds one-, two-, and four-segment chains, verifies locked translations and Jolt angular-spring configuration, rejects duplicate action mappings, checks swing/twist round-trips, nonlinear passive hardening, damping, soft stops, and passive return to rest with all model actuator authority disabled.

The four-limb suite also checks the unified-room coordinator, separate rolling limb-model storage, fixed sixteen-output action contracts (twelve joints plus four grips), jump-contact anti-farming, qualified landing reward, sustained real-joint-limit punishment, dead-worker camera exclusion, reward-card checkpoint persistence, the generic four-chain/eight-segment adapter, load-bearing joint-axis alignment, and physical-body simulation. The focused stability test disables every model actuator, settles the real body for 240 Jolt physics frames, applies a chassis impulse, then checks another 180 frames of passive recovery. It fails if the chassis loses standing height, touches the floor, tips over, becomes non-finite, or folds its feet beneath the body.
The target-handler suite checks independent per-group navigation behaviour, deterministic semantic priority routing, survival-over-task ordering, nearest/urgent target selection, stable tie-breaking, and live target registration/removal without changing the model objective contract.
The target-room integration suite checks that the room-default evaluator/template marker stays hidden during ordinary per-group training, appears only for a live evaluator that consumes it, and that runtime worker dispatch repairs a missing group handler instead of aliasing workers back to the room-default objective.

The turret suite checks the three-output yaw/pitch/trigger contract, acceleration- and
braking-limited manual servos, authored pitch stops, fixed named observations, spatial-hash
target acquisition, shared drone/limb threat perception, finite-speed projectile hit ledgers,
aim/hit/discipline/damage rewards, rolling turret checkpoints, and dead-worker camera exclusion.
