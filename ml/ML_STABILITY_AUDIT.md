# ML Stability Audit — 2026-08-08

## Scope and policy

This ledger now covers three consecutive static stability passes on the 2026-08-08 ML handoff. The current pass started from the previous packaged source state (the ZIP did not contain the original `.git` history) and re-audited the active ML/training stack plus the shared hardware serializers reached by ML checkpoint restore.

The project policy for ML code is **correctness over old checkpoint compatibility**. Observation/action schemas, model state, trainer state, evaluator contracts, and persistence formats may change when that produces the technically better system. Old trained models are not a reason to preserve a weaker contract.

This document is a ledger for repeated audits. “Statically verified” means the implementation and its invariants were followed through the relevant producer/consumer code and backed by regression assertions where practical. It does **not** mean that Godot/Jolt runtime behavior or convergence has been proven without running the engine.

## Statically verified core areas

### 1. PPO transition and return semantics

Audited for drone PPO, four-limb PPO, and turret PPO.

- A **true terminal** transition has zero bootstrap and does not require a fabricated successor observation/value.
- A **truncation** is not treated as death: it requires a valid final successor and bootstraps from that state.
- `terminated && truncated` is rejected as an impossible boundary.
- Transition duration must be finite and positive before entering rollout state.
- Discounting uses actual elapsed simulation time relative to the configured reference interval.
- GAE lambda uses the same elapsed-time reference semantics as gamma, so changing control frequency does not silently change the estimator's trace horizon.
- Four-limb and turret scheduling keep scheduler phase/remainder separate from the actual duration for which an action was held. `fmod()` remainder is not counted twice.
- Drone PPO Candidate nomination uses accumulated transition seconds rather than `sample_count * nominal_interval`.

### 2. SAC/HER Bellman and replay semantics

Audited for the current drone SAC-HER implementation.

- `done` is required to agree with `terminated` at replay-load and optimizer boundaries.
- True terminals do not bootstrap.
- True terminals may omit successor actor/critic tensors entirely; the critic target is the terminal reward without evaluating a successor policy or target Q.
- Continuing and truncated transitions still require valid successor tensors.
- Invalid/non-finite/zero transition durations and contradictory boundaries are rejected before replay insertion.
- A terminal frame whose destroyed body can no longer produce a valid goal/successor snapshot remains trainable as the real failure transition.
- Such a terminal frame is excluded from HER relabeling rather than fabricating an achieved goal, while the already-collected valid episode prefix is still eligible for HER processing.
- Exploration cooldown/time bookkeeping advances from actual transition duration.
- Full training resume restores durable learner state (network/optimizers, replay, replay index, RNG/counters) but intentionally does **not** restore worker-ID keyed episode/navigation/warm-up state without a matching physics-world snapshot. Full-resume schema/ring/counter/RNG metadata uses type-safe conversion so malformed continuation JSON cannot throw before the transactional restore guard.

### 3. Optimizer/network state integrity

Audited for all current PPO actor-critics and drone SAC.

- Model/network loads are transactional: a valid actor followed by a corrupt critic/optimizer section cannot leave the live policy half replaced. Schema/count/RNG/optimizer metadata uses type-safe finite conversion and nested actor/critic/Q state shapes are checked before typed loader calls, so wrong-type JSON metadata is rejected rather than throwing during restore. Runtime model wrappers and catalog inspection use the same type-safe contract checks.
- Parameter vectors and Adam first/second moments participate in finite-state validation.
- PPO exploration/log-standard-deviation optimizer state is finite-validated as well.
- Trainer checkpoint restore preflights the incoming state before tearing down live state. Coordinator-owned room/loadout/reward metadata is likewise shape-checked and finite-sanitized before a trainer restore can mutate the live policy.
- An in-flight background optimizer is joined/discarded at the restore boundary so an update computed from the old model cannot later overwrite freshly restored weights.
- Trainer configuration sanitization uses finite fallback defaults before applying clamps. `NaN` is not assumed to become safe merely because it was passed through `clampf()`/`maxf()`.
- Runtime drone PPO/SAC model control intervals likewise use finite fallbacks. Four-limb and turret coordinator control intervals now use the same finite fallback at setter, checkpoint, evaluation, scheduler, and terminal-duration boundaries.
- Restored `last_metrics.feature_audit` diagnostics are treated as disposable derived state; malformed diagnostic payloads cannot crash the next background optimizer launch.
- Four-limb and turret PPO checkpoints preserve the trainer seed, minibatch-shuffle RNG state, and behavior exploration RNG state separately from policy weights, so resumed training does not silently restart its stochastic stream or contaminate deterministic policy hashes with sampler state.

### 4. Episode-final reward accounting

Audited for the active drone room, four-limb coordinator, turret coordinator, and deterministic limb/turret evaluators.

- Four-limb and turret workers settle the final accumulated dense-reward interval exactly once before timeout/death terminal adjustment.
- A timeout with no valid final successor becomes an invalid-observation terminal instead of incorrectly bootstrapping from stale state.
- Non-finite four-limb physics is a terminal `unstable_physics` failure, not a retryable policy fault that can leave a broken worker alive forever.
- Structural settling failures such as a missing adapter terminate the worker rather than silently exiting settling and stalling the group.
- Four-limb deterministic evaluation distinguishes genuine gameplay death reasons from actual non-finite physics.
- The active drone room does not encode a dead body's successor state for a true terminal transition; truncations still encode a real successor for bootstrap.

### 5. Deterministic Candidate/Best selection

Audited across drone PPO, drone SAC, four-limb PPO, and turret PPO.

- Deterministic evaluation suite schema is v2 and scenario descriptors include their planned duration.
- Result validation checks determinism, exact case/seed membership, finite returns, candidate hash, suite hash, and duration.
- Candidate/Best scores are not compared across different suite hashes as if they meant the same thing.
- Evaluation cases of different planned duration use duration-normalized scores for promotion comparison.
- Pending Candidate network state is deep-loaded/validated on restore. Nested Candidate contract/plan metadata is type-checked as disposable derived state across drone PPO/SAC, four-limb PPO, and turret PPO; malformed nested metadata clears the Candidate instead of breaking policy restore.
- The frozen Candidate network hash is recomputed both at checkpoint restore and when an evaluation result is consumed; a substituted/corrupt policy cannot be promoted under another policy's result.
- Invalid pending Candidate state clears its nomination gate rather than blocking future nominations with a ghost score.
- Invalid/missing Best network state also clears Best evaluation/selection metadata so a non-existent policy cannot reject future candidates.
- Selection metadata identifies the current deterministic fixed-seed suite as v2.
- A deterministic summary is eligible for Best comparison only when success/crash/termination/truncation rates are finite probabilities, termination plus truncation is approximately one, and every completed scenario has exactly one terminal/truncated outcome. NaN rate metadata cannot silently disable the safety-regression gate.
- Drone PPO historical Best/Candidate diagnostics are non-authoritative: malformed restored diagnostic blobs or non-finite historical scores degrade to an unverified/empty Best instead of interrupting a valid policy restore.
- Four-limb default deterministic evaluation includes a dedicated climbing case so checkpoint selection cannot optimize only walking/standing while silently forgetting climbing.

### 6. Observation/action and external-input boundaries

Closely audited in this pass or the immediately preceding per-body audits.

- Four-limb observation/action contracts and physical joint/control path are documented separately in `ml/bodies/four_limb/LIMB_ML_AUDIT.md`.
- Drone observation/action and learning-path details are documented separately in `ml/bodies/drone/DRONE_ML_AUDIT.md`.
- Turret body snapshots are validated before malformed/non-finite observations can reach reward or policy code.
- Shared reward-card intensity/min/max/step construction and loading contain non-finite values rather than propagating them into every reward. The older drone `configure_components()` entry point, reward target radius, episode duration, and reward-step duration now use the same finite fallback contract.
- Live pending reward-card changes for drone, four-limb, and turret use finite/type-safe values. Saved reward-card presets cannot bypass the shared card loader with wrong-type booleans or non-finite intensities, and malformed presets are not falsely identified as matching a valid preset.
- Registered/generic/path target systems reject or sanitize non-finite positions, velocities, radius, priority, urgency, distance weighting, and path scalar configuration before those values reach observations.
- Persisted four-limb core/limb geometry, mass, health, damping, joint ranges, attachment transforms, and end-effector/grip parameters use finite fallback values before they can become physics or policy inputs.
- Turret base/gun scalar definitions reached by ML loadout restore use finite fallback parsing rather than relying on `clampf()`/`maxf()` to repair NaN.

