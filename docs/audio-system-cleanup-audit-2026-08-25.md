# Audio-system cleanup audit — 2026-08-25

## Status and scope

This audit was executed on 2026-08-26. The document preserves the original diagnosis and now ends
with the implementation and measured validation result.

Reported symptom: while walking into the bunker corner below the back-left speaker, above/behind the white prop, the music can become strangely distorted or change character abruptly.

The white prop is `generator_1`, located directly in front of the back-left speaker. The audit used the authored bunker geometry and the real server propagation service, with one persistent listener moved in 5 cm increments at the normal 50 ms server update interval.

## System map

The relevant signal path is:

1. `speaker_cluster_demo_layout.gd` authors the bunker, four speaker locations, props, and acoustic probes.
2. `server_speaker_cluster.gd` builds the clustered collision/acoustic geometry and four synchronized emitters.
3. `server_acoustic_service.gd` evaluates source-to-listener propagation at 20 Hz. It combines direct transmission, graph/probe paths, room diffusion, material filtering, apparent source direction, and reverb parameters into emitter state packets.
4. `radio_audio_renderer.gd` renders each speaker as its own pooled `AudioStreamPlayer3D` voice.
5. `spatial_audio_effect_rack.gd` smooths packet values and applies distortion, EQ, and filters on each direct voice. Standalone sources retain one local reverb; synchronized speaker groups split authoritative energy between their spatial direct voices and one listener-space wet-only late field. The continuous-program bus ends in a stereo-linked hard limiter.

The design is broadly sound: server-authoritative propagation, fixed voice/effect pools, cached static probe data, room diffusion, material-dependent transmission, and client interpolation are all worth preserving.

## Reproduction result

Three paths were measured around the back-left speaker.

### Generator-shadow edge — defect reproduced

Listener path in bunker-local coordinates:

- from approximately `(-8.0, 1.55, 2.3)` to `(-2.8, 1.55, 2.3)`
- 5 cm spacing
- 50 ms between samples

Measured maximum adjacent changes:

| Quantity | Largest 5 cm change |
| --- | ---: |
| Final volume | **2.902 dB** |
| Occlusion | 0.35 |
| Low-pass cutoff ratio | 1.262x |
| Reverb send | 0.0385 |
| Apparent source position | 1.603 m |

The most useful sequence was:

| Local X | Occlusion | Volume | Low-pass | Route state |
| ---: | ---: | ---: | ---: | --- |
| -5.40 | 0.344 | -15.29 dB | 15,949 Hz | edge crossfade |
| -5.35 | 0.600 | -15.24 dB | 14,363 Hz | edge crossfade |
| -5.30 | 0.600 | **-12.34 dB** | 12,431 Hz | parallel routes |

The final step adds about 2.9 dB over 5 cm while occlusion remains exactly 0.600. This rules out ordinary distance attenuation and strongly implicates route combination/state transition logic.

### Direct approach into the corner — no comparable discontinuity

The diagonal path from about `(-8.0, 1.55, 4.35)` to `(-4.0, 1.55, 5.9)` had a maximum adjacent volume change of roughly 0.05 dB.

### Directly below the back-left cabinet — no comparable discontinuity

The path along the back wall at about `z = 6.45` had a maximum adjacent volume change of roughly 0.07 dB and did not become obstructed at listener height.

The defect is therefore localized to crossing the generator's acoustic shadow. It is not a generic distance curve problem, a generic bunker-corner problem, or evidence that the speaker cabinet itself blocks the listener path.

## Findings, ranked

### P0 — confirmed: route participation is discontinuous

`server_acoustic_service.gd` uses different combination rules during and after an obstruction-edge transition:

- during `edge_crossfade`, graph participation is faded against direct participation;
- after that timer ends, while the central ray is still blocked, the code changes to the normal parallel-route combination and gives both graph and transmitted-direct results full participation.

That state change can reintroduce transmitted-direct energy at full weight on the next 20 Hz packet. The measured 2.9 dB jump occurs on exactly this `edge_crossfade -> parallel` transition while obstruction is unchanged.

This needs a single continuous energy model. Extra output smoothing would conceal the discontinuity but would not repair it.

### P1 — confirmed: partial obstruction is coarse and incompletely smoothed

