> Superseded contract note: profile v9 now uses 398 inputs and 16 direct outputs, retains full target height/vertical relative motion, and adds physical per-limb grip/carry state. See `docs/generic-grip-and-pickup-review-2026-08-06.md`.

# Limb worker jump and climb capability review — 2026-08-06


## Current profile-v9 update

The friction-only impossibility statements below describe the pre-v9 body. Profile v9 implements
one controlled physical grip at every distal tip, with compatible-surface tags, separate normal and
shear holding limits, overload breakaway, rearming, and observed load/attachment state. Tagged
vertical walls can therefore support climbing, and dynamic `carryable` bodies can be physically
held. The current fixed policy contract is 398 inputs to 16 outputs. Extra end-effector collision
geometry remains disabled by default; the stock grip operates at the existing segment tip.

## Review scope

This historical review treated the confirmed standing profile-v7 rig as a protected baseline; profile v8 retains those standing mechanics. It does not change joint frames, masses, rest geometry, passive elasticity, active torque, spawn height, collision materials, observations, actions, rewards, or trainer behavior. The purpose is to determine what the body can theoretically do, what the current training contract can teach it to do, and what must change before jumping or climbing becomes a supported skill.

## Bottom-line verdict

- **Jumping is mechanically plausible with the current body, but it is not yet proven by a dynamic test and the current ground-navigation task actively discourages it.**
- **Ramps, stairs, and low step-ups are mechanically plausible.** They need terrain examples and terrain-aware rewards, not a replacement body.
- **Jumping onto or mantling a ledge is conditionally plausible.** The front legs can reach and pull while the rear legs push, but the current perception and contact telemetry are too coarse for reliable training.
- **Climbing a wall that provides upward-facing footholds or ledges is plausible after task and sensor work.**
- **Climbing a featureless vertical wall was physically impossible for the pre-v9 friction-only rig.** The feet are only rounded capsule ends with ordinary Coulomb friction. They have no adhesion, hook, claw, magnet, suction, or opposed bracing mechanism capable of maintaining inward normal force.
- **Overhang and ceiling locomotion were also impossible without an attachment mechanism; profile v9 now supplies a bounded attachment mechanism on tagged surfaces.**
- The generic physical limb layer already supports arbitrary segment counts, but the current four-limb policy does not. Extra ankles, claws, or grip joints require a new versioned model profile rather than silently changing that historical 315-input/12-output contract. That historical profile-v8 tensor was 300→12; profile v9 is explicitly versioned as 398→16.

## Current rig inventory

### Physical structure

- One rectangular rigid chassis.
- Four serial limbs.
- Two rigid capsule segments per limb.
- Total bare mass: approximately **6.24 kg**:
  - 3.2 kg chassis;
  - eight 0.38 kg limb segments.
- Maximum straight geometric reach per limb: **2.15 m** before joint-limit and mounting constraints.
- No separate ankle, wrist, foot pad, toe, claw, or gripper body.
- All bodies belonging to the same creature ignore one another for collision. This prevents solver explosions and self-jamming, but also allows anatomically impossible interpenetration during extreme maneuvers.

Relevant implementation:

- `ml/bodies/four_limb/four_limb_body_definition.gd`
- `ml/bodies/four_limb/four_limb_slot_definition.gd`
- `ml/bodies/four_limb/four_limb_physical_rig_3d.gd`

### Joint workspace

Each leg has three policy-controlled coordinates:

1. hip elevation, stock span ±68 degrees;
2. hip horizontal sweep, stock span ±72 degrees;
3. knee bend, stock hard range -8 to +72 degrees.

The hip supplies the two directions needed to place a leg around the chassis, while the knee changes reach. This is enough for a three-dimensional foot workspace even without an ankle. It is sufficient in principle for basic crouching, extension, takeoff, landing, stepping, and reaching onto a ledge.

### Actuation and elasticity

Stock active settings:

- hip stiffness 210 Nm/rad, damping 22, maximum active torque 320 Nm;
- knee stiffness 240 Nm/rad, damping 24, maximum active torque 360 Nm;
- target slew 260 degrees/second.

Stock passive settings:

- stiffness 130 Nm/rad;
- damping 18;
- maximum passive torque 420 Nm;
- nonlinear hardening starts at 40% of the authored range;
- progressive stiffness ratio 5;
- 35% of baseline passive impedance runs in Jolt's joint spring.

