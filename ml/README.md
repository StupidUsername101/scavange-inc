# Drone ML pipeline

This folder contains the quadrotor learning stack. Each worker group selects its learner:
clipped Proximal Policy Optimization (PPO) with generalized advantage estimation (GAE), or an
off-policy Soft Actor-Critic learner with hindsight replay and local visitation memory for maze
navigation.

## Data flow

1. `DroneMLObservation.capture()` reads one authoritative physics snapshot.
2. `DroneMLFeatureEncoder` produces the stable task/navigation block.
3. The accepted `MLBodyInterfaceManifest` encodes topology-dependent Core/attachment observations.
4. `MLModelInputVectorBuilder` combines the task block with the accepted body block.
5. `DroneMLController` accepts the manifest-tagged model action and routes each control back to its physical Core/slot owner.
6. Propeller commands enter the existing power-limited rotor simulation; limb commands enter the same generic articulated-limb controller used by limb workers.
7. The next snapshot contains the resulting physical state and body-part observations.

`DroneMLModel` remains the framework-neutral empty base class. `DronePPOModel` and
`DroneSACModel` implement it for their respective saved checkpoints. Empty, malformed, non-finite
and wrong-topology actions still fail safe to zero thrust.

## ServerDrone API

```gdscript
drone.enable_ml_control() # Enables external-action mode.
drone.set_ml_objective({"target_position_world": Vector3(3.0, 2.0, 0.0)})
var observation: Dictionary = drone.get_ml_snapshot()
drone.submit_ml_action({
    "propeller_commands": [
        {"slot_index": 0, "command": 0.52},
        {"slot_index": 1, "command": 0.52},
        {"slot_index": 2, "command": 0.52},
        {"slot_index": 3, "command": 0.52},
    ],
})
```

Pass a `DroneMLModel` instance to `enable_ml_control(model)` for in-process inference. External
trainers submit an action whenever it changes; the controller validates it once and holds the
same motor targets until the next action arrives.

## Variable propeller counts

Observations contain an ordered `propellers` array with stable `slot_index` fields. Actions must contain the same number and order. Nothing in this ML layer assumes four propellers.

The general `encoded` snapshot entry contains `global_features` and one `propeller_features` row
per slot. Feature names travel beside both arrays so their order cannot silently drift. Those raw
diagnostic values deliberately remain in physical units. A model must use a model-specific
encoder; the quad-only PPO encoder selects its fixed subset and maps every learned input to
`[-1, 1]`.

A conventional dense neural network still needs fixed dimensions for one trained policy. The
model-forge solution is an editable body draft followed by an explicit **Accept** boundary. Accept
freezes the Core/slot topology into an `MLBodyInterfaceManifest`; only then is PPO allocated with
the resulting action and body-observation counts. Different accepted topologies therefore receive
different model contracts instead of guessing hardware from action count. See
`docs/ml-model-body-contract.md`.

## Interactive training room

Choose **ML Training Room** in the main menu to open the first environment. This room currently
keeps the flight core at four propellers. Fresh PPO groups can optionally install an ordinary
two-segment `GenericLimbDefinition` in a normal belly attachment slot. The model receives four
independent limb controls (shoulder X/Z, elbow Z, grip) in addition to the four propellers, and the
standard grip can hold both `climbable` static surfaces and `carryable` dynamic items.

Target selection is routed per worker group without changing policy tensor sizes. **Target Settings**
shows a **Type** dropdown above **Behaviour**. Selecting a worker-group card edits only that group's
`TrainingTargetHandler`; with no worker group selected, the controls edit the room-default target
used by evaluators. Every group owns its own `TrainingPathTargetSystem`, so two groups can use the
same target type while one orbits and the other follows random waypoints. Branches clone target
configuration into a separate runtime instance rather than sharing path state.

The Navigation-path type can remain stationary, orbit, travel on a line, choose random waypoints,
or move to a live X/Z destination selected on the two-dimensional target pad. Its compact
behavior-specific panel shows only settings used by the current behaviour. Random waypoints expose
bounds, maximum jump distance, waypoint interval and an optional translucent preview. The same
**Path speed** controls Orbit, Line, Random-waypoint and Manual-pad movement. Orbit and Line support
three-axis path rotation, starting phase and direction.

A handler may own several target-system providers simultaneously. `TrainingRegisteredTargetSystem`
is the runtime bridge for many-candidate task systems such as cargo receivers, pickup items, swarm
members and explicit escape points. The handler rebuilds the available candidate list continuously,
uses the hardcoded semantic order survival escape > cargo delivery > cargo pickup > combat objective
> navigation, then deterministically resolves urgency, distance and stable-ID ties. Only the winner
crosses the ML boundary. Existing threat/obstacle inputs and survival rewards remain unchanged; a
future escape planner can publish a `survival_escape` target without replacing those safety signals.
Drones therefore retain their existing target position/velocity/radius inputs, and limb/turret
policies retain their existing target contracts. See `ml/training/targeting/README.md` before adding
another target type.

The **Drone Spawn Position** box controls the common reset point used by every training worker and
saved-model evaluator. Its X/Z pad uses the same room projection as the manual target pad, while a
separate numeric height field controls Y. A cyan world marker shows the exact configured point.
Releasing the pad or changing height restarts the controlled episode so every model begins from
the new position together. Checkpoints record the spawn coordinate as part of their training
environment metadata.