Direct obstruction is sampled with one center ray and four offset rays. Non-boundary props therefore produce only five coverage levels: `0.0`, `0.2`, `0.4`, `0.6`, `0.8`, and `1.0`.

The edge transition is primarily triggered when the central `geometry_blocked` boolean changes. Coverage changes such as 20% to 40%, while the center ray keeps the same boolean state, can pass through without that transition smoothing.

This explains why a small prop can create spatially stepped filter/level targets. It is separate from the P0 branch bug: even with continuous route mixing, the obstruction estimator needs a continuous or appropriately reconstructed coverage signal.

### P1 — confirmed: the generator has the bunker's wall material

`server_speaker_cluster.gd` assigns the scene-wide `garage_concrete_metal` acoustic material to every baked prop. `PROP_SURFACES` differentiates physical/footstep surfaces, but not acoustic materials.

The generator consequently uses the same strong transmission loss, low-pass behavior, absorption, scattering, resonance, and reverb contribution as the concrete/metal bunker shell. Its current material includes approximately:

- transmission volume: `-8.2 dB`
- transmission low-pass: `1,650 Hz`
- transmission gain by band: `(0.38, 0.075, 0.014)`
- reverb send: `0.38`

A generator-sized prop should not behave like a solid section of the bunker wall. The material model should be assigned by prop/category and remain independent from the footstep surface classification.

This must be fixed generically in the material/import/prop metadata path, not with a generator-coordinate exception.

### P1 — confirmed: the facility PA inherits the portable-radio coloration profile

The speaker cluster uses `portable_radio.tres` as its playback profile. That brings portable-radio static and distortion into every facility speaker:

- distortion mode: Overdrive
- configured drive: `0.1`
- high-frequency retention: `12 kHz`
- post gain: `-1.5 dB`
- static: approximately `-24 dB`

Godot 4.6's Overdrive implementation does not use the exposed `drive` value in the Overdrive branch; it applies a fixed waveshaping curve. The rack also keeps distortion processing active for persistent radio/program voices. Therefore `drive = 0.1` does not mean a subtle 10% coloration: the entire PA program passes through the fixed overdrive curve.

This is a credible cause of the word “distorted,” especially close to one dominant speaker. Facility PA, portable radio, intercom, and clean source playback need separate source/playback profiles, even when they share the propagation system.

Official implementation reference: <https://github.com/godotengine/godot/blob/4.6/servers/audio/effects/audio_effect_distortion.cpp>

### P1 — likely: local scattering and the shared room field are double-counted near the prop

The generator both:

- filters/scatters the direct route through its concrete/metal material; and
- contributes additional route reverb while the listener already receives the bunker's shared diffuse room field.

The back-left probe is also very close to the generator. Its baked reflection rays treat the generator as a wall-like concrete/metal surface, which can bias the local hall shape and apparent enclosure of this corner.

This does not create the measured 2.9 dB branch jump by itself, but it can make the resulting timbral transition sound much more aggressive.

### P2 — partially resolved: coherent direct voices still diverge spectrally

The four speakers play the same synchronized digital program. Their scalar source levels are normalized so an ideal coherent sum approximates an energy sum. After normalization, however, every voice receives different:

- panning and apparent position;
- obstruction EQ and filtering;
- reverb parameters;
- distortion/static processing;
- activation history and possible decoder seek history.

One scalar normalization factor cannot preserve energy independently for left/right channels and frequency bands after those paths diverge. In a corner, one newly filtered/unfiltered voice can therefore change the spectral sum disproportionately. This may produce hollowness, phase-like coloration, or limiter activity even when the scalar server volume looks plausible.

The 2026-08-26 correction now performs coherent normalization after splitting direct and wet power,
so room energy cannot distort that scalar budget. Per-ear and per-band differences after obstruction
EQ remain a bounded approximation and stay covered by the rendered waveform test.

### Resolved — four independent reverb networks modeled one room

Each emitter owns a separate reverb effect rack, even though the four speakers excite one listener-space bunker response. Correlated program material can therefore create several similar but independent late tails. Their summed behavior depends on each voice's current filters and interpolation state.

The shared listener/room late-field path described at the end of this document replaced those
independent tails after the bunker-entrance field failure exposed the missing transition case.

