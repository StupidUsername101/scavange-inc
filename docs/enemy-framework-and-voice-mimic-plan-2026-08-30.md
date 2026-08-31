# Enemy framework and voice-mimic plan — 2026-08-30

## Purpose

This document records the implementation plan for reusable expressive enemies and the first vertical
slice: a derpy flute player that becomes threatening when geometry, darkness and pursuit hide its
body but preserve its sound. It also evaluates how a later enemy can repeat or synthesize speech in
a player's voice after proximity voice chat exists.

This began as a read-only architecture plan. The first server-authoritative vertical slice described
below was implemented on 2026-08-30; the remaining shared-motor, navigation, voice-chat and mimicry
work stays explicitly staged rather than being hidden inside that prototype.

## Implementation status — first vertical slice

Implemented:

- `FluteRunnerDefinition` and an allocation-free `FluteRunnerBehaviorController` with loiter,
  curious, pursue, chase, search and collision-derived fumble states;
- low-rate authoritative sight queries plus a fixed-capacity acoustic stimulus ring. Hidden players
  are remembered only from real player-originated gameplay sounds evaluated through the existing
  acoustic geometry, not from distance-only wall vision;
- acceleration/turning/local obstacle feelers and a physical tackle gated by real slide contact,
  relative speed, facing and cooldown;
- compact enemy snapshots containing gait/awareness/action clocks and no bone transforms;
- `EnemyHumanoidPresentation3D`, composing the existing imported skin, procedural contact legs,
  pose controller, expressive oculars and weighted authored-body ragdoll;
- generic forearm channels in `CharacterPoseDefinition`, enabling a proper two-handed flute pose and
  later emotes without a flute-specific skeleton patch;
- material footsteps and a reproducibly authored flute loop on the same per-listener continuous
  acoustic lane as radios and speaker arrays;
- a single removable field-test spawn at the parkour clearing and dedicated headless contract and
  physics-integration coverage.

Deliberately still pending:

- extracting `CharacterLocomotionMotor` from the player without changing established movement;
- navmesh/path-corridor routing through multi-room structures (the first open-area encounter uses
  bounded local steering and target memory);
- shared missing-limb enemy capability state and authoritative enemy ragdoll anchors/recovery;
- proximity voice chat, captured phrase replay, inference benchmarking and all mimicry consent/UI.

The field-test enemy therefore proves the architecture and is playable, but is not being presented
as the completion of every later phase in this document.

## Current project boundary

The dormant enemy stack still provides useful authoritative infrastructure:

- `ServerEnemy` owns registration, health, faction, targetability, damage and snapshots.
- `Server` already registers enemies in the spatial hash and exposes them to projectiles and deployed
  worker targeting.
- `ServerReplicationService` publishes lifecycle-aware enemy snapshots on the bulk physics stream.
- `EnemyProxy` owns client interpolation and proxy lifecycle.

The old zoo gait and behavior implementation must not become the new foundation. Its behavior chooses
the nearest candidate and moves directly toward it; its physical limbs follow a kinematic chassis.
The active player character now has a substantially better procedural stack:

- `PlayerGait` provides allocation-light, distance-driven and non-uniform stepping.
- `PlayerProceduralLegRig` provides real foot probes, stairs, uneven support, independent landing,
  missing-limb handling and contact events.
- `PlayerCharacterPoseController` provides layered breathing, leaning, impacts, arms, recovery and
  authored action poses.
- `PlayerCharacterSkin` drives the imported PSX/Mixamo body.
- `PlayerOcularExpressionController` provides attention, pupils, eyelids and deterministic idles.
- `PlayerRagdoll3D` provides articulated presentation and the player runtime has authoritative impact,
  trip and ragdoll recovery behavior.

The new enemy should compose shared character components. It must not subclass or instantiate
`ServerPlayer`, because player input, prediction, inventory, weapons, PBD state and stamina policy are
player-specific.

## Non-negotiable rules

1. The server owns enemy decisions, paths, contacts, damage, target memory and ragdoll outcomes.
2. Clients produce procedural presentation from compact motion state; bones are never replicated.
3. Missing limbs remain a supported capability state, not an exceptional code path.
4. Pathfinding answers where to travel. The physical locomotion motor answers how the body travels
   there, and the detailed foot rig answers where visible feet land.
5. Enemy audio uses the same listener-specific acoustic system as every other game sound.
6. Comedy must mostly emerge from physical events and expression, not arbitrary animation timers.
7. No scene-name, bunker-position or enemy-specific acoustic fixes are permitted.
8. Expensive navigation, speech inference and acoustic graph work never runs once per enemy per
   rendered frame.

