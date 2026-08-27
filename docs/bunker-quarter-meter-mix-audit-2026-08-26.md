# Bunker quarter-metre sound-mixture audit — 2026-08-26

## Result after correction

The route-composition defect is corrected. Direct/transmitted and graph/diffracted arrivals now
compose as route-specific early energy first. The listener room's diffuse/late field is applied once
to that composite result. When a listener field refreshes, the service independently constructs one
complete old estimate and one complete new estimate, then crossfades them; it never adds them as two
physical arrivals.

No bunker float, emitter exception, or coordinate-specific branch was introduced. The rule lives in
`ServerAcousticService` and applies to all continuous sources and environments.

## Measurement

The diagnostic instantiates the production server world, forces the garage array to its maximum
control setting and deterministic track 0, and measures one listener plane at ear height (1.7 m).
It places independent static listeners every 0.25 m across:

- the walkable interior, local `x = -8.5..8.5`, `z = -6.5..6.5`;
- a front exterior apron, local `x = -11..11`, `z = -10..-6.75`.

Each position records every server-authoritative cabinet packet, every packet after synchronized
shared-program normalization, the single shared late-field target, route weights, direct
occlusion, distance/path length, probe ownership, material modifiers, diffuse-field values,
three-band gains, filters, reverb parameters, and derived dry/late energy. A fresh listener identity
is used for every position and immediately forgotten, so row order and temporal smoothing cannot
shape the static field.

The post-fix run produced 4,903 samples. 130 listener points intersected solid collision and remain in the
raw data but are excluded from the walkable summaries. There were no inaudible holes. Runtime was
10.96 seconds.

Artifacts:

- `tests/generated/bunker_quarter_meter_mix_summary.json` — 46 KiB compact statistics and ranked
  neighbor edges;
- `tests/generated/bunker_quarter_meter_mix_report.json` — 94 MiB complete per-position and
  per-cabinet record;
- `tests/bunker_quarter_meter_mix_probe.gd` — reproducible diagnostic.

Absolute propagation levels below are tied to the deterministic test track and maximum PA control.
They are internal received-energy references, not measured dB SPL or post-limiter dBFS. Differences,
ratios, and spatial continuity are the useful quantities.

## Interior field after correction

| Quantity | p10 | median | p90 | full range |
| --- | ---: | ---: | ---: | ---: |
| Combined received energy | 3.59 dB | 3.96 dB | 4.99 dB | 2.69..7.79 dB |
| Renderer dry-to-late ratio | 8.10 dB | 8.24 dB | 9.26 dB | 7.42..15.56 dB |
| Late-field fraction | 10.60% | 13.04% | 13.40% | 2.70..15.34% |
| Shared reverb send | 0.478 | 0.538 | 0.546 | 0.232..0.594 |
| Mean modeled decay | 1.20 s | 1.55 s | 1.65 s | 0.81..1.75 s |
| Mean enclosure | 0.845 | 0.988 | 0.997 | 0.378..1.000 |

The combined interior field now has a 0.66 dB standard deviation. Its central 80% spans 1.40 dB,
while the central 80% late fraction spans only 2.8 percentage points. The interior 25 cm mixture
step is 0.027 dB at the median, 0.125 dB at p90, and 0.350 dB at p99.

## Reproduced defect and post-fix regression

There were 217 per-cabinet `direct`/`parallel` transitions on adjacent interior samples. On 151 of
them (69.6%), the obstructed `parallel` side was louder than the clear side. Within that erroneous
subset, the increase was:

- median: **+2.52 dB**;
- p90: **+2.68 dB**;
- maximum: **+2.87 dB**.

With the generalized composition rule, the same 217 transitions now produce:

- obstructed side louder on 28 transitions (12.9%), down from 69.6%;
- median obstructed-minus-clear change: **-0.161 dB**;
- p90: **+0.007 dB**;
- p99: **+0.104 dB**;
- maximum: **+0.126 dB**.

Restricting the set to the 198 transitions whose absolute diffuse-field level changes by at most
0.25 dB gives the same p90 and maximum within rounding. The remaining small positive differences
come from ordinary distance/aperture sampling across a 25 cm step, not an extra room-energy term.

In the pre-fix run, the underlying diffuse-field absolute level barely moved at these transitions:
its median change was 0.040 dB. However, the reported `diffuse_field_gain_db` rose by a median
3.45 dB and reverb send rose by 0.019. At 31.0% of all valid interior positions, at least one
cabinet received 2.5 dB or more of parallel-route summation gain.

Representative pre-fix locations:

- Generator shadow, `(-6.0, 1.7, 2.50) -> (-6.0, 1.7, 2.75)`: total mixture rises 1.69 dB. The
  back-left cabinet changes from clear/direct to 0.8 occlusion/parallel and its own result rises
  about 2.52 dB.
