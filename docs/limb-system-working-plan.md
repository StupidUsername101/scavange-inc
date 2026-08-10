# Limb system working plan

Status: **active until the user explicitly asks to discard it**.

Project-root invariant: the project root is always named exactly `scavange-inc`.
Environment invariant: do not download or install Godot in this workspace.

## Current runtime baseline

The generic elastic limb rig now constructs successfully and the user confirmed that unpiloted and freshly piloted bodies stand in the intended broad spider pose. The chassis can retain its shape even while tilted roughly 90 degrees. Preserve the known-good load-bearing baseline unless a measured defect requires a narrow change:

- core and segment geometry, mass, and surface materials;
- distal-foot spawn-height calculation;
- passive spring, damping, progressive hardening, and torque caps;
- native Jolt spring share and solver priority;
- equal/opposite internal torque application;
- no hidden chassis force, gait remote, or virtual foot placement.

The former open-edge, axial-hip, and chassis-drag reward exploits now have explicit protections.
Current work is capability expansion rather than collapse repair:

1. Validate profile-v9 pickup/grip learning in the live room without changing the known-good standing gains.
2. Use the **Item Pickup** cardset for carry training; pickup objects must not exist in unrelated cardsets.
3. Add a separately versioned Climbing/Grip cardset once live wall attachment and breakaway behavior are observed.
4. Keep future model-forge anatomy variable, but give every released topology an explicit observation/action profile.
5. Build the Spore-like body creator later on top of generic definitions and assemblies; do not mix editor UI into the present runtime layer.

## Current profile-v9 control contract

The fixed four-limb model has four stable limb slots. Each limb exposes three normalized joint-position
targets plus one physical grip activation, for sixteen direct outputs. Profile v9 adds assigned-item
and grip state to the previous full-3D target contract. The known-good standing mechanics are unchanged.

Per limb action order:

1. **Hip elevation** — raises/lowers the upper leg in its radial vertical plane.
2. **Hip horizontal sweep** — yaws the complete upper leg around body-local up.
3. **Knee bend** — bends the lower segment in the authored leg plane.
4. **Grip activation** — releases at zero/negative input and engages compatible nearby surfaces as activation rises.

Physical hip frame:

- joint X: body-local up at the neutral pose; horizontal sweep/yaw;
- joint Z: tangent to the radial leg direction; load-bearing elevation/depression;
- joint Y: locked remaining axis.

Stock spans:

- elevation: ±68 degrees;
- horizontal sweep: ±72 degrees;
- knee: authored asymmetric hinge limits.

The legacy serialized field `hip_twist_span_degrees` remains only for body-file compatibility and
means horizontal sweep, not upper-segment axial twist.

Version identifiers:

- body profile: `four_limb_physics_v9`;
- observation schema: 9;
- feature encoder schema: 9;
- action schema: 4;
- input count: 398;
- action count: 16.

Pre-v9 checkpoints are intentionally incompatible. Profile v8 was a 300→12 joint-only controller
and cannot safely drive the four new grip channels or interpret the added grip/item observations.

## Generic modular architecture

The four-limb worker is an adapter over the reusable model-forge stack:

- `LimbSegmentDefinition`: segment geometry, mass, health, and surface properties.
- `LimbJointDefinition`: per-axis limits, mapping, passive elasticity, active authority, and soft stops.
- `GenericLimbDefinition`: one mount with any positive serial segment count and one independent end effector.
- `LimbEndEffectorDefinition` / `LimbEndEffector3D`: optional terminal geometry/material and grip capability/runtime.
- `GenericGrip3D`: host-independent acquisition, bounded holding, breakaway, carry, and climbing support.
- `LimbSegment3D`: one physical rigid segment.
- `GenericLimb3D`: arbitrary-length rigid chain with `Generic6DOFJoint3D` constraints.
- `LimbsController3D`: dense action-map validation plus joint and grip dispatch.
- `GenericLimbAssembly3D`: mounts arbitrary generic limbs on any `RigidBody3D`, including drones.
- `DroneLimbAttachmentDefinition`: loadout bridge used by `ServerDrone` to build generic limb assemblies.
- `ItemDefinition` / `ServerItem`: generic gameplay-item grip contract through a `grippable` flag and surface tags; ordinary items default to `carryable`.
- `FourLimbPhysicalRig3D`: fixed profile-v9 adapter over that generic stack.

Future creature-editor bodies may have arbitrary limb/segment/end-effector combinations. Each released
topology still needs an explicit policy profile or a padded/set/graph contract; never silently feed
variable anatomy into the fixed 398→16 network.

## Input and grip telemetry — 2026-08-06