### 7. Persistence boundaries

- Drone, four-limb, and turret model registries deep-validate runtime network state and type-check persisted schema/count metadata before accepting checkpoints for persistent storage. Wrong-type checkpoint metadata is rejected instead of being cast during library inspection/save.
- Rolling model/checkpoint JSON writes use temporary-file promotion with rollback rather than truncating the current file in place. Rolling checkpoint + manifest replacement is rollback-safe as a pair: four-limb/turret restore the prior checkpoint if manifest commit fails, while drone rolling saves also stage the old evaluation directory and restore it on failure so a failed save cannot silently delete the previous revision's results.
- Training-map manifest/usage/version-sequence writes use the same atomic replacement pattern. Loaded map timestamps/counts/version metadata, obstacle shape/dimension records, and obstacle transforms use type-safe finite fallbacks so malformed map JSON degrades safely instead of crashing the map browser or injecting non-finite physics geometry.
- Custom reward-cardset persistence uses atomic replacement and explicitly flushes/closes its temporary file.
- Per-run drone evaluation result files remain unique append-like artifacts; a partial failed run file cannot overwrite an existing model/checkpoint.
- Model registry/catalog inspection and saved-model spawning type-check nested manifest/checkpoint dictionaries. Corrupt `training_environment`, `runtime_contract`, `weights`, reward/loadout/target-handler metadata, or network/config blobs degrade to unknown/incompatible/default metadata rather than crashing the model browser/runtime setup or throwing after a live trainer has already been replaced.

## Regression coverage added/expanded in this pass

The existing headless Godot test scripts were expanded to assert, among other things:

- terminal-vs-truncated PPO semantics;
- real-time GAE/discount behavior;
- invalid transition duration rejection;
- transactional/corrupt network restore behavior, including wrong-type schema/nested-network/entropy-optimizer metadata;
- optimizer-moment finiteness;
- SAC replay `done == terminated` invariants;
- SAC true-terminal training without successor tensors;
- durable replay-only SAC full resume;
- Candidate hash tamper rejection and ghost-Best cleanup;
- deterministic evaluator suite/hash/duration contracts;
- invalid turret snapshots;
- non-finite trainer configuration fallback;
- non-finite reward-card configuration containment;
- non-finite target routing/configuration containment;
- non-finite four-limb/turret room control intervals and malformed coordinator metadata;
- malformed nested Candidate/Best/feature-audit checkpoint metadata;
- four-limb/turret trainer seed, shuffle-RNG, and exploration-RNG continuation across checkpoint restore;
- deterministic evaluation NaN-rate and impossible outcome-record rejection;
- malformed model manifest/catalog/browser metadata;
- malformed training-map metadata/obstacle records and non-finite obstacle geometry containment;
- malformed saved reward-card preset matching/queueing;
- legacy drone reward-component/timing/radius NaN containment;
- serialized four-limb body, attachment, end-effector, and turret definition numeric corruption containment;
- model-registry wrong-type checkpoint metadata rejection and successful rolling revision/evaluation-ownership behavior.

These tests were **not executed in this audit environment because Godot is intentionally not installed here**. Static syntax/invariant checks were run instead.

## Limb physics / locomotion audit — pass 3

The third pass followed the user-observed foot placement, skating, poor walking progress, and low FPS through the active `DroneTrainingRoom -> FourLimbTrainingCoordinator -> FourLimbPhysicalBody3D` path.

- Profile `four_limb_physics_v12` fixes the stock sole geometry. The prior v11 sole was centered on the distal capsule tip, causing the physical box to overlap the lower-leg collision volume. The v12 sole is placed beyond the capsule using the shape's directional support radius plus a 3 mm separation gap, remains flat at the authored neutral pose, and participates in the spawn/support envelope.
- Observation schema 13 (the schema current during this historical pass) reflects the corrected grip geometry. A physical grip now measures and springs from the end-effector support surface to the target surface instead of pulling the end-effector center onto/through the target collider.
- Stock ground-locomotion reward no longer permits perfect stationary posture away from the target to produce a positive total. The target-search time cost was raised while target progress remains the dominant potential signal. Planted-foot slip is also materially penalized so translating by skating is less profitable than clean support transfer. Positive target progress is additionally reduced to a small recovery hint only while the chassis itself is load-bearing on the ground, closing the old rolling/crawling reward exploit without gating ugly leg-supported first steps behind upright posture.
- Target/action routing was re-traced: all 16 outputs remain direct per-limb joint/grip channels, and the same routed full-3D target feeds observation, progress reward, success, and telemetry. No static sign/axis or stale-target bug was found in that path.
- Physics CPU work is reduced without changing the control rate: swept CCD remains on the core and four distal contact links but is disabled on the four protected proximal links; free-grip candidate queries use a 10 Hz refresh rather than every 20 Hz policy tick.
- Limb neural-network work on the physics thread is also reduced: live training samples execute the actor only. Current/next critic values are reconstructed on the detached PPO worker from the immutable producer-policy snapshot before GAE, preserving PPO targets while removing the critic forward pass from every live limb decision. Deterministic runtime/evaluation action prediction is actor-only for the same reason.
- Diagnostic CPU contention is reduced: the then-419-feature correlation/rank audit now inspects at most 64 samples every 50 PPO updates (plus the initial audit) instead of 128 samples every 10 updates, and it skips self-correlation calculations. This is diagnostic-only and does not change gradients or policy inputs.
- Startup/reset CPU work is reduced as well: the 0.35 s neutral settle window no longer rebuilds the complete limb observation on every physics tick. Settling performs only the required finite-state/neutral-command checks and captures the first real observation once the episode/action interval actually begins.
- Four-limb and turret PPO now count physical interactions discarded during a background on-policy update in `environment_steps`, matching drone PPO. The samples remain correctly excluded from the rollout; only experience telemetry/checkpoint counters are corrected.
- Static inspection confirms the stock foot material is already maximum friction (`1.0`), `rough = true`, and zero bounce. The remaining question is therefore live Jolt contact/solver behavior rather than an obvious friction-property typo.

## Runtime evidence still required

The following areas should not be marked “proven” from static inspection alone:

- Jolt contact behavior for four-limb soles/grippers under real training load.
- Multi-grip climbing stability and whether grip constraints remain numerically stable under adversarial body poses.
- Whether four-limb policies converge reliably on reach -> grip -> support/pull -> regrip -> mount rather than a crawling/local-optimum strategy.
- Residual hip chatter, skating, foot slip, and posture recovery quality.
- Turret projectile/weapon timing and hit bookkeeping under real physics load.
- Actual sample efficiency, convergence, reward-scale quality, and learned behavior for PPO/SAC/HER.
- Thread scheduling/timing behavior of background optimizers under an actual Godot build, including the deferred limb-critic hydration path.
- Deterministic evaluation scenario behavior in live physics, including the climbing case.
- Long-run file-system interruption behavior on every target OS despite the atomic replacement design.

## Standalone prototype note

The packaged source contains a tracked standalone `ml/training/four_limb/four_limb_training_room.gd` and `.tscn`, but no other project code references that room; the active integrated path is `DroneTrainingRoom` -> `FourLimbTrainingCoordinator`. This pass leaves that standalone loop unchanged because it uses a separate synchronous update path. If that room is intentionally reactivated later, it should be consolidated onto the coordinator rather than allowed to maintain a second training implementation.

## Current audit conclusion

After the final static sweep of this third pass, no additional **substantiated** correctness/stability defect remained in the audited active ML core or its checkpoint-reached hardware serializers that could be patched confidently without runtime evidence. Future audit passes should begin from the invariants above and focus first on new diffs or on runtime evidence that contradicts them, rather than re-opening already-verified contracts without a concrete signal.

