# Generic grip, carrying, and drone-limb bridge review — 2026-08-06

## Goal

Add one physical grip implementation that is not owned by the four-limb trainer. The same terminal
hardware must work on creature limbs, future editor-built bodies, and drone-mounted generic limb
assemblies. Grip is a direct actuator, not a `pick_up`, `carry`, or `climb` macro action.

## Physical implementation

`GenericGrip3D` is hosted by `LimbEndEffector3D` at the authored distal tip. It uses a small sphere
shape query to locate the nearest compatible surface and records the candidate point, normal,
object identity, mass, dynamics state, and surface tags. The query excludes every rigid part in its
own assembly and runs at a configurable low cadence rather than performing a shape query on every
physics frame. In Godot 4.6, `PhysicsDirectSpaceState3D.get_rest_info()` returns the nearest
intersection together with collider ID, RID, point, normal, and velocity data; this is the source of
the acquisition contact rather than a trainer-specific item lookup.

Once engaged, the grip stores the contact point and normal in the target body's local frame. Every
physics update it applies a bounded spring-damper force at the distal point. A dynamic target
receives the equal and opposite force, so carrying remains physical. The distal owner segment and a
held dynamic object receive a temporary mutual collision exception so their overlapping contact does
not fight the holding spring; the exception is removed on release. Static and kinematic surfaces
act as world anchors, allowing the same actuator to support climbing. Normal and tangential loads
have separate force envelopes and the connection releases when the configured breakaway ratio is
exceeded. A broken controlled grip enters an explicit rearm state: the controller must lower activation below
the release threshold before that grip can attach again. A passive grip rearms only after leaving the
overloaded surface or encountering a different candidate, preventing immediate break/reconnect
oscillation without requiring an action channel. Rearm state is included in policy telemetry, so
overload hysteresis is observable rather than hidden.

The implementation deliberately does not create a `PinJoint3D`: Godot's Jolt backend does not
support the pin joint's impulse clamp, so such a joint would not provide the requested enforceable
holding-force limit. Explicit per-physics-step forces retain measurable limits and breakaway. A
destroyed end effector is passed to the generic grip as non-operational, which immediately releases
even a passive grip instead of allowing damaged hardware to remain latched.

## Generic surface contract

Grip compatibility is data-driven through `grip_surface_tags` metadata. The implementation also
recognizes the existing training metadata and maps it to these tags:

- `climbable`: fixed/custom training walls;
- `carryable`: the pickup training rigid item and future gameplay items;
- `ground`: the training floor, intentionally excluded by the stock grip definition.

`LimbEndEffectorDefinition` owns acquisition radius, collision mask, static/dynamic permissions,
maximum held mass, response speed, spring and damping, normal/shear force limits, breakaway ratio,
energy cost, and compatible tags. Geometry remains independent from grip: a definition can add a
pad/claw shape or run a non-geometric grip at the existing segment tip.

Gameplay `ItemDefinition` resources now expose `grippable` plus a tag list, defaulting to
`carryable`. `ServerItem` publishes that contract as metadata whenever it rebuilds, so the same
physical grip can carry ordinary game items rather than recognizing only the trainer's amber box.
An item can explicitly disable grip without changing its collision layer. The generic grip also
honors this opt-out even when an end effector is configured to accept otherwise untagged surfaces.

## Four-limb profile v9

The stock body retains exactly the confirmed standing geometry and all known-good joint physics.
Extra end-effector collision geometry remains disabled (`GeometryType.NONE`), but each distal tip
now owns one enabled controlled grip actuator.

Per limb outputs are:

1. hip elevation;
2. hip horizontal sweep;
3. knee bend;
4. grip activation.

The fixed profile is therefore 398 inputs to 16 outputs:

- body profile `four_limb_physics_v9`;
- observation/feature schema 9;
- action schema 4;
- 74 global inputs, including an optional assigned pickup item;
- 68 fixed attachment inputs;
- 64 inputs per limb, including candidate and attached surface type, mass, attachment, load state, and whether an overloaded grip must be released before it can reattach.

Old profile-v8 checkpoints are intentionally rejected. Their 300→12 networks have neither grip
outputs nor the additional grip/item observations.

