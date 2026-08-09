> Historical note: this review describes the profile-v6 standing fix. The active profile-v9 grip/carry contract and inherited hip/arena/reward corrections are documented in `docs/limb-system-working-plan.md` and `docs/limb-locomotion-boundary-review-2026-08-06.md`.

# Four-limb physics review

Reviewed: 2026-08-06

## Reported symptom

The authored pose is broad and spider-like while physics is paused, but the live body rapidly
loses height and folds its feet beneath the chassis when an episode starts. Pausing stops the
physical-bone simulation and displays the authored skeleton pose, so the paused view is useful
for checking construction but does not prove that the live constraints and motors can hold it.

## Engine and implementation differences found

### 1. Hip constraint axis disagreed with the controller

Godot's `ConeTwistJoint3D` uses joint-local X as its twist axis. The model/controller contract
uses upper-segment local Y, the segment's long axis, for hip twist. Upper physical bones were
created with an identity joint basis, making the constraint twist around local X while the motor
commanded local Y.

**Correction:** create a dedicated hip joint basis whose local X aligns with the upper segment's
local Y. Runtime validation and tests now reject a mismatched frame.

Source:
- https://docs.godotengine.org/en/stable/classes/class_conetwistjoint3d.html

### 2. Configured joint softness was inactive under Jolt

The project uses Jolt Physics. Godot 4.6 documents `bias`, `softness`, and `relaxation` as
unsupported for both `HingeJoint3D` and `ConeTwistJoint3D`; non-default values only produce a
warning. The rig set all of these values and therefore appeared more constrained in code than it
was in the running engine.

**Correction:** stop setting unsupported parameters. Explicit PD torques and the independent
hard-limit controller are now the authoritative stiffness, damping, and limit protection.

Source:
- https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html#joint-properties

### 3. The intended standing pose had no gravity support

The previous vertical stance spring produced force only after the foot moved away from its
intended height. At the exact authored pose its force was zero, although the complete body still
weighs roughly 61 N. The chassis therefore had to fall and compress the pose before the spring
could react. With the former 85 N/m vertical stiffness, carrying one quarter of the body weight
required substantial displacement even before solver losses and limb geometry were considered.

**Correction:** add a configurable gravity preload. Each functional leg receives its share of
body weight as a downward foot force, with the equal upward reaction applied to the chassis. This
keeps net internal force balanced while allowing the floor contact to support the complete body
at the authored pose. Load is redistributed across the remaining functional legs.

### 4. Passive and active holding strength were too soft for the intended body

The old neutral-pose bias and stance gains were sufficient to create visible torque but not to
prove that the assembled body could retain height and foot spread. Formula-level tests checked
only that force existed and stayed below a cap.

**Correction:** increase default hip/knee PD strength, passive neutral-pose stiffness, outward
stance stiffness, vertical stance stiffness, damping, and force caps. The policy still owns the
same twelve direct targets; no gait command or hidden movement controller was added. This
retains the project's existing impedance-style spring/damper control, which is consistent with
legged-robot controllers that render support through joint stiffness and damping rather than
leaving torque-controlled joints mechanically limp.

Source:
- https://www.frontiersin.org/journals/robotics-and-ai/articles/10.3389/frobt.2022.874290/full

### 5. Exploratory policy output was applied immediately on spawn

A fresh episode sampled PPO before the physical body had settled onto the floor. An untrained
sample could command all twelve axes at once during the first physical contact transient.

**Correction:** hold neutral targets for 0.35 seconds before the first policy sample. Settling is
not counted as episode or reward time, so this does not reward passive waiting or shorten the
training attempt.


### 6. Joint limit units were checked and left unchanged

Godot's `PhysicalBone3D` inspector-facing cone and hinge limit properties use degrees and convert
them to radians internally when the joint is configured. The limb definition already stores and
passes degrees, so changing these values to radians would have made the limits incorrect.

**Correction:** none. This was verified specifically to avoid "fixing" a part that was already
correct.

Source:
- https://github.com/godotengine/godot/blob/4.6-stable/scene/3d/physics/physical_bone_3d.cpp

## Regression coverage added

The four-limb test suite now verifies:

- the configured gravity preload can carry at least the complete default body weight;
- a leg at its exact authored pose still pushes down with its assigned preload;
- the hip cone twist frame aligns with the segment/controller long axis;
- passive stance parameters survive body-definition serialization;
- after 180 physics frames with neutral commands, the assembled chassis remains finite,
  upright, clear of the floor, and at least 75% of its authored standing height;
- every foot retains at least 65% of its authored outward projection instead of folding beneath
  the chassis;
- new training episodes receive a bounded neutral settling phase before exploration.
- a dedicated `four_limb_stability_test.gd` reproduces only the unpiloted standing check for fast headless regression runs.

## Compatibility

The observation count, action count, limb-slot order, and direct joint-target semantics are
unchanged. The body profile identifier remains `four_limb_physics_v6`. The new gravity preload is
serialized but deliberately excluded from the tensor/hardware signature so older checkpoints
with the same anatomy can still load and benefit from this physical stability correction.