For a roughly 61 N body weight, those torque caps are not obviously too weak. The existing static standing tests already estimate substantial load-bearing headroom. However, static torque headroom does **not** prove jump capability. A jump also depends on usable angular stroke, target response, contact duration, angular velocity, mechanical work, and whether passive hardening lets the actuators reach a deep enough crouch.

There is currently no explicit actuator power or joint-speed budget. The system limits torque and target slew, but not motor power as a function of angular speed. This makes explosive maneuvers theoretically easier than on a real motor and means a successful jump test would prove game-physics capability, not motor realism.

Relevant implementation:

- `scripts/limbs/limb_joint_definition.gd`
- `scripts/limbs/limbs_controller_3d.gd`

## Jumping review

### Why the physical body can probably jump

1. **The action space is not the blocker.** A jump can emerge from raw joint targets: crouch by bending and lowering, then rapidly extend. No hidden `jump` command is necessary.
2. **The body is light relative to the authored torque limits.** Four legs can contribute ground impulse at once.
3. **The passive springs can store and return energy.** Bending away from the rest pose loads the elastic controller; returning toward rest can assist extension.
4. **The foot material is high-friction on a sufficiently grippy floor.** Stock friction is 0.95, which is useful for turning extension into forward impulse rather than immediate slip.
5. **Airborne state is not a hard terminal condition.** The current coordinator terminates for timeout, body failure, leaving the horizontal arena, or falling below the arena—not simply for losing foot contact.
6. **The chassis and joint observations include vertical velocity, body orientation, foot velocity, contact, and joint state.** The policy has enough proprioception to stabilize a landing once an appropriate task teaches it to do so.

### Why the current trainer is unlikely to discover a good jump

1. **The target is deliberately flattened to the horizontal plane.** Both target offset Y and target velocity Y are erased before inference. The policy cannot be told that a landing point is above it.
2. **The reward explicitly prefers smooth constant-height locomotion instead of hopping.** Height departure, vertical speed, and vertical acceleration reduce `height_stability`.
3. **Airborne progress is heavily discounted.** With no supporting feet, the positive target-progress quality falls to its minimum support multiplier; poor standing-height quality reduces it further.
4. **Descending near the floor is punished as `falling`.** That is useful for accidental falls, but it also overlaps with the landing phase of a deliberate jump.
5. **Approaching a wall is punished.** The obstacle-avoidance card penalizes closing speed toward nearby wall geometry—the exact approach needed for jumping onto or over an obstacle.
6. **The policy receives only a coarse obstacle description.** It gets 26 clearance rays, target-path blockage, and one wall-top-relative-height scalar, but not a landing footprint, platform depth, edge location, or desired landing pose.
7. **There is no dynamic jump regression.** Existing tests prove standing, settling, disturbance recovery, action mapping, and observations. They do not prove crouch depth, takeoff velocity, airborne clearance, landing, or recovery.
8. **Strong nonlinear passive hardening may reduce usable crouch depth.** This is not currently a defect—the same hardening prevents collapse—but it must be measured under scripted jump commands before any gain is changed.

### Jump verdict

The body should be considered **jump-capable in theory, unverified in the solver, and not learnable under the present generic walking reward without substantial luck or exploitation**.

Do not weaken the standing springs based on theory. First run a deterministic scripted launch test and inspect:

- maximum crouch angles actually reached;
- active/passive/soft-limit torque per joint;
- saturation duration;
- foot slip;
- total ground impulse;
- chassis vertical velocity at takeoff;
- apex height;
- body orientation during flight;
- landing impulse and recovery time.

Only then decide whether jump-specific anatomy needs more target slew, more active torque, less progressive resistance, or a different rest pose.

## Climbing review

“Climbing” needs to be divided into physically different tasks.

### Ramps and ordinary stairs

**Likely possible now.** The body has ample reach, two useful hip axes, knees, high friction, upward/downward obstacle rays, and real support contacts. The principal missing parts are terrain curriculum and rewards that permit temporary height changes and deliberate foot lifting.

The current sensor can notice obstacle height in a rough way, but reliable stair/stepping-stone locomotion normally benefits from local terrain samples near intended foot placements. A single nearest obstacle and sparse rays are weaker than a small local height map or per-foot terrain samples.

### Low blocks and ledge mantling

**Conditionally possible.** A feasible maneuver would be:

1. approach the obstacle;
2. crouch and push with rear legs;
3. place one or both front distal segments on the top surface;
4. pull with front legs while rear legs continue to push;
5. transfer the chassis over the edge;
6. recover standing posture on top.