- Feature count is 398: 74 global + 68 fixed attachment + four times 64 limb features.
- Full target height and vertical target-relative velocity remain present for both limb and drone workers.
- Optional pickup input includes assigned item presence, 3D offset/distance, relative velocity, mass, and held state.
- Per-limb grip input includes command, filtered activation, candidate availability, target point/normal, distance,
  attachment state, dynamic/static classification, candidate/attached mass, `climbable`/`carryable`
  semantics, normalized holding-load ratio, and an explicit rearm flag after overload breakaway.
- `FourLimbPPOFeatureAudit` remains evidence-only; do not auto-delete correlated features from a narrow lesson.

## Generic grip and carrying baseline — 2026-08-06

- Stock additional end-effector **geometry remains disabled**, preserving the confirmed foot collision shape.
- The non-geometric stock grip actuator is now enabled at each distal tip and has one output per limb.
- Grip surfaces are data-driven (`climbable`, `carryable`, `ground`) rather than tied to trainer classes.
- Candidate acquisition runs at a configurable low cadence; holding forces still run every physics step.
- A held dynamic body temporarily ignores collision only with the gripping distal segment, and the
  exception is removed on release.
- Static surfaces support climbing; dynamic rigid bodies receive equal/opposite force and can be carried.
- Normal and shear forces are independently capped and excessive required load causes measurable breakaway.
- After overload breakaway, a controlled grip must be released below its threshold before it can attach again;
  a passive grip must leave the overloaded target or encounter a different candidate.
  `grip_requires_rearm` exposes that state to the policy instead of hiding actuator hysteresis.
- End-effector health is authoritative for every grip mode: destroyed hardware releases immediately.
- Generic drone limb assemblies exclude host/segment self-collision by default, including across multiple
  opted-in assemblies on one drone; custom definitions can opt out when deliberate self-contact is required.
- Ground is intentionally not compatible with the stock grip, preventing accidental floor adhesion.
- The **Item Pickup** preset alone spawns assigned carryable boxes and enables the pickup reward card.
- Each training box is restricted to its assigned worker's body, preventing workers in the same group from
  stealing one another's objective while ordinary gameplay items remain universally grippable by default.
- Pickup reward provides a small first-grab signal and a larger one-time lift signal; re-grabbing cannot farm it.

Detailed review: `docs/generic-grip-and-pickup-review-2026-08-06.md`.

## Reward-cardsets

Typed reward cards, sliders, persistent preset tabs, and built-in Ground Locomotion, Long Jump, and
Item Pickup cardsets are implemented. The next new preset should be **Climbing / Grip** after live
telemetry confirms sensible attachment, load, slip, breakaway, and energy scales. Cardset identity
must remain in group/checkpoint metadata.

## Passive “rubber limb” rules

Every free joint axis has permanent rest-pose impedance even with zero model authority:

- part of the baseline spring/damper runs in Jolt's angular spring;
- the explicit controller supplies the remaining bounded spring-damper torque;
- resistance increases progressively near the allowed range edge;
- model torque works against, rather than replaces, passive elasticity;
- parent and child receive equal and opposite torque;
- missing/damaged actuators may lose active authority while passive structure remains.

Do not tune the standing spring strengths merely because a fresh PPO worker jitters. Fresh profile-v9 policies sample sixteen independent Gaussian actions every control interval. Compare against the passive-only settled-motion test first.


## Horizontal chassis wiggle audit — 2026-08-07

The known-good standing mechanics remain protected. No body mass, joint frame, stiffness, damping,
torque limit, action schema, PPO exploration standard deviation, or control interval was changed in
this audit. Static inspection found two distinct contributors that must not be conflated:

- A fresh profile-v9 PPO policy samples sixteen independent Gaussian actions every 0.05 s. Twelve of
  those are joint targets, and the hip target limiter can move at 260 degrees/s. Real equal/opposite
  hip reaction torque therefore reaches the 3.2 kg chassis; visible exploratory horizontal/yaw
  twitch is expected even when the passive body itself is stable.
- The later ground-bracing patch accidentally bypassed the stock grip's authored
  `[climbable, carryable]` filter and allowed any stock `generic_grip` to anchor to tagged ground.
  A held static grip is a strong spring-damper world anchor, not ordinary friction, so intermittent
  activation could inject abrupt horizontal forces. Stock locomotion now follows the original
  explicit surface contract again: ground anchoring requires `ground` to be deliberately authored
  into the end-effector's compatible tags. Wall climbing and carrying are unchanged.

The `Joint command spam` reward now measures only the twelve joint-target channels. Grip activation
no longer dilutes that RMS smoothness signal. Its default reward-card intensity is unchanged to avoid
unannounced retuning of working policies. `four_limb_stability_test.gd` also reports passive-only
horizontal chassis speed explicitly, making the key diagnosis observable: passive horizontal motion
means physics/contact trouble; a quiet passive body plus a twitchy worker points at policy commands.

## Arena-boundary rules

