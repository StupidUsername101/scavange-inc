# Limb system review — 2026-08-06

## Observed state

The paused worker displays the intended four-legged spider stance, so the authored hip mounts, target feet, and two-bone solve are broadly plausible. Once the episode runs, the chassis falls and the legs fold over or under it. The latest screenshot is consistent with a joint-space/load-path failure: the parts remain connected and mobile, but the articulated structure does not present useful resistance in the directions needed to carry the chassis.

## Differences from the source guidance

| Area | Former/current problem found | Source-backed expectation | Correction |
|---|---|---|---|
| Physical representation | The old worker depended on Skeleton/PhysicalBone offsets, joint offsets, a separate controller, and virtual stance forces. Several coordinate systems could disagree. | A Generic6DOF joint can directly constrain independent rigid parts on all six axes. | Four-limb physics is now a compatibility adapter over generic rigid segments and Generic6DOF joints. |
| Hip coordinates | The first generic attempt aligned X twist correctly but chose its free Z swing axis from an arbitrary helper basis. The allowed bending direction was not guaranteed to match the leg plane. | Jolt uses X as twist and Y/Z as swing. A one-axis swing must be oriented in the intended anatomical plane. | X follows the upper segment. Z follows `upper_direction × lower_direction`, the authored bending-plane normal. Y is locked. |
| Passive behavior | Pose resistance was either too weak, dependent on explicit controller timing, or mixed with virtual foot forces. | Angular spring torque is stiffness × angle error plus damping × angular-velocity error. Flexible-joint impedance uses stiffness and damping as the mechanical target. | Every free joint has permanent passive impedance. A share runs natively in Jolt and the controller supplies the bounded remainder. |
| Extreme folding | A purely linear spring can remain easy to fold near a large command if active torque is comparable. | Real/compliant mechanisms often combine passive and active stiffness; the useful behavior is compliant near neutral and resistant near extremes. | Passive stiffness now hardens quadratically after a configurable range fraction, while retaining torque caps. |
| Soft limits | Previous code attempted to tune joint softness/bias-style properties. | Godot documents Generic6DOF limit softness, restitution, damping, and ERP as unsupported by Jolt. | Hard solver limits remain authoritative; a separate bounded soft-stop torque acts before them. Unsupported properties are not relied upon. |
| Episode release | Spawn height treated the authored distal foot offset as if it were a segment center and added radius again. | The constructed capsule already ends at the authored distal point. | Spawn height is now `-rest_foot_offset.y + clearance`, removing the initial extra drop. |
| Tests | Earlier tests proved formulas and force budgets but did not prove the real assembled body stood without policy authority. | Load-bearing behavior must be verified in the actual solver with contacts. | New headless tests disable all model actuators, settle the real nine-body rig, check height/uprightness/spread/contact, disturb it, and check recovery. |
| Future anatomy | Four fixed two-part legs were embedded in the physical implementation. | A creature editor needs independent parts, per-joint definitions, and variable topology. | `GenericLimb3D` supports any positive segment count; `LimbsController3D` accepts any number of chains and derives/validates action mappings. |

## The key load-axis finding

For a diagonal spider leg, vertical ground reaction produces a hip torque perpendicular to the plane containing the upper and lower segments. The previous free swing axis was not derived from that plane. Static analysis of the default front-right leg showed a substantial part of the required support torque appearing in the wrong joint coordinates. This meant increasing generic stiffness alone did not guarantee that the stiffness opposed the actual collapsing motion.

The corrected basis is:

```text
X = normalized upper segment direction
Z = normalized cross(upper direction, lower direction)
Y = normalized cross(Z, X)
```

This matches Jolt's X-twist/YZ-swing convention and makes Z the four-limb adapter's sole free hip swing axis. A regression test now calculates the gravity-support torque and fails if meaningful load projects into locked Y.

## New generic limb structure

```text
Creature/core rigid part
  └─ LimbsController3D
       ├─ GenericLimb3D
       │    ├─ LimbSegment3D + Generic6DOFJoint3D
       │    ├─ LimbSegment3D + Generic6DOFJoint3D
       │    └─ ... arbitrary part count
       ├─ GenericLimb3D
       └─ ... arbitrary limb count
```

Definitions are separate from runtime parts:

- `GenericLimbDefinition` owns mount position and a segment array.
- Each `LimbSegmentDefinition` owns geometry/mass and the joint connecting it to its parent.
- Each `LimbJointDefinition` owns axes, limits, action indices, passive impedance, active impedance, and soft-stop behavior.

This mirrors the project's drone pattern: physical parts have definitions; the assembled body owns them; a dedicated controller translates model outputs into forces/torques.

## Passive elasticity model

For each free axis, the controller computes a rest-pose error and relative angular speed. The baseline behavior follows the spring-damper form:

```text
torque = stiffness × angular_error - damping × relative_angular_speed
```

A configured fraction of baseline stiffness/damping is assigned to Jolt's native angular spring. The explicit controller applies the remainder and adds a quadratic progressive term after the onset ratio. Parent and child receive equal and opposite torques. Active/model torque is calculated separately against the commanded target. Therefore:

- no input returns toward rest;
- a damaged actuator can lose command authority without becoming a lifeless hinge;
- commands must overcome the body's intrinsic elasticity;
- large deviations become increasingly resistant;
- there is no hidden walk, turn, foot-placement, or chassis-lift command.

## Strength checks

The new tests calculate the default body's total gravity load, distribute it across four legs, and estimate the worst hip torque. They verify:

- support torque aligns with free hip Z;
- passive torque caps have at least fourfold headroom over the estimate;
- expected linear spring deflection is under twelve degrees;
- progressive edge resistance is substantially stronger than the linear spring;
- native and explicit passive components are both present;
- runtime solver spring flags and gains match the definitions.

The physics regression then disables all model actuator effectiveness, uses neutral commands, and releases the real body onto a floor. After 240 frames it checks finite state, at least 75% of authored height, uprightness of at least 0.85, no core-floor contact, and at least 65% of authored outward foot spread. It then applies an impulse and repeats the standing checks after 180 recovery frames.

## Remaining uncertainty

The code and static load path have been reviewed, but the headless physics tests could not be executed here because Godot is intentionally not installed. Consequently, this change addresses specific discovered defects and supplies executable regressions, but runtime success should be confirmed in the user's Godot environment. If it still fails, the next step is telemetry-driven gain tuning—not another coordinate-system rewrite or hidden support force.

## Sources kept for future work

- Godot 4.6 `Generic6DOFJoint3D`: https://docs.godotengine.org/en/4.6/classes/class_generic6dofjoint3d.html
- Godot 4.6 Jolt differences: https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html
- Jolt swing/twist decomposition: https://jrouwe.github.io/JoltPhysicsDocs/5.3.0/class_swing_twist_constraint_part.html
- Jolt spring/motor architecture: https://jrouwe.github.io/JoltPhysics/
- Ott et al., passivity-based impedance control of flexible-joint robots: https://elib.dlr.de/55366/1/Impedance_Control-Ott.pdf