The **Training Obstacles** box now builds unrestricted editable obstacles without scene edits. A shape
picker offers box, cylinder, sphere and capsule primitives; the Dimensions section is rebuilt for
the selected primitive instead of showing irrelevant fields. Each visible dimension has its own
chain toggle, so width and depth can be synchronized without linking height. Link choices are kept
separately for each primitive shape. Positive dimensions have no configured
upper bound, X/Y/Z placement and pitch/yaw/roll are unbounded, and mouse placement/dragging no longer clamps to
the arena rectangle. Mouse placement starts an obstacle on the floor, while the numeric editor may move it anywhere. Existing obstacles remain selectable in the 3D view, highlight when selected,
load their shape-specific values into the editor, and can be moved, reshaped, resized, rotated or
deleted. **Auto Place** keeps mouse placement armed after each click; every click creates another
obstacle instead of moving or deleting the previous one. Its orange moving border makes the armed
mode visible. Existing obstacles are changed explicitly with Apply to Selected. Every obstacle is a solid `StaticBody3D` on the arena collision layer. The extent-aware
static spatial hash registers every X/Z cell touched by each primitive and performs exact local-space
box, cylinder, sphere or capsule ray intersections for the policy sensor. Creating, moving, editing
or removing obstacles restarts the current episode to keep all worker groups on the same environment,
and checkpoints record shape, dimensions, full position and full rotation with the other training settings.
The **Map Library** in Simulation & Camera stores these custom-obstacle layouts independently from
models under `user://ml_training_maps`. Maps are never created automatically. The library can save a
new version, update the selected version, load it into the current room, inspect created/updated/last-used
times, and batch-delete saved versions. The storage path remains available inside the Map Library rather than taking permanent room space.

The left side is split into two independent scanner bars with a visible gap between them. The
first bar stacks **Simulation & Camera** above Worker Groups inside a draggable vertical split. Its
height is large enough for episode controls, spectator controls and the Map Library shortcut, but
the divider can still be dragged at runtime. Camera controls are no longer wrapped in a needless
scroll container. The group list scrolls independently, while a pinned
top bar keeps the `+` action first and the compact all-group play/pause control immediately to its
right. The `+` popup either opens branch-group creation or opens the Model Library to choose a
saved checkpoint for an evaluation drone. The old Compare All Groups button is gone; clicking the
arena still clears the selected group and restores all-group plots. The second bar owns the
remaining collapsible training-setup boxes: drone spawn, target and walls. Target **Type** is the
first target option, immediately followed by **Behaviour** when the selected type exposes path
behaviours; Path speed and Hover radius sit directly below Target height, and the redundant nested
Behaviour & Success Zone box is gone. Every
worker-group card keeps its compact play/pause control in the upper-right corner, animates a
`. .. ... ....` activity indicator while running, and exposes an always-visible worker-count slider.
Changing that slider rebuilds only that group's worker population and restarts the shared drone
episode; every active drone group's incomplete on-policy fragment is discarded at that reset
boundary. Groups keep independent target-handler configuration and deterministic target runtime
state rather than sharing one room-global path. Selecting a card expands its save, model-library, plot, tuning
and removal actions. **Keep newest** is enabled by default and is one of those card buttons rather than a buried settings
checkbox; while rolling overwrite is active, group-colored dashes visibly travel slowly around its border.
Pressing F2 while a group is selected replaces its card title with a blinking
inline editor; Enter or focus loss accepts the name and Escape cancels it. The main-menu action
remains pinned below the setup bar's scroll area.
The right panel has a second navigation layer for **Model**, **Plots** and **Tuning**, so model
files, graphs and advanced learner controls never form one long wall of text. Explanations live in
tooltips instead of permanent paragraphs. The Plots page begins with **Live Model Actions**: one
source-aware tree for every runtime training kind. Drone groups expose all four raw propeller
commands, four-limb groups expose all sixteen direct actuator outputs (three named joint targets plus
the independent grip for each authored limb), and turret groups expose yaw drive, pitch drive and
trigger. Limb channel labels use the group's authored slot names, so custom anatomy stays readable.
Each worker kind owns its own episode trace instead of being cleared by an unrelated drone reset.
The fullscreen button moves the same live inspector into a full-viewport scanner panel, where the
selected worker gains its complete action contract plus readable current/mean/range/saturation
summaries and a dynamically sized condensed episode table. Background opacity is adjustable
only in fullscreen and resets when fullscreen closes. Each worker keeps a bounded current-episode
trace in 0.25-second buckets; when the buffer fills, the smallest adjacent time buckets are merged so
the complete episode remains represented without retaining every control tick. The trace is cleared
only when that worker group begins a new episode, not when a group is merely paused. Clicking the
selected card again or the 3D arena deselects it and replaces detail plots with comparisons for every
runtime model.

Expandable scanner boxes use a short scale/fade transition that ignores simulation time scale,
so the effect remains visible at 8x or 16x. Their lower-right grip can be dragged vertically within
a bounded height; nested minimum sizes propagate through Godot's containers, so expanding an inner
box expands its parent and reflows neighboring children. Double-clicking the grip restores
automatic content sizing.

