# Four-Limb AI Body — Implementation Context Map

Baseline project commit: `006802c2b6e5ffa530abfa0696dcd2c797c8a65f`

## Goal

Add a gameplay-ready, physics-driven body with four independently controlled limbs and train AI models to operate it. The first version is fixed to four limb slots, but every contract must be designed so damaged/missing limbs and later bodies with more limbs can be added without replacing the system.

## Non-negotiable rules

1. **Raw actuator control only.** The model must never output `walk`, `turn`, `jump`, gait names, or premixed movement commands.
2. **One output maps to one real actuator axis.** Four limbs × (hip elevation, hip horizontal sweep, knee bend, grip activation) = 16 continuous actions.
3. **No hidden chassis movement.** The body core must move because limb forces act through physics contacts—not because code sets a desired walking velocity.
4. **The existing drone action contracts remain untouched.** Drone PPO/SAC continue to output raw propeller commands.
5. **The learned controller must be able to react to damage.** Observations include installed/functional masks and realized actuator response. Commands for a missing limb are safely ignored.
6. **The procedural gait planner is not part of the learned action path.** It may be used as a baseline/demo controller, but learned models control joints directly.
7. **Separate model contracts.** Drone and limb models can never be loaded into one another accidentally.

## Architecture decision

Do not force the new body into the current `ServerEnemy` locomotion path. `ServerEnemy` is a `CharacterBody3D` whose velocity is set directly, while its physical limbs only follow that chassis. That cannot teach genuine locomotion.

Create a new fully simulated body whose root/core and limb segments are physics bodies. Reuse the existing anatomy resources and physical-drive math where safe, but not the kinematic chassis movement.

## Phase 1 — Reusable physical four-limb body

### New runtime classes

- `FourLimbPhysicalBody3D`
  - Owns the simulated core/root.
  - Owns four stable limb slots.
  - Exposes reset, health, alive state, camera anchor, contact state, and authoritative transform.
  - Is usable in both training and the actual game.

- `FourLimbActuatorController`
  - Holds the latest 16 normalized actuator commands until another action arrives.
  - Converts each command to a target angle inside that joint's authored limits.
  - Applies bounded PD torque to the real joint/segments.
  - Records requested target, applied torque, realized angle change, saturation, and actuator health.

- `FourLimbSlotDefinition`
  - Stable semantic slot ID: front-left, front-right, back-left, back-right.
  - References an `EnemyPhysicalLimbDefinition`.
  - Never relies on scene child order.

### Reuse/refactor

Reuse these resources:

- `scripts/enemies/enemy_physical_anatomy_definition.gd`
- `scripts/enemies/enemy_physical_limb_definition.gd`

Extract safe construction/math helpers from:

- `scripts/enemies/enemy_physical_limb_rig_3d.gd`

Do not change the behavior of existing enemies while extracting helpers.

### Physical contract

Per limb actions:

1. Hip elevation target `[-1, 1]`
2. Hip horizontal-sweep target `[-1, 1]`
3. Knee bend target `[-1, 1]`
4. Grip activation `[-1, 1]` (non-positive releases; positive values engage progressively)

Joint values map directly into authored limits and grip remains a direct physical attachment actuator. Drive strength, holding force, and breakaway remain body/hardware properties; there is no premade locomotion, pickup, or climb action.

### Acceptance checks

- Zero action holds the authored neutral pose.
- Positive/negative commands rotate the intended axis in the intended direction.
- One limb command does not silently drive another limb.
- The core moves only through physical forces and contacts.
- Removing/disabling one limb does not crash the controller.
- No procedural gait update runs while ML control is active.

## Phase 2 — Generic controllable-body boundary

Add a small adapter boundary instead of rewriting the drone pipeline.

### Base adapter

`MLControllableBodyAdapter` responsibilities:

- Body/control-profile ID
- Observation schema ID
- Action semantics ID
- Capture observation
- Validate/apply action
- Reset body
- Alive/terminated state
- Camera anchor and bounds
- Hardware/anatomy signature

### Implementations

- `DroneMLBodyAdapter`: wraps the current drone API without changing its semantics.
- `FourLimbMLBodyAdapter`: wraps `FourLimbPhysicalBody3D`.

This boundary is for training/runtime orchestration only. It must not convert limb actions into movement intentions.

## Phase 3 — Four-limb observation and action schemas

### New ML files

- `ml/bodies/four_limb/four_limb_ml_observation.gd`
- `ml/bodies/four_limb/four_limb_ml_feature_encoder.gd`
- `ml/bodies/four_limb/four_limb_ml_action.gd`

### Global observation features

- Target position and velocity in body-local space
- Core linear and angular velocity
- Core orientation/uprightness
- Core height and ground clearance
- Core-ground and core-obstacle contacts
- Body mass/inertia summary
- Previous action age/control interval

### Per-limb features

For each of the four stable slots:

- Installed/functional mask
- Hip offset and authored geometry
- Segment lengths/masses
- Current hip elevation/horizontal-sweep and knee angle
- Joint angular velocities
- Previous requested commands
- Applied/realized torque and saturation
- Joint/limb health or effectiveness
- Foot position and velocity in body-local space
- Foot ground contact, contact normal, clearance, and slip speed

### Fixed v1 tensor

