# Maze SAC-HER change manifest

## Added learner

The worker-group algorithm picker now includes **Maze SAC + Hindsight Replay** (`sac_her_maze`) alongside the existing **Clipped PPO + GAE** learner.

The new learner contains:

- an off-policy Soft Actor-Critic implementation with four independent stochastic propeller outputs;
- twin Q critics and slowly updated target critics;
- replay-memory sampling and detached background optimization;
- Hindsight Experience Replay using safe future positions from completed episodes;
- per-worker X/Z visitation memory with heading-relative near/far sector features;
- blocked-path detour relief and a small unvisited-cell exploration bonus; and
- separate checkpoint, runtime-model, branching, status and tuning support.

## Compatibility

- PPO remains the default algorithm.
- Existing PPO checkpoints keep their original schema and runtime model.
- PPO update equations were not replaced. The shared MLP only gained reusable input-gradient and soft-target-update helpers needed by SAC.
- PPO and SAC checkpoints cannot be cross-loaded or cross-branched.
- SAC replay memory and temporary visitation maps intentionally restart empty after loading a checkpoint. Network and optimizer state are preserved.
- All actions still pass through the existing four-propeller validation and fail-safe path.

## Training use

1. Open **ML Training Room**.
2. Create a new root/branch worker group.
3. Select **Maze SAC + Hindsight Replay** as the learning algorithm.
4. Keep obstacle and failure rewards enabled.
5. Use reachable wall layouts first, then increase corridor length and dead-end complexity.
6. Lengthen the episode if the valid route requires a long detour.

## Validation included

`tests/drone_sac_her_test.gd` covers catalog registration, tensor shapes, bounded actions, navigation memory, hindsight insertion, relabelled wall-path fields, finite replay updates, actor changes, checkpoint inspection and runtime inference.

## Post-implementation audit corrections

The first SAC-HER archive was audited against the original upload after weak learning was observed.
The audit found and corrected several concrete implementation problems:

- the entropy objective operated on absolute motor commands, which pulled every rotor toward `0.5`
  even though the configured neutral hover command is about `0.72`;
- the Q critics and actor objective used inconsistent action representations;
- the entropy temperature was too large relative to this project's small per-control-tick rewards;
- all workers accidentally shared one structured warm-up state because the generic sampling call did
  not pass the worker instance ID;
- the replay update ratio was too low for an off-policy learner;
- the exploration bonus could be collected repeatedly while remaining inside one fresh cell; and
- the old detour-relief range allowed values that could positively reward moving away from the goal;
- the structured warm-up mixer did not match the project's established propeller order;
- the learned actor could take control as soon as replay reached its threshold, before the detached
  optimizer had actually completed a useful update; and
- the first hover-relative actuator map turned symmetric policy noise into a strong downward physical
  thrust bias because the available command range is asymmetric around hover.

That audit aligned actor and critic action tensors, reduced entropy strength, separated worker
warm-up state, increased replay reuse, removed stationary exploration farming and delayed policy
takeover until completed optimizer updates existed. Its version-2 SAC checkpoints rejected the
first archive's incompatible state. The later direction-sign audit below supersedes its remaining
direct-rotor action mapping. PPO checkpoint schemas and PPO learning equations remained unchanged.


## Direction-sign audit

A follow-up audit traced target offsets, real reward accumulation, Bellman targets, critic losses,
actor gradients, rotor slot geometry and reaction-torque signs end to end. The SAC Bellman and
optimizer signs were correct, but two control/credit-assignment problems were found:

- the policy still emitted four unrelated rotor residuals, forcing the critic and actor to rediscover
  the quadrotor mixer from noisy replay; the structured warm-up copied a baseline mixer whose labels
  did not match the actual physical torque axes; and
- hindsight replay added two sparse relabelled samples per real transition, using a dominating `+1`
  terminal spike and almost no signed progress signal.

SAC emits four independent hover-relative propeller actions. Output index 0–3 maps directly to propeller slot 0–3, exactly like PPO. Structured warm-up may generate coherent motor combinations, but the learned actor and both Q critics never use a movement mixer.

The SAC actor-state, observation and checkpoint schemas are now version 3, and the serialized state
also names the `raw_propeller_residual_v1` action contract. Policies trained with the older
direct-rotor action meaning are rejected instead of being interpreted with the new axis mixer. PPO
files and PPO checkpoint schemas remain unchanged.