## General stability audit — pass 4

This pass re-audited the active ML folder after the limb-physics/locomotion pass, with emphasis on restart behavior, deterministic Candidate/Best state, malformed serialized metadata, replay/HER continuation, and live transition boundaries.

- Four-limb and turret PPO now serialize score validity explicitly. `-INF` ("no nomination yet") is no longer written as an ambiguous `0.0`, so resuming a run with still-negative rewards cannot silently raise the Candidate nomination floor to zero. Real negative nomination/episode scores remain distinct and resumable.
- Shared deterministic evaluation contracts, plans, records, summaries, and promotion comparisons use type-safe finite reads for persisted metadata. Integer fields now reject fractional floats instead of rounding them into plausible schema/seed/ID values, and deterministic/terminal flags must remain actual booleans. Malformed scenario records invalidate the suite rather than being silently skipped/coerced into Best-selection evidence.
- Pending Candidate identity is part of the restore invariant across drone PPO/SAC, four-limb PPO, and turret PPO. A malformed `candidate_id` discards the derived Candidate state instead of surviving restore and failing later in the evaluator/UI.
- `RLTrainingVariantCodec` validates tagged packed-array/dictionary payloads before constructing Godot packed types. Malformed full-checkpoint JSON therefore reaches normal replay validation as an invalid/empty value instead of throwing inside decoding.
- SAC full-replay preflight now proves replay tensor types, booleans, origin/HER consistency, finite reward/duration, and logical transition identity before the live model is committed. Wrong-type tensor fields or logical IDs cleanly reject the checkpoint.
- Live PPO/SAC transition ingestion validates action-sample tensor/scalar structure before typed use. A malformed inference/sample dictionary becomes a rejected transition rather than masking the original problem with a secondary GDScript type error.
- Best-summary diagnostics are non-authoritative across all trainers. A malformed restored `promoted_training_summary.selection_score` cannot break inspection/export of an otherwise valid Best policy; finite deterministic evaluation data remains authoritative.
- The pass3 deferred four-limb critic path was re-traced. Actor actions/log-probabilities remain produced by the live producer policy, and critic values are hydrated from the matching frozen producer-policy snapshot before per-worker GAE. No static semantic regression was found in that optimization.
- The four-limb target/action route was rechecked again and no new stale-target/sign/axis defect was found. Remaining walking/contact questions require the live Godot/Jolt run rather than another speculative wiring change.

### Regression coverage added/expanded in pass 4

Static test sources now cover score-sentinel round trips, malformed Candidate IDs, wrong-type/fractional deterministic-evaluation metadata, strict persisted boolean evidence, malformed variant-codec packed arrays/dictionaries, SAC replay tensor/logical-ID corruption, and malformed live action/transition metadata. The deterministic-suite fixture itself was also corrected to emit exactly one terminal/truncated outcome so its valid-suite assertions actually exercise the success path. These Godot tests remain unexecuted in this environment because Godot is intentionally not installed.

### Pass 4 conclusion

After the final adjacent-pattern sweep, the new substantiated issues in this pass are concentrated at restart/evaluation/replay boundaries rather than in the core PPO/SAC equations or the pass3 limb locomotion changes. Runtime evidence from the user's current test run remains the next source of truth for physics/contact quality, walking convergence, and real threaded performance.

## Turret control / targeting audit — pass 8

This focused pass followed live turret behavior from worker-group target routing through perception,
servo observations, firing, projectile lifetime, reward attribution, and deterministic evaluation.

- Explicit worker-group targeting now has one authoritative selected member. The room publishes live
  members within weapon range, keeps a visible selected member sticky, switches away when that member
  becomes occluded and another visible member exists, and passes the resolved entity id into the gun
  sensor. The target marker and the policy therefore no longer make independent nearest-member choices.
- Automatic sensor fallback prefers a visible candidate over a closer wall-occluded candidate. A
  selected exact member is still honored so UI and gun state cannot silently diverge.
- Turret observation schema 2 / feature schema 2 adds signed intercept yaw and pitch error channels
  (31 total features). This makes the servo-control error directly observable instead of requiring the
  MLP to reconstruct it from base yaw/pitch trigonometry and world-relative target vectors. Old turret
  policies are intentionally incompatible and should be retrained.
- Aim reward shaping is no longer nearly binary around an already-good 0.90 alignment. Visible-target
  alignment now supplies a bounded hold reward plus a signed, telescoping improvement term, while the
  much stricter shot-viability threshold is separate from the learning-shaping threshold.
- Shot discipline is classified at the instant the gun fires using the current selected target, wall
  line of sight, and barrel/intercept alignment. Delayed reward sampling no longer reclassifies a shot
  from the turret pose reached after the projectile was launched.
- In-flight projectiles are tracked and cancelled without reward at episode, pause, manual/autonomous,
  target-group, worker-removal, and behavior-policy swap boundaries. Delayed rounds cannot assign an
  old action's hit/miss to a new episode, target task, or policy revision.
- Explicit target-group changes are action boundaries rather than physical episode resets: old rounds
  and pending weapon events are cleared, the held action is neutralized, and the next physics tick is
  forced to sample against the new target task.
- The deterministic occluded-target case now defines success correctly: withholding bad fire behind
  cover can pass. Previously its generic "hit or precise visible aim" condition made the occlusion case
  impossible to succeed at by behaving correctly.
- Turret evaluation scenario manifest version is bumped so the changed evaluation semantics cannot be
  compared against results produced by the prior suite contract.

Runtime evidence is still required for servo feel, target-switch behavior under real moving/occluded
worker groups, and actual PPO convergence with the denser aim shaping.

## General ML bugfix audit — pass 11 (2026-08-08)

This pass started from the current turret-targeting/UI/telemetry project snapshot and treated the
previously audited PPO/SAC equations, deterministic Candidate/Best contract, four-limb target/action
route, and current turret target-routing work as sanity-check areas rather than reopening them without
a concrete signal.

### New substantiated fixes

- Four-limb and turret PPO no longer replace a live worker action in the middle of its physical
  control interval when a detached optimizer result is adopted. The old behavior action remains
  active until the normal decision boundary, so the reward calculation receives the full elapsed
  interval between its previous and current observations. The one held action that straddles policy
  adoption is counted as a real environment step but discarded from the new on-policy rollout,
  matching the already-safe drone PPO boundary semantics. This removes a reward/time-accounting
  discontinuity that could distort per-second shaping and derivative-like reward terms exactly when
  a new policy revision became visible.
- Current-format drone and turret reward-card configuration loading no longer coerces arbitrary scalar
  values such as the string `"false"` to booleans. Current configuration uses the structured shared
  reward-card dictionary contract; the drone's separately named legacy loader remains the explicit
  compatibility path for old enabled-component maps.
- Turret and four-limb action decoding now type-check schema and numeric action fields through the
  shared finite conversion helpers, and the generic drone action validator type-checks dictionary
  slot identities before comparison. Malformed actuator dictionaries are rejected at the body-control
  boundary instead of risking secondary GDScript numeric-cast failures.
- The branch-dialog tooltip now uses the common user-facing term `Exploration strength`; the leftover
  `entropy coefficient` wording no longer disagrees with the PPO/SAC tuning controls.

### Recent turret/UI work sanity-checked

- Turret group cards contain the `+` worker-placement control next to the turret count.
- Turret Candidate evaluation status uses the room's shared compact evaluation text/tooltip path and
  preserves the separate deterministic `BEST` display contract.
- Plot widgets replace normalized named series on refresh; metric histories skip unavailable metrics
  rather than appending another body type's missing value as a fake zero series.
- Explicit turret worker-group targeting carries the handler-selected entity id into
  `TurretTrainingTargetSensor`. The current sensor keeps an explicit live group target observable even
  outside immediate range/pitch and honors the exact selected entity rather than independently picking
  a second nearest target.
- Current turret observation/feature schema is v5 with 35 named features, including separate direct
  and finite-speed intercept direction channels, signed intercept yaw/pitch errors, and explicit
  `target_is_combat` / `target_is_shootable` task-state bits. Older pass notes are historical, not
  the current contract.

### Regression coverage changed in pass 11

