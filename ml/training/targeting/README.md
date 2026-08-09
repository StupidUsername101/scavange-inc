# Training target routing

The training room deliberately keeps target selection **outside** every neural-network schema.
A policy still receives the same single objective it received before this framework existed:
position, velocity and accepted radius where that body type already exposes those values.

`TrainingTargetHandler` owns one or more `TrainingTargetSystem` providers. On every active tick the
handler asks every provider for its current candidates, ranks them deterministically, and forwards
only the winning candidate to the existing observation/reward path.

Current providers:

- `TrainingPathTargetSystem` — the original Stationary / Orbit / Line / Random waypoints / Manual
  target implementation. Every worker group owns its own instance, so two groups can use the same
  provider with unrelated behaviour and runtime state.
- `TrainingRegisteredTargetSystem` — a runtime bridge for task systems that naturally expose many
  candidates, such as cargo receivers, pickup items, swarm members or explicit escape points.
  Call `DroneTrainingRoom.register_group_target_candidate()` with a stable ID and update that same
  ID whenever the world target moves. Remove it when the target is no longer available.

Semantic target classes are ranked in `TrainingTargetHandler.DEFAULT_PRIORITY_BY_KIND`. Survival
escape is above cargo delivery, cargo pickup, combat objectives and ordinary navigation. Candidate
`priority_bias` only orders candidates *inside* a semantic class and therefore cannot make a cargo
candidate outrank survival. Ties then use urgency, distance and stable ID in that order.

Existing obstacle/threat observations and damage/survival rewards remain independent of this router;
the framework does not replace them with a target position. If a deterministic escape planner later
publishes a `survival_escape` candidate, that candidate becomes the routed objective ahead of cargo
or navigation while the normal threat inputs remain available to the policy.

`TODO(target-priority-ui)` in `training_target_handler.gd` marks the planned UI work: expose the
semantic ordering/weights as rows or sliders while preserving deterministic tie-breaking and
per-handler persistence.

Do not add a new target directly to policy tensors unless the policy genuinely needs information
that cannot be represented as the existing routed objective. Prefer a new target-system provider
and keep the model contract unchanged.
