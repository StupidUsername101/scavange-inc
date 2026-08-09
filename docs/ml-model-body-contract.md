# Generic ML model-body contract

This document defines the body/model boundary used by the model forge. It is intentionally
independent of drone, four-limb, and turret trainer implementations.

## Body rule

Every model-controlled physical body has exactly one **Core**. The Core owns an ordered set of
stable, typed attachment slots. A slot may contain zero or one compatible part. Existing gameplay
loadouts keep their current serialized slot arrays and indices; adapters expose them through this
common contract instead of replacing or renumbering them.

A Core or equipped part may declare:

- zero or more independent control channels;
- zero or more normalized observation channels;
- part/capability tags used by typed slots;
- runtime code that encodes its declared observations from the physical instance.

The body builder never asks whether a part is a limb, gun, propeller, tool, or some future type.
It asks the part for its model contract. This is the extension point for the future body creator.

## Draft -> Accept -> immutable manifest

`MLBodyBuildDraft` is the editable representation. Editing a draft does **not** assign neural
indices and must not create or resize a policy network.

The future body-creator UI should follow this lifecycle:

1. Create or adapt a Core and its ordered slots.
2. Equip/unequip compatible parts while the build is a draft.
3. Optionally preview the physical build. Do not create a model yet.
4. The user presses **Accept**.
5. Call `MLBodyBuildDraft.accept_build()` exactly once.
6. The returned `MLBodyInterfaceManifest` freezes deep copies of the Core/parts, assigns dense
   control and observation offsets, and records an exact topology signature.
7. Only now allocate the model/network using the accepted counts.
8. To edit the body again, call `MLBodyInterfaceManifest.editable_revision()` to open an isolated
   draft from the frozen accepted Core, slot definitions, mount transforms, and equipped parts. The
   running manifest does not change. Accepting the revision creates a new model interface and
   normally a new/retrained model.

An accepted manifest is therefore the authority for a checkpoint, training group, evaluator, and
runtime body. A model must never infer equipment from action count alone.

## Creator presets, not runtime defaults

Whole-body starting configurations live in `MLBodyPresetLibrary`. Runtime worker classes no longer
manufacture a stock body when hardware is missing. The built-in creator presets are:

- **Quad Drone**
- **Quad Drone + Grabber Limb**
- **Four-Limb Walker**
- **Stationary Turret**

Selecting a preset returns a fresh, mutable `MLBodyBuildDraft`; it never returns a globally shared
editable body and it never finalizes a neural interface. Preset records expose stable IDs, display
names, descriptions, body kinds, Core names, slot counts, and preview control/observation counts for
the upcoming UI. `MLBodyBuildDraft.ui_snapshot()`
provides read-only slot/equipment plus preview channel counts without freezing anything. The UI should
instantiate a draft by preset ID, edit that draft, and call Accept only after the user confirms the body.

PPO no longer contains a synthetic quadrotor body-interface fallback. Constructing a PPO trainer
without an accepted manifest fails instead of silently allocating a four-output policy. Places that only
need a tuning preview explicitly instantiate the **Quad Drone** preset first. This keeps the future
creator's Accept action as the only normal boundary that can finalize model dimensions.

`MLBodyCoreDefinition` is the creator-facing Core and owns the authoritative slot list. Existing
gameplay Core resources may be wrapped as `physical_core` while worker families migrate. The
Four-Limb Walker preset does **not** hide a `FourLimbBodyDefinition` inside that creator Core: its
Core uses generic rigid-body physics and its four legs exist only as ordinary equipped
`GenericLimbDefinition` parts. `FourLimbBodyDefinition` remains only as a current-runtime
compatibility representation for the fixed four-limb trainer.

The presets intentionally contain no reward configuration. Reward-card composition belongs to the
training/model-creator layer and can be attached separately later without changing body topology or
body preset definitions.

Reusable individual drone components remain ordinary **part presets** (for example Standard Core,
Standard Battery, and Standard Propeller). They are not whole-body defaults and selecting one never
creates or finalizes a body by itself.

### Creator persistence

`MLBodyBuildSnapshot` persists an editable draft as JSON-safe Core/slot/part Resources without
finalizing a model. `MLBodyResourceSnapshot` recursively stores exported/storage properties, including
nested Resources inside typed arrays such as limb segments, joints, and end effectors. This is the
generic persistence path the upcoming creator UI should use for custom physical builds; adding a new
part type does not require adding another worker-specific property list.

Loading a creator snapshot produces another **draft**. It must still go through Accept before any
network is allocated. Missing/corrupt hardware fails closed rather than selecting a stock preset.
Current drone checkpoint hardware records use the same generic Resource snapshot machinery so
creator-edited articulated attachments survive evaluation/checkpoint restoration.