- Four-limb detached-optimizer coverage now asserts that the post-adoption held action is accepted as
  a counted environment interaction while remaining absent from the next rollout.
- Four-limb and turret coordinator contract checks guard against reintroducing mid-interval policy
  resampling.
- Turret PPO has explicit stale-adoption boundary coverage.
- Reward-card tests cover malformed scalar current-format entries for drone and turret decks.
- Turret and four-limb action tests cover wrong-type schema/numeric fields at `packed_commands()`,
  and the generic drone pipeline covers malformed dictionary slot identities.

The Godot 4.6 suites could not be executed in this environment because no Godot binary is installed.
Static source-contract checks, duplicate class/function scans, modified-test dispatch checks, and
`git diff --check` were run instead. Runtime evidence is still required for turret servo/target feel,
projectile timing under Jolt, limb contact/grip stability, and actual learning convergence.

## Model architecture / hidden-dimensions audit — pass 12 (2026-08-08)

This pass was triggered by a live comparison in which two newly created drone models with substantially
different requested hidden dimensions appeared to earn rewards almost identically. The architecture
path was traced from the new-model dialog through trainer construction, live actor/critic networks,
background optimizers, branching, checkpoint save/load, runtime/evaluator loading, and the equivalent
four-limb/turret creation paths.

### New substantiated fix

- Fresh drone groups previously created their PPO/SAC-HER trainer with an empty configuration and only
  applied the dialog configuration afterward. Both trainers deliberately reject
  `hidden_layer_width`/`hidden_layer_depth` changes after construction because changing tensor topology
  in place is unsafe. As a result, the UI accepted custom hidden dimensions while the newly created
  network silently kept the algorithm default architecture (PPO 64x2, SAC-HER 128x2). Two fresh groups
  of the same algorithm could therefore display different requested dimensions yet actually train the
  same topology. The room now passes the complete startup configuration into
  `DroneTrainingAlgorithmCatalog.create()` before actor/critic construction. Mutable tuning values are
  still re-applied after live-policy branching so explicit branch-dialog overrides win over source
  configuration copies.
- The fresh-model integration regression now enters through the same room helper used by group creation
  and proves that PPO 96x3 and SAC-HER 192x4 requests become the live trainer architecture. Malformed
  startup configuration cleanly falls back to each trainer's default rather than throwing.
- Direct MLP regression coverage proves both width and depth change the real layer topology/parameter
  count, not only checkpoint metadata.

### Architecture path verified

- `DronePPOMLP` dynamically sizes all hidden layers, forward/backward workspaces, optimizer vectors, and
  serialized state from the selected width/depth. PPO actor and critic are both constructed with that
  shape.
- SAC-HER constructs its stochastic actor, both online Q networks, and both target Q networks with the
  selected width/depth. Serialized network state carries the shape and staged load reconstructs it.
- Drone PPO/SAC checkpoint loading adopts the network's validated actual hidden width/depth and
  synchronizes those values into trainer configuration. Checkpoint inspection validates nested MLP
  shapes against the top-level network architecture before a model is accepted.
- Background PPO/SAC optimization consumes the serialized live network state, so optimizer workers do
  not collapse a custom architecture back to defaults.
- The active integrated four-limb and turret coordinators already passed their `network_config` into the
  trainer constructor before policy creation; the fresh-creation ordering defect was specific to drone
  groups. Their detached PPO optimizers also load the transferred network state dynamically.
- The tracked standalone legacy `FourLimbTrainingRoom` still uses its old default-only creation path,
  but no active project code references that room; the integrated `DroneTrainingRoom` ->
  `FourLimbTrainingCoordinator` path remains authoritative.

### Visibility / comparison guardrails

- Expanded live worker UI now shows the architecture read from the constructed trainer itself, e.g.
  `hidden 3x96`, rather than trusting creation-dialog values. Drone model summaries and limb/turret
  identity rows therefore expose the actual policy shape currently in memory.
- The drone branch dialog now uses the selected algorithm's actual default architecture as its fallback
  instead of hard-coding PPO defaults for every algorithm.
- A larger network is not expected to have a higher reward merely because it is larger. After this fix,
  capacity comparisons should use equal environment decisions/updates and multiple seeds plus the
  deterministic evaluator, not only equal wall-clock time: wider/deeper networks do more optimizer
  work per update and may complete fewer updates per hour. If the smaller topology already has enough
  capacity for the current task, equal reward is also a valid outcome.

### Pass 12 conclusion

The user's current pre-fix fresh-drone comparison cannot be treated as evidence about model capacity:
for a same-algorithm fresh-model comparison, the requested architecture was not reaching construction,
so both groups could in fact be training the same default topology. New models created with this pass
use the requested hidden dimensions and expose their actual live shape in the group UI.

The Godot 4.6 suites remain unexecuted here because no Godot binary is installed. Static source checks,
regression-dispatch checks, architecture-path tracing, and `git diff --check` are used instead; live
convergence still requires the user's Godot run.

## Training UI consistency / numeric-input audit — pass 14 (2026-08-08)

This pass focused on inconsistent numeric-control interaction speed and a source-level review of the
training-room UI after the hidden-dimensions and startup-window changes.

### Numeric input behavior

- All ML `SpinBox` controls now share one accelerated arrow-step policy through
  `DroneTrainingRoomPresentation.configure_spinbox_arrow_speed()`. The underlying `Range.step` remains
  the authored fine precision, while fractional controls use at least a 5x arrow step and all arrow
  steps are scale-aware and capped at 10x precision. This keeps exact typed values/fine quantization while
  avoiding controls that require hundreds or thousands of arrow ticks to make a useful change.
- Direct SpinBoxes outside the shared number-input builder (fullscreen action-trace opacity, camera
  orbit speed, dynamic obstacle dimensions, and the tracked standalone four-limb worker count) now
  use the same policy. A source sweep found no remaining ML `SpinBox.new()` path without shared arrow
  configuration.

### UI bugs / inconsistencies fixed

- Compact drone, four-limb, and turret worker cards now show the live constructed network topology
  (`3x88`, etc.) before update/source text, so architecture A/B tests do not require expanding each
  card and cannot accidentally rely on dialog metadata.
- `BEST` no longer displays `BEST PENDING` while a Candidate is being evaluated. Candidate progress
  already owns the `EVAL ...` status; until deterministic promotion exists, BEST remains `BEST —`.
  This removes duplicated state and the frequently ellipsized `BEST PENDI...` header from narrow
  worker cards.
- The four-limb expanded identity row now wraps like the turret/drone detail rows instead of allowing
  long architecture/output text to overflow the card.
- The tracked standalone `FourLimbTrainingRoom` model/map library windows now start hidden as well.
  The integrated room was already fixed in pass 13, but the legacy scene still carried the same
  default-visible Window lifecycle bug.
- The dormant turret worker-slider label path now uses `Turrets:` rather than the stale `Workers:`
  wording, keeping future/re-enabled worker-count controls consistent with the live turret card.

No Godot executable was installed or downloaded. Validation for this pass is static: modified-source
source/structure scans, direct SpinBox coverage, Window startup-visibility coverage, duplicate
function/class checks, format-argument review, and `git diff --check`. Runtime visual behavior still
needs the user's Godot 4.6 session.

## Turret reward / visual audit — pass 15 (2026-08-08)

This pass followed a live observation that turret policies converged toward continuous rotation while
reward-component plots appeared unable to produce meaningful positive aim reward.

### Reward defects fixed

- The turret aim hold term was previously non-negative: it paid `alignment^2` while the intercept point
  was in the forward hemisphere and paid exactly zero while the barrel pointed away. A constant yaw
  command therefore earned positive reward every time a full rotation crossed the forward half of the
  target direction, while the smoothness card charged almost nothing after the command stopped
  changing. Continuous spinning was consequently a genuine reward local optimum. Aim hold shaping is
  now signed cosine alignment. Settled correct aim earns continuously, settled wrong-way aim loses
  reward, and a complete constant-speed revolution integrates to approximately zero instead of farming
  reward.
- Alignment-progress shaping is stronger and remains immediate even when a turret begins with the
  target behind it. Improving alignment can therefore be net-positive before the barrel enters the
  forward hemisphere, while stopping at a bad heading remains negative.