The Worker Groups, Training Setup and selected-group panels also have thin draggable inner-edge
grips for horizontal resizing. Double-clicking one restores automatic responsive width. Their
collapse buttons remain available independently. Side-panel widths and plot columns adapt to the
current viewport. Plot boxes can be closed,
restored, or expanded without exceeding a bounded share of the visible height. The mouse wheel
zooms a plot's timeline up to 8x around the pointer, middle-drag pans the visible range, and right
click resets it. Every plot also has a **CUT** mode: an orange triangle and dashed guide select the
old timeline section to hide, after which the remaining points expand across the complete chart.
Episode averages appear only after every worker in that group has finished, so a half-calculated
point cannot move the graph scale. Expanded plots also add grid labels, point markers and numeric
latest/minimum/maximum summaries. Over the 3D arena, middle-drag changes the spectator orbit and
the mouse wheel zooms from a 1.25-metre close inspection to a 150-metre overview. Evaluation-drone
cards are selectable and use the existing **Selected group / evaluator** camera mode rather than a
separate evaluator-only setting. The Camera box can smoothly center/follow the room, live target,
spawn point, selected worker group/evaluator, or all drones. **Random selected-group drone
(attached)** chooses a live worker at every episode start, makes that drone's installed camera part
current, and moves to another living worker if the host finishes early. Automatic orbit still works
for spectator modes and can rotate in either direction at an adjustable speed. Finished drones
fade out of group/all-drone spectator centroids over one real-time second, preventing crashed bodies
from permanently pulling the view away while keeping the camera transition visually smooth. A
**Reverse** button sits directly beside Auto orbit so its direction can be flipped without entering
a negative speed value.

The observer is a reusable `DroneCameraAttachmentDefinition`, installed through a normal core
attachment slot where one is free. It contributes exactly zero loadout mass, consumes no power, has
no collision or visual geometry yet, and creates its `Camera3D` from part-defined mount/FOV/clip
settings. A core-mounted fallback preserves fully occupied gameplay loadouts without removing a
weapon or arm; the same resource can later be installed as an ordinary gameplay attachment.

Episode settings include 1x, 1.5x, 2x, 3x, 4x, 6x, 8x, 12x and 16x simulation-speed choices.
The room raises physics tick rate together with Godot's simulation clock so each individual physics
step retains its normal duration; UI telemetry and hitch measurement remain tied to real time.
Leaving the room restores the original engine timing settings.

The selected group's **Drone Parts & Power** box owns a private `DroneLoadout` template. Existing
gameplay core, battery and propeller resources can be installed as presets, then their physical
mass, bus-power, motor-response, drag, capacity, fluctuation and rotor-aerodynamic values can be
edited without mutating the original `.tres` resources. A quick **Linked flight power** field
changes all four propeller caps plus the battery and core bus ceilings together, preventing a
hidden power bottleneck; a calculated summary reports mass, estimated hover power and nominal
lift-to-weight ratio. Target height is the literal world-space drone objective height; the marker,
hover-radius ring, observations, reward, and evaluator all use that same Y value with no hidden
vertical offset. Rotor power changes lift and climb authority. Hardware edits lock while a group is running, branches inherit a
deep private copy, checkpoints serialize the exact part stats, saved evaluators reconstruct them,
and loading a modern checkpoint restores its hardware alongside its policy. Both installed
learners retain the same validated four-motor action contract; each owns its own observation tensor.

Finished drones are intentionally frozen at their terminal position until the synchronized episode
ends. A floating terminal-reason label distinguishes a horizontal `left_arena` exit, crash, wall
deadlock, power loss or time limit from a physics body that merely stopped responding. Height is
not an arena boundary: flying over walls or making a large vertical excursion no longer terminates
an otherwise valid episode. When a terminal label appears, one MP3 from
`res://assets/sounds/hit_effects` is chosen from streams cached at room startup and played through
a distance-attenuated 3D player fixed at that drone's terminal position. The default is now -16 dB
and can be adjusted from -40 dB to a safety-capped -3 dB in the episode settings. A bounded shared
player pool prevents a mass crash from stacking an ear-splitting number of effects.

The right panel deliberately separates the live training policy from a stored model being
inspected. A new
worker group always says that it is a fresh session initialization unless a user explicitly
branches it or loads a checkpoint. Merely highlighting an old checkpoint in the Model Library never
changes a running group. The larger, centered, resizable and title-bar-draggable Model Library shows
lineage, update/step counts, creation time, the most recent saved training update, last use, exact-score
semantics, reward provenance and the runtime observation/action contract. It preflights a
checkpoint before spawning an evaluator and validates the evaluator's first four motor commands
after reset, so an incompatible checkpoint reports an error instead of leaving a silent frozen
drone. The library has a checkbox on every version plus Select All and Clear controls, so any
number of checkpoints can be batch-deleted through one explicit confirmation. Successful deletions
remove each selected version folder, checkpoint and recorded runs; already-running in-memory
policies are not silently changed, and partial filesystem failures are reported without hiding the
versions that could not be removed.

### PPO learner

The first learned model is intentionally quad-only. It uses:

- a 34-value current actor observation with every value finite and normalized to `[-1, 1]`;
- target offset and target-relative velocity, angular velocity, local gravity direction, ground
  clearance, target radius, available power, realized actuator response, nearest-obstacle
  direction/clearance and direct-target-path occlusion;