## Shared character architecture

### `CharacterLocomotionMotor`

Extract the reusable movement primitives currently embedded in `ServerPlayer`. The motor accepts a
small intent structure rather than reading input itself:

- desired planar direction and speed;
- jump request and optional capabilities;
- body/loadout capabilities;
- current physical state and collision environment.

It owns acceleration, retained momentum, recovery steps, small-step traversal, gravity, landing,
velocity-derived impacts, tripping and ragdoll triggers. Player-only input history, flip recognition,
PBD restrictions, inventory and prediction remain in the player adapter. Enemy policies may enable
or disable individual capabilities without forking the solver.

### `CharacterMotionState`

Use one compact presentation contract for players and humanoid enemies:

- transform, linear velocity and grounded state;
- gait phase, stride, foot-contact sequence and recovery intensity;
- airborne/landing state and impact impulse;
- action-pose ID and blend weight;
- attention target/look direction and expression clock;
- limb availability;
- ragdoll state and authoritative anchor.

Snapshots carry state and discrete events, not per-bone transforms. Proxies interpolate/extrapolate
continuous values and apply sequenced footfall, impact, action and audio events exactly once.

### `ProceduralCharacterPresentation`

Compose the existing gait, procedural legs, pose controller, character skin, ocular controller and
ragdoll behind one presentation component. Both `PlayerProxy` and humanoid `EnemyProxy` feed it a
`CharacterMotionState`. Appearance is an explicit resource/path or stable appearance ID; it never
depends on filesystem child order or incidental player IDs.

## The first enemy: the flute runner

Working name: **Flötenläufer**. The exact name is content, not architecture.

### Character rule

The same behavior should be funny when clearly visible and frightening when partly understood:

- In an open field the player sees an awkward character overcommit to player-quality running,
  stumble against geometry and recover while playing a foolish melody.
- In a maze, tunnel or dark building the acoustic system carries the flute and physical footsteps
  around the valid route before the body becomes visible.
- The game never teleports the enemy or lies about acoustic geometry to create fear.

### Small state machine

A compact state machine is sufficient; a behavior tree is not justified for the first enemy.

1. `LOITER`: awkward idle breathing and flute practice.
2. `CURIOUS`: eyes and head acquire a seen or heard stimulus before the body turns.
3. `PURSUE`: navigate toward a visible target or last-known position at a controlled pace.
4. `CHASE`: build sprint speed, increase gait commitment and close distance.
5. `FUMBLE`: recover from a real collision, failed attack, loss of footing or sharp obstruction.
6. `SEARCH`: inspect the last-known area, with quieter and less frequent flute phrases.
7. `STUNNED` / `RAGDOLL` / `DEAD`: use the shared impact and ragdoll path.

Fumbles are consequences of simulated events. A random clock must not periodically force slapstick
regardless of context.

### Awareness and navigation

- Query nearby candidates through the existing spatial hash.
- Confirm candidates using sight and admitted/heard sound; retain a bounded last-known-position lease.
- Build one server navigation surface from the level's clustered static collision geometry.
- Recalculate path corridors at a low fixed rate or when target/path validity changes.
- Perform light local steering at physics rate. Adapt the existing planar avoidance concepts only
  after a single enemy is correct; the drone's 3D hover avoidance is not a ground controller.
- Keep detailed stair/foot collision separate from the navigation surface so navigation can use a
  walkable ramp while visible feet still rest on individual steps.

### Attack

The first attack is a physical tackle/body check rather than an invisible radius:

- Validate real contact, relative velocity, facing and cooldown on the server.
- Low energy produces a shove or flinch.
- A committed hit can trip or ragdoll the player.
- Colliding with scenery applies the same class of consequence to the enemy.
- Projectiles and deployed workers already reach the enemy through the generic target/damage lanes.

### Flute presentation and sound

- Add an authored flute-holding `CharacterPoseDefinition` layered over procedural locomotion.
- Attach the source to a named mouth/flute mount on the real character presentation.
- Generalize the continuous radio-program state/renderer boundary; do not pretend the enemy is a
  radio or create a client-only `AudioStreamPlayer`.
- Give the flute a stable source ID, stream revision and playback phase so snapshots cannot restart
  the melody.
- Let current moving-source acoustic attachments and listener-specific filtering carry it through
  rooms, tunnels, forests and the maze.
- Emit footsteps from actual foot contacts using the existing physical-surface rules.
- Wrong notes and breath breaks may respond to impacts, low balance or recovery; melody tempo may
  follow actual chase cadence within a bounded musical range.
