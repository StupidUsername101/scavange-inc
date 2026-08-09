> Historical profile-v8 review: profile v9 now enables four controlled physical grips and uses a 398-input/16-output contract. See `docs/generic-grip-and-pickup-review-2026-08-06.md`.

# Limb input reduction, target-height, and end-effector review — 2026-08-06

## Decision summary

The four-limb policy had no captured rollout dataset in the project archive, so fitting PCA now would be guesswork. PCA learns a projection from representative samples; a projection fitted before jumping, climbing, damage, and attachment states have occurred can discard low-frequency but control-critical information. The project therefore keeps the original named physical features and adds the same empirical rollout audit already used by drone PPO: constant inputs, pairwise Pearson correlation, maximum absolute correlation, and numerical rank.

The safe reduction is structural rather than statistical. Profile v8 removes only a guaranteed constant and exact linear combinations:

- constant target-present flag;
- ground-clearance error, because it is clearance minus preferred clearance;
- duplicated uprightness, because it is exactly the Y component of body-local world-up;
- three joint target-error values per limb, because the stock limits keep `held target - measured angle` inside the non-wrapping range;
- signed horizontal boundary error, because it is exactly `horizontal distance - target radius`.

Sixteen old inputs are removed and one new full-3D target-distance scalar is added: 315 becomes 300. No contact, torque, velocity, obstacle, damage, attachment, actuator-state, or target-direction information was removed. The unit target direction remains useful when raw offset components are clipped, and the inside-radius flag retains the nonlinear success threshold.

## Target information

### Four-limb workers

Schema 8 keeps navigation in a yaw-only coordinate frame, but no longer flattens the objective:

- target offset X/Z is horizontal and heading-relative;
- target offset Y is the exact world-vertical target-height difference;
- target-relative velocity includes vertical relative motion;
- both horizontal target distance and full 3D target distance are explicit; the existing success radius and locomotion reward remain horizontal ground-task concepts;
- full 3D unit direction is retained because normalized/clipped offsets do not preserve it at long range, and the inside-radius flag remains an explicit nonlinear success cue.

This makes the same body usable by a later jump/parkour lesson without changing the physical action contract.

### Drone workers

Drone PPO already encodes the complete body-local 3D target offset and complete 3D target-relative velocity. Its Y features therefore already contain target-height and vertical approach information. Drone SAC derives its base observation from the PPO encoder, so it retains the same target-height information. No checkpoint-breaking drone schema change was necessary.

## Empirical correlation audit

`FourLimbPPOFeatureAudit` now analyzes up to 128 normalized rollout samples inside the detached optimizer job on the first update and every tenth update after that. It reports:

- changing versus constant inputs;
- maximum absolute Pearson correlation;
- the count of feature pairs with absolute correlation at least 0.995, retaining the strongest sixteen labels for diagnostics;
- numerical rank of the centered, standardized varying-feature sample matrix.

The report appears in the selected limb group's tooltip. It is diagnostic only: a high correlation in one lesson is not sufficient to delete a sensor. Removal should require repeated evidence across standing, locomotion, damage, jumping, climbing, and attachment curricula.

## Versioning

- body profile: `four_limb_physics_v8`;
- observation schema: 8;
- feature schema: 8;
- feature count: 300;
- action schema: 3;
- action count: 12.

The action semantics and the known-good standing physics are unchanged. Older checkpoints are rejected because their input tensor has a different shape and target meaning.

## Generic end-effectors

The generic limb stack now has two new types:

- `LimbEndEffectorDefinition`: optional per-limb terminal hardware contract;
- `LimbEndEffector3D`: runtime collision shape, visual, command state, and telemetry attached directly to the distal rigid body.

Every `GenericLimbDefinition` owns an independent end-effector definition. Every `FourLimbSlotDefinition` serializes its own definition, so one body may mix different terminal hardware on different limbs.

The definition stores:

- none/sphere/box/capsule geometry and local pose;
- added mass, health, friction, bounce, roughness, and absorbency;
- future passive-compliance capability values;
- none/passive/controlled grip mode;
- optional global action index;
- activation response and threshold;
- normal/shear holding envelopes, breakaway ratio, energy cost, and compatible surface tags.

An enabled physical effector is a direct `CollisionShape3D` child of the distal `RigidBody3D`, matching Godot's collision-shape ownership model. Its shape support envelope is included in generic reach and in the fixed body's spawn-height/horizontal footprint calculations, so mixed terminal geometry does not begin intersecting the floor or escape arena margins. Because `PhysicsMaterial` belongs to the complete rigid body, an enabled effector intentionally becomes the distal segment's surface material rather than pretending one rigid body can have independent materials per child shape.

The generic controller includes optional controlled-effector action indices in its dense action-map validation and advances effector command state each physics step. The current fixed four-limb profile leaves grip action indices at `-1`, so it still has exactly twelve outputs. If a fixed-profile slot is authored with an out-of-profile controlled grip index, the adapter keeps the hardware but forces it released rather than invalidating all twelve joint controls.

No adhesion or hidden holding force was added. The fields and telemetry are the clean extension point for a later versioned grip implementation; ordinary stock limbs remain physically identical because their default end effectors are disabled.

## Deferred policy-profile boundary

Profile v8 deliberately does not encode the new end-effector descriptor block or add grip actions because stock effectors are disabled and the confirmed 12-output standing controller must remain unchanged. The rich per-limb snapshot contains the hardware type, geometry/material capability, activation, attachment/load placeholders, health, energy, and surface tags so a later mixed-hardware or grip profile can add fixed per-limb inputs without changing the generic physics classes. A profile that actively controls four grips should be explicitly versioned rather than silently extending v8.

The next reward-design task is likewise separate: ground locomotion, jump/parkour, and climbing/grip need distinct selectable reward cardsets because support loss and body-height changes mean failure on the ground but are intentional during a jump or wall transition.

## Sources retained

- Godot `CollisionShape3D`: a collision shape supplies a shape to a `CollisionObject3D` parent.
- Godot `Generic6DOFJoint3D`: independent angular limits and springs remain the joint primitive.
- scikit-learn PCA documentation: PCA is a data-fitted SVD projection to a lower-dimensional space and centers but does not automatically scale features.
- Curriculum-based quadrupedal jumping: desired landing position/orientation and obstacle dimensions are useful conditioning variables for learned jumping.

Verified links:

- https://docs.godotengine.org/en/4.6/classes/class_generic6dofjoint3d.html
- https://docs.godotengine.org/en/stable/classes/class_collisionshape3d.html
- https://scikit-learn.org/stable/modules/generated/sklearn.decomposition.PCA.html
- https://scikit-learn.org/stable/modules/decomposition.html
- https://arxiv.org/abs/2401.16337

## Verification decision

No new Godot test files were added. Existing tests were only kept schema-consistent; this workspace uses static validation because Godot is intentionally absent, and new physical behavior must be inspected in the user’s live room.