- eight 12-metre egocentric wall-clearance sectors plus the target-path wall distance and the
  blocking wall's height relative to the drone, giving a new policy enough local geometry to choose
  corridors or climb over a barrier; sector bearings follow heading only, so roll and pitch do not
  rotate or skew the horizontal maze map;
- no duplicate target/body velocity triplets and no redundant nine-value rotation matrix;
- a lossless collective/roll/pitch/yaw transform of the four rotor feedback values, which removes
  their obvious common-mode correlation while retaining all actuator information;
- one critic-only episode-progress value, for 35 current critic inputs;
- a 32x32 tanh Gaussian actor with four sigmoid-bounded motor outputs;
- a separate 32x32 value critic;
- clipped PPO, GAE, Adam, advantage normalization, entropy regularization, gradient clipping and
  KL early stopping; and
- independently configurable control rates from several non-colliding Godot physics workers; and
- detached low-priority optimizer threads with a stable behavior-policy copy, so PPO keeps the
  same minibatch/epoch/Adam semantics while backpropagation never monopolizes the UI or physics
  callbacks.

The actor starts close to the known hover command instead of random zero thrust. Exploration is
still stochastic, but this makes the first rollouts informative instead of making every drone
immediately fall. The network and optimizer are implemented in GDScript; no Python, PyTorch
process or network service is required.

A comparison against the initial imported PPO implementation found no change to clipped-ratio,
GAE, Adam, entropy, gradient-clipping or minibatch mathematics. The learning regression was in the
surrounding reward/sensor contract: an over-broad terminal correction removed useful progress, the
smoothness cost scaled with high control rates, and tilted body-local wall direction could contain a
misleading vertical component. Those contracts are corrected without changing PPO update equations.

The runtime hot path uses compact PPO-only snapshots at the decision rate rather than rebuilding
the larger diagnostic schema on every physics tick. Held actions, normalized motor commands and
thrust targets are cached; inference and backpropagation reuse fixed neural-network workspaces;
wall sensing is phase-staggered between workers and follows the policy control interval up to 100
Hz, while one spatial-hash candidate lookup is reused by the full local ray set; plot histories are
redrawn only when visible data changes; and the expensive feature-correlation audit runs on the
background optimizer on the first and every twenty-fifth update. Evaluator policies are also cached between
episodes instead of being reloaded from disk on every reset. These hot-path changes reduce simulation overhead without dropping samples or changing the
meaning of a selected observation schema.

Maze sensing was introduced in observation schema v4, which stores 34 actor and 35 critic inputs.
Observation schema v5 keeps that exact tensor size but corrects the compact nearest-wall direction to
heading-relative horizontal coordinates, so roll and pitch cannot inject a false vertical wall
direction. Existing schema-v4 checkpoints remain resumable and continue receiving their original
full-body-local wall direction; the trainer encodes observations according to the loaded policy's
schema instead of silently changing its learned input contract. Schema-v3 checkpoints retain their
original 24/25 input meaning and remain deterministic-evaluator-only because their network width is
different.

### Maze SAC + Hindsight Replay

`Maze SAC + Hindsight Replay` (`sac_her_maze`) is a separate reinforcement-learning option, not a
replacement for PPO. Select it in the new-group dialog when the task contains corridors, corners,
dead ends, or a target whose direct path is blocked.

The learner adds these mechanisms:

- off-policy Soft Actor-Critic updates with a stochastic tanh-Gaussian actor. Its four
  normalized actions map one-to-one to propeller slots 0, 1, 2 and 3, matching PPO. The actor also
  predicts four observation-dependent log standard deviations, so exploration can remain broad in
  uncertain/open states and become precise around a stable hover without changing the raw-motor
  action contract. Twin Q critics, target critics, entropy exploration, Adam and gradient clipping
  remain in the same normalized raw propeller action space;
- a replay ring that reuses experience from many earlier policies instead of discarding every
  transition after one rollout;
- Hindsight Experience Replay after each completed worker episode. Future safe positions are
  relabelled as achieved goals, so a failed maze attempt still teaches which intermediate places
  were reachable;
- a private two-dimensional visitation grid per worker. The actor receives current, near and far
  visit density in eight heading-relative sectors plus a least-visited open heading, allowing it to
  distinguish a new corridor from a repeatedly explored dead end; and
- maze-specific shaping that cancels only the direct-distance penalty caused by moving away from a
  target while the target ray is blocked, plus a small configurable bonus for entering a cell absent
  from that worker's timed visitation memory. Each worker owns its own cell timestamps, revisits pay
  nothing until the configured cooldown expires, and the memory resets at episode boundaries. Existing
  collision, stability, target-radius and failure rewards remain authoritative.

The SAC actor receives the existing 34 normalized flight/wall features plus 19 visitation features
(53 total). Its critic adds episode progress (54 values), and each Q network receives those 54
values plus four four normalized hover-relative raw propeller actions. SAC's target-forward, realized
right/forward control and least-visited-forward features use the same positive signs as those actions;
PPO retains its existing feature meanings for checkpoint compatibility. The default networks use two
64-unit hidden layers. Before policy sampling begins, each worker independently collects temporally
held, hover-centred axis-control segments so the first replay data contains coherent translations
and turns rather than uncorrelated rotor noise. Relabelled goals rebuild their goal-dependent wall
fields and use signed distance progress on the same scale as the real approach reward, rather than a
sparse success spike. Goal-dependent wall fields are rebuilt from the still-valid egocentric lidar
sectors instead of reusing geometry captured for the original target.