- Stun/death stops new input while valid acoustic tails decay normally.

## Enemy implementation phases

### Phase 1 — shared body without player regressions

1. Introduce the motion-state contract and shared presentation component.
2. Extract the locomotion motor behind the existing player adapter.
3. Keep every current player control, flip, momentum, missing-limb and ragdoll result unchanged.
4. Add an explicit humanoid enemy definition and a non-AI test actor using the player character skin.
5. Drive it through stairs, uneven supports, jumps, impacts and ragdoll in a deterministic fixture.

Gate: all current player movement/presentation tests plus shared-character equivalence tests pass.

### Phase 2 — authoritative flute-runner vertical slice

1. Replace the old direct-line controller for the new definition with the compact state machine.
2. Add sight/hearing memory, low-rate navigation and physics-rate local steering.
3. Add authoritative tackle contacts and shared physical recovery.
4. Generalize the continuous program source and implement synchronized spatial flute playback.
5. Replicate compact gait, pose, expression and action state with sequenced discrete events.

Gate: host and remote clients see the same target, gait, foot contacts, tackle, flute phase and
ragdoll outcome while hearing their own listener-specific acoustic result.

### Phase 3 — expression, damage and scalable runtime

1. Add eye/head attention, event-driven fumbles, wrong-note responses and search personality.
2. Make missing/damaged limbs alter gait and available behavior instead of merely hiding meshes.
3. Optionally make the flute a physical item that can be dropped, stolen or retrieved.
4. Add region activation, path-query budgets, maximum active counts and snapshot byte budgets.
5. Add a level-editor spawn descriptor based on stable enemy definition IDs.

Gate: multiple enemies remain deterministic and performant, and dormant enemies produce no repeating
network or navigation work.

## Voice chat prerequisite

There is currently no microphone or voice transport code in the project. The output side is already
well suited to proximity voice: fixed client voice/DSP pools, moving source attachments, cached
listener contexts, physical travel delay and smoothed acoustic parameters.

### Capture and transport

Primary Steam builds should start with the Steam Voice API:

- push-to-talk calls `StartVoiceRecording` / `StopVoiceRecording`;
- poll compressed data with `GetAvailableVoice` and `GetVoice`;
- send it over a dedicated unreliable voice channel;
- recipients use `DecompressVoice` and stream decoded mono PCM into a preallocated playback buffer.

Valve explicitly leaves transport to the game. Steam networking supports separate channels and
unreliable delivery, which is appropriate for short-lived voice frames; delayed reliable packets
must not block newer speech. Each packet needs source player ID, session generation, sequence,
capture timestamp and codec-frame bytes. A small adaptive jitter buffer reorders within a bounded
window, conceals loss and drops late frames.

`AudioStreamMicrophone` plus `AudioEffectCapture` is the non-Steam fallback. Godot exposes captured
stereo float PCM through a ring buffer, so that fallback still needs an encoder such as Opus before
network transport. Do not send raw PCM.

Start with push-to-talk. Always-on capture adds echo cancellation, background capture and consent
problems before the gameplay value is proven. Optional RNNoise preprocessing can provide inexpensive
real-time denoising/VAD, but it should be benchmarked against Steam's captured output before being
added.

### Server/client acoustic split

Voice frames must not cause a ray/probe calculation per packet.

1. The server maintains a low-rate audible-source set for every listener using player mouth
   transforms, spatial hashing and the existing acoustic graph.
2. It relays compressed frames only to eligible peers and publishes smoothed acoustic context at a
   lower rate, approximately the existing local-audio-context cadence.
3. Every client decodes admitted frames continuously and applies the latest context through a
   dedicated `SpatialVoiceChatRenderer` built from the current persistent effect racks.
4. Host playback follows the same renderer path. There is no direct host-only bypass.
5. Mouth movement may use a cheap local envelope sent at low rate; it must not require raw audio or
   bone replication.

The voice-chat renderer can share acoustic DSP/rack primitives with radios and one-shots, but it is
not a seekable radio voice. It owns bounded per-speaker jitter/PCM rings rather than track positions.

### Voice-chat controls

- push-to-talk binding and visible speaking indication;
- per-player mute, session mute and input/output device selection;
- independent voice volume with the final safety limiter retained;
- clear behavior during reconnect and peer-ID rebinding;
- no playback before session admission or after disconnect generation changes.

## What “mimic the player's speech” can mean

These are distinct products and should be implemented in increasing-risk order.