The shared room deliberately has an open viewing side, but a ground body must treat the floor rectangle as a cliff:

- merge the arena rectangle into the existing directional obstacle feed as a virtual non-traversable boundary;
- use the same body-inflation margin as wall sensing;
- mark a target path as blocked when the straight path crosses the floor edge;
- terminate with `left_arena` before the load-bearing chassis footprint leaves the floor;
- terminate if the body falls substantially below the room;
- do not terminate merely for being tilted, upside-down, or chassis-supported while still inside the floor area, so recovery can be learned.

The virtual edge is model telemetry only. It must not add a visible wall or change drone collision geometry.

## Locomotion-reward rules

Target progress must represent useful legged locomotion rather than arbitrary translation:

- moving away from the target remains fully negative in every posture;
- positive progress is scaled by uprightness, standing-height quality, and useful foot-support ratio;
- positive progress becomes zero while the chassis has an upward-facing support contact with the ground;
- chassis-ground support receives a continuous `core_drag` punishment;
- a wall brush is still a collision/obstacle event but is not misclassified as chassis crawling;
- one-time collision penalties remain separate from continuous drag;
- survival stays much weaker than useful target progress;
- recovery states remain alive inside the arena.

Authoritative `core_support_contact` is separate from generic `core_contact` and `core_wall_contact`. The dedicated model feature reports load-bearing chassis contact under observation schema 9. Wall contact remains visible through obstacle/contact inputs.

## Jump reward hardening and joint protection — 2026-08-07

- Losing all foot contacts is only a jump candidate, not an immediate reward event.
- A candidate must begin from at least half-foot support after a short stable preparation window,
  exceed the minimum upward launch speed, remain airborne for at least 0.22 seconds, and increase
  chassis ground clearance by at least 0.16 m before takeoff or airborne-progress reward can pay.
- An unqualified support flicker ends silently: no launch, distance, or controlled-landing reward
  and no artificial landing punishment.
- Positive controlled-landing reward scales from zero until the jump has made meaningful
  target-directed horizontal distance, so repeated in-place jumping jacks cannot farm it.
- Long Jump built-in intensities are reduced from the former multi-point spikes to 0.40 launch,
  0.80 airborne progress, 1.50 distance, and 0.50 landing quality.
- `joint_overstretch` measures actual elevation/sweep/knee angles against each limb's authored
  physical limits. It has a short grace period, then ramps continuously; hip axes are weighted
  more strongly than deep knee flexion so momentary step/jump compression remains possible.
- Joint-limit diagnostics do not enter the policy tensor, so profile-v9 input/output and checkpoint
  compatibility remain unchanged.

Headless regressions cover contact-flicker rejection, qualified jump/landing reward, real joint-limit
punishment, rolling limb-model overwrite, and dead-worker camera exclusion. Run them with Godot 4.6
when that executable is available; do not install Godot in this workspace.

## Observation and action integrity

The model must be able to correctly analyze and control the body:

- full target offset including height, horizontal distance/radius, and full target-relative velocity;
- chassis pose, world-up projection, velocity, angular velocity, height, mass, health, and load-bearing core contact;
- 26 directional obstacle/arena-edge clearances plus target-path blockage;
- stable installed/functional limb masks;
- measured elevation, horizontal sweep, and knee angle;
- held rate-limited targets and angular velocities; wrapped target errors remain rich diagnostics but are not duplicated in the tensor;
- raw current/previous commands;
- total physical torque and saturation;
- distal-foot position, velocity, authoritative support, normal, clearance, slip, and wall contact;
- fixed attachment feed.

Validation rejects non-finite or wrongly typed observations/actions. The global action map must be dense: every output maps exactly once, with no duplicate mapping or hole.


## Jump, carrying, and climbing capability — 2026-08-06

- The protected standing mechanics remain theoretically capable of jumping; profile v9 adds grip
  without changing joint gains, masses, limits, rest geometry, or floor contact.
- The Long Jump cardset already supplies takeoff, airborne progress, landed distance, and landing
  quality signals. Live solver behavior still determines whether the present slew/torque envelope
  produces sufficient impulse.
- Ramps, stairs, step-ups, and ledge mantling remain plausible.
- Smooth-wall support is now physically possible only where the surface is tagged `climbable` and
  a grip is actually engaged. Ordinary friction-only contact remains insufficient.
- Carrying is physical: a dynamic target receives the equal/opposite holding force, has a mass
  limit, and can break away under excessive normal or shear load.
- Extra ankles, fingers, claws, or different limb counts still require new explicit model profiles.

Use live scenarios in addition to headless tests for jump impulse, attachment acquisition, wall
support, load sharing, breakaway, carrying, and landing recovery.

## Limb save and camera parity — 2026-08-07