The first model uses exactly four slots and 16 actions. Missing limbs remain represented by a zeroed feature row plus a mask. This is intentional preparation for damage, not general variable-count support yet.

### Future expansion

Later bodies with more than four limbs can use either:

- A new fixed topology/profile per limb count, or
- A padded maximum with masks, or
- A set/graph policy.

Do not prematurely replace the first four-limb dense model with a graph network.

## Phase 4 — Learner implementation

### First learner

Implement a dedicated four-limb continuous-control trainer without changing the existing drone learner math.

Preferred order:

1. Four-limb PPO for stable initial contact locomotion experiments.
2. Four-limb SAC after the actuator and reward contracts are validated.

Reuse generic MLP, optimizer, replay, and checkpoint utilities where possible. Do not refactor working drone trainers merely to remove duplication during the first implementation.

### Exploration

For SAC, use the state-dependent mean and variance design already introduced for drones, but with 16 action channels. Evaluation remains deterministic.

### Checkpoint contract

Every model must store:

- `body_profile_id = four_limb_physics_v9`
- Anatomy signature
- Limb slot order
- Joint action semantics
- Observation schema version
- Action schema version
- Algorithm and network dimensions

An incompatible model must be rejected with a readable reason.

## Phase 5 — Training environment

Create a separate `Physical Body Training Room` initially instead of destabilizing the mature drone room. Reuse shared map, target, plot, model-library, camera, and UI components.

### Initial curriculum

1. **Remain alive/upright** — no target movement.
2. **Stand near a stationary target**.
3. **Move to a stationary target**.
4. **Follow random waypoints**.
5. **Navigate around obstacles**.
6. **Damage randomization** only after intact locomotion works.

### Reward cards

Implement the planned reward/punishment-card UI here and make it reusable by the drone room later. Initial cards:

- Survival
- Uprightness
- Core ground clearance
- Target progress
- Stable target hold
- Body velocity near target
- Foot support/contact quality
- Foot slip
- Joint motion smoothness
- Sustained actuator saturation
- Energy/torque use
- Core collision/fall
- Early failure

Each card shows enable state, intensity, live contribution, episode total, and a plain-language explanation. Changes apply only at episode boundaries unless explicitly safe live.

### Reward rules

- Never flatten all non-success episodes to one negative score.
- Useful partial locomotion must remain useful experience.
- Full target-hold reward requires low relative velocity and reasonable uprightness.
- Survival is positive but much weaker than stable target following.
- Fast deliberate failure must not be cheaper than attempting recovery.
- Do not reward a foot merely for repeatedly tapping the floor.

## Phase 6 — Training-room and model-library integration

- New-group dialog gets a body/profile selector.
- Model Library filters by compatible body profile and algorithm.
- Worker-group cards show the body type/anatomy.
- Camera follows the body core and can attach to its camera anchor.
- Action inspector displays 16 channels grouped by limb, not one unreadable list.
- Plots and rolling saves use the same infrastructure as drone groups.
- Map Library remains shared.

Mixed drone and limb groups in one room are not required for v1. Compatibility metadata must nevertheless make that possible later.

## Phase 7 — Damage and missing-limb validation

After intact four-limb walking works:

- Randomly reduce one limb's torque effectiveness.
- Add delayed actuator response.
- Disable one joint axis.
- Remove one complete limb while retaining its fixed slot/mask.

The policy still outputs all 16 channels. Disabled actuators ignore commands, and observations reveal the failure through masks and realized response.

## Tests and diagnostics

Required readable behavior checks:

- “Each action controls the intended joint.”
- “A missing limb is reported and safely ignored.”
- “The body is moved by physics, not hidden velocity code.”
- “The learned mode does not run the gait planner.”
- “Observation values remain finite and normalized.”
- “A reset restores the same neutral body state.”
- “A four-limb model cannot load into a drone.”
- “A drone model cannot load into a four-limb body.”
- “Saved runtime inference matches training inference.”
- “Worker groups do not share actuator state.”

Diagnostics should include:

- Live per-joint target, angle, velocity, torque, saturation, and health
- Foot contacts and slip
- Core height/uprightness
- Per-reward-card contributions
- Action traces grouped by limb

## Implementation order for the next task

1. Add the four-limb slot/action definitions and physics body shell.
2. Build and validate the fully simulated root plus four limb chains.
3. Add direct joint actuator control and a manual debug panel.
4. Add observation/action adapters and readable tests.
5. Add a simple scripted/raw-actuator baseline that can stand without using movement commands.
6. Add the first four-limb learner and checkpoint contract.
7. Add the separate training room and reward cards.
8. Add model-library/runtime integration.
9. Only then add damaged/missing-limb curriculum.

## Explicitly out of scope for the first pass

- Arbitrary limb counts in one neural network
- Graph neural networks
- Arms, grabbing, weapons, or jumping-specific commands
- Premade gait/movement actions
- Replacing existing drone PPO/SAC code
- Mixed drone and limb groups in one simulation
- Visual polish for the creature

## Definition of done for v1

A fresh four-limb model can learn to keep a fully physics-driven body upright, produce forward locomotion toward a target using twelve independent joint targets and four independent grip actuators, and continue operating when one limb is weakened. The same saved model can run on the gameplay body through the exact training-time observation/action contract.