### Tier A — captured phrase replay

Keep a short, bounded ring of VAD-delimited utterances that were already transmitted through voice
chat. The enemy later replays one phrase from its own mouth through the acoustic system, optionally
with small nonlinear pitch/formant instability and physical breath/noise layers.

This is not generative ML, but it is the most faithful mimic, needs no inference hardware and is an
excellent gameplay prototype. It also establishes consent, lifetime, caching and network contracts
needed by later tiers.

### Tier B — zero-shot voice conversion

Voice conversion preserves the content and timing of a source performance while changing its timbre
to a reference speaker. This is useful when an authored actor performs an enemy line with deliberate
scary/derpy prosody and the runtime converts it toward an opted-in player's voice.

Seed-VC is a relevant research baseline: its paper reports strong zero-shot speaker similarity and
content preservation, and the project supports reference clips of roughly 1–30 seconds. Its real-time
path reports hundreds of milliseconds of algorithm/device latency and recommends a GPU; its GPL-3.0
code also makes direct shipping integration a deliberate licensing decision rather than a casual
dependency. Treat it as a benchmark behind an interface, not the hard-coded final runtime.

Tier B does not require ASR, a language model or new text. It is therefore the preferred first ML
experiment.

### Tier C — transcription plus cloned TTS

For the enemy to repeat cleaned-up speech, rearrange words, or say authored new content in the
player's voice:

1. Segment an opted-in utterance with VAD.
2. Transcribe it locally.
3. Select either the exact transcript or an authored phrase; do not feed arbitrary transcripts into
   a general-purpose LLM for the first version.
4. Synthesize it using a session-only voice condition derived from clean reference speech.
5. Encode the one canonical waveform, register it as a bounded session clip, then schedule it from
   the enemy source through normal acoustics.

Current candidates must be benchmarked on target machines behind a replaceable `VoiceMimicBackend`:

- Pocket TTS is the most practical prototype candidate as of this document: its official project is
  MIT-licensed, about 100M parameters, supports German, voice cloning, CPU streaming and reports about
  200 ms to the first chunk on its reference hardware. Voice-state extraction is comparatively slow,
  so one opted-in state should be prepared once and retained only for the session.
- Qwen3-TTS is a higher-quality/heavier comparison candidate. Its 0.6B and 1.7B families support
  streaming and three-second voice cloning; the paper reports first-packet latency near 100 ms on its
  evaluation setup and Apache-2.0 model releases. It is not evidence that every player's gaming PC
  can run it alongside the game without profiling.
- CosyVoice 3 is another quality benchmark for multilingual zero-shot synthesis, but its 0.5B/1.5B
  scale makes it less attractive than Pocket TTS for a default CPU-side prototype.
- Whisper can provide a well-understood multilingual ASR baseline, but transcription is optional for
  authored voice-conversion lines and should not be added until Tier C is explicitly selected.

Reported first-packet latency is not an end-to-end game latency guarantee. Capture segmentation,
denoising, model warmup, reference encoding, synthesis, compression, upload, scheduling, network
delivery, jitter buffering and physical acoustic delay must all be measured separately.

## Recommended inference ownership

Do not require every listener to synthesize independently: model differences would produce different
waveforms, timings and tails for the same world event.

Recommended cooperative-session path:

1. The player explicitly opts into enemy mimicry.
2. That player's client retains the clean reference and creates the session-only voice state locally.
3. The authoritative server sends a bounded `MimicSynthesisRequest` containing an authored phrase ID
   or an approved captured-utterance ID, enemy ID, seed, nonce and maximum duration.
4. The opted-in client renders one result, encodes it and returns the payload.
5. The server validates request ownership, nonce, codec, rate, channel count, duration, byte limit and
   hash, then caches the immutable session clip.
6. The server schedules that same clip for every listener from the enemy's source position.
7. If inference is unavailable, late or rejected, the enemy uses its generic authored voice.

This keeps the raw voice reference off other clients, avoids forcing the host to own a capable GPU,
and gives all listeners one waveform. A client can still submit malicious audio, so enemy damage,
timing and AI must never depend on the returned waveform. For untrusted/public matchmaking, move
inference to the authoritative host/service or restrict the feature to captured phrase replay.

A local sidecar process is acceptable for prototyping model quality because it isolates Python/model
dependencies from Godot. It is not automatically the shipping architecture. A release candidate must
measure package size, startup, CPU/GPU contention and crash isolation before choosing native/ONNX,
an optional local worker, or no generative model at all.

## Consent, lifetime and abuse boundaries