- Shared-room limb group cards expose the same animated **Keep Newest** control as drone groups;
  it defaults on and provides separate **Save Best** and **Save Current** actions.
- Rolling limb saves increment one manifest revision instead of creating unlimited versions.
- A loaded model, branch, deleted rolling target, or changed body hardware starts a new group-owned
  rolling chain. Source checkpoints are never overwritten.
- Selected-group and all-worker camera centroids exclude finished, dead, invalid, and non-finite
  limb workers, matching the drone retirement behavior.

## Shared reward cardsets — 2026-08-06

The shared room uses typed green/red/amber cards, card-specific sliders, persistent preset tabs, and
cardset identity in group/checkpoint metadata. Built-ins are:

- drone: **Balanced Flight**, **Fast Target Chase**;
- limb: **Ground Locomotion**, **Long Jump**, **Item Pickup**.

Only **Item Pickup** spawns assigned carryable boxes. Its pickup card gives a small first-grab signal
and a larger one-time lift reward. The next cardset should be **Climbing / Grip**, after live data
shows useful ranges for attachment age, load ratio, breakaway, energy, body clearance, and vertical
progress. Reward presets configure learning signals; they must never silently rewrite physical body
definitions.

Detailed reviews:

- `docs/reward-cardsets-review-2026-08-06.md`;
- `docs/generic-grip-and-pickup-review-2026-08-06.md`.

## Source-backed implementation rules

1. Godot's `Generic6DOFJoint3D` supports independently locked/limited X, Y, and Z angular axes and independent angular springs with equilibrium, stiffness, and damping.
   Source: https://docs.godotengine.org/en/4.6/classes/class_generic6dofjoint3d.html

2. Godot's Jolt backend does not support Generic6DOF limit softness, restitution, damping, or ERP. Stability must not depend on those fields.
   Source: https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html

3. Continuous joint torque must be applied every physics update. Contact telemetry comes from direct body state, with body/collider point velocities, normals, and impulses.
   Source: https://docs.godotengine.org/en/4.6/classes/class_physicsdirectbodystate3d.html

4. In Godot 4, friction and bounce belong to `PhysicsMaterial`, assigned to a `RigidBody3D` through `physics_material_override`.
   Sources:
   - https://docs.godotengine.org/en/4.6/classes/class_physicsmaterial.html
   - https://docs.godotengine.org/en/4.6/classes/class_rigidbody3d.html

5. Learned legged-locomotion reward designs commonly expose joint angles/velocities, base orientation/angular velocity, previous actions, body velocity, and foot contacts. Their reward terms commonly include orientation/height tracking, foot slip, torque, base acceleration, and collision penalties. Chassis dragging therefore needs separate treatment from target progress.
   Source: https://www.nature.com/articles/s41598-024-79292-4

6. Recovery-oriented locomotion work shows why every tilted or fallen-but-recoverable state should not be unconditionally terminated. The hard terminal boundary here is leaving the physical floor, not body tilt alone.
   Sources:
   - https://research.google/pubs/safe-reinforcement-learning-for-legged-locomotion/
   - https://arxiv.org/abs/2203.02638

7. Joint-position targets remain an appropriate low-level learned control representation when the policy also receives base, joint, held-command, foot, and contact state.
   Sources:
   - https://arxiv.org/abs/2202.05481
   - https://arxiv.org/abs/2406.01152

8. `PhysicsDirectSpaceState3D.get_rest_info()` can provide the nearest shape-query contact, including collider identity, point, and normal. Generic grip acquisition should use that physics-space result rather than trainer-class lookups.
   Source: https://docs.godotengine.org/en/4.6/classes/class_physicsdirectspacestate3d.html

9. A continuous physical holding force must be applied every physics update, and a force position offset is expressed in global coordinates relative to the body origin. Dynamic carrying therefore applies bounded equal/opposite forces at both attachment points.
   Source: https://docs.godotengine.org/en/4.6/classes/class_physicsdirectbodystate3d.html

10. Jolt does not support `PinJoint3D` bias, damping, or impulse clamp. Grip load limits and breakaway must not depend on those unsupported properties; the generic grip uses explicit capped spring-damper forces instead.
    Source: https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html

11. A `Node3D` marked top-level does not inherit its parent's transform. `GenericLimbAssembly3D` uses this so it may remain a lifecycle child of a drone while its independently simulated rigid segments stay in world space.
    Source: https://docs.godotengine.org/en/4.6/classes/class_node3d.html

12. A single gripper architecture can serve both manipulation/carrying and climbing when it exposes attachment state, load limits, surface compatibility, and breakaway instead of hiding those mechanics behind task macros.
    Source: https://arxiv.org/abs/2312.04856

## Verification policy and current status