SAC checkpoints save the eight-output actor (four motor means plus four state-dependent exploration
heads), both critics, target critics, optimizer state and
configuration. Replay contents and the temporary per-episode map deliberately start empty after a
load, because persisting a large environment-specific replay buffer would make checkpoints huge and
could mix obsolete wall layouts into a new lesson. Existing PPO checkpoints and PPO training math
remain unchanged and cannot be cross-loaded into SAC groups.

Schema-v4 SAC checkpoints with four learned motor means plus four global exploration values remain
loadable. Migration copies the complete learned motor policy and critic state, initializes each new
variance head with zero state-dependent weights and the matching old global value as its bias, and
writes schema v5 on the next save. The first action distribution after migration is therefore the
same distribution the old checkpoint used; specialization begins only through later training.

For a maze lesson, keep obstacle and failure rewards enabled, give the episode enough simulated time
to complete the required detour, and begin with several reachable corridor layouts before adding
long dead ends. The learner improves the representation and credit assignment for this task; it
does not hard-code a pathfinder or guarantee that every maze will be solved without sufficient
experience.

When a SAC episode ends in ground impact or wall contact, HER no longer throws away the default
relabelled sample merely because the final achieved state is unsafe. It searches the episode's
future states once, selects the latest safe achieved state for the default sample, and draws any
additional goals only from safe future states. The actual impact/contact state is never labelled as
a successful goal.

The room distinguishes four concepts:

1. **Worker group:** an independent mutable learner branch with its own workers, algorithm settings,
   statistics and plots.
2. **Training workers:** disposable drone instances gathering experience for their group's shared
   policy. Workers inside one group are not separate models.
3. **Behavior policy:** the stable live policy used for action sampling while a private low-priority
   CPU thread processes a detached PPO rollout or SAC replay update.
4. **Saved checkpoints:** append-only model versions by default. A group can opt into **Keep only
   newest save**, which creates one new group-owned rolling version and updates only that exact
   version afterward. A loaded or branched source checkpoint is never used as the rolling target.
   Loading resumes the exact network and Adam state.

An algorithm update label means an optimizer result changed the live weights; it is not a disk
save. PPO evaluates fixed-policy rollout groups and preserves the exact behavior-policy weights of
its robust winner. SAC learns continuously from replay, so its best completed-episode candidate is
the live policy snapshot associated with that episode and is explicitly marked as non-exact rather
than claiming perfect rollout-policy identity. Cards show an amber pending indicator followed by a
green **AUTO-SAVED** version indicator. PPO selection never reweights or replays PPO samples, while
SAC replay and hindsight transitions remain private to the SAC trainer.

Creating a new branch group opens a manually centered setup dialog. It copies the selected live
model core, starts fresh with no selection, or opens the centered Model Library so a saved trainable
checkpoint can be inserted directly as the new root group's exact starting policy. Live branches can
add seeded Gaussian weight variation relative to each network's
existing RMS weight magnitude, accepts a group/checkpoint name, and independently enables or disables
approach, radius-hold, survival, ground-safety, smoothness, obstacle and failure reward components. The same dialog now sets
starting workers, control rate, exploration strength, and whether the branch starts immediately;
compatible branches inherit the parent's remaining algorithm configuration before these explicit
starting overrides are applied. **Apply to all groups**
deliberately puts every compatible group back on the selected core while preserving each group's
hyperparameters and reward recipe, which makes it easy to evolve the same good checkpoint in
different directions. **Save Best** creates a named copy of the same exact robust rollout winner
that Automatic Best preserves; **Reset averages** clears plots/statistics without changing weights.
Worker count changes throughput, not the model architecture. The branch exploration field maps to
PPO entropy coefficient or SAC entropy temperature according to the selected learner. Its range and
step now change with the algorithm: PPO exposes 0–2.0 in 0.005 steps, while SAC exposes only its
actual 0–0.05 temperature range in 0.0005 steps instead of silently clamping a misleading generic
value. SAC's temperature now regularizes observation-dependent variance heads rather than one global
noise value per motor. A manually aborted episode discards PPO's incomplete rollout, while SAC keeps valid replay
transitions but clears unfinished hindsight bookkeeping and visitation memory.

Runtime groups are shown as a VS Code-style lineage tree. Every descendant remains a complete,
independently selectable scanner box with private learner state. **Branch Variant** can create a child
from any live node; the default 2.5% variation is deliberately small and its inherited Adam
momentum is cleared. **Make Root** moves a branch to the top level while keeping every descendant
attached, so an entire promising subtree can become its own model family. Removing a parent moves
its direct children up one level instead of hiding or deleting them.

### Model versions