Voice cloning is qualitatively different from ordinary playback and must be visible and optional.

- `Allow enemies to mimic my voice` is explicit, revocable session consent and defaults off.
- Live voice mute/block applies to captured and synthesized variants attributed to that player.
- Raw reference PCM, embeddings/voice states, transcripts and generated clips are memory-bounded and
  deleted on opt-out, disconnect lease expiry and session teardown. They are not written to saves,
  logs, crash reports or source control.
- Late joiners receive no historical player samples. They may receive only a currently scheduled,
  already-admitted enemy clip.
- Generated audio is internally tagged with source player, model/backend revision and request nonce
  for mute/report attribution; the UI should make the mimic setting understandable.
- The server accepts only responses to live requests and never accepts arbitrary file paths, codecs,
  sample rates, durations or unbounded blobs.
- Do not use a cloud inference service by default. Any later cloud option requires a separate explicit
  disclosure because microphone/reference audio would leave the machine.

## Test and measurement gates

### Shared enemy body

- Player movement and presentation remain bit/behavior equivalent where extraction is intended to be
  mechanical.
- Player and enemy traverse the same small-step/stair/uneven-support fixture.
- Missing one or both legs produces no phantom contacts or invalid pose.
- Tackle damage occurs only after verified collision and relative velocity.
- Ragdoll recovery cannot return to a pre-impact position or remain embedded in the stair fixture.

### Navigation and replication

- Target acquisition uses spatial candidates plus sight/hearing and cannot scan every entity.
- The enemy routes through doors and around walls without oscillation.
- State transitions are deterministic for a fixed seed and clock.
- Host, remote client and late join agree on target, gait phase, action pose, flute phase and death.
- Enemy snapshots stay compact and do not replicate bones.

### Voice chat

- Simulate loss, duplication, reordering, jitter and reconnect generation changes.
- Bound capture-to-audible latency and log capture, encode, network, jitter, decode, renderer and
  physical-propagation time separately.
- Verify that context updates remain smooth while PCM is continuous.
- Two listeners in different rooms hear different acoustic results from one speaker.
- Muted or out-of-range speakers allocate no active playback voice.
- Capture, network and playback rings remain bounded with no per-frame buffer churn.

### Mimicry

- No opt-in means no retained samples, voice state, request or generated clip.
- Revocation and session teardown erase every retained artifact.
- Every listener receives the same immutable clip hash but a listener-specific acoustic mix.
- Rejected, timed-out or unsupported inference always falls back to a generic authored voice.
- One player/enemy cannot flood the inference queue; requests are rate-limited and coalesced.
- ASR/TTS errors never alter enemy authority, damage or navigation.
- Benchmark German and English, noisy microphones, clipped input, very short references, CPU-only
  machines and simultaneous game load before choosing a model.

## Recommended delivery order

1. Shared character foundation and flute runner without voice chat.
2. Push-to-talk proximity voice with Steam capture/codec, bounded unreliable transport and spatial
   playback through the existing acoustic system.
3. Session-only captured phrase replay from the flute runner or a dedicated mimic enemy.
4. Offline benchmark harness comparing direct replay, Seed-VC conversion, Pocket TTS, Qwen3-TTS and
   the generic fallback on real target hardware.
5. Ship Tier B or Tier C only if the benchmark, package, consent and multiplayer gates are satisfied.

This order makes every stage independently useful and prevents an ML runtime from blocking the enemy,
voice chat or acoustic integration.

## Primary references

- [Valve Steam Voice](https://partner.steamgames.com/doc/features/voice?language=english)
- [Valve ISteamNetworkingMessages](https://partner.steamgames.com/doc/api/ISteamNetworkingMessages)
- [Godot AudioEffectCapture](https://docs.godotengine.org/en/stable/classes/class_audioeffectcapture.html)
- [IETF RFC 6716: Opus](https://datatracker.ietf.org/doc/html/rfc6716)
- [Xiph RNNoise](https://github.com/xiph/rnnoise)
- [Seed-VC paper](https://arxiv.org/abs/2411.09943) and
  [reference implementation](https://github.com/Plachtaa/seed-vc)
- [Pocket TTS reference implementation](https://github.com/kyutai-labs/pocket-tts)
- [Qwen3-TTS technical report](https://arxiv.org/abs/2601.15621)
- [CosyVoice 3 paper](https://arxiv.org/abs/2505.17589) and
  [reference implementation](https://github.com/QwenAudio/CosyVoice)
- [OpenAI Whisper reference implementation](https://github.com/openai/whisper)