Godot is not installed in this workspace, so engine-side tests cannot be executed here. New regression tests may still be authored when a code change needs a durable contract, but they must be reported as **authored, not run** until executed in the user's Godot environment. Static contract checks and explicit runtime telemetry/manual scenarios remain mandatory for every pass.

Existing standing/generic tests retain:

- arbitrary 1-, 2-, and 4-segment limb construction;
- locked translations and bounded anatomical rotations;
- valid physical materials on core and all segments;
- native and explicit passive elasticity;
- static gravity torque headroom;
- passive-only standing, settling, disturbance, and recovery;
- complete finite observation and dense action mapping;
- direct input/output reachability.

Inherited profile-v7 additions:

- every hip X axis aligns with body up and every Z axis with radial elevation;
- output 0 maps to elevation and output 1 maps to actual horizontal sweep;
- stock horizontal sweep remains at least 70 degrees and is sanitized to at most 90 degrees;
- arena edges enter directional sensing and target-path blockage;
- chassis-footprint boundary crossing produces `left_arena`;
- sideways bodies inside the arena remain recoverable;
- positive target progress requires leg-supported posture;
- chassis-ground support produces continuous negative `core_drag` and zero positive progress;
- an upright wall brush is not treated as chassis dragging;
- `core_support_contact` is required, encoded, finite, and independently testable.

Runtime status: Godot is intentionally not installed. Run static parsing/consistency checks here and use the user’s live training room for behavioral verification. Regression tests added in this workspace are coverage for the next local/headless Godot run, not evidence that engine physics already passed.

## Next runtime checks

1. Start fresh profile-v9 groups; profile-v8 checkpoints are intentionally incompatible.
2. Open **Training Items**, place several authored carryables, enable **Item Pickup**, and confirm every four-limb worker can perceive the nearest authored item; when no authored items exist, the legacy per-worker fallback prop still appears for the pickup lesson.
3. Confirm grip activation is released at neutral/negative command and engages only a nearby
   compatible surface.
4. Confirm a carried item pushes/pulls back on the limb and breaks away when overloaded.
5. After breakaway, keep the command engaged to confirm the grip stays disarmed; release below the
   threshold and engage again to confirm rearming works and is visible in telemetry.
6. Confirm authored room items are genuinely shared physical objects (multiple workers can perceive the same item), while the legacy fallback prop remains owner-filtered when no authored items exist.
7. Confirm tagged walls can support a gripping limb while untagged ground cannot be gripped.
8. Switch to Ground Locomotion or Long Jump and confirm authored Training Items remain part of the room while only the legacy auto-spawn pickup props disappear.
9. Inspect grip candidate point/normal, attachment state, target mass, and load ratio before tuning
   acquisition radius or holding force.
10. Confirm ordinary `ServerItem` instances expose their definition's default `carryable` tag and
   that a definition with `grippable = false` is rejected even by an unrestricted generic grip.
11. Install a `DroneLimbAttachmentDefinition` on a test drone and exercise its direct attachment
   command/state API before creating a combined drone-manipulator ML profile.

## Work log

- 2026-08-06: Replaced the failed PhysicalBone-based limb worker with generic rigid segments, Generic6DOF constraints, and one generic limbs controller.
- 2026-08-06: Added hybrid passive impedance, nonlinear hardening, arbitrary segment counts, and passive standing/recovery tests.
- 2026-08-06: Corrected the original load-bearing hip frame and distal-foot spawn-height offset.
- 2026-08-06: Fixed invalid direct `RigidBody3D.friction`/`bounce` assignments by creating `PhysicsMaterial` overrides.
- 2026-08-06: User confirmed the generic elastic bodies stand correctly; preserved all known-good standing parameters.
- 2026-08-06: Audited model I/O, added strict finite validation, exact controller diagnostics, authoritative distal support/slip, and passive-jitter tests.
- 2026-08-06: User observed open-edge falls, stiff crab motion, and a chassis-rolling “jellyfish” exploit while also confirming strong passive posture retention.
- 2026-08-06: Reframed the hip as body-up horizontal sweep plus radial elevation, widened stock sweep to ±72 degrees, and versioned profile/action/observation semantics.
- 2026-08-06: Added virtual arena-edge sensing and `left_arena` termination while preserving in-arena recovery states.
- 2026-08-06: Added posture/support-gated positive progress, continuous chassis-drag punishment, and separate authoritative chassis support contact.
- 2026-08-06: Added explicit profile-v6 checkpoint rejection, target-path edge regression, and schema-3 action labels for hip elevation and horizontal sweep.
- 2026-08-06: Reviewed jump and climbing capability. Jumping is physically plausible but unproven and currently discouraged by the ground-only observation/reward contract; smooth-wall climbing requires explicit grip/adhesion hardware. Added a staged capability-test, parkour-profile, and generic end-effector plan.

