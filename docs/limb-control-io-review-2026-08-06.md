> Historical note: the standing and I/O audit remains relevant, but its profile-v6 hip labels were first superseded by profile v7: `[hip elevation, hip horizontal sweep, knee]`. See `docs/limb-system-working-plan.md`.

# Four-limb control and model-I/O review — 2026-08-06

## Protected runtime baseline

The user confirmed that the generic elastic-limb body now stands in the intended broad spider pose. This review treats that as a protected baseline. It does **not** change:

- rest geometry, spawn height, masses, collision shapes, friction or bounce;
- joint frames, anatomical limits, solver priority or native-spring share;
- passive stiffness/damping, active stiffness/damping or torque limits;
- PPO exploration, decision interval, observation dimensions or action dimensions.

The physical spring/torque calculation that produced the successful standing result is also preserved. The review only exposes more accurate telemetry from that controller and hardens the model boundary around it.

## Jitter assessment

A newly created PPO worker is expected to look substantially less quiet than a neutral passive body. The fresh policy samples twelve independent Gaussian latent actions every `0.05` seconds. Its initial standard deviation is `exp(-1.4) ~= 0.247`; those samples are converted through `tanh` and repeatedly move the held joint targets. That is enough to create visible exploratory twitching even when the passive body itself is stable.

The stability test now measures passive-only chassis and limb motion for sixty frames after the body has already settled for 240 frames. This gives a direct runtime distinction:

- passive test quiet, fresh worker jittery → policy exploration / command changes;
- passive test also jittery → solver, contact or impedance tuning issue.

No standing parameter was changed based on the screenshot alone.

## Sources checked

1. Godot 4.6 `PhysicsDirectBodyState3D`
   - Continuous torque is a force intended to be submitted every physics update.
   - Contact counts require monitored contacts.
   - Direct body state exposes the body-side and collider-side velocity at each contact point, the contact normal and the contact impulse.
   - Despite the legacy `get_contact_local_normal()` name, the returned 3D normal is in global space; an open Godot documentation issue tracks that wording.
   - https://docs.godotengine.org/en/4.6/classes/class_physicsdirectbodystate3d.html
   - https://github.com/godotengine/godot-docs/issues/10678

2. Godot 4.6 `Generic6DOFJoint3D`
   - Angular springs have independent equilibrium, stiffness and damping parameters per axis.
   - https://docs.godotengine.org/en/4.6/classes/class_generic6dofjoint3d.html

3. Godot 4.6 Jolt limitations
   - Generic6DOF limit softness, restitution, limit damping and ERP are unsupported by Jolt. The limb system does not rely on them.
   - https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html

4. Learning-based legged-locomotion literature
   - Joint position targets are a common low-level action representation.
   - Useful proprioception includes joint state, base pose/projected gravity, base velocity, foot/contact state and the action/actuator state held between decisions.
   - https://arxiv.org/abs/2202.05481
   - https://arxiv.org/abs/2406.01152

## Concrete findings and corrections

### 1. Preserve the working physical controller; expose its exact error

For a joint with simultaneous twist and swing, the shortest physical relative rotation is not generally identical to subtracting two decomposed swing/twist vectors component by component. Replacing the physical controller with component-wise subtraction would therefore be a risky change after the user confirmed that the body stands.

The controller remains in its known-good form:

1. build the desired relative joint rotation;
2. compute the shortest quaternion rotation from measured to desired pose;
3. project that physical error onto the joint's X/Y/Z axes;
4. apply bounded spring-damper torque on each free axis.

The review adds only telemetry. `LimbsController3D` now records the exact projected active and passive errors it actually used, and `FourLimbPhysicalRig3D` exposes those values as rich diagnostics in the external fixed order `[hip swing, hip twist, knee]`. The encoded schema-6 `joint_target_errors` value deliberately keeps its existing wrapped joint-coordinate meaning (`target - measured`) so saved policies do not receive an unannounced semantic change. Standing mechanics and checkpoint tensor meaning remain unchanged.

### 2. Replace ray-only foot contact with real distal support contact

The former `foot_contact` flag was primarily a downward-ray proximity estimate. That can report a foot as supported when the distal rigid segment is not actually touching anything, and a generic per-limb contact count can include upper-segment or self contact.

The shared contact snapshot now records per limb:

- external contacts on the distal rigid segment;
- contacts whose normal has an upward component and can actually support the body;
- the strongest support normal;
- tangential velocity of the foot contact point relative to the contacted body;
- existing wall contact counts and impulses.

Own-rig collider RIDs are excluded from support detection. A vertical wall touch is not counted as foot support, while an upward-facing surface can support the body even when it belongs to obstacle geometry. `foot_contact`, `ground_normal_local` and `foot_slip_speed` use this authoritative contact information when a shared contact snapshot is present. The downward ray remains a fallback for isolated diagnostics.

### 3. Reject bad sensor snapshots before reward and inference