### P2 — possible: fast DSP coefficient movement turns packet steps into audible artifacts

Server targets update at 20 Hz. Client DSP followers are deliberately fast, so a route jump can become a short filter sweep, reverb change, or pan movement rather than a single scalar volume step. Previous waveform isolation already showed that large moving wet/dry and filter targets are capable of producing strong waveform derivatives.

The earlier right-channel “spark” caused by live reverb-spread changes is already guarded by keeping spread fixed at `0.92`; that protection should remain. Other reverb parameters are still live and should be tested with the real corner packet trace.

### P2 — possible: the continuous-program hard limiter pumps on correlated peaks

The program group ends in Godot's stereo-linked hard limiter. Four correlated copies can hit it differently as obstruction filters and pans change. Its stereo linking explains why this is more likely to sound like whole-image pumping than genuine one-ear clipping, but gain reduction is currently not measured by tests.

Official implementation reference: <https://github.com/godotengine/godot/blob/4.6/servers/audio/effects/audio_effect_hard_limiter.cpp>

### P3 — cleanup debt: prop collision metadata is contradictory

Layout prop descriptors still contain `collision_size` and `collision_offset`, while the baked prop builder uses the baked convex shape at the descriptor transform and ignores those fields. Existing tests largely verify that the descriptor fields exist rather than checking the resulting collision AABB against the visual asset.

This is not the measured audio defect, but dead collision metadata makes future acoustic geometry diagnosis unreliable. There should be one authoritative collision representation and an import-time visual/collision bounds check.

## What is currently working and must not regress

- Acoustic propagation is server-authoritative and produces per-listener emitter states.
- Static probes and spatial data are cached rather than rebuilt per audio frame.
- Runtime sources and effect chains use bounded pools instead of allocating voices/effects in hot paths.
- Loud sources receive greater physical reach; distance is not simply ignored.
- Direct transmission, alternate paths, enclosure, room diffusion, and material spectra are represented separately.
- The bunker has a shared diffuse-room contribution instead of relying only on nearest-probe loudness.
- Output state is interpolated on the client.
- Reverb spread remains fixed, protecting the previous right-channel impulse regression.
- Speaker cones remain driven from the actual program envelope.
- The current open-field, forest, tunnel, entrance, and ordinary bunker behavior should remain reference cases.

## Required next-run order

### 1. Add the regression before changing behavior

Promote the disposable corner walk into a deterministic test using the actual bunker scene and one persistent listener. Record at least:

- final dB;
- band gains;
- low/high-pass cutoffs;
- reverb send and room shape;
- obstruction coverage;
- direct and graph participation;
- route state;
- apparent source position/direction.

The test must traverse both generator-shadow edges at 5 cm/50 ms resolution. It should fail on the current 2.9 dB branch jump.

### 2. Make route combination continuous

Replace the transition-versus-steady-state participation split with one conserved-energy formulation whose output is continuous for:

- clear direct only;
- partially obstructed direct;
- fully obstructed transmitted direct;
- graph/diffracted alternatives;
- appearance and disappearance of either route.

Do not simply lengthen a lerp. Validate the scalar response first, then tune perceptual smoothing.

### 3. Make obstruction coverage continuous enough for small props

Evaluate a low-allocation improvement to the five-sample fan. Options to measure include temporally stable stratified samples, analytical coverage from cached collider bounds, or spatial reconstruction/hysteresis of the existing samples. Preserve wall-edge precision and avoid leaking outside probes across real boundaries.

### 4. Separate acoustic materials from physical surfaces

Add prop/category material metadata through the existing generic scene/import path. At minimum distinguish bunker shell, thin metal housing, machinery/generator, wood/nature, speaker cabinet, and open doorway. Re-bake probes after the material assignment is authoritative.

### 5. Separate PA and portable-radio playback profiles

Give the facility PA its own source profile. Verify distortion modes against Godot's implementation and measure the transfer curve; do not assume the exposed drive means the same thing for every mode. Decide deliberately whether each device contributes static, saturation, bandwidth limitation, and speaker resonance.

### 6. Capture the rendered four-speaker output

Feed a serialized corner packet trace into the actual four-voice renderer using a deterministic broadband/music-like test signal. Capture left and right output and inspect:

