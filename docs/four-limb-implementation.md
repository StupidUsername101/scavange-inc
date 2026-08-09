# Four-limb physical AI implementation

The project contains a four-limb training/runtime pipeline integrated into the default drone
training arena while sharing its generic physical limb stack with future model-forge bodies and
drone attachments.

## Physical contract

- The chassis and every limb segment are independent `RigidBody3D` parts.
- Generic serial chains use `Generic6DOFJoint3D` constraints and `LimbsController3D`.
- The current dense policy has four stable limb slots.
- Each limb exposes hip elevation, hip horizontal sweep, knee bend, and grip activation.
- The network emits sixteen direct normalized actuator values.
- There is no walk, turn, jump, pickup, climb, desired velocity, foot-placement, or gait macro.
- Neutral joint outputs target the authored bent rest pose.
- A zero grip output maps to the hysteresis-neutral activation level: it cannot engage from rest but
  can maintain an existing attachment. Negative output releases and positive output engages.
- Passive spring/damper behavior remains active without model input.
- Stock profile-v12 limbs have a physical rough box sole beyond the distal capsule tip. The sole is
  aligned flat in the authored neutral pose and separated from the capsule by a small gap; support/slip
  observations only count contacts on this terminal shape, not lower-leg/shin scraping.

Hip axes are X horizontal sweep, Z radial elevation/depression, and locked Y. Stock horizontal sweep
remains ±72 degrees. The elevation workspace keeps the established 68-degree walking span and adds
positive-only overhead recovery authority.

## Model contract

- body profile: `four_limb_physics_v12`;
- observation schema: 14;
- action schema: 5;
- feature count: 420;
- action count: 16.

Live training and deterministic runtime inference execute only the actor on the physics/gameplay path. PPO critic values are reconstructed during the detached optimizer update from the immutable producer-policy snapshot before GAE, so this performance optimization does not change action commands or value targets.
The 0.35-second neutral startup settle is also kept off the observation hot path: intermediate settle ticks do not build the 420-value snapshot because no action or reward consumes it; the first real snapshot is captured when control begins.

Old limb policies are not a compatibility target. When the physical or ML contract is improved, the
profile/schema is allowed to invalidate old policies and training should restart from the new contract.

The observation contains complete 3D target geometry/motion, chassis state, obstacle and arena-edge
sensing, joint/foot/contact state, fixed attachment inputs, an optional assigned pickup object (including its authored task/reward value), and
per-limb grip candidate, attachment, mass, surface, rearm, and load telemetry. The policy-facing grip
target is represented as one coherent physical-terminal-surface-to-target offset/normal/distance: it points to the
compatible candidate before latch and the real attachment anchor afterward, rather than pairing an
anchor vector with candidate-absent metadata. It is relative rather than an absolute
world/core position.

## Generic grip

`GenericGrip3D` is owned by a `LimbEndEffector3D` but depends only on a host `RigidBody3D`. It detects
compatible tagged surfaces farther away than the physical latch radius, stores local material anchors
on both the terminal support surface and target surface, and applies bounded spring-damper forces every
physics tick. Dynamic targets receive equal and
opposite force; static tagged walls provide climbing support.

Spring/damper demand and holding-force limits scale coherently with grip activation. Separate
normal/shear limits cap the physical force, and breakaway requires overload to persist briefly rather
than treating one solver/acquisition spike as an immediate failed latch. Sustained overload still
breaks the attachment and requires release/rearm.

## Model-forge and drone bridge

`GenericLimbAssembly3D` mounts arbitrary limb definitions on any rigid host. `ServerDrone` builds
these assemblies for installed `DroneLimbAttachmentDefinition` resources and exposes direct command,
action-count, and state APIs. Existing drone PPO/SAC profiles remain propeller-only; a future
manipulator profile must explicitly add those attachment actions and observations.

## Training

The unified room supports drone, four-limb, and turret groups with shared typed reward-card UI and
persistent cardset tabs. Limb presets include Ground Locomotion, Climbing / Grip, Long Jump, and Item
Pickup. Item Pickup spawns assigned carryable boxes. Climbing uses only the same direct joint/grip
actions and supplies reach, real-latch, and high-water ascent shaping for elevated objectives.

Full 3D target progress is the primary navigation signal and is not multiplied by posture quality.
Separate uprightness, body-drag, planted-foot support/slip, collision, rotational stability, joint and
torque terms describe how the worker should move without weakening the answer to “did I get closer
to the destination?”