- 2026-08-06: Advanced to profile v8, removed 16 old constant/exactly redundant inputs, added one full-3D distance feature, restored limb target height/vertical relative motion, and added empirical limb rollout correlation/rank auditing.
- 2026-08-06: Added generic per-limb end-effector definitions/runtime shapes and optional generic grip-action mapping without changing the stock 12-action body or adding hidden adhesion.

- 2026-08-06: Reduced the limb tensor conservatively to 300 features, restored full target-height/vertical-motion information, added low-cadence rollout correlation/rank diagnostics, and integrated independent generic end-effector definitions without changing stock standing physics.
- 2026-08-06: Added shared typed reward cards, per-card sliders, persistent body-specific cardset tabs, built-in drone/limb presets, and a Long Jump limb cardset with takeoff/flight/distance/landing signals. At that revision, stock end effectors remained disabled.

- 2026-08-06: Advanced to profile v9 (398→16), added four physical grip outputs, assigned-item/grip observations, bounded generic grip forces with breakaway, an Item Pickup cardset/reward, and a ServerDrone generic-limb attachment bridge. Stock extra end-effector geometry remains disabled.
- 2026-08-06: Extended the generic surface contract to normal gameplay items: `ItemDefinition` now owns `grippable` and surface tags, `ServerItem` publishes them, and explicit item opt-out is authoritative.
- 2026-08-06: Added breakaway rearming telemetry, per-worker pickup-object ownership filtering, and reserved no-op action slots so missing limbs or passive/no-grip terminal definitions do not invalidate the fixed profile-v9 controller.
- 2026-08-06: Final grip review made health authoritative even for passive grips and added configurable host/segment self-collision exclusion to generic drone limb assemblies, preventing damaged latches and appendage self-jamming.
- 2026-08-08: UI pass 14 standardized ML SpinBox arrow acceleration, exposed live network dimensions in compact limb/drone/turret cards, wrapped the long limb identity row, and made the tracked standalone limb library windows start hidden.
- 2026-08-08: Standardized training pause semantics around the four-limb reference behavior: generic limbs attached to drones now freeze without releasing an established grip during an ordinary training pause; configuration/reset paths still use the normal release/rebuild behavior.
- 2026-08-08: Added generic authored `TrainingItem3D` room objects built on the existing carryable grip contract. Training Items support obstacle-style primitive shape/dimension editing with linked equalizer controls, real rigid-body mass, intrinsic reward value, continuous mouse placement, stable task ids, shared spatial-hash discovery, map persistence, and future target-provider candidates for take/deliver tasks. Four-limb observation schema 14 adds item reward value (420 inputs), and the existing Item Pickup reward scales by the authored item value.
- 2026-08-08: Item pass 23 made pickup lift credit worker-local, added the Item Pickup lesson to deterministic limb evaluation when enabled, and froze private/shared held item physics coherently across worker pause.
- 2026-08-08: Deep item pass 24 hardened authored-spawn editing, shape/radius semantics, cargo-pickup target priority, malformed map/physics recovery, continuous-placement/editor ray behavior around fallback props, frozen-item task velocity, and lost-item recovery with explicit RL episode boundaries.
- 2026-08-09: Pre-test item/destination pass 29 corrected delivery containment to use exact oriented primitive height instead of bounding-sphere height, made lost-item recovery independently spawn-aware per axis with an upper-Y escape envelope, and made configuration-driven limb teardown release shared cargo grips before rig destruction. Added regressions for all three contracts.
- 2026-08-09: Creator-readiness pass 34 hardened resource-backed body persistence: Walker slot `.tres` files remain authoring inputs while synthesized `GenericLimbDefinition` parts retain the generic-limb template as their reconstructible snapshot backing; stale wrong-class backing paths now fail over to the encoded script without being re-persisted. Drone, Walker, and Turret creator drafts are isolated deep copies, and copied training items/drone parts preserve their authored `.tres` provenance for reopen, inspection, and network/UI state.
- 2026-08-09: Creator UI pass 35 removed `DroneTrainingRoom`'s direct dependency on the four-limb rig for held-item queries and broke the concrete body↔rig class cycle that caused external-member resolution failures. The Worker Groups `+` now opens the first orange Model Body Creator: presets/Cores and compatible serialized `.tres` parts are editable through the shared body contract, accepted builds are round-tripped through their family runtime adapter before group creation, and four-limb Core attachment ports remain explicitly read-only until the runtime has a generic serialized attachment installer.
- 2026-08-09: Creator setup pass 38 restored fresh-model controls inside the orange Model Body Creator (algorithm where supported, immutable hidden width/depth, starting worker count, control rate, exploration, reward-card preset, and start-paused/start-now). Training-room startup no longer creates an implicit drone group. The room-level episode readout now represents the one shared episode-duration setting instead of rendering one duration/progress row per body family, while each group card keeps its own rollout episode counter. Drone candidate nomination now retains a bounded exact-resource cache keyed by frozen evaluation-contract hash (protecting both pending candidates and the trainer contract of an optimizer that can finish after pause) so fixed-seed verification remains independent of pause-time live hardware edits.
- 2026-08-09: Evaluation/creator bug-hunt pass 39 fixed the hidden turret-exposure fixtures used by both drone and four-limb fixed-seed evaluation: every evaluator threat turret now validates and receives an isolated Stationary Turret preset before `_ready()`, turret resets fail closed on invalid bodies, the normal turret trainer/evaluator also validate copied bodies before reset, and failed environment fixtures preserve their actual evaluator error instead of being mislabeled as an unsupported scenario. Four-limb pickup fixtures now fail closed as well. The orange Model Body Creator now sizes from realized content, reserves a content-driven attached-parts scroll region, clamps/centers itself inside the game viewport, and no longer lets long OptionButton entries inflate its opening width. Delivery-destination placement reuses its preview mesh/material instead of allocating them on every mouse move.
- 2026-08-10: Factory/runtime pass 40 audited creator → accepted manifest → trainer → live actuator routing. Drone workers now fail closed at spawn when a finalized control/observation channel has no real runtime consumer/provider; generic limb assemblies expose mapping-valid preflight rather than only comparing action counts. The legacy Utility Manipulator Arm resource is now a real `DroneLimbAttachmentDefinition` backed by the generic articulated arm, so its shoulder X/Z, elbow Z, grip controls and limb observations are part of the accepted neural contract. Generic limb reset now stores Core-local rest transforms and rebuilds world poses from the host's current transform, fixing drone arms snapping toward their construction-time world position after episode teleports. Degraded-propeller evaluation now disables thrust without deleting an accepted propeller slot, preserving body/action topology. The creator uses one full-dialog vertical scroll surface and labels parts with their declared ML control/observation counts (or passive/no-control status).