- sample discontinuities and short transient energy;
- peak, RMS, and crest factor;
- per-band level over position;
- stereo balance and correlation;
- limiter gain reduction;
- behavior with distortion, reverb, and filters bypassed one stage at a time.

Only then decide whether coherent-program normalization and room reverb should move to a shared program/listener bus.

### 7. Expand the tests to rendered perceptual invariants

Current tests cover many scalar rules but do not cover this interior prop edge or the final multi-voice waveform. Add assertions for:

- no abrupt scalar jump along dense continuous walks;
- no abrupt low-pass ratio or apparent-direction jump;
- monotonic average attenuation away from a stationary source, allowing bounded reflections;
- continuous wall/prop edge crossings;
- comparable room response above props and at ordinary listener height;
- no unilateral impulse from live DSP changes;
- bounded limiter activity for four synchronized speakers;
- distinct but continuous behavior for open field, forest, tunnel, bunker center, doorway, and prop-shadow corner.

Thresholds should come from captured clean baselines and perceptual checks, not arbitrary values chosen only to make the current scene pass.

## Do not do

- Do not add a special case for `SpeakerBackLeft`, the generator, or a world coordinate.
- Do not add or move a probe solely to hide this corner transition.
- Do not cap this generator's occlusion with a one-off float.
- Do not reduce all speaker volume or bass to mask the artifact.
- Do not add more final-output smoothing before fixing the energy discontinuity.
- Do not disable material geometry, alternate paths, room diffusion, or the hard limiter globally.
- Do not merge the PA voices or reverb buses without first capturing the current rendered failure.

## Existing test gap that allowed this

`tests/speaker_cluster_system_test.gd` samples one point in the generator shadow, but it only verifies that occlusion is partial and that enclosure/reverb are present. Its dense walks cover exterior bunker edges, not a traversal across the interior generator shadow. Adjacent continuity checks also do not fully cover low-pass ratio, apparent direction, route weights, or the final per-ear waveform.

The current single-rack waveform guard protects the reverb-spread regression, but it does not exercise four synchronized PA voices, portable-radio overdrive, the real corner packet sequence, or limiter gain reduction.

## Primary files for the next run

- `scripts/audio/server_acoustic_service.gd`
- `scripts/audio/radio_audio_renderer.gd`
- `scripts/audio/spatial_audio_effect_rack.gd`
- `scripts/world/speaker_cluster_demo_layout.gd`
- `scripts/server/server_speaker_cluster.gd`
- `scenes/server/speaker_cluster_demo.tscn`
- `resources/items/radios/portable_radio.tres`
- `resources/items/radios/facility_pa_playback.tres`
- `tests/speaker_cluster_system_test.gd`
- the existing spatial-audio waveform/effect-rack tests

## Exit criteria for the cleanup run

The cleanup is complete when the real generator-shadow walk and final four-speaker rendered capture are continuous, the PA no longer inherits accidental portable-radio coloration, prop materials are assigned generically, and all existing tunnel/forest/bunker/open-field behavior remains green and perceptually intact.

## Execution result — 2026-08-26

The cleanup was implemented as a generic system change, with no emitter, generator-coordinate, or
probe-position exception.

- The disposable generator walk became a deterministic two-way 5 cm regression using the real
  bunker scene and one persistent listener.
- The transition-only route branch was removed. Transmitted direct energy remains represented by
  the material path, while graph/diffracted participation grows continuously with measured aperture
  obstruction under one energy-domain mixer.
- All five-ray aperture coverage targets now pass through the existing movement/time reconstruction,
  including changes where the central blocked boolean does not flip. This adds no raycasts and no
  hot-path collection allocation.
- The generic baked-prop collision path now accepts acoustic material metadata independently of its
  physical/footstep surface. Machinery, thin metal, wood, and speaker cabinets receive reusable
  material resources; the generator is no longer acoustically a bunker wall.
- The facility array now owns a clean PA playback profile. Portable-radio overdrive and receiver
  static remain device-specific instead of colouring every facility speaker.

The scalar two-edge trace now measures:

| Quantity | Before | After |
| --- | ---: | ---: |
| Largest adjacent final-volume change | 2.902 dB | 0.465 dB |
| Largest low-pass cutoff ratio | 1.262x | 1.049x |
| Largest route-participation change | discontinuous branch | 0.113 |
| Largest apparent-source movement | 1.603 m | 0.283 m |