- Dense tracking reward no longer disappears merely because a selected reachable target is temporarily
  occluded by a wall. Target presence plus the authored pitch envelope define whether tracking shaping
  is active; line of sight is still mandatory for shot viability, so the correct covered-target behavior
  is to keep tracking but withhold fire. The aim card is now correctly presented as mixed
  reward/punishment rather than reward-only.
- PPO policy adoption now cancels in-flight projectiles from the old behavior policy. The held stale
  action interval is still completed and excluded from the new rollout as in pass 11, but a delayed old
  hit/miss can no longer resolve afterward and contaminate the next new-policy reward interval.

### Turret visuals

- Turret base, rotating head, and barrel meshes use the worker-group color through one per-turret shared
  material. The color survives physical-body rebuilds caused by loadout changes.
- The floating `TrainingGroupLabel` is no longer created for turret workers. `set_visual_color()` also
  removes a legacy label if one is present, so a reused body cannot retain the old billboard.

### Regression coverage

- Turret reward tests now assert that holding a bad heading is negative, moving toward the intercept
  solution from behind is positive, tracking through cover still receives aim shaping, and one complete
  synthetic rotation has approximately zero cumulative aim reward.
- Turret body tests verify that all three visible mesh sections receive the exact group color and that
  the legacy floating label is absent.
- The optimizer-boundary source contract now verifies that policy adoption both preserves the held
  action until its normal decision boundary and cancels old-policy projectiles.

No Godot executable was installed or downloaded. Runtime learning behavior, projectile timing, and
visual material appearance still need the user's Godot 4.6 session; static source checks and
`git diff --check` are used here.

## Turret routed-target / reward telemetry audit — pass 17 (2026-08-08)

This pass followed a live reward-card report where shot-discipline and servo penalties updated while
`Track the intercept point` remained exactly zero even though the barrel visibly reacted to the room
target. The display path was alive; the routed-target contract upstream of the reward deck was not.

### Root cause and reward fix

- `DroneTrainingRoom` already resolves a complete per-group target record (availability, stable identity,
  kind, position, velocity, radius and metadata), but `TurretTrainingCoordinator` previously forwarded
  only `position_world` to `TurretTrainingTargetSensor`. When no live combat adapter was selected from
  the entity hash, the sensor used that position for directional geometry while still setting
  `target.present = false`. The turret could therefore visibly rotate toward the marker while the dense
  aim reward was hard-gated to exactly zero.
- The coordinator now retains and forwards the complete resolved target. A finite available routed
  navigation/fallback target is represented as a real **aim objective** with stable identity and velocity
  even when it is not a damageable combat body. This also makes finite-speed intercept geometry use the
  target handler's real velocity instead of silently treating the marker as stationary.
- Dense aim shaping now keys on objective presence rather than the firing pitch envelope. A target that
  is currently above/below gun reach still supplies the directional learning signal needed to move toward
  the best reachable solution. Range, pitch, line of sight and live-combat identity remain mandatory for
  shot viability.
- Navigation/task markers remain non-damageable. `Hit targets` therefore still requires a confirmed
  projectile hit on a live combat target, and firing at an aim-only marker is classified as a bad shot.
  This separates learning to track the routed objective from learning the trigger/ballistics task.
- Turret observation schema is now v4 with 34 scalar inputs. `target_present` now has the corrected
  semantic contract: any routed finite aim objective can be present, not only a body found in the combat
  spatial hash. A new `target_is_combat` input explicitly tells the policy whether firing can produce a
  real hit. Without that bit, navigation and live targets could otherwise become observationally identical
  while requiring opposite trigger behavior. Stable target identity/kind are retained in the observation
  dictionary for reward/debug logic.

### UI diagnostics / regression coverage

- The selected turret reward panel now appends live target telemetry showing target kind, alignment, LOS,
  range, pitch and whether the objective is `live combat` or `aim only`. This makes a future zero reward
  diagnosable directly in the UI instead of inferring sensor state from barrel motion.
- Reward tests cover positive dense reward for a routed non-combat navigation target, aim shaping outside
  the pitch envelope, and punishment for trying to fire at an aim-only marker. Sensor/coordinator tests
  verify that the full routed target identity and velocity survive the room -> coordinator -> sensor path.
- Configuration restarts clear cached resolved-target identity so an old objective cannot leak through the
  first observation of a newly configured episode.

No Godot executable is installed in this environment. Validation remains static plus the deterministic
Godot regression suite authored for the next local/headless engine run.

## Creation-dialog / general UI lifecycle audit — pass 18 (2026-08-08)

This pass followed the reproducible report that `New Stationary Turret Model` opened excessively tall
on the first invocation but at the intended size after closing and reopening it.

### First-open dialog defect fixed

- `ConfirmationDialog` inherits `AcceptDialog`, whose `wrap_controls` behavior is enabled by default.
  The turret dialog adds custom wrapped labels and sliders during room construction, so the Window could
  adopt a child-derived build-time size before its first popup. `popup_centered(BRANCH_DIALOG_SIZE)` then
  treated the requested dimensions as a minimum rather than forcing the already-inflated Window smaller.
  The previous deferred normalization corrected the stored size only after that first bad popup, explaining
  why every later opening looked normal.
- The turret creation/branch dialog now disables `wrap_controls` before adding custom children, explicitly
  restores its authored `580x560` size before each popup, and uses `popup_centered()` with that current size.
  Its custom body is vertically scrollable and has a stable content width, so later text/theme minimum-size
  changes cannot grow the Window.
- The drone and four-limb custom creation dialogs now use the same explicit-size/no-auto-wrap contract.
  They were not currently reproducing the turret symptom, but they used the same fragile AcceptDialog
  lifecycle and are now prevented from developing the same first-open bug.

### Additional UI findings fixed

- The turret creation text previously always claimed that it copied a live policy, even for a genuinely
  fresh random model. The source explanation now distinguishes a fresh network from a live branch and tells
  the user when hidden width/depth are actually selectable.
- The `Groups start with one placed turret` note now wraps instead of contributing an unbounded horizontal
  minimum, and the duplicated manual-control autowrap assignment was cleaned up.
- A source sweep covered every ML `ConfirmationDialog` construction. Delete-confirmation dialogs intentionally
  retain AcceptDialog's normal content wrapping because they use the built-in dialog body; all custom model-
  creation forms now opt out and own their dimensions explicitly.

Regression source checks cover the turret exact-size/scroll contract, the equivalent drone/limb contract,
and fresh-vs-branch turret source text. No Godot executable was installed or downloaded; runtime popup
measurement still needs verification in the user's Godot 4.6 session.

## Turret synthetic hit / reward UI audit — pass 19 (2026-08-08)

This pass followed the runtime report that dense turret tracking reward now changes correctly while
`Hit targets` remains exactly zero in the normal routed-target training setup. It supersedes the pass-17
decision that treated routed navigation markers as aim-only objectives.

### Root cause and hit contract fix

- The routed Navigation path target had deliberately been made a real aim objective in pass 17, but it
  still had no combat adapter or physical collision body. Projectile hit accounting only resolved against
  combat adapters from the entity spatial hash. As a result, the default visible training marker could be
  tracked perfectly but could never generate a confirmed projectile hit; `Hit targets` was structurally
  impossible unless the operator explicitly selected another live worker group as the turret target.
- Navigation-path candidates now explicitly declare themselves `shootable`. The turret sensor preserves
  that distinction separately from `is_combat_target`: the policy/reward system can treat the routed marker
  as a synthetic range target without pretending that it owns health or is a combat entity.
- A projectile fired at a non-combat shootable objective retains a shot-time copy of the routed target's
  position, velocity and radius and performs swept relative-motion sphere intersection while it flies.
  Walls and physical combatants still participate in nearest-hit ordering. Crossing the routed target sphere
  produces one confirmed hit and zero fake damage; a wall or unrelated body that intercepts the projectile
  first produces a miss for the synthetic-target task instead of stealing hit credit.
- Live worker-group targets retain the existing physical adapter/damage hit path. The evaluator also remains
  on physical evaluation combatants. No turret feature-count/schema change is required in this pass.