The current geometry can perform those motions in principle. The main limitations are:

- no precise ledge-top geometry or landing-area input;
- no contact point or wall normal encoded per foot;
- vertical wall contact is only a boolean/impulse/count, not a load-bearing state;
- no ankle or compliant foot pad to align to the top surface;
- rounded capsule ends may skid or roll off narrow ledges;
- wall approach and wall contact are currently punished;
- horizontal-only target progress does not explicitly value gaining height or reaching the top.

### Vertical wall with discrete footholds, cracks, or protrusions

**Potentially possible after sensor, reward, and end-effector work.** Upward-facing ledges can already count as support. A foot that can hook a protrusion or sit on a small shelf can carry body weight without magical adhesion.

For reliable behavior, add:

- the exact distal contact point and surface normal;
- relative normal and tangential foot velocity;
- contact impulse/load estimate;
- a local terrain/foothold description;
- a dedicated foot or claw shape that can catch geometry;
- compliant ankle alignment or another controllable distal joint;
- load-sharing and slip rewards.

### Featureless vertical wall

**Impossible with the current physical hardware.** Friction only resists tangential sliding when another mechanism supplies normal force. A foot pushing into a single flat wall pushes the creature away from that wall; the current body has no adhesion or grasp that can maintain attachment.

The current code makes the mismatch even clearer:

- distal contacts count as `foot_contact` support only when the surface normal has an upward component;
- a vertical wall normal therefore does not count as support;
- wall telemetry lacks a grip state, holding-force limit, breakaway state, surface compatibility, or attachment action;
- the distal segment uses ordinary friction with `rough = false`, so effective friction can be limited by the contacted material;
- no constraint or force attaches a foot to a wall.

Possible real physical models:

1. **Microspines/claws for rough surfaces**
   - engage only on tagged rough or featured surfaces;
   - require correct approach and loading direction;
   - provide a bounded shear and pull-in force envelope;
   - distribute load across several compliant toes/spines;
   - slip or break away when overloaded.

2. **Magnetic feet for compatible metal surfaces**
   - explicit on/off action per foot;
   - surface compatibility tag;
   - force decreases with poor alignment or gap;
   - bounded holding force and probabilistic/health-based failure.

3. **Suction or dry adhesion for smooth surfaces**
   - contact-area and orientation requirements;
   - seal/attachment state;
   - energy use and breakaway limit.

4. **Opposed-wall or crevice bracing**
   - no adhesion required when limbs can push against opposing surfaces;
   - requires geometry on both sides and explicit internal-force control;
   - cannot solve a single isolated flat wall.

### Overhangs and ceilings

**Impossible without attachment hardware.** Even a successful vertical friction climb does not imply overhang capability. The feet must pull toward the surface while supporting the full body load, so grip force, load distribution, release timing, and failure recovery must be explicit physical state.

## Model I/O implications

### What can stay

The current direct low-level control philosophy is sound:

- one output per physical actuator axis;
- no premixed walk or jump action;
- held joint target, measured joint state, torque, saturation, body state, and foot state visible to the policy;
- passive elasticity remains hardware behavior rather than a hidden gait controller.

### What must change for a parkour profile

A new versioned profile should add or reinterpret observations for:

- full three-dimensional target/desired landing offset;
- desired landing orientation;
- obstacle/ledge dimensions and top surface bounds;
- local terrain heights around each foot and candidate landing zone;
- airborne/takeoff/landing phase evidence derived from contacts and vertical motion;
- per-foot contact point, contact normal, relative normal/tangential velocity, and load;
- time since each foot attached/detached;
- jump or climb task mode—without replacing direct joint actions.

The reward needs phase-aware terms:

- crouch/launch quality;
- upward and forward takeoff impulse toward the requested landing point;
- obstacle clearance;
- flight orientation;
- landing-foot contact and low chassis impact;
- post-landing recovery;
- vertical progress while climbing;
- secure load sharing and low slip;
- correct release timing.

Standing-height and foot-support rewards should remain for ordinary locomotion but must not punish the intended airborne phase.

### Grip actions and topology

A controllable climbing foot is a real actuator and should be represented honestly. The clean fixed-profile option is:

- retain 12 joint targets;
- add one grip/adhesion output per limb;
- new action count: 16;
- add per-limb grip state, available holding force, actual load, surface compatibility, and slip to observations;
- version body/action/observation schemas and reject incompatible checkpoints.

