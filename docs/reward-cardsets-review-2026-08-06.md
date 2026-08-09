# Shared reward cardsets review — 2026-08-06

## Scope

The drone and four-limb trainers now use the same reward-card presentation and preset workflow in the shared ML Training Room. This change does not alter the known-good limb anatomy, joint controller, standing springs, target/action tensor, drone actuator contract, or stock end-effector defaults.

## Card semantics

Every reward card now declares one of three signal types:

- **Reward** — the raw component is non-negative and its intensity scales a desired behavior.
- **Punishment** — the raw component is non-positive and its intensity scales an undesirable behavior.
- **Mixed** — the component can reward or punish depending on the state.

The shared UI uses green panels for rewards, red panels for punishments, and amber panels for mixed cards. The type label is explicit so color is not the only cue.

Every card is controlled by:

- an enable switch;
- an `HSlider` using the card's own minimum, maximum, and step;
- a visible `current / maximum` intensity readout;
- live current-step and episode-total contribution labels.

The slider controls magnitude. The reward component itself owns the sign, so a punishment slider never needs a confusing negative range.

## Cardset presets

`TrainingRewardCardsetLibrary` provides one shared persistence layer for both body types. Presets are complete cardsets: every card's enabled state and intensity is stored together.

Built-in drone tabs:

- **Balanced Flight**
- **Fast Target Chase**

Built-in four-limb tabs:

- **Ground Locomotion**
- **Long Jump**

User presets are saved separately for drone and four-limb bodies under:

`user://ml_reward_cardsets/cardsets.json`

The reward workspace shows:

- a `Custom` tab for unsaved/manual combinations;
- built-in tabs;
- alphabetically sorted user tabs;
- a preset-name field;
- **Save Current** to create or overwrite a same-named user preset;
- **Delete Tab** for user presets only.

Selecting a tab queues its complete switch/value configuration for the selected group's next episode. Manual changes move the group to `Custom`. Cardset identity is stored with four-limb checkpoints and in drone training-environment metadata. Deleting a user preset converts every currently referencing group of the matching body type to `Custom` without changing its active numeric reward configuration.

## Long Jump cardset

Four jump-specific limb cards were added but remain disabled in the normal Ground Locomotion deck:

- **Explosive takeoff** — detects transition from supported stance to flight and rewards useful upward plus target-directed launch velocity.
- **Airborne target progress** — rewards target-directed horizontal progress while no foot or chassis supports the body.
- **Long jump distance** — pays once after landing, based on target-directed displacement and landing quality.
- **Controlled landing** — rewards upright, feet-first, low-impact landings and punishes hard or chassis-first landings.

The built-in **Long Jump** tab:

- strongly weights airborne progress and landed distance;
- keeps a small ordinary target-progress signal so moving away remains undesirable;
- reduces or disables constant-height, permanent-foot-support, command-smoothing, torque, saturation, wall-approach, and near-floor falling terms that would otherwise suppress takeoff;
- retains chassis dragging, collision, terminal failure, target search, and stable target hold protections.

The jump state persists throughout flight and resets only when support or chassis contact returns. This prevents the launch frame from being mistaken for an entire jump.

## Compatibility and safety

- Existing ground cards retain their default values.
- New jump cards are disabled by default.
- Drone reward calculations retain their existing component semantics; only card metadata, ranges, UI, and reusable presets changed.
- Reward configuration changes still apply at episode boundaries rather than mutating an in-progress episode.
- Built-in presets cannot be deleted.
- No new Godot test files were added. One stale existing target-height assertion was corrected to match profile v8, which deliberately exposes target height.

## End-effector reminder

Stock limb end effectors are still disabled. `LimbEndEffectorDefinition.enabled` defaults to `false`, and the stock four-limb body creates independent no-op definitions for future mixed terminal hardware. The Long Jump cardset does not enable feet, claws, grip, adhesion, or hidden holding forces.

## Static verification performed

Without installing Godot:

- all reward deck card orders match their defined cards;
- every built-in preset references only existing cards;
- all project GDScript bracket/string scans pass;
- global `class_name` values remain unique;
- `git diff --check` passes;
- stock end-effectors remain disabled;
- the archive root remains exactly `scavange-inc`.