### Reward UI observability

- Limb/turret reward cards previously displayed only `group.last_reward_state`, which is whichever worker
  happened to write the group field last. In a multi-turret group a genuine hit by turret A could therefore
  remain invisible if turret B ticked afterward with zero hit reward. The UI now averages per-worker reward
  components/totals and sums discrete weapon-event counters across the group.
- Turret reward notes now include cumulative fire telemetry: shots, viable shots, confirmed hits, misses,
  unresolved projectiles and damage. Target telemetry distinguishes `synthetic target`, `live combat` and
  `aim only`, making it possible to tell whether zero hit reward means no shots, misses, or a target-contract
  problem without inferring it from animation.
- Regression coverage now exercises a synthetic routed target hit end-to-end through projectile events and
  reward calculation, verifies that an unrelated blocker cannot earn synthetic hit credit, and verifies
  multi-worker reward UI aggregation.

No Godot executable is installed in this environment. Validation remains static plus the deterministic
Godot regression suite authored for the next local/headless engine run.


## Turret task-contract / projectile-horizon audit — pass 20 (2026-08-08)

This pass continued from the synthetic-hit fix and audited whether the turret policy receives enough
information to learn the trigger task, whether the room's selected target is actually authoritative, and
whether projectile outcomes can escape the finite episode/evaluation horizon.

### Target contract fixes

- The room UI calls the default turret option `Path training target`, but the target sensor still ran its
  legacy automatic nearest-enemy scan whenever no explicit worker group was selected. In a mixed room an
  ambient drone/limb could therefore silently replace the routed path marker even though the handler and
  visual target had selected the path objective. A non-empty routed target is now authoritative. The
  evaluator/direct sensor path retains automatic combat acquisition by calling the sensor without a routed
  objective.
- An explicitly selected worker group can no longer fall back to an unrelated navigation marker when the
  selected group temporarily has no live target. Routed fallback is accepted for explicit targeting only
  when its metadata identifies the selected worker group. This prevents the task from silently changing
  from `shoot group X` to `shoot the range marker` during pause/death/registration gaps.
- `is_shootable_target` is now fail-closed in observation/reward/viability code. Missing metadata means
  non-shootable instead of implicitly granting trigger permission.
- Removing a drone, limb or turret group now clears every turret group's explicit reference to that
  target through `set_group_target_worker(..., -1)` before the target disappears. This applies the normal
  projectile/action boundary immediately instead of leaving an unselected background turret stuck on a
  stale group id until its UI card happens to be opened.

### Policy observability

- Pass 19 introduced a third target state: a routed synthetic target is non-combat **and shootable**, while
  generic registered task objectives may be non-combat **and aim-only**. Schema v4 exposed only
  `target_is_combat`, making those two states observationally identical even though firing is rewarded for
  one and punished for the other. The turret observation/feature contract is now schema v5 with 35 inputs
  and an explicit `target_is_shootable` feature. This intentionally invalidates v4 turret checkpoints; the
  old policy interface lacked information required by its reward contract.

### Projectile horizon accounting

- A projectile still in flight when a real episode/evaluation horizon ended was previously cancelled
  without a miss event. A policy could therefore fire late in the episode and evade the normal miss
  penalty whenever the round had insufficient flight time to resolve. Real task horizons now cancel
  unresolved rounds **as misses before final reward settlement**.
- Policy adoption, target changes, configuration changes and other decision-context invalidations still use
  no-reward cancellation. Those are not task failures and must not deposit stale events into the replacement
  policy. The projectile API now makes this distinction explicit with `cancel_as_miss()` versus
  `cancel_without_reward()`.
- The deterministic turret evaluator applies the same horizon rule, so candidate reward and shot discipline
  cannot receive a more permissive terminal-shot contract than training.

Regression coverage now checks path-target authority in the presence of ambient workers, rejection of an
unrelated fallback for a missing explicit target group, all three combat/shootable target-state feature
combinations, and unresolved projectile miss accounting at a true horizon. No Godot executable is installed
in this environment, so these are source/static contracts awaiting the user's Godot 4.6 runtime test.

## Background-step / turret evaluator consistency audit — pass 21 (2026-08-08)

This pass checked the boundary between detached PPO optimization and live simulation, plus the
stationary-turret evaluator's success metric and multi-worker manual-control ownership.

### Physical environment-step accounting

- Four-limb and turret PPO trainers already implement the same safe background-update contract as drone
  PPO: while a detached optimizer owns the previous rollout, `add_transition()` counts the physical
  environment step but deliberately discards the stale on-policy sample.
- Their coordinators were bypassing `add_transition()` entirely through a separate
  `episode_collects_training` flag whenever a background update was active. As a result, bodies continued
  moving while `environment_steps` stopped advancing, making training-rate telemetry and step-based
  comparisons inconsistent with drones.
- The redundant coordinator gate is removed. Held-action boundaries always reach the trainer; the trainer
  remains the single authority for whether a transition is stored or count-but-discarded during detached
  optimization.

### Turret precision/evaluation contract

- Live turret training counted `time_precisely_aimed_seconds` only when the routed target was visible,
  inside weapon range, inside the pitch envelope, and above the precision alignment threshold.
- The hidden turret evaluator previously omitted range and pitch when accumulating the same success metric.
  A short-range/custom-loadout candidate could therefore receive evaluator success credit under a looser
  rule than the live training telemetry.
- `TurretTrainingTargetSensor.is_precision_tracking_state()` is now the shared predicate used by both live
  training and hidden evaluation, so the success metric cannot drift between the two paths.

### Multi-turret manual-control ownership

- Manual override controls only worker 0, but toggling it previously cleared every worker's held action,
  reward interval, projectile set, and the complete group PPO rollout. One debug/manual turret could thus
  discard valid autonomous experience from all sibling turrets.
- The ownership boundary is now worker-local. Only turret 0 clears its open interval/projectiles, and the
  trainer removes only worker 0's current rollout fragments so GAE cannot bridge across the manual gap.
  Autonomous sibling turrets keep their physical state and valid rollout samples.

Regression coverage checks the coordinator-to-trainer background-step contract, the shared precision
predicate's range/pitch requirements, and preservation of sibling turret intervals/rollout data across
manual override. No Godot executable is installed in this environment, so runtime physics/test execution
still requires the user's Godot 4.6 session.


## Authored training-item lifecycle audit — pass 24 (2026-08-08)

This pass treated the Training Items implementation as an end-to-end task/physics subsystem rather than a
UI feature. The audit followed authoring, map persistence, placement, spatial discovery, grip compatibility,
policy observation/reward, pause/resume, evaluator behavior, loss/recovery, and cleanup.

### Authoring and geometry contracts

- Item editing now reads `spawn_transform_world`, not the current rigid-body transform. A worker can drag an
  authored item around and selecting it later to change only Weight or Reward value no longer silently
  rewrites the item's reset/map spawn to wherever physics happened to leave it.
- Primitive target radii now use an exact origin-centred bounding sphere for the shared Box/Cylinder/Sphere/
  Capsule geometry contract. The previous AABB-half-extents length made a sphere report `sqrt(3)` times its
  real radius and similarly overestimated rotationally symmetric shapes.
- Coupled dimensions are normalized **before** Training Item SpinBoxes are rebuilt. In particular, capsule
  total height is shown with the same `height >= 2r` constraint that collision and mesh creation use, so the
  UI cannot display a size different from the body that will actually spawn.
- Item transforms are finite/right-handed/orthonormalized before application. Explicit dimensions remain
  the sole owner of geometry size; malformed maps/callers cannot smuggle scale, shear, mirroring or a
  degenerate basis into a physics item. Weight and Reward value also fail closed to finite non-negative
  values.

### Discovery and future task semantics

- `TrainingItem3D` now publishes the semantic target kind `cargo_pickup`, matching
  `TrainingTargetHandler.DEFAULT_PRIORITY_BY_KIND`. The old ad-hoc `pickup_item` kind had no registered
  priority and would have ranked below ordinary navigation in a future Take task despite representing cargo.
  `task_role = pickup_item` remains available as descriptive metadata.