A passive claw that mechanically hooks geometry could avoid an extra action, but its latch/release rules must still be physical, visible to the policy, bounded, and testable.

The generic limb builder can already construct extra segments. The current dense four-limb adapter cannot expose extra joints without a new model contract. For the later creature editor, choose one of:

- a fixed maximum number of joint slots with masks;
- a shared per-limb/per-joint network;
- a set/transformer encoder;
- a graph policy over body parts and joints.

Do not silently resize a released policy. This recommendation was implemented as profile v9 (398→16), while profile v8 remains a rejected historical 300→12 contract.

## Recommended implementation order

### Stage 1 — capability tests without changing the body

1. **Scripted vertical hop test**
   - settle with neutral commands;
   - command a synchronized crouch;
   - command rapid extension;
   - require a measurable airborne interval and positive apex gain;
   - require finite state and a stable recovery after landing.

2. **Scripted forward jump test**
   - add coordinated hip sweep during extension;
   - measure horizontal travel, yaw/roll error, foot slip, and landing recovery.

3. **Step and stair tests**
   - fixed low step first;
   - increasing heights;
   - verify distal support on the upper surface and no core collision.

4. **Ledge reach/mantle test**
   - verify a front distal segment can reach and remain on the top surface;
   - verify rear push plus front pull can move the core above the ledge.

5. **Expected-failure smooth-wall hang test**
   - document that the unmodified friction-only body cannot remain on a flat vertical wall;
   - keep this test failing or explicitly marked unsupported until grip hardware exists.

### Stage 2 — separate parkour training contract

- Keep the known-good standing mechanics untouched in profile v8 for ordinary ground locomotion.
- Introduce a new profile for jump/terrain observations and phase-aware rewards.
- Curriculum:
  1. standing and walking;
  2. in-place hop;
  3. controlled landing;
  4. short forward/diagonal jump;
  5. low box landing;
  6. obstacle or gap jump;
  7. ledge mantle.

### Stage 3 — climbing end effectors

- Add a generic `LimbEndEffectorDefinition` rather than hard-coding climbing into the four-limb worker.
- Give it surface material, geometry, passive compliance, optional grip capability, holding-force envelope, breakaway behavior, and telemetry.
- Add a matching runtime end-effector component and controller path, analogous to drone part definitions and propeller control.
- Add a versioned grip action only when the hardware is controllable.

### Stage 4 — climbing curriculum

- ground crawl with grip disabled;
- incline walking;
- progressively steeper surfaces;
- vertical wall with reliable attachment;
- randomized attachment failures and recovery;
- ledges, corners, and transitions;
- overhangs only after attachment mechanics are proven.

## Tests that must remain protected

Every jump/climb change must continue to pass the existing invariants:

- passive unpiloted standing;
- disturbance recovery;
- stable broad foot spread;
- finite observations/actions;
- exact dense action mapping;
- no hidden chassis force;
- no accidental checkpoint compatibility;
- root folder remains exactly `scavange-inc`.

## External findings retained in the working plan

- Godot's `Generic6DOFJoint3D` supports independent angular limits and angular springs per axis, so the current direct joint-target architecture remains suitable for dynamic skills.
- The published Extreme Parkour system demonstrates that learned quadrupeds can perform high and long jumps and traverse ramps when perception, commands, and training are designed for those maneuvers.
- Reference-free quadruped jumping research conditions the policy on desired three-dimensional landing pose and obstacle dimensions and uses a curriculum from in-place jumping to forward/diagonal and obstacle jumps. Direct long-jump training can otherwise settle into a standing local optimum.
- Terrain-aware locomotion work uses local terrain samples around feet; discrete footholds and gaps are substantially harder without exteroception.
- Stanford climbing work emphasizes specialized hands/feet, compliant ankles, internal-force distribution, and microspines that provide the inward normal force missing from friction-only wall contact.
- Recent magnetic climbing RL explicitly models attachment state, geometric alignment, force limits/failures, adhesion actions, and a ground-to-vertical curriculum.

## Final decision

Do **not** redesign or weaken the standing rig yet.

The next engineering step should be the scripted jump capability test. It will answer whether the current actuator/rest-pose combination can produce useful takeoff impulse without guessing. In parallel, treat smooth-wall climbing as a hardware feature—not a reward-tuning problem—and design a generic end effector before attempting to train it.