## Tensor assembly

The accepted manifest owns the topology-dependent block:

- Core observations first;
- then slot observations in stable slot order;
- each part's channels in the order declared by that part.

`MLModelInputVectorBuilder` combines the trainer's stable task/environment features with that body
block. A trainer may add navigation targets, obstacles, threats, episode state, reward-task inputs,
etc. without knowing which physical parts produced the body channels.

The same manifest owns the action topology. Global model outputs are routed back to the Core and
individual slots by their accepted offsets. Control descriptors carry physical minimum, maximum,
and neutral values; the policy network itself can continue to use a normalized latent action range.

The manifest signature describes the **neural interface**, not incidental physical tuning. Changing
propeller power, mass, color, or another tuning value does not invalidate a policy when the part
still declares the same controls and observations. Adding/removing/retyping a slot or changing the
channel topology does.

## Generic limbs

There is no drone-specific ML arm implementation.

`GenericLimbDefinition`, `GenericLimbAssembly3D`, `GenericLimb3D`, `LimbsController3D`, and the
ordinary `LimbEndEffectorDefinition`/`GenericGrip3D` stack are shared. A limb may have any positive
segment count. Each `LimbJointDefinition` declares which axes are controllable; accepted-body
finalization assigns dense model indices later. A controlled end effector contributes its own grip
channel.

`GenericLimbModelContract` walks the authored definition and derives controls/observations from it.
Consequently, adding another controlled joint axis or segment automatically changes the accepted
body topology. The editable limb resource never owns global neural-network indices: a physical host
packs the limb's declared controls into a **local** runtime mapping, while the accepted manifest owns
the global offsets. This keeps draft parts reusable when slots are reordered or other attachments are
added. Static `climbable` grips and dynamic `carryable` item grips use the same physical grip system
regardless of whether the limb is on a creature or a drone.

The training drone convenience option currently installs an ordinary two-segment limb through a
normal drone attachment slot. Its controls are shoulder X, shoulder Z, elbow Z, and grip. These are
independent channels in addition to the four propeller channels; there is no single "arm" macro.

## Existing body adapters

The common contract is already exposed by all current physical worker families:

- **Drone**: existing battery, propeller, AI-chip, and attachment slots are all represented in stable
  gameplay order. Zero-channel parts still remain visible to the creator; propellers and generic limb
  attachments declare their model channels.
- **Four-limb body**: the current runtime compatibility profile is physically built from the generic
  limb stack. Creator presets convert its known-good anatomy into generic Core physics plus ordinary
  typed limb slots; runtime limbs expose the same body contract.
- **Turret**: the base is the actual Core and owns yaw; the gun is a slot part and owns pitch and
  trigger. This prevents actuator ownership from being faked by trainer-specific action ordering.

The current four-limb and turret PPO task encoders still preserve their established fixed training
profiles. Their bodies nevertheless expose the common body manifest now. Those compatibility
encoders do not construct, repair, or default body topology; new groups receive an explicit creator
preset/template and the group's accepted body remains authoritative afterward. This avoids
destabilizing working trainers while making body topology a shared concept for the next body-creator
stage.

Current drone PPO is body-manifest aware and sizes its action/body-observation blocks only after the
loadout is finalized. Current SAC deliberately remains rotor-only and rejects controlled attachment
topologies instead of silently ignoring them.

### Current physical-host boundary

The creator/body contract is intentionally more general than every current physical host. A draft may
represent arbitrary ordered Core slots and attachment types, but spawning must still validate that the
selected runtime host can physically instantiate that topology. `ServerDrone` currently owns four
physical propeller nodes, the current four-limb trainer owns its established four-leg host, and the
current turret host owns its base + gun structure. Those host limits are **not** encoded as body-creator
defaults or neural-interface assumptions. They are runtime compatibility checks that can be removed as
the physical assemblers become generic.

Consequently, the next body-creator UI can safely edit, save, reopen, preview, and Accept generic body
drafts now. It should prevent spawning a build on a host that cannot yet instantiate the accepted
physical topology rather than silently rewriting that build to a stock preset.

## Adding a future gun/tool/attachment

A new serialized part should implement the model-part methods used by `MLBodyPartContract`:

- `ml_part_tags()`
- `ml_control_descriptors()`
- `ml_observation_descriptors()`
- `ml_encode_observation(runtime_state, host_state)`

Its physical host must expose a runtime state snapshot and accept the local command array routed to
its slot. No PPO-specific feature or action hardcoding should be added for the new part.

This is the intended path for guns, tools, sensors with topology-dependent channels, extra limbs,
and later bodies produced by the model-body creator.