The room includes a lightweight model registry. New groups begin with **Keep newest** enabled, so
manual and automatic saves reuse one group-owned version unless you turn that button off. With the
button off, **Save Best Version** and **Save Current** create numbered artifacts such as `Model X v0001`,
then `v0002`. New robust-score records also create **Automatic Best** artifacts. A worker group's
**Keep newest** card button changes only that group to a rolling mode: its first save creates a new version, and later manual or
automatic saves replace the checkpoint inside that same version folder. Turning the toggle off ends
that rolling chain; turning it on again starts another new version. Source/parent versions are never
overwritten.
**Spawn Evaluator** can create any number of independent runtime instances of any saved version.
A version-derived color makes instances with the same saved parameters visually identifiable.
Evaluators appear below the worker-group lineage as their own scanner boxes, with model inspection
and removal actions. Removing an evaluator affects only that scene instance, never its checkpoint.
The episode settings include **Evaluation drones keep episode running**, disabled by default. While
training workers exist, unfinished evaluators are closed as recorded truncations when those workers
finish, so a deterministic observer cannot hold the next training episode open. Evaluators still run
to their normal completion when no training worker is active.

The all-model dashboard averages all workers in a group into one point per episode, avoiding a
misleading stack of worker traces. Its comparison plots cover reward per second, time inside the
target radius, final distance, critic loss, policy-change KL, and saved-best improvement. The
checkpoint-improvement plot uses only artifacts whose metadata says the score exactly belongs to
the saved weights. PPO robust winners qualify; SAC's online episode snapshots and **Save Current**
artifacts are not falsely presented as exact comparisons.

Persistent artifacts use this layout in the Godot user-data folder:

```text
ml_models/
  model-x/
    v0001/
      model.json
      checkpoint.json
      runs/
        run-<timestamp>-<sequence>.json
    v0002/
      model.json
      runs/
```

`model.json` contains the model identity, topology, creation time and parent version. New PPO
manifests also carry a deployment contract for the runtime model: observation schema, actor/critic
input sizes, body/action topology, control interval and intended drone body kind. The checkpoint
records the reward recipe and training-room configuration that produced it. Manual
baselines store their parameters there; PPO versions store the network, Adam moments and training
counters in `checkpoint.json`. Each completed evaluation writes a separate result file under the
exact checkpoint revision that produced it. Updating a rolling version increments its revision,
removes result files associated with the replaced weights, and rejects late evaluator results from
the stale in-memory revision. The library can explicitly delete selected versions after confirmation.

### Controlled episodes

Every active model instance participates in the same controlled episode. At episode start,
all drones receive the same configured spawn transform, full battery/health, cleared controller
and power-bus state, target timeline, duration and random seed. **Unlimited battery during episodes** is enabled
by default because the normal `Minute Cell` is deliberately exhausted after roughly one minute;
with the option enabled, stored charge remains full while battery mass, voltage, output limits and
power fluctuations stay physically unchanged. Disable it when battery endurance or power-loss
recovery should be part of the lesson. Drones share the arena collision but ignore one another,
so the room no longer needs one collision layer per instance and imposes no artificial trial
count limit.

An episode ends for an individual candidate when it:

- loses power or is destroyed;
- leaves the arena;
- remains trapped in the same wall-contact pocket for three seconds; or
- reaches the configured timeout.

Ground contact and inverted orientation are deliberately **non-terminal by default**. Drone-family
groups expose two optional per-group training cutoffs under **Tuning → Workers and Control**:
`End episode on low ground contact` and `End episode when flipped`. These legacy conveniences are
kept for tasks that need them, but creator-built ground bodies may otherwise tumble, roll, spin,
recover, or intentionally use non-upright locomotion. The ground-safety reward remains independent
of episode termination.

The two left panels and the selected-group panel on the right each have a persistent edge button
that collapses the panel to a narrow strip without stopping training. Drone terminal sounds are
cached when the room opens; their shared positional-player pool uses an adjustable -40 dB to -3 dB
volume control in the episode settings, with -16 dB as the default.

Finished candidates freeze while the remaining candidates continue. The live episode line and
completion message show the actual elapsed/configured time plus a count of each ending reason,
so an early stop is distinguishable from the configured timeout. The room records reward,
termination reason, `terminated`/`truncated` flags, seed, target configuration and final
position, then resets all active instances together for the next comparison. Physical task
failures are terminal states; reaching the configured time limit is a truncation. Keeping that
distinction is important for future value-learning algorithms. Adding a version or changing
target/episode settings aborts the partial comparison and restarts every instance from the
shared initial state; incomplete runs are not mixed into evaluation history.

`DroneTrainingReward` produces a decomposed transition reward:

- **Approach:** the exact decrease in distance to the elevated drone objective, normalized over
  10 metres, plus a very small frame-rate-independent search-time cost while the drone remains
  outside the accepted radius. The objective is the selected target/reference point plus a fixed
  2 m vertical offset. Reward depends on metres of actual progress during the step, not on how far
  away the drone currently is; one metre closer is `+0.1` and one metre farther is `-0.1`, capped
  to `[-1, +1]` per reward step. Circular or wiggling motion at constant distance cannot farm it.
  Unreached episodes keep this complete dense signal; there is no longer a terminal correction that
  flattens every useful partial flight back below zero.
- **Radius hold:** one point per second inside the accepted radius around that elevated objective.
  This remains the dominant positive reward and is frame-rate independent.
- **Survival:** a small dense reward grows later in the episode. Its budget is `+0.01 × duration`,
  capped at `+0.20` total. Reaching the actual time limit adds `+0.05 + 0.005 × duration`,
  capped at `+0.20`. The combined survival signal is intentionally tiny beside sustained radius
  hold, but makes continued viable flight preferable to immediate failure.