- Item candidates are explicitly non-shootable, keep a stable `training_item:<id>` address, expose current
  task position/velocity/radius/mass/value metadata, and fail `available` closed if runtime position becomes
  invalid. This is suitable for a later Take/Bring-Here provider without changing the item's identity model.
- The shared spatial hash remains the discovery source for authored items. Regression coverage also reaches
  the real `GenericGrip3D` compatibility predicate, verifying that the authored Weight participates in the
  gripper's maximum-held-mass rule and the `carryable` surface tag is the generic attachment contract.

### Physics, pause and loss recovery

- A frozen item now reports zero **task-visible** velocity while preserving its stored rigid-body velocity
  for exact resume. This prevents an active sibling worker from observing a shared item as moving while it is
  intentionally frozen because another limb group is paused holding it.
- Non-finite rigid-body transform, linear velocity or angular velocity schedules authored-spawn recovery.
  A normal in-arena authored item that falls through the arena's open side or leaves the horizontal recovery
  envelope is reset to its authored spawn. Recovery is an explicit configuration/episode boundary for drone,
  limb and turret groups so no PPO trajectory crosses the teleport.
- Deliberately authored out-of-bounds spawns are not repeatedly auto-recovered, avoiding an endless
  reset/restart loop for intentionally unusual numeric layouts.
- Continuous mouse placement and editor selection now ray through private fallback pickup props instead of
  treating those simulation-only layer-1 bodies as authored editor surfaces. The custom-obstacle picker also
  looks through those lesson-only item bodies, so adding the item system cannot make a wall behind a fallback
  prop unselectable. Real walls/arena geometry still occlude item selection, while upward-facing authored item
  surfaces remain valid stacking surfaces.
- Mouse placement offsets the new item's centre by the primitive's exact directional support extent along the
  hit normal. Rotated boxes/cylinders/capsules therefore rest on sloped upward-facing surfaces instead of using
  a world-Y AABB half-height that could embed or float the item.

### Persistence and regression coverage

- Map restore is exercised with valid, duplicate-id and malformed item records. Duplicate/corrupt ids are
  monotonically remapped so stable task addresses remain unique; malformed dimensions/mass/value/transform
  data recover to finite usable defaults; restored items are re-registered in the shared spatial index; and
  map records round-trip authored mass/value/spawn rather than transient motion.
- The existing worker-local lift-credit and pickup-evaluator fixes from pass 23 remain intact. The now-unused
  spawn-relative `lift_height()` helpers were removed so there is no second, causally-wrong lift definition for
  future reward/task code to accidentally reuse. This pass does **not** change the limb observation schema: it
  remains schema 14 / 420 inputs.

Static validation in this workspace checks all project GDScript files for duplicate top-level declarations,
class-name collisions, delimiter balance, modified test-dispatch completeness, new `:=` inference, and
`git diff --check`. The new Godot regressions are authored coverage only: no Godot executable is installed
here, so engine/physics execution still requires the user's runtime.

## Grouped item-delivery task audit — pass 25 (2026-08-08)

This pass extends authored Training Items into a complete pickup-and-delivery task contract without adding a
limb policy tensor field solely for destination identity. Delivery reuses the existing generic target channel
and the already-observed `pickup_item_held` state, so four-limb observation schema 14 / 420 inputs remains
unchanged.

### Destination authoring and persistence

- Training Items now owns delivery-destination groups. A group has one shared name/color, accepted-item-type
  policy, radius/height, approach-reward scale and completion-reward scale, while containing any number of
  separately placed destination volumes. The row `+` action places one additional volume with that same group
  policy; editing policy reconfigures every existing volume in the group.
- Training Items have a normalized stable `item_type` key. Destination groups may accept multiple type keys at
  once or explicitly accept every item type. The item type is part of item discovery metadata and map records.
- Destination volumes are non-blocking `Node3D` task volumes, not collision obstacles. They use stable
  `training_delivery:<group>:<destination>` task addresses, register as shared spatial entities of kind
  `delivery_destination`, publish `target_kind = cargo_delivery`, and are explicitly non-shootable.
- Destination placement raycasts through movable training/fallback items and other dynamic bodies to the
  arena/static obstacle support beneath them. A transient crate position therefore cannot become a delivery
  volume's authored base merely because it was under the mouse when the zone was placed.
- Delivery policy/volume edits restart only delivery-enabled **live limb trajectories** whose task semantics
  changed. The zones have no collision/physics effect, so unrelated drone/turret training, locomotion-only limb
  groups, and fixed canonical candidate-evaluation jobs are not reset just because a live-room destination is
  authored.
- Training-map schema 3 persists item types and complete destination-group policy plus all authored destination
  transforms. Older maps remain readable because absent destination-group data defaults to an empty list.
  Duplicate/corrupt restored group/destination ids are remapped, and malformed policy/transform data is
  finite-sanitized before registration.

### Two-phase worker objective

- A limb group only enters delivery routing when its `item_delivery` reward card is enabled. Before grip, its
  assigned cargo is restricted to item types accepted by at least one placed destination and becomes the
  generic navigation target. The pickup target's navigation Y stays at current chassis height while the
  dedicated pickup observation retains the exact 3D cargo vector, avoiding a reward incentive to collapse the
  core down to floor-item height.
- Once an accepted item is physically held, the same generic target channel switches to the nearest accepting
  destination. The navigation point uses the body's preferred chassis height above the destination floor while
  delivery progress/containment is measured from the actual carried item against the authored delivery volume.
- If multiple compatible destinations overlap, containment outranks mere centre distance. This prevents the
  router from choosing a slightly nearer non-containing volume and hiding a valid delivery completion.
- The target-progress deck suppresses generic progress only on the pickup/delivery semantic phase-swap frame.
  This avoids attributing an action selected for the old cargo target to the newly introduced destination.
  The normal signed target-progress signal resumes immediately afterward.

### Conditional delivery reward and evaluation

- `item_delivery` is a mixed reward card. While an accepted item is actually held, it pays the signed reduction
  in item-to-destination distance; moving away produces the symmetric negative shaping. Item Reward value and
  the destination group's approach scale multiply that signal. Switching between sibling volumes in the same
  group keeps the same potential contract instead of creating a zero-reward loophole at the nearest-volume
  handoff; changing to a different group starts a different policy/reward context.
- Entering any compatible volume in the group while still holding the item pays one completion event, scaled by
  the item's Reward value and the group's delivery scale. Completion is keyed by physical item for the worker episode, so lingering inside, moving among sibling
  volumes, or carrying the same parcel into another accepting destination group cannot repeatedly farm completion
  reward.
- The `Item Pickup + Delivery` built-in preset enables pickup, delivery and modest generic target approach/search
  shaping so the sparse grip event remains learnable before the conditional carry reward can activate.
- Fixed-seed four-limb evaluation adds a canonical 16-second `item_delivery` case whenever the frozen reward
  contract enables the delivery card. Its observation mirrors the live two-phase routing and the case succeeds
  only after a real physical grip and a recorded delivery completion.

Static validation for this pass checks project GDScript declarations/delimiters, direct signal-handler targets,
modified test dispatch coverage, newly introduced `:=` inference and `git diff --check`. No Godot executable is
installed in this environment, so the new physics/grip/evaluator tests remain authored regressions awaiting the
user's Godot 4.6 runtime execution.

### Delivery anti-farming follow-up

- Authored cargo already resting inside any accepting destination is treated as delivered and is not assigned as fresh pickup cargo for a delivery-enabled limb group. This matters because authored items are shared room physics and deliberately survive one worker's episode reset; without the filter, a successful delivery could become the next episode's pickup target while still sitting in the bay.
- Completion eligibility is established when a worker first holds a given item for the delivery task. If the item is already inside an accepting volume at that moment, that item is ineligible for a completion bonus for the rest of the episode. Walking it out and back in therefore cannot manufacture a delivery event.
- The one-time completion key is scoped to the physical item, not to an individual placed volume or destination group. Sibling volumes still share one group policy exactly as the authoring UI promises, while a parcel that has already completed once cannot be sold again to another accepting group in the same worker episode.
- Delivery completion eligibility is item-scoped rather than destination-scoped. An item first held outside all accepting bays stays completion-eligible if nearest routing switches destination groups on the exact boundary frame where it enters a valid bay; an item first held inside a bay remains ineligible for the episode. Approach shaping still requires the same destination-group policy between consecutive observations so routing changes cannot manufacture potential reward.