### Pass 41 creator/attachment reset invariant
- The Model Body Creator keeps its Cancel/Create footer outside the scrolling form; realized slot rows must never reserve stale blank height after a preset/Core rebuild.
- Generic articulated hosts store both segment and joint rest transforms in Core-local space. Episode/reset teleports rebuild the complete constraint graph from the Core's current transform; moving only the RigidBody segments is insufficient for drone-mounted limbs.
- Propeller failure/degradation resolves authored slot ids through the runtime slot table rather than assuming slot id == array index.

### Pass 42 staged creator / authored mount invariant
- The creator-facing drone arm is canonicalized as `resources/drones/attachments/utility_arm.tres`; the old top-level Training Belly attachment wrapper is removed. Its nested GenericLimb segment/joint/gripper resources remain the implementation of that one arm, not separate selectable attachments.
- Drone creation is now staged: choose the physical Core and author Core-local attachment-slot transforms in a rotatable 3D preview, then Accept the Core layout and assign hardware/training settings in a second step. Fresh hardware slots begin empty; required slots must be explicitly filled before creation. Every drone attachment mount explicitly placed in Step 1 is required in Step 2; remove the mount in Step 1 if the final body should not carry hardware there.
- Creator-authored attachment slots store a full Core-local `Transform3D` (position + orientation). That transform must survive `DroneLoadout` copies, frozen evaluation hardware records, ServerDrone collision/limb mounting/inertia, and client proxy state. A side-mounted articulated limb therefore changes its mount basis as well as its offset.
- The worker preflight compares live attachment mount transforms against the accepted manifest, so a body whose physical slot placement drifted after Accept cannot train under a topology-compatible but physically different creator body unnoticed.
- The creator uses one outer vertical `ScrollContainer`; the Core preview passes unhandled wheel input upward, hardware rows do not create a nested scroller, and the Cancel/Back/Create footer stays pinned outside the scroll surface.
- Mirrored placement is transactional: mirror-next either adds a valid symmetric pair or adds nothing. Replacing a physical Core invalidates transforms authored against the previous chassis; exact copied/frozen bodies reapply their serialized transforms afterward. A successful Create clears the reusable Window draft so the next `+` starts a fresh body instead of inheriting the previous group layout.