The feature encoder deliberately clamps values to protect tensor math. Without complete validation, a non-finite sensor value could be converted into a plausible zero and become training data.

`FourLimbMLObservation.is_valid()` now checks:

- the complete finite chassis transform, position, basis, linear/angular velocity, support data, health and mass;
- four stable limb slots in the correct order;
- finite joint angles, held targets, wrapped joint-coordinate target error, relative angular velocities, commands, torque and foot state;
- structurally valid booleans and non-negative contact counts;
- finite target state and all 26 obstacle clearances;
- exact fixed attachment-feed length and finite attachment features;
- finite non-negative action age.

`FourLimbMLBodyAdapter` validates the complete snapshot before returning it. This is important because the adapter output is consumed by both reward calculation and policy inference. An invalid physical sample now becomes an explicit worker fault rather than a zero-like state.

### 4. Harden the twelve-output action mapping

The action decoder already verifies all twelve unique `(limb, axis)` numeric slots. It now also verifies that limb/axis identifiers are actual integers, targets are actual finite numbers, and each entry's descriptive `axis_name` agrees with its numeric axis. A malformed action cannot claim to be a knee command while occupying a hip slot or rely on implicit string/float coercion.

The generic `LimbsController3D` now rejects both duplicate mappings and sparse mappings with unused holes. For the stock body, all twelve dense policy outputs must map to exactly one physical joint axis before any command is accepted.

The actual control contract is unchanged:

- four limbs;
- `hip swing`, `hip twist`, `knee bend` per limb;
- twelve normalized `[-1, 1]` joint-position targets;
- rate-limited targets followed by bounded impedance torque;
- no gait, walk, turn, foot-placement, chassis-force or hidden recovery action.

## Current model input contract

The encoder remains observation schema `6` with exactly **315** normalized features:

- 67 global/body/objective/obstacle features;
- 68 fixed attachment features (`4 x 17`);
- 180 limb features (`4 x 45`).

The policy can distinguish:

- horizontal target offset, direction, distance, radius, boundary error, inside-radius state and target-relative velocity;
- core linear/angular velocity in body coordinates and projected world-up/body orientation;
- actual and preferred standing height, height error, chassis contact, uprightness, health and mass;
- nearest obstacle direction/distance/closing speed, target-path blockage and 26 directional clearances;
- for each stable limb slot: installation/function/health, socket offset, segment lengths, measured angles, held targets, wrapped joint-coordinate target error, joint angular velocities, current command, applied torque, command saturation, foot pose/velocity, real support contact, support normal, clearance, relative slip and wall impacts;
- fixed attachment installation/category/mass/health/payload data.

The model sees both the current normalized command and the smoothed target currently held by the physics controller. Therefore the actuator state between 20 Hz decisions is represented without adding a new history tensor or changing old checkpoint dimensions. `previous_commands` remains available in rich diagnostics but is not encoded in this compatibility-preserving pass.

## Deliberately unchanged

- The successful standing body and all physical tuning values.
- Generic arbitrary-length limb topology and future creature-editor direction.
- PPO standard deviation and the `0.05` second control interval.
- Feature count, action count, schema versions and checkpoint shape.
- Applied-torque feature scaling. It can clip at very high torque, but changing its normalization would change the meaning of an existing feature and should be done only as an explicit future schema revision.
- Applied torque currently means the complete torque physically acting at the joint: passive rest-pose torque, active model torque and soft-limit resistance. That is appropriate body-state telemetry. The existing small reward effort term therefore also observes total physical torque; changing it to active-only effort would be a separate reward-design change and was deliberately not folded into this compatibility review.
- Target height is intentionally omitted from locomotion direction features; this body is a ground platform and follows the target horizontally even when the shared room target has a different Y coordinate.

## Regressions added

- Pure joint twist and swing map to the correct physical torque axes.
- Live quaternion-controller error is exposed exactly in diagnostics while the encoded schema-6 coordinate-error meaning remains unchanged.
- Mislabeled, coercible, duplicated and sparsely mapped output slots are rejected.
- Non-finite chassis, joint and obstacle-ray data are rejected.
- The body adapter rejects corrupt samples before reward/inference.
- Chassis motion, joint state and foot state each change the encoded tensor.
- The live assembled body yields a complete finite normalized observation.
- Contact arrays reserve support count, normal and relative-slip data for every limb, and supported feet report zero clearance.
- Only upward-facing external distal contacts count as support.
- Passive-only standing must settle below conservative chassis/limb motion thresholds.

## Runtime verification still required

Godot is not installed in this environment and was not downloaded or installed. Run with the user's existing Godot installation:

```text
godot --headless --path . --script res://tests/generic_limb_test.gd
godot --headless --path . --script res://tests/four_limb_stability_test.gd
godot --headless --path . --script res://tests/four_limb_ml_test.gd
```

The most useful runtime comparison is one neutral passive body against one fresh stochastic worker. Record the passive test's printed mean chassis linear speed, chassis angular speed and limb angular speed before changing any spring setting.