## Delivery release-candidate hardening — pass 26 (2026-08-08)

- Accepted-type parsing now ignores whitespace-only comma fields instead of normalizing them to `generic`.
  `ore, , medical_crate` therefore accepts exactly the two authored types the UI shows.
- Restored `accept_all_item_types` uses strict bool parsing. Malformed JSON such as the string `"false"` now
  fails closed instead of becoming truthy and silently broadening the delivery policy.
- Carry shaping now uses distance to the destination's actual cylindrical acceptance volume, with exactly the
  same horizontal/vertical semantics as `contains_item()`. Potential is zero everywhere inside a valid bay, so
  cargo wobble after delivery cannot manufacture approach reward or penalty.
- Completion is item-scoped for the worker episode. Once one physical parcel has completed, moving it out and
  into another accepting destination group cannot earn another completion bonus. Routing may still switch groups
  before the first completion without losing eligibility.
- Delivery group acceptance normalizes its stored type collection at the read boundary, making internal/map data
  robust to Array, PackedStringArray, String, duplicates and blank entries.
- Training-map UI copy now states that maps persist authored Training Items and delivery groups/volumes as well as
  obstacles, matching schema 3 behavior.

This pass intentionally does not change the four-limb observation contract (schema 14 / 420 inputs) or the
working pickup/tracking/grip math. Godot is unavailable in this workspace, so engine/Jolt execution remains a
runtime verification step.

## Item/delivery continuity hardening — pass 27 (2026-08-08)

This pass re-audited the authored Training Item and grouped delivery flow from episode assignment through
fallback cargo, grip ownership, destination compatibility, pause/finish behavior and loss recovery.

- Delivery-enabled groups no longer depend on the standalone `item_pickup` reward card to receive cargo. A
  delivery-only lesson is still a cargo task, so the coordinator creates a private fallback item when no usable
  authored item is available.
- Private fallback cargo is no longer hard-coded to the `generic` item type. When delivery is enabled, the room
  deterministically selects a type accepted by an actually placed delivery destination (or `generic` when an
  accept-all destination exists). This closes the dead-end where successfully delivered authored cargo is
  intentionally excluded from reassignment, but the next episode's replacement prop could not be accepted by
  a specific-type destination such as `ore` or `medical_crate`.
- `TrainingItem3D.DEFAULT_ITEM_TYPE` now owns the generic item-type default used by generic and fallback items,
  avoiding a second literal default in the task-item path.
- Private fallback props now stop simulating as soon as their owning worker finishes. They can no longer remain
  as stray dynamic collision bodies during the rest of a multi-worker episode or the respawn intermission.
- Private fallback props now participate in an explicit loss path. If one becomes non-finite, falls below the
  supported envelope, or leaves the authored arena recovery envelope, it is restored to its spawn and the
  affected worker ends with `task_item_lost`. This prevents PPO from spending the remainder of an episode
  training against cargo that can no longer be reached. Shared authored items keep their existing room-level
  recovery/restart contract.
- Regression coverage now checks delivery-only cargo requirements, normalized fallback types, compatibility of
  fallback cargo with active destination policy, finished-worker prop freezing, and private-prop recovery.

Static validation for this pass checks GDScript declaration/class-name uniqueness, delimiter balance, changed
lines for new `:=` inference, test references for the new item/delivery helpers, and `git diff --check`. No Godot
executable is installed in this workspace, so engine/Jolt physics execution remains a runtime verification step
for the user's Godot 4.6 environment.

## Item/delivery lifecycle follow-up — pass 28 (2026-08-09)

This second pass focused on state that survives a worker boundary rather than on destination routing itself.
It found two lifecycle faults that were not visible in a single fresh episode.

- Private fallback cargo now explicitly reactivates in `reset_item()`. Pass 27 correctly froze the prop when its
  owning worker finished, but `TrainingItem3D.configure_item()` deliberately preserves `simulation_active`.
  Reusing that same fallback node on the normal next-episode respawn therefore preserved the terminal frozen
  state and could make episode 2+ cargo permanently immovable. The fallback reset is now the explicit
  `finished/frozen -> next live lesson` activation boundary, with a regression covering that full transition.
- Terminal four-limb workers now release every physical grip before their body is frozen. `set_runtime_active`
  intentionally preserves grips for user pause/resume, but using the same behavior at episode termination let a
  finished worker remain latched to shared authored cargo while sibling workers were still active. The physical
  rig now exposes `release_all_grips()` and `_finish_worker()` uses it only for terminal ownership cleanup; pause
  semantics are unchanged. A regression checks that a held target id is actually surrendered.
- The room-level training-item default now aliases `TrainingItem3D.DEFAULT_ITEM_TYPE` rather than keeping a
  second `"generic"` literal, completing the single-source default introduced in pass 27.

The grouped map save/load path was rechecked in this pass and already persists complete destination-group
records through map schema 3, so it was intentionally left unchanged. Limb checkpoint room settings likewise
remain narrower than a whole-room map and were not expanded as part of this item lifecycle fix.

Static validation checks project GDScript declaration/class-name uniqueness, delimiter balance, added-line
`:=` inference, test dispatch references, and `git diff --check`. No Godot executable is installed in this
workspace, so engine/Jolt execution remains a runtime verification step in the user's Godot 4.6 environment.

## Item/destination pre-test hardening — pass 29 (2026-08-09)

This pass was performed as the final item/destination review before live user testing. It focused on physical
acceptance geometry, item-loss recovery boundaries, and grip ownership during configuration-driven worker
rebuilds.

- Delivery-volume vertical acceptance no longer uses an item's full bounding-sphere radius. A wide, flat box
  previously inherited a very large vertical tolerance from its horizontal dimensions and could therefore count
  as delivered while its physical shape was still metres above the destination. `contains_item()` and
  `distance_to_item()` now share the primitive's exact oriented support extent along the destination's world-up
  axis. Horizontal acceptance intentionally remains centre-inside-radius, preserving the established anti-brush
  contract. The same destination methods are used by live training and deterministic evaluation.
- Training-item recovery is now armed independently per authored axis, matching its documented intent. An item
  deliberately authored outside X is not repeatedly reset merely for remaining outside X, but it can still be
  recovered if it subsequently falls through the valid floor envelope or escapes along another axis whose spawn
  was valid. This closes the old all-or-nothing guard where one intentionally out-of-bounds coordinate disabled
  every recovery condition.
- Ordinary authored items now also have an upper world-Y loss envelope (64 m by default). An item launched far
  above the usable training space no longer remains an unreachable assigned objective forever. The upper check
  is itself spawn-aware: a deliberately authored high item does not enter an endless reset loop. Recovery
  defaults live on `TrainingItem3D`, and the room aliases those constants rather than duplicating magic values.
- Configuration-driven four-limb worker teardown now explicitly calls `release_all_grips()` before stopping and
  freeing a body. This path is terminal ownership cleanup, unlike ordinary pause/resume, and therefore must not
  preserve a shared authored cargo joint or collision exception while the owning rig disappears.
- Regression coverage now includes per-axis recovery arming, below-floor recovery from a horizontally
  out-of-bounds authored spawn, upper-Y recovery without penalizing intentionally high authoring, a wide-flat
  cargo false-delivery case, exact volume-distance behavior, and grip release through coordinator teardown.

The reward/selection path was rechecked after these changes. Compatible routing remains containment-first across
all accepting groups, delivery completion remains item-scoped per worker episode, and authored cargo already
inside an accepting destination remains excluded from fresh delivery assignment. No observation/action schema
change was required.

Static validation checks all 253 GDScript files for class-name uniqueness and gross delimiter consistency,
verifies no new `:=` inference was introduced in this pass, and runs `git diff --check`. Godot is intentionally
not installed in this workspace, so the authored physics/grip regressions still require execution in the user's
Godot runtime.