- **Ground safety:** the independent downward ray supplies ground clearance. Descending below 2 m
  receives a clearance- and descent-speed-scaled penalty, with an additional small critical-clearance
  cost below 0.65 m even if descent has almost stopped.
- **Action smoothness and abuse:** command changes smaller than `0.04` are ignored. Larger jumps use
  the existing time-normalized smoothness cost. Brief extreme commands remain free, but after
  0.25 s of continuous output near 0/1 or a motor spread above 0.75, a bounded `-0.08/s` maximum
  penalty discourages constant one-propeller/full-saturation suicide without changing the raw four
  propeller action contract. Repeating an unchanged setpoint is already held by the controller and
  is not treated as another physical motor command.
- **Obstacle avoidance:** a gravity-aligned short-range fan plus velocity- and target-directed
  probes preserve the compact nearest-wall signal. Eight longer egocentric sectors describe open
  corridors, while a separate target ray reports both distance to a blocker and its top height.
  Sensing follows the policy control interval and uses exact primitive intersections. A small
  penalty applies only while moving into nearby geometry, plus a bounded one-time contact penalty.
  Proximity alone and moving away are not punished.
- **Failure:** destruction, power loss, arena exits and confirmed wall deadlocks terminate the
  episode. The optional per-group low-ground and flipped cutoffs also count as terminal failures
  when explicitly enabled. The base penalty is `-1`. During the first five seconds, an additional
  penalty up to `-2` fades to zero, making deliberate immediate suicide more expensive than spending
  several seconds attempting recovery. Ground contact and sustained inversion alone are otherwise
  non-terminal; time limits remain truncations and bootstrap from the critic.

This contract is reward schema v4. Older checkpoint weights remain loadable, but scores from earlier
reward schemas are not comparable; continuing training clears the old best-score baseline while
preserving network and optimizer state. Every trial exposes step, total and reward-per-second values
plus all decomposed components for diagnostics and plots.

## Training progression

Start with a stationary target, a generous hover radius and several workers. Once saved evaluators
reliably approach and remain in the radius, reduce the radius and then enable line, orbit or
random target motion. This is manual curriculum learning: the environment becomes harder while
the same checkpoint lineage continues.

Godot-native training favors inspectability over maximum throughput. A future large-scale GPU
trainer can reuse the same observation/action/reward contract, but is not required for the first
working controller.

### High-count training performance

The training room uses the full authoritative `ServerDrone` physics contract, but removes work that
has no effect on local ML workers:

- hidden training/evaluation drones are omitted from multiplayer snapshot serialization;
- ML control disables the combat/ORCA consumer flags that would otherwise keep the general dynamic
  entity spatial hash awake;
- static propeller properties, collision radius, spool/drag values, attachment presence and maximum
  rotor thrust are cached when the loadout changes instead of rediscovered during every
  physics/control step;
- perfectly regulated powertrains use an exact constant-output path instead of evaluating unused
  fluctuation sine waves and spike RNG every physics tick;
- passive camera-only loadouts remain on the attachment fast path, so they do not trigger power, cooldown, targeting or weapon processing;
- ground effect remains exact for normal gameplay, while training refreshes one rotor probe per
  physics tick after an exact four-rotor warm-up;
- the maze sensor performs one cached extent-aware wall query and one batched primitive-shape pass for
  its full ray fan instead of repeating Dictionary/transform work for every ray;
- a next action's critic value is reused as the previous transition's bootstrap value, removing one
  redundant critic network pass per ordinary worker decision without crossing PPO policy revisions;
- completed frozen workers stop power/controller/rotor simulation and contact reporting while they
  wait for the remaining workers; and
- training-only drone meshes do not cast shadows.

These changes remove accidental duplicate and hidden-system work, but the remaining physics and
network inference still scale approximately linearly with active workers. Simulation speed multiplies
that load directly: 16x speed preserves 60 simulated physics ticks per second by running 960 physics
ticks per real second. A group of eight workers at 60 Hz therefore requests 7,680 actor/critic decisions
per real second. Lowering control rate or simulation speed remains the correct way to trade temporal
fidelity for additional workers after the avoidable overhead is gone.

### Normalization and feature correlation

The readable snapshot is telemetry, not a neural-network tensor, so it keeps volts, watts, metres
and the rest of the physical state. `DronePPOObservationEncoder` is the only PPO input boundary and
guarantees that all 50 current actor values and all 51 critic values lie in `[-1, 1]`. Schema 7
appends nine turret-threat values to the schema-6 actor contract; the critic keeps all 42 schema-6
columns as an exact prefix before those appended values. Older schemas remain available for saved
model compatibility.

PCA is intentionally not fitted before representative rollouts exist. A PCA transform fitted on
guessed or early-only states can discard rare but control-critical voltage/attitude signals, and
changing that transform later would change the meaning of saved checkpoints. Known algebraic
redundancies are removed directly instead. After every PPO update, `DronePPOFeatureAudit` measures
the actual rollout's varying features, numerical rank, maximum absolute Pearson correlation and
any pair with `|r| >= 0.995`. The report appears in the learner status panel and is stored with
checkpoint metrics. Constant features are listed separately because a stationary-target lesson
will naturally keep some valid future-task inputs constant.