The fixed profile reserves all four actuator slots for every stable limb index. Missing limbs and
custom passive/no-grip terminals register their unused channels as explicit no-op mappings, so
mixed hardware does not disable the rest of the controller or silently rewrite terminal behavior.

## Carrying and pickup training

The built-in **Item Pickup** reward cardset spawns one assigned `FourLimbTrainingGrabbableItem3D`
for each worker. Other cardsets do not spawn those boxes, so ground and jump lessons are not
silently changed. Each box carries its assigned body instance ID, and generic candidate filtering
rejects it for other workers; normal gameplay items omit this restriction and remain grippable by
any compatible end effector.

The model receives the assigned item's 3D offset, distance, relative velocity, mass, and held state.
Each limb also sees whether a candidate or attached surface is dynamic, its mass, and whether it is
tagged `climbable` or `carryable`, so one physical grip action can be interpreted correctly in both
climbing and carrying lessons.
The **Pick up an item** card gives a small one-time acquisition signal when the assigned carryable
is first gripped and the larger one-time reward after the object has been lifted at least 0.12 m
above its episode spawn height. Each physical object can pay each stage only once, preventing
release/re-grab farming.

## Drone and model-forge integration

`GenericLimbAssembly3D` now accepts any `RigidBody3D` host. It is kept as a lifecycle child but is
`top_level`, preventing independently simulated limb bodies from inheriting the host transform a
second time.

`DroneLimbAttachmentDefinition` stores arbitrary generic limb definitions. `ServerDrone`
automatically creates one assembly for every installed limb attachment. By default, each assembly
adds mutual collision exceptions between its host and every segment and between all segments in the
same assembly. `ServerDrone` then extends that filtering across every opted-in limb assembly on the
same drone, matching the creature rig's no-self-jamming policy; an attachment definition can opt out
for a future morphology that intentionally needs self-contact. The server exposes:

- required limb-action count;
- direct command submission;
- grip/limb state snapshots.

Existing drone PPO/SAC profiles remain propeller-only and are not silently resized. A future drone
manipulator model must explicitly combine the propeller action block with the attachment's reported
action count and include the assembly snapshot in a versioned observation profile. ServerDrone
exposes both per-slot and combined attachment action/state APIs, while
`DroneLimbAttachmentDefinition` can densely pack arbitrary joint and grip indices for an editor-built
appendage.

## Behavioral checks for the live project

No new automated test files were added because Godot is unavailable in this workspace. The first
live checks should be:

1. select **Item Pickup**, start a fresh profile-v9 limb group, and confirm one amber box per worker;
2. verify negative grip commands release and positive commands acquire only within the distal
   acquisition radius;
3. lift an item and confirm its motion is physical, with the item pulling back on the limb;
4. confirm overloading a grip increments breakaway state and releases it;
   keep the grip command high to confirm it stays disarmed, then release and re-engage it;
5. move a tip to a tagged wall and confirm a static grip can carry body load;
6. spawn an ordinary `ServerItem`, confirm its default `carryable` tag is visible to the grip, and
   verify that setting its definition's `grippable` flag to false prevents acquisition;
7. select Ground Locomotion or Long Jump and confirm pickup boxes disappear at the next episode;
8. install a `DroneLimbAttachmentDefinition` on a non-training drone and exercise its public raw
   limb-command API before designing a new drone ML profile.

## Sources retained in the working plan

- Godot 4.6 `PhysicsDirectSpaceState3D.get_rest_info()`:
  https://docs.godotengine.org/en/4.6/classes/class_physicsdirectspacestate3d.html
- Godot 4.6 continuous force semantics:
  https://docs.godotengine.org/en/4.6/classes/class_physicsdirectbodystate3d.html
- Godot 4.6 Jolt unsupported joint properties:
  https://docs.godotengine.org/en/4.6/tutorials/physics/using_jolt_physics.html
- Godot `Node3D.top_level` transform behavior:
  https://docs.godotengine.org/en/4.6/classes/class_node3d.html
- Godot `PhysicsBody3D` collision-exception API:
  https://docs.godotengine.org/en/4.6/classes/class_physicsbody3d.html
- SCALER multi-limbed robot grippers used for both locomotion/climbing and object grasping:
  https://arxiv.org/abs/2312.04856
