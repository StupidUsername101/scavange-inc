# Drone ML body audit

## Current authoritative contract

- The physical flight core in the current training room still uses four independent propellers.
- PPO body topology is no longer inferred from a fixed action count. `DroneMLBodyInterfaceFactory`
  adapts the existing gameplay Core/slot loadout and `MLBodyBuildDraft.accept_build()` freezes the
  exact controls, body observations, and topology signature before the PPO network is allocated.
- The optional training belly limb is a normal two-segment `GenericLimbDefinition` mounted through
  an existing drone attachment slot. It exposes shoulder X, shoulder Z, elbow Z, and the ordinary
  controlled grip independently. The grip uses the same static `climbable` / dynamic `carryable`
  system as standalone limb workers.
- The accepted training-belly topology therefore currently has eight controls: four propellers plus
  four regular limb controls. This count is a result of the part definitions, not a special profile
  hardcoded into PPO.
- Body observations are likewise declared by the equipped parts and appended to the stable drone
  task/navigation inputs only after the body build is accepted.
- Evaluators/checkpoints compare the exact accepted body-interface signature and channel counts;
  matching action count alone is not sufficient to identify hardware.
- SAC is intentionally pinned to its established rotor/navigation schema and rejects controlled
  attachment topologies until SAC itself is converted to the shared dynamic body interface.

See `docs/ml-model-body-contract.md` for the shared Core/slot/part lifecycle used by drone,
four-limb, turret, and future body-creator builds.