- Service-divider edge, `(2.25, 1.7, -0.25) -> (2.50, 1.7, -0.25)`: total mixture rises 1.33 dB.
  The right-interior cabinet becomes 0.6 occluded/parallel and its own result rises 2.31 dB.
- Service-divider rear edge, `(3.0, 1.7, 4.50) -> (3.0, 1.7, 4.75)`: the route transition changes
  total mixture by 1.41 dB and late-field energy by 1.89 dB.

Two pre-fix ranked extremes need to be interpreted separately:

- The 4.31 dB interior maximum sits immediately behind the right wall-mounted cabinet at
  `x = 8.5`, crossing from the front of its sound origin to its cabinet/wall side. It is real data
  but not evidence that the middle of the room is broken.
- The 5.34 dB exterior maximum crosses the bunker front-left concrete corner. Its late field is
  already zero; it is another hard direct/parallel geometry transition, not Hall accumulation.

## Why it happened

The former service built a direct result and applied the room environment—including diffuse
support—to it. When the direct path was blocked, it separately built a graph result and applied the
same room environment to that too. `_mix_parallel_route_results()` then summed the complete direct and
graph packets in the power domain.

Adding distinct transmitted and edge-diffracted arrivals is correct. Adding the same room diffuse
field once inside each arrival is not. The `parallel_route_gain_db` ceiling of almost exactly
3.01 dB is the signature of two near-equal powers being counted twice. The renderer subsequently
sees that larger scalar result and legitimately allocates part of it to the shared wet field, so the
mistake is heard as both a loudness change and a Hall-mixture change.

The correct generalized composition is:

1. decompose each candidate into route-unique direct/early energy and shared diffuse/late energy;
2. combine only the route-unique components according to obstruction/aperture participation;
3. attach one room diffuse field after route selection/mixing;
4. continue rendering one synchronized shared wet return for the speaker group.

That rule applies to every room, prop, wall, and source. It does not require another bunker special
case.

## Comparison with measured room data

The [dEchorate measured RIR dataset and paper](https://asmp-eurasipjournals.springeropen.com/articles/10.1186/s13636-021-00229-0)
is a useful structural comparison. It separates a room impulse response into direct propagation,
position-dependent early reflections, and a dense late reverberant field. Its controlled room is
6 × 6 × 2.4 m, with multiple sources and 30 microphones under different wall configurations. At
1 kHz, reported RT60 runs from 0.14 s in the absorbent configuration to 0.73 s in the most reflective
configuration. Source-facing DRR varies substantially with position/configuration, reaching about
-2 dB in one-reflective-surface cases and -7.5 dB in the most reflective cases. The underlying data
are published on [Zenodo](https://doi.org/10.5281/zenodo.4626590).

The numerical DRR values must not be copied into this game. Our bunker is much larger
(18 × 14 × 5.4 m), uses a four-source array, and `dry_to_late_db` is a renderer split rather than a
Schroeder/impulse-response DRR: part of our modeled diffuse reinforcement is already folded into
each authoritative route's scalar level. The valuable comparison is the decomposition rule. Real
direct/early response is strongly position-dependent; a settled late room field is much smoother
and must not be independently duplicated when a geometric path classification changes.

The bunker's 1.20–1.65 s central decay is longer than dEchorate's highly reflective smaller room,
but room volume and absorption differ too much to call that alone a bug. It may still explain any
remaining cave-like taste. Decay/send calibration should remain a separate perceptual pass now that
route energy is trustworthy.

## Implemented regression contract

The focused 25 cm field is now an acceptance test, not just a serializer. It fails unless:

- all 4,903 points receive audible states;
- at least 100 stable-field direct/parallel transitions exercise the real topology;
- fewer than 25% of those transitions make the blocked side even slightly louder;
- blocked-side gain is at most 0.25 dB at p90 and 0.5 dB at the maximum;
- the interior all-route 25 cm mixture step remains at or below 0.75 dB at p99.

The compact `A27` unit invariant additionally converts the composite early level and one reported
diffuse level back to linear power and asserts that their sum exactly equals the rendered power.
This catches the energy-accounting error without depending on bunker coordinates. The dense field
then proves that the same invariant survives production geometry, speaker grouping, and rendering.

This test choice follows the primary literature's common direct/early/late decomposition and its
emphasis on smooth spatial interpolation: Microsoft's
[precomputed wave simulation](https://www.microsoft.com/en-us/research/publication/precomputed-wave-simulation-real-time-sound-propagation-dynamic-sources-complex-scenes/)
stores source-dependent early response separately from one room late response;
[Planeverb](https://www.microsoft.com/en-us/research/uploads/prod/2020/08/Planeverb_CameraReady_wFonts.pdf)
tracks direct and reflected energy independently and interpolates parameters at audio rate; and
[adaptive sampling for sound propagation](https://www.microsoft.com/en-us/research/uploads/prod/2019/03/AdaptiveSamplingSoundProp.pdf)
evaluates reconstruction error over spatial fields because tiny listener motion must not create
loudness jumps across boundaries.