The selected-group panel exposes and restores all settings that materially affect the implemented
learner: worker count, control rate, background optimizer chunk size, learning rate, discount
factor, GAE lambda, clipping, entropy, value loss, gradient cap, update epochs,
minibatch/rollout sizes, partial-update minimum and target KL. These controls lock while that group
is running so a rollout is not collected under changing settings. Background scheduling changes
only where the configured optimizer work executes; it does not reduce rollout size, epochs,
minibatches, or Adam steps.

### Learning-algorithm boundary

`DroneTrainingAlgorithm` is the stable contract between the room and a learner. An implementation
owns action sampling, transitions, background updates, configuration definitions, branching,
status metrics and checkpoint serialization. `DroneTrainingAlgorithmCatalog` owns the installed
algorithm descriptors and factories. Group creation, tuning controls, copy/load compatibility and
checkpoint metadata use this interface rather than concrete PPO fields.

Two learners are registered: Clipped PPO + GAE (`ppo_clip`) and Maze SAC + Hindsight Replay
(`sac_her_maze`). The hand-written baseline is an evaluation controller, not another training
algorithm. The branch dialog renders the selected implementation's own tuning controls. Cross-
algorithm weight copies are rejected; branches can copy weights only within the same compatible
algorithm family.

## Design references

- [Proximal Policy Optimization Algorithms](https://arxiv.org/abs/1707.06347)
- [High-Dimensional Continuous Control Using Generalized Advantage Estimation](https://arxiv.org/abs/1506.02438)
- [Soft Actor-Critic: Off-Policy Maximum Entropy Deep Reinforcement Learning with a Stochastic Actor](https://arxiv.org/abs/1801.01290)
- [Hindsight Experience Replay](https://arxiv.org/abs/1707.01495)
- [Deep Reinforcement Learning at the Edge of the Statistical Precipice](https://arxiv.org/abs/2108.13264)
- [Population Based Training of Neural Networks](https://arxiv.org/abs/1711.09846)
- [What Matters in Learning a Zero-Shot Sim-to-Real RL Policy for Quadrotor Control?](https://arxiv.org/abs/2412.11764)
- [Curriculum-based Sample Efficient Reinforcement Learning for Robust Stabilization of a Quadrotor](https://arxiv.org/abs/2501.18490)


The SAC actor and both Q critics use the same four independent physical propeller channels as PPO:
action indices `0..3` map directly to propeller slots `0..3`. The stochastic policy represents each
channel as a hover-relative residual, but the environment, replay buffer and critics retain the raw
per-propeller command contract. No learned-policy mixer or premade movement action sits between the
network and the drone. Initial replay is populated by per-worker, temporally held raw-propeller
segments. The learned actor does not take over until the replay threshold and multiple detached
optimizer updates are complete.

## Four-limb physical bodies

The default training room supports drone, four-limb, and stationary-turret groups in one arena while
each body type keeps its own trainer/checkpoint contract. Four-limb profile v12 uses a fully simulated
core, four physical two-segment limbs, twelve direct joint targets, four direct grip actuators, and a
flat rough plantar pad separated beyond each distal capsule tip. Observation schema 14 uses 420 values,
including authored pickup-item Reward value, and keeps surface-to-surface grip-target semantics; old limb policies are not a compatibility target and
should be retrained when these contracts improve. Live limb decisions run actor-only; PPO critic
values are deferred to the detached optimizer and reconstructed from the frozen producer snapshot.
The neutral startup settle likewise avoids rebuilding the full observation tensor every physics tick and snapshots once when the first policy decision begins.


## Stationary turret workers

Stationary turrets are first-class physical workers with a private base part, gun part, PPO trainer,
reward deck, model library, branching, rolling saves, plots, camera selection, worker-count controls,
and manual override for worker 1. The three continuous outputs drive a rate-limited yaw servo, a
rate-limited pitch servo, and the trigger; neither learned nor manual aiming can teleport the barrel.
Shots are finite-speed projectiles with cooldown, range, spread, wall occlusion, and confirmed-hit
accounting. Turret observation schema v5 exposes 35 normalized inputs, including separate
`target_is_combat` and `target_is_shootable` bits so live combat bodies, synthetic range targets, and
aim-only task objectives cannot become observationally identical while requiring different trigger
behavior. Drones, limb bodies, and turrets publish one shared `TrainingCombatantAdapter` contract
into `ServerSpatialHash3D`, which is used for targeting, hit delivery, and versioned threat perception.

The generic limb stack accepts arbitrary segment counts and independent end-effector definitions.
`GenericGrip3D` can hold tagged static climbing surfaces or apply equal/opposite force to tagged
dynamic carryable bodies. `GenericLimbAssembly3D` accepts any rigid host; `ServerDrone` uses it for
`DroneLimbAttachmentDefinition` loadout parts. PPO derives every controlled joint axis and end-effector
channel from the accepted body manifest; SAC remains deliberately propeller-only for now. Ordinary `ItemDefinition`
resources are grippable and tagged `carryable` by default; `ServerItem` publishes that contract and
can explicitly opt out per definition.

Reward cards are shared across worker kinds. Limb built-ins include Ground Locomotion, Climbing /
Grip, Long Jump, and Item Pickup. Stock distal effectors combine a real rough box sole with the same
independent direct grip action; the grip can perceive compatible surfaces before physical latch range and anchors its physical support
point to the target surface instead of pulling the sole center through it, while support/slip observations
count only genuine sole contact rather than lower-leg scraping.