### Pass 43 Core-authored drone topology invariant
- The Model Body Creator has no body-family `OptionButton` at all. The selected physical Core chooses the current runtime adapter internally; for drone Cores, the Core plus the Step-1 mount layout is the body-authoring authority.
- A drone Core contributes one intrinsic battery slot and a total non-intrinsic mount budget only. Propeller and attachment slots are not materialized from legacy Core propeller/attachment counts. Every such Step-2 slot must come from an explicitly placed and typed Step-1 marker.
- Step-1 drone markers are typed before placement (`propeller` or `attachment`), use LMB to place/select, RMB to remove the pointed marker, MMB drag to orbit, and Ctrl+wheel to zoom. Mirroring preserves slot kind and orientation.
- Propeller mount transforms are part of the accepted body contract and persist through `DroneLoadout`, runtime spawning, replication, checkpoints, and fixed-seed evaluation. Propeller local +Y is the thrust axis and is oriented outward from the clicked Core surface; articulated attachments keep their established outward = local -Y convention. Rotor ground-effect probing follows the opposite of each real lift axis rather than assuming world-down, so side/diagonal creator rotors do not receive floor-based lift bonuses.
- PPO may own zero to four explicitly authored propeller controls plus generic attachment controls. Creator-authored rotor geometry is exposed to PPO feedback through real local rotor positions, lift axes, and spin directions. SAC/SAC-HER remain restricted to the canonical stock four-corner rotor geometry because their structured warm-up mixer assigns fixed physical meaning to the four action indices.


### Pass 44 creator-authored articulated limb / spider invariant
- Drone Core attachment mounts no longer have a creator or `DroneCoreDefinition` hard ceiling. Step 1 may author any number of typed attachment transforms; the Core stores that exact count, `DroneLoadout` keeps every transform, and `ServerDrone` creates attachment collision shapes dynamically beyond the four legacy scene placeholders. Propellers remain separately capped at four by the current flight runtime.
- A Core may intentionally have zero propeller mounts. PPO accepts zero-to-four propeller feedback entries and may train a leg-only body as long as some installed hardware contributes model controls; SAC/SAC-HER remain stock-quad-only. This is the generic spider path rather than a special spider body class. Fixed-seed evaluation derives this from the frozen hardware contract and omits the impossible degraded-propeller scenario for zero-rotor bodies; loadout summaries likewise report them as articulated ground bodies rather than incomplete drones.
- The hardware stage exposes the actual nested `GenericLimbDefinition` inside a `DroneLimbAttachmentDefinition`. Segment count edits resize the serialized segment array, per-segment length/radius/mass edits mutate the physical `LimbSegmentDefinition`, and terminal selection swaps the real `LimbEndEffectorDefinition`; control/observation topology is therefore regenerated from the edited body rather than mirrored in UI-only state.
- `Configurable Articulated Limb` is a resource-backed creator part with a two-axis proximal joint, a distal articulated segment, and a normal-sized plain foot. Additional segments are cloned from the generic articulated-segment `.tres` template and receive dense action mappings when the attachment is assembled.
- Terminal hardware templates are resource-backed and currently include no effector, Plain Foot Pad, Passive Grip, and Controlled Grip. A controlled grip adds its own policy output through the existing generic limb contract.
- The old standalone Four-Limb Walker remains a two-segment compatibility adapter. Its direct `GenericLimbDefinition` slots are not exposed through the new arbitrary geometry editor because that adapter would average/drop authored per-segment data. Arbitrary serial limb topology is authoritative on generic Core-mounted articulated attachments.
- Regression coverage now includes an eight-attachment, zero-propeller creator layout and a five-segment edited drone limb with independent dimensions and terminal-control topology. Godot is not installed in this workspace, so these tests are authored but not executed here.

### Pass 45 articulated-limb performance invariant
- Generic Core-mounted articulated limbs use the low-overhead rigid-body defaults: sleeping is allowed and contact monitoring/contact buffers are disabled unless a host explicitly requests them. The legacy standalone Four-Limb Walker opts back into always-awake/contact-reporting behavior because its support/contact reward path still consumes those contacts.
- PPO observation encoding for generic limb attachments reads the instantiated `GenericLimbAssembly3D` directly. It must not deep-duplicate the limb Resource tree or build a nested assembly/limb/segment/joint snapshot merely to encode the accepted tensor. Debug/compatibility snapshots remain available on demand.
- Generic `LimbsController3D` instances keep typed live joint state and do not rewrite diagnostic Dictionaries every physics frame. The legacy four-limb adapter explicitly retains per-frame Dictionary publication until its older observation/reward code is migrated to the typed path.
- Plain/no-grip terminal hardware does not instantiate `GenericGrip3D`; controlled/passive grip hardware keeps the existing physical candidate-query and breakaway behavior.
- `ServerDrone` caches its articulated attachment slot order, bypasses descriptor reconstruction during limb action preflight, caches aggregate non-weapon idle attachment power, and skips weapon cooldown/fire bookkeeping when the body has no weapon attachment. Articulated limbs keep their authored electrical draw without forcing an eight-slot Resource scan every physics frame.
- Current regression target is two PPO workers with eight articulated attachment limbs each at 1x simulation speed. Godot is intentionally unavailable in this workspace, so this pass removes verified hot-path allocations/physics bookkeeping and authors regressions, but the actual frame-time improvement must be measured in the user's Godot 4.6 training room.