The original `pa_four_speaker_render_probe.gd` drove the actual four pooled 3D voices, their
production per-voice DSP racks, group normalization, panning, and the final hard limiter with a
deterministic five-band program over both generator-shadow edges. Its post-DSP measurement was
non-silent and recorded approximately:

- left/right derivative outlier scores: 1.24 / 1.39;
- largest 50 ms output-level movement: 0.55 dB;
- largest stereo-balance movement: 0.46 dB;
- largest 200 ms perceptual-band movement at a 50 ms stride: 1.72 dB;
- maximum correlation movement: 0.055;
- inferred limiter reduction: below 0.001 dB.

The full 10,961-point tunnel field caught one additional law error during the regression pass: when
the transmitted direct path had already become inaudible, direct-aperture coverage was still reducing
the sole guided arrival. The final mixer now gives a sole route full participation and uses the smooth
two-edge exposure union `1 - (1 - coverage)^2` only while direct and diffracted waves coexist. The
dense field finishes with zero hard cutoffs or reappearances, a 5.18 dB largest usefully audible
same-regime quarter-metre step, and a bounded 1.94 dB largest centerline outward rise.

The first deterministic rendered trace did not support merging the PA voices: it crossed the indoor
generator shadow and remained bounded. A later real-music field test did expose the missing case at
the bunker entrance: the same synchronized program could acquire several concurrent late tails,
briefly sound doubled, and lose direct focus at the exterior cabinet. The original render guard never
crossed the indoor/outdoor field boundary, so its green result was valid but incomplete.

## 2026-08-26 shared-program late-field correction

The direct speakers remain separate. Each still owns its physical position, panning, obstruction EQ,
filtering, distortion, and server-authored path level. Only the correlated listener-space late field
is shared. The renderer now applies these general rules:

1. Split each cabinet's authoritative power into equal-power direct and wet components from its
   geometry-authored reverb send.
2. Normalize the synchronized direct copies as one coherent program after that split, independently
   for the low, middle, and high acoustic bands. One scalar cannot preserve power once cabinet
   paths have different material filtering.
3. Sum wet contributions in the power domain and play one centered wet-only program through one
   energy-weighted room response.
4. Never insert the aggregate room effect over the direct speaker bus. Doing so would reduce a clear
   exterior cabinet because an unrelated indoor cabinet excites the room.
5. Disable the now-unused per-cabinet reverb processors for shared programs.
6. Treat the group's decoders as one clock domain: a genuine hard recovery seeks every direct copy
   and the late-field copy in the same frame, never one cabinet at a time.
7. Treat the reverb processor as a non-normalized return. Godot's wet network contains eight
   parallel feedback combs and a feedback predelay, so its steady-state output can carry far more
   power than the authored input split. Bound its undamped diffuse return once from the network
   coefficients:
   `1 / (sqrt(8) * f / sqrt(1 - f²) * 0.6 / sqrt(1 - p²))`, where
   `f = 0.7 + 0.28 * room_size` and `p` is predelay feedback. This correction is applied to every
   rack's wet coefficient. It does not inspect program peaks, allocate meters, alter stored tails,
   or change with a beat, so it cannot pump or create a bunker-only control regime.

`pa_four_speaker_render_probe.gd` now traverses the actual bunker entrance in both directions at five
centimetre spacing. In addition to waveform continuity, it asserts one active shared late field and
zero active per-cabinet reverb networks. Trace scheduling follows captured audio frames rather than
the unrelated headless render-loop clock, so FFT windows are repeatable. `radio_system_test.gd`
reconstructs direct plus late power and asserts that the split preserves the server-authoritative
input power to within 0.1%, and verifies that the analytical return correction is deterministic and
becomes stronger as room and predelay feedback increase.

The independent broadband render probe measures the resulting wet-only return at about -6.5 dB for
bunker parameters and -6.9 dB for a larger damped tunnel. Those values are deliberately below unity:
the coefficient formula bounds the feedback network while Godot's frequency damping removes further
energy. Unlike a compressor or meter follower, the correction cannot react differently to a snare,
bass note, MP3 master, or delayed tail.
