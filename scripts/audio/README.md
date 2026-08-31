# Server acoustic propagation

## Normative rule contract

`tests/acoustic_propagation_test.gd` owns the executable core of this list; focused bake, radio, and
industrial-environment tests own the hybrid-rendering additions. Preserve these rules when tuning
or extending audio:

1. Only server-authoritative semantic events cross the sanitized network boundary.
2. Source level changes physical hearing reach; approximately +6.02 dB doubles free-field reach.
3. Distance loss, air absorption, range fades, and speed-of-sound delay stay physical and continuous.
4. Structural obstruction applies the surface's nonlinear low/mid/high transmission response.
5. Small props partially occlude a fixed-width direct aperture; every sampled coverage change is
   reconstructed continuously, and a prop never erases the listener's diffuse room field.
6. Expensive surface response is sampled during graph rebuild and reused by runtime sources.
7. Late reverb belongs to the listener space; open air cannot inherit an enclosed source's room.
8. Rooms, tunnels, and outdoor scattering derive from the same sampled-geometry/material rule.
9. Tunnel guidance remains inside its baked volume, radiates through openings, then decays smoothly.
10. Impactful one-shots prepare one bounded pressure response per source event; explicit zero opts out.
11. Clients use fixed pooled voices/DSP and replay delayed copies only from dedicated pressure layers.
12. A blocked direct path and an open diffracted path add their energies instead of electing one
    winner. Clear, partial, and fully transmitted states use one conserved participation law with no
    transition-only route branch. Two finite-obstacle edges expose alternate energy continuously,
    while a sole audible route is never attenuated by an unavailable competitor; omitted continuous
    snapshots fade out.
13. Independent sources retain independent voices and add energy in the ordinary audio mix.
14. Collision-bearing nature contributes a short, dark response distinct from an unobstructed
    field, while one slender trunk scatters only part of the direct wave instead of becoming a wall.
15. Pistol and rifle reports use the identical server propagation and client pressure contract.
16. Sources and listeners in one baked air volume sum direct and diffuse energy; past critical
    distance the reflected field loses about 1 dB per distance doubling instead of another 6 dB.
17. Sustained upper-mid brilliance may bloom in a reflective enclosure, but dark material, quiet
    receiver noise, absorptive surfaces, and open air cannot trigger it; the mix stays power bounded.
18. Every source resolves a cached set of collision-visible air endpoints. A nearer probe behind a
    wall is rejected, shared-probe detours retain both endpoint segments, and level bakes never add
    probes named for one troublesome emitter.
19. Continuous multi-speaker overload protection leaves ordinary program dynamics untouched and
    limits only genuine digital overs; room rendering must retain most of the dry bass path. The
    real four-speaker render trace must remain continuous in both ears and perceptual bands.
20. Cabinets carrying one synchronized digital program share a phase-stable client timeline and a
    group energy normalization; independent sources retain physical delay and independent voices.
    Facility PA, portable radio, and future intercoms own distinct playback-colour profiles even
    though they share propagation and renderer infrastructure.
21. Non-audio systems consume one bounded listener-activity envelope derived only from sound after
    server propagation; simultaneous sources combine by energy and cannot exceed the unit range.
22. A live hall may morph its audible response, but its populated stereo comb/all-pass delay lengths
    remain fixed; changing Godot's right-only spread topology during playback is forbidden.
23. Indirect sound begins only at collision-visible listener air probes. A hidden nearest-probe
    fallback may preserve diagnostics, but it cannot render energy from the opposite side of a wall.
24. Successive cached route estimates crossfade as one wavefront in spatial level/frequency space;
    they never acquire the additive gain reserved for simultaneous physical paths or sources.
25. Every continuous source/listener pair has one allocation-stable server output dezipper. Gain,
    loss, spectrum, room controls, and apparent direction change by bounded spatial rates while the
    listener or source moves; stationary control changes use a bounded time rate. One-shots and
    teleport-sized changes remain immediate.
26. Baked route bends apply a frequency-dependent path-deviation response after route election:
    lows wrap more readily than mids and highs, a straight probe chain remains neutral, and repeated
    bends approach a finite diffuse/reverberant floor instead of deleting whole music bands. Route
    topology remains based on traveled spreading and authored material transmission, so bend colour
    cannot make a listener leave and re-enter a sealed room through a wall shortcut.
27. Direct, transmitted, and diffracted arrivals are route-specific early energy and may add in the
    power domain. The listener-space diffuse/late field is shared room energy: it is attached once,
    after early-route composition, and only then may successive cached fields crossfade. A change
    from `direct` to `parallel` must never count the same room field once per route candidate.
28. A directly visible source may receive at most two first-order image-source reflections from the
    baked static boundary/material index before the existing shared late field. Dry and taps remain
    equal-power normalized, delay feedback is forbidden, and a populated tap fades below audibility
    before its read head is retuned. This is source-generic: continuous sources cache results until
    either endpoint moves 40 cm, while a one-shot solves once for the event.
29. In a synchronized multi-cabinet program, path-direct energy determines the distribution between
    physical 3D cabinet voices. Diffuse-field recovery remains listener-space energy and cannot make
    a distant cabinet appear directionally equal to a nearby clear cabinet. Group normalization must
    preserve the original propagated pressure and shared late return while applying this split.
30. Once an undriven room return falls beneath the useful musical tail, one shared client rule
    progressively darkens and tapers only its residual comb/noise floor below audibility before
    Godot's audio-bus idle shutdown. The baked RT60 is carried through synchronized group mixing and
    prevents a fixed timer from retiring valid Hall; measured return level may begin cleanup earlier
    only after it is already quiet. One-shots, radios, and synchronized arrays use the same rule.
    "Undriven" means the stream player has actually stopped feeding the rack—not that one unreliable
    source snapshot was absent. Returning input resets every tail-filter state, while populated
    spread and pre-delay topology are never retuned under live samples. Active input, physical
    cabinet direction, and useful early decay therefore remain untouched across movement, packet
    gaps, and pause/resume.
31. Locally knowable owner cues start on the input frame, using the latest server-issued listener
    context when available and a dry free-field fallback before its first arrival. Prediction never
    grants gameplay authority. A bounded key reconciles the owner's confirmation to exactly one
    voice in either arrival order; remote listeners receive the ordinary unkeyed authoritative event.
    Host and joining-client gait both integrate input sampled on the current physics frame with the
    same movement acceleration solver and deterministic per-step range profile as authority. Actual
    horizontal speed continuously scales stride width/lift and the restrained impact gain, so walking
    and sprinting do not replay one invariant cue; an older
    snapshot may correct phase forward but never pull an already-rendered local footfall backward in
    time. A predicted footstep begins only when the detailed foot-contact rig plants on sampled world
    geometry. Authority validates that sequence/limb/rate, resolves the matching floor contact and
    material, and propagates it from foot height. The fixed voice/DSP pool is built
    during world setup, never on the first input event. If listen-server authority reaches the
    renderer before its local presentation phase in the same frame, the keyed confirmation waits in
    a bounded 50 ms reconciliation window. Same-frame prediction consumes it; absent prediction, the
    original authoritative packet falls through unchanged. Unkeyed remote/world sounds never enter
    this window.
32. Continuous-source transport carries one bounded, compressed, client-sanitized snapshot per
    listener on one replaceable, unreliable-ordered lane. Starts, stops, revisions, audible-set
    transitions, position, and DSP state all repeat at 20 Hz on that same lane. A parallel reliable
    lifecycle lane is forbidden: cross-channel overtaking can restore stale program state and
    re-excite a populated room return. Reliable movement snapshots are likewise forbidden because
    their backlog reproduces stale-room audio.
33. A synchronized program's direct cabinets and shared indirect field follow listener-motion gain
    with one response envelope. Room colour, decay, and filter coefficients may morph more slowly,
    but the wet level cannot retain a second spatial lag that makes Hall grow relative to dry sound
    after crossing a doorway. The wet/direct spatial ratio is applied after the persistent reverb
    network, so samples already circulating in a long room cannot retain the listener's previous
    indoor gain. This movement envelope is separate from a genuinely undriven RT60 tail, which
    freezes its last spatial ratio and remains free to decay after playback stops.

## Static propagation bake and rollback

The server persists the expensive deterministic portion of a world rebuild in
`user://acoustic_bakes/server_world_v1.sacb`. The artifact contains probe positions and IDs,
directed visibility edges, portal modifiers, guided/diffuse links, sampled environment and pressure
responses, and a sparse index of static structural box boundaries. It contains only Godot value
types; resources and executable objects are never deserialized from the file.

The artifact has a schema version and SHA-256 world signature. The signature covers the acoustic
behavior version, probe settings and transforms, portals, collision shapes and transforms, boundary
flags, acoustic materials, collision mask, and environment sample count. Missing, truncated,
corrupt, old-schema, or stale-signature data is ignored: the service follows the original ray-based
rebuild and writes a replacement through a temporary file while retaining the previous artifact
until replacement succeeds. Level edits therefore require no manual cache cleanup.

Static transmission keeps one ordinary center-line physics query to establish that a direct route
is structurally blocked. It then traverses an eight-metre sparse bucket grid baked from static box
colliders and analytically intersects the segment with only those candidate oriented boxes. Adjacent
or overlapping modular pieces within eight centimetres merge into one physical boundary; separated
walls accumulate low/mid/high transmission, dB loss, material delay, filter limits, resonance, and
room send. Scratch candidate and interval arrays are retained by the bake, so repeated queries do
not allocate new traversal containers. Moving bodies and unsupported shapes retain the previous
first-hit path. A clear line still bypasses both graph and boundary index.

The same baked oriented boxes retain surface absorption and scattering for an optional hybrid
renderer. A bounded first-order image-source solve considers broad wall-like faces, analytically
finds the specular point, checks both path legs against the sparse boundary index, and returns the
two strongest distinct delays. It introduces no runtime reflection ray fan. On the client, one
persistent `AudioEffectDelay` sits before the existing late reverb. Its two feedback-free taps are
equal-power normalized with the dry path and panned from the reflection point. Delay topology
changes fade below -52 dB before retuning, preserving the no-spark rule used by the populated reverb
network.

Rollback is independent:

- Set `ENABLE_ACOUSTIC_STATIC_BAKE_CACHE` to `false` in `scripts/server/server.gd` to rebuild the
  graph at every server-world start while retaining cumulative structural transmission.
- Set `ENABLE_ACOUSTIC_CUMULATIVE_TRANSMISSION` to `false` there to restore first-hit structural
  transmission while retaining the graph cache.
- Set `ENABLE_ACOUSTIC_HYBRID_EARLY_REFLECTIONS` to `false` there to remove the new early taps while
  leaving transmission, pressure events, propagation, and the existing late return unchanged.
- Disable all three switches to recover the pre-bake execution path without changing level data.

This follows the split used by Steam Audio pathing—bake a probe visibility graph and reuse it at
runtime—while retaining this project's server-authoritative packets and fallbacks. References:
[Steam Audio baking](https://valvesoftware.github.io/steam-audio/doc/capi/baking.html) and
[pathing simulation](https://valvesoftware.github.io/steam-audio/doc/capi/simulation.html).

`ServerAcousticService` builds a sparse graph from `AcousticProbe3D` markers and
`AcousticPortal3D` edges below the authoritative server world. Line-of-sight probe pairs are
connected during graph rebuild. Runtime endpoint handling normally uses one direct visibility line.
Only a central hit on a non-boundary prop pays four parallel, fixed-width aperture samples, so a
slender obstacle cannot become an infinite wall merely because it is close to one endpoint. One-shot
events pay this once, while continuous sources cache it briefly and invalidate at the
20 Hz snapshot cadence after 4 cm of listener or 3 cm of source movement. A clear physical line wins over the sparse graph,
so a nearest-probe boundary cannot extend a finite warehouse wall across the whole map. A blocked
line receives the accumulated baked transmission of every distinct static structural box on that
segment; its transmitted early energy is then summed with the longer open graph route. Only after
that route-specific sum does the graph attach the listener room's single diffuse/late field. Moving or
unsupported boundaries fall back to the first hit's `AcousticMaterial`. Obstacle-edge aperture
weights crossfade those paths as visibility opens.

Each listener owns a ping-pong pair of reusable `AcousticPropagationField` buffers. Routing is
recomputed after 24 cm or a graph change; the previous and current estimates crossfade over that
same 24 cm in decibel/frequency space. This removes shortest-route ownership pops without treating
two estimates of one wavefront as independent energy or adding source-specific raycasts. The solve
walks packed graph arrays and does not touch physics; all sources share both cached fields.
After route composition, continuous sources pass through one compact state record keyed by listener
and source IDs. This final spatial dezipper bounds any residual output change from direct aperture,
probe ownership, or cache refresh to a symmetric 10 dB/m, and morphs EQ
and room controls exponentially. It performs scalar arithmetic only—no rays, duplicate voices, or
per-snapshot container allocation—and is discarded when either endpoint disappears.
The field retains eight ordinary nearby air samples plus a separate bounded reserve of six
candidates from nearby guided regions. Guided candidates are discovered independently of the global nearest-probe
list, so adding props, rooms, or a second tunnel cannot evict the still-visible mouth carrying the
sound. A few representatives are checked per guide because its nearest interior sample may be
hidden while its opening is clear. Distant guides are rejected before visibility sampling. At a
grazing opening, a small deterministic aperture turns visible area into attachment pressure; this
work occurs only on the 24 cm field refresh, never per source or audio snapshot. Each refresh moves
the reusable attachment strengths toward their new spatial targets across 75 cm; teleport-sized
movement resolves immediately. Weak route visibility affects the local room response through a
fourth-power coverage kernel, so it cannot transplant an interior environment outside a wall.
Room blending normalizes among probes with active spatial support, so a collision-visible probe
whose authored response has faded to zero cannot dilute valid local air. The normalized response is
then multiplied by the strongest continuous local coverage: overlapping room cells remain full, but
the outermost cell still fades into open air instead of holding full strength until a hard boundary.
This prevents support holes above props and field edges near openings without emitter-specific tuning.
If none of the nearby probes is collision-visible, the nearest probe remains a diagnostic anchor
only and the audible result falls back to the material-filtered direct path. Rendering that hidden
anchor used to turn tunnel interiors into loud outdoor stripes wherever nearest-probe ownership
changed.
The graph route remains cached between those solves, while the listener's live local segment,
distance attenuation, apparent direction, and propagation delay update every snapshot. Ordinary
traveled-path spreading owns attenuation, while authored hearing reach remains a radial source bound;
a bent path is not charged once for real travel and again merely for turning. The final radial region uses a
bounded-slope dB tail with quadratic ease-in/out. This avoids both a hard cutoff, the old half-range
linear knee, and a cubic midpoint that concentrates attenuation into one steep patch. Server calculations originate at
`ServerPlayer.get_audio_listener_position()`, which mirrors a body-centred client `AudioListener3D`
at head height. It intentionally excludes the camera/grab point's forward offset so yaw cannot move
the listener across an acoustic boundary.

Wavefront route election minimizes cumulative rendered signal loss: effective traveled spreading plus
the nonlinear three-band/material amplitude. Arrival delay is retained separately at 343 m/s. A quiet
wall shortcut can therefore arrive earlier without stealing the apparent direction from a stronger open
corridor, and reciprocal indoor/outdoor portals do not need source-specific edge directions.

After that material/distance route is elected, consecutive baked edge directions produce a smooth
finite-edge deviation response. Turns below eight degrees are treated as probe-placement jitter.
Larger turns accumulate a low/mid/high burden and approach bounded 5/15/32 dB floors, retaining the
late/reverberant energy that real enclosed paths do not lose to infinite multiplication. Routing and
render gains live in separate packed field arrays: the hot solve allocates nothing per edge, straight
paths stay bit-neutral, and a many-corner entrance path can no longer arrive in the forest with clean
outdoor EQ. This follows Steam Audio's separation between baked shortest-path lookup and the
frequency-dependent attenuation evaluated from path deviation.

Each sound origin owns an `AcousticSourceAttachment`. On creation—or after a continuous source moves
24 cm—the server examines up to twelve nearby baked probes and retains the first three reachable air
samples. Small non-boundary props are ignored exactly as they are for listener attachment; structural
surfaces reject the candidate. The listener then chooses the lowest-cost reachable source endpoint
using only cached graph arrays. Stationary speakers pay this visibility work once, carried radios pay
it only after meaningful movement, and a one-shot prepares one attachment for every listener. When
both endpoints share an air probe, the route retains source-to-probe plus probe-to-listener distance;
it never collapses a doorway detour into a blocked centre ray.

Every acoustic graph rebuild also samples 50 deterministic directions around each opted-in probe:
the six exact axes plus a 44-point Fibonacci sphere that can resolve smaller openings. A missed
surface is escaped sound energy; a hit contributes its distance, absorption and scattering. The
shared `AcousticEnvironmentModel` turns those samples into enclosure, mean free path and an
Eyring-style diffuse decay. The same response naturally approaches zero outdoors, becomes a short
room tail in small enclosed spaces, and grows into a narrower, delayed hall-like tail when the
sample shape is long and enclosed. This is environment analysis, not an extra per-source ray fan.
The rebuild also bakes a detonation-pressure signature into each stable probe: confinement, compact
room bass reinforcement, first-reflection onset, source-tail decay, open-air escape, and the dominant
escape direction. Runtime impulses never resample those surfaces.
The nature layout derives one sparse probe per sufficiently occupied 14 m forest cell directly from
its collision-bearing tree distribution. These probes therefore move with future layout changes and
sample the actual wood/stone collision materials instead of a separate hand-authored acoustic map.
They produce a short absorptive outdoor scatter tail, not an indoor hall; the open central field has
no nature response. Their environment rays are still rebuild-only.
Endpoint attachment ignores non-boundary trunks and narrow props while structural surfaces remain
authoritative. Foliage can therefore scatter and partially cover a direct wave without hiding a
concrete wall farther along the same source-to-listener ray. Probes may additionally bake an endpoint
exclusion volume, a continuous attachment-influence box, and physics-style auto-connect layer/mask.
The influence box has a reusable outward fade: dense doorway/corridor samples overlap smoothly, but
a diagonal zero-width corner cannot become an endpoint shortcut into another cell. A zero-sized box
retains the original unbounded open-world behavior. Explicit portals bypass the mask; this separates
interior, exterior, and world topology without preventing deliberate radiation paths.
The maze derives exterior perimeter samples from its dimensions. Reciprocal material-filtered boundary
edges turn adjacent wall cells into reusable exterior radiators, and one identity edge carries
the open doorway. Exterior probes reject endpoints inside the shell and cannot auto-connect back into
the interior, but still connect to ordinary world probes. Runtime then blends those stable graph waves
with direct transmission, avoiding angular one-wall/two-wall hotspots without adding source ray fans.
During rebuild, enclosed probes with a structural line of sight are grouped into shared air volumes.
This bake deliberately ignores small non-boundary props but stops at real walls, so a crate cannot
split one garage while unrelated enclosed rooms cannot borrow each other's pressure. The same radial
surface samples estimate each volume with the star-volume integral; escaping doorway rays use the
median wall distance instead of the sampling horizon.

Within one shared air volume, runtime combines direct and diffuse components in the energy domain.
The baked volume and RT60 derive the omnidirectional critical distance (`0.057 * sqrt(V / RT60)`),
where those components are equal. Direct energy still loses about 6 dB per distance doubling. Beyond
critical distance the diffuse component loses 1 dB per doubling, so a steady indoor source approaches
a gently declining room field rather than following inverse distance all the way across the room.
Diffuse decay uses the baked propagation length, never a Euclidean shortcut through a partition. In
a plain room the two distances coincide; in a maze, bent tunnel, or doorway chain, late energy
follows the connected air route just like the early field. Transitive room ownership therefore does
not flatten a whole labyrinth into one pressure value: excess route distance applies a smooth
fourth-order support falloff, scaled by critical distance with a twelve-metre lower bound. Small room
dividers retain their shared late field while long chained detours decay instead of teleporting it.
Probe influence fades that field continuously at doors. Authored response radii derive from probe
spacing so connected room cells overlap instead of leaving silent reverb holes above or between
props. Tunnel guidance suppresses the diffuse field where waveguide
recovery already owns propagation, and open air receives none. All volume grouping and surface math
remain rebuild-only; a runtime source performs only scalar energy arithmetic.
Strongly elongated, enclosed responses also derive a bounded waveguide coefficient. The server uses
it to recover part of the ordinary inverse-distance spreading loss, subtracts material-dependent wall
loss per metre, and extends the source's nominal open-air hearing range. This keeps a tunnel's dry
signal alive as well as its reverberant tail; ordinary rooms and open air retain their normal distance
curve.

Tunnel-mouth routing probes may author `guided_spill_strength`. This does not create outdoor reverb:
the remaining guided gain radiates through a baked aperture lobe whose horizontal and vertical
half-widths grow continuously with forward distance. Axial energy decays reciprocally, while a
fourth-order off-axis shoulder supplies a quiet diffraction tail instead of a cone edge. The lobe
starts at the physical opening even when its collision-visible graph probe sits farther outside.
Hearing eligibility therefore follows the opening long enough for the wave to radiate out, then the
dry signal returns continuously to normal outdoor spreading and range fade.
Enclosed guided fields still author a center offset, half extents and a soft boundary to keep
preserved energy inside the actual air passage. Open mouth lobes do not use finite influence boxes:
their aperture, forward axis, divergence and falloff are derived from the same modular tunnel
dimensions. This prevents side-wall tunnel gain without introducing a hidden cutoff or per-source
raycasts.
Modular tunnels derive the same interior chain, local mouth spill, and ordinary exterior perimeter
chains from their structure dimensions. The exterior chains are not waveguides: they merely provide
collision-visible air routes around both mouths, so side-wall listeners never need a hidden interior
fallback. Each mouth also derives samples just beyond its two real shell corners; these let the
exterior graph converge on the physical diagonal diffraction path instead of following a long
axis-aligned detour until direct mouth visibility suddenly wins. No tunnel owns a world-scale
hand-authored spill box. Structural visibility remains authoritative for the graph links around the
opening, so a lobe cannot make tunnel energy pass through the shell itself.

Emit semantic events only from authoritative game code:

```gdscript
Server.emit_spatial_sound(
	&"service_pistol_fire",
	muzzle_position,
	80.0,
	0.0,
	null,
	0.9,
	0.9 # Optional override. Omit for automatic response; pass zero to opt out.
)
```

An authored maximum distance is the source's reach at 0 dB. Before any listener culling or path
solve, the server scales that reach by `10^(source_level_db / 20)`, capped at 10 km. Consequently,
about +6.02 dB doubles free-field reach and -6.02 dB halves it. The same scaled distance defines
radial eligibility and the eased range tail for direct and probe routes. A routed arrival pays its
complete traveled length exactly once through geometric spreading, air absorption, material loss,
and delay; turns do not spend the radial budget a second time. Guided tunnel extension and
pressure-arrival bounds remain conservative. A radio's playback gain calibrates the
recording to its authored device output; its runtime amplifier control uses the identical range
rule. Lowering that control therefore reduces how far snapshots are distributed instead of merely
making a full-range voice quieter.

Every authoritative one-shot gets a conservative pressure/early-reflection response by default. Its
automatic strength derives from the event's authored reach, level and priority, so item handling and
footsteps stay subtle while louder, farther-reaching events carry more energy. Passing `0` explicitly
opts a sound out; passing `0..1` authors an override for guns, explosions or unusually soft sources.
Pressure-enabled events prepare their source response once, before the per-listener server loop. The
primary collision-visible source probe blends only with directly connected, transmission-weighted neighbors, smoothing a muzzle
crossing an open doorway without leaking a room response through unrelated walls. Events preserve the
ordinary directional report and add one dedicated low-frequency body arrival. The graph may add at most two quieter escape arrivals when the source probe has genuinely
independent routes to the listener. Their positions, material filtering, level, and speed-of-sound
delays come from the already-baked edges and cached listener wavefield. The selected primary edge is
not replayed, routes that loop through the source are rejected, and near-simultaneous alternatives are
discarded, preventing comb-filtered copies of the gunshot. Packet version 4 validates and caps both
the nested pressure arrivals and first-order reflection taps before they reach client audio. Early
reflection taps are independent of pressure strength, so device sounds, footsteps, guns, radios, and
future semantic sources use one room-rendering contract. A level with no acoustic probes still gets
one dry open-air pressure body; it simply cannot produce geometry-derived escape arrivals or room
reinforcement.

Clients prefer separately registered short mono layers for strong impulses. Without one, the renderer
uses a quieter, filtered, delayed copy of the exact same source take and pitch for the primary response.
That generic reflection fades continuously to zero with source enclosure, so open air does not acquire
an artificial doubled copy, and it is not multiplied across alternate escape paths. Both forms reuse the
fixed spatial voice/DSP pool and converge into a shared soft-limiting output bus. A voice remains reserved
for its baked reverb decay after the dry stream ends, preventing a subsequent sound from abruptly
recoloring the tail. The shared `GameAudioLibrary` owns both weapon registrations, so neither report
depends on an easy-to-miss world-scene registration node. The service pistol uses four dry
48 kHz mono reports plus four dedicated bass transients derived from the licensed raw recording bundle.
The automatic rifle follows the same contract with four trimmed, mono Rust & Blood reports and four
filtered pressure transients. Its pressure assets are calibrated +5.5 dB at registration because the
source bundle is mastered about that much below the pistol pressure recordings; this changes only
asset balance, never server geometry or room values. Automatic cadence therefore does not stack baked room tails. Both weapons
get their room character from simulation. Continuous sources such as radios receive cached early
reflections plus continuously updated path/reverb snapshots. They do not enter the impulse-pressure
path and pay no pressure-system cost.

Clients register local streams with a `SpatialAudioPlayer3D` node or
`Client.register_spatial_sound()`. One-shot events send sound IDs, never resource paths.

### Owner prediction and network latency

Locally knowable player cues use an owner-predicted presentation layer; the acoustic simulation does
not become client-authoritative. At 5 Hz the server sends each peer one replaceable near-body
acoustic context on dedicated unreliable-ordered lane 7. It contains the current listener room,
filters, first reflections, and a normalized pressure response assembled from the same cached probe
field and static bake as ordinary events. It is neither a world-geometry copy nor permission to emit
arbitrary sounds. The server continues to keep the actual audible-source interest set: one-shots are
sent only to listeners for which `calculate_listener_result()` is audible, while radio/PA snapshots
contain only currently audible continuous sources.

Input/visual events that the owner can know—Fieldlink motion/UI cues, accepted-ground jump attempts,
the shared gait phase, and each deterministic automatic-weapon shot—start immediately through the
ordinary prewarmed voice/DSP pool. They use the latest cached context when one exists and otherwise
start with a dry free-field packet rather than waiting for networking. Their small integer prediction
key travels with the gameplay intent. Ammo, cooldowns, movement, equipment, source position,
audibility, graph routing, and all remote recipients remain server-validated. The authoritative
result returns the key only to its originating peer; that renderer consumes it as confirmation
instead of replaying the sample. Other peers never receive the key and render the normal
authoritative packet once. The reconciler is order-independent so host-speed loopback and a
non-host's extrapolated gait behave the same. In the authority-first host ordering, the keyed packet
waits for at most 50 ms for the local presentation phase instead of committing the acoustically
delayed copy first; if no prediction arrives it falls through normally. Rejected actions discard
any not-yet-played predicted arrivals.

Remote players, impacts, world interactions, radio/PA program selection, and every cause the local
client cannot know remain purely authoritative. Network round-trip delay is removed from predictable
owner feedback; real speed-of-sound delay for propagated sources is intentionally not removed. If a
prediction cannot be built because its semantic sound is not registered, the client sends key zero
and automatically falls back to the previous server-only path. `LocalAudioPrediction.ENABLED` is the
single rollback switch; disabling it changes no server propagation rule or packet for ordinary
listeners. Multiplayer builds must share the same prediction-key protocol version, like every other
RPC contract in the project.

Continuous radios use a separate state stream because they must preserve track position across
movement and late joins. `ServerRadio` chooses tracks from `assets/sounds/music`, and the server
sends each listener a current playback offset plus the same acoustic path result used above.
`RadioStatePacket` only permits audio paths beneath that music folder. Clients render at most
eight audible radios through persistent distortion/EQ/filter buses. Repeated dictionary keys are
serialized once and DEFLATE-compressed by `RadioStateSnapshotCodec`; a twelve-cabinet regression
must remain below 4 KiB and at least four times smaller than the verbose Variant form. A reliable
keyframe guarantees program changes, while 20 Hz listener acoustics stay on their independent
unreliable-ordered lane so packet loss drops old positions instead of queueing them. Devices that explicitly author
receiver noise also mix the same small, pre-generated hiss/crackle loop before those effects, so
static follows the device's position and server-derived propagation without runtime noise synthesis
or per-voice sample buffers. Clean PA profiles do not start a static player at all; a low gain is not
treated as an off-switch.
The same fixed voice rack ends in a 512-sample spectrum analyzer. The renderer samples two broad
frequency bands once per active voice, caches a smoothed envelope, and lets the matching item visual
move only its speaker cone by a few percent—no beat replication or visual-side audio analysis.
Add another `.mp3`, `.ogg`, or `.wav` beneath the folder to include it in the next server session.
Run `python3 tools/generate_music_loudness_catalog.py --project .` after adding or replacing music.
It measures every track once with FFmpeg EBU R128 plus true peak, then bakes a deterministic,
peak-safe gain catalog and a compact 20 Hz source-level motion envelope. Radio and PA output therefore
excite the same physical room model at one reference program loudness instead of making a heavily
mastered song appear to have a stronger hall. Speaker-cone motion follows the baked program timeline,
not listener attenuation or room filtering, so quiet archival masters remain animated and every
audible cabinet in a synchronized PA can share the same pulse. Each envelope sample occupies one byte.
The balancing stage stays separate from a 6.5 dB device-reference calibration, so modern tracks retain
roughly their original speaker loudness at default and 100 percent instead of making normalization feel
like a quieter amplifier. Enabled receiver static remains calibrated to the device rather than either
program correction.

Continuous volume, EQ, and filter targets interpolate locally so crossing an acoustic boundary does
not switch the DSP rack in one network tick. Wall-edge visibility is cached as a finite aperture and
traversed over listener distance/time, while the renderer additionally limits volume slew in dB per
second. This second bound also covers packet loss, coarse snapshots, and movement fast enough to cross
more than one spatial sample. Missing continuous sources retire through a short fade and reclaim their
fixed pool slot only once inaudible. The reverb rack uses a power-normalized dry/wet split because the
server result already contains direct-plus-diffuse room energy; adding a full-volume wet path again
would double-count the bake and make dense mixes song-dependent.

Continuous music voices reuse their existing FFT analyzer before the reverb stage. One additional
upper-mid query compares 1.8–9 kHz brilliance against body energy, then a slow envelope gates a small
wet-send, wall-reflectivity, and early-feedback lift by the listener's baked enclosure. Sustained
strings, brass, and similarly bright tones can therefore make concrete or metal rooms open up, while
percussive ticks, receiver static, dark masters, forest absorption, and open air do not pump the tail.
The bloom still passes through the same equal-power dry/wet law. All continuous speaker buses then sum
into one shared predictive hard limiter with zero pre-gain. It catches only genuine overs near 0 dB,
allowing multi-speaker bass and transients to add without the old -3 dB soft-limiter threshold pulling
down the entire program.

A coordinated PA array additionally marks every cabinet with one shared-program identifier. The
client keeps those copies on the same sample timeline, preventing path-delay differences from turning
the music into a position-dependent comb filter. A single group gain converts their coherent pressure
sum back to the server's power sum, so two equal boxes still add 3.01 dB rather than either cancelling
or jumping by 6.02 dB. Because the server's steady-room level includes diffuse recovery, that recovery
is excluded only while distributing the phase-locked dry pressure between cabinet positions. The
same group gain restores the untouched propagated pressure, and the shared listener-space late return
retains the room energy. A far cabinet therefore cannot steal localization merely because both boxes
excite the same room. This opt-in contract does not alter propagation delay for unrelated radios,
weapons, footsteps, or independently playing speakers.

Fixed PA layouts may also author a bounded per-cabinet `installation_gain_db`. This represents a
real channel trim or a more efficient outdoor cabinet, not listener-space reverb: it changes emitted
level and physical hearing reach through the same decibel law while leaving geometry, obstruction,
room response, and shared-program normalization untouched. Its linear reach multiplier is cached when
the cabinet layout loads, so the server does not evaluate an exponential per listener tick. The bunker
suite verifies the exterior channels against both interior channels at matched player-height positions.

`ListenerAcousticActivity` is the intentionally narrow bridge from this system into diegetic
presentation. Short sounds excite it from their received playback level; continuous programs reuse
the spectrum analyzers already present in the fixed radio pool, so a quiet passage does not register
as a loud speaker merely because its volume control is high. The client energy-sums both paths and
exposes one normalized scalar. The Fieldlink display uses that scalar to raise only the probability
and coverage of its existing pixel glitch—never to bypass acoustic geometry or run another FFT.

Foreground movement attacks can author a `foreground_transient_strength`. When such a one-shot
actually reaches a client, the continuous renderer briefly creates up to 5 dB of headroom in only
the radios loud enough to mask it. The short hold preserves the footstep's hard contact while the
exponential release leaves the music dominant; quiet or distant radios are untouched. This uses one
scalar envelope over the existing fixed pools—no extra player, DSP bus, stream, or sample buffer.

Characters without equipped eyes receive an `EyelessAcousticPerception` layer above the black ocular
view. One-shots enter it only when the fixed spatial renderer actually admits and starts their final
listener-specific packet; continuous speakers provide their already-filtered spectrum level at 15 Hz.
Both use `apparent_position`, never the omniscient source position. Pressing Q always requests a
server-validated `mouth_click`, making it an ordinary audible expression for sighted and eyeless
players alike. A 12-click/second token bucket with short burst headroom preserves musical input while
bounding malicious RPC/acoustic spam; it is intentionally not an ability-style cooldown. While
eyeless, that same click permits one local 88-ray, first-hit-only near-field echo
sweep. The sweep follows the same bounded rhythmic input, never runs continuously, stops at the first
wall, and supplements ordinary sound direction with short
organic contour fragments. Recorded variations are discovered from
`res://assets/sounds/player/mouth_clicks`; the existing terminal click is development fallback only.

For a door, vent or transmissive wall, connect the probes on either side with an
`AcousticPortal3D`. Its `AcousticMaterial` controls low/mid/high transmission, volume loss,
filter limits, resonance and reverb send. `additional_modifier` can add a named effect such as a
duct, radio, helmet or powered barrier. After changing portal topology at runtime, call
`Server.rebuild_server_acoustics()`.

Static and animatable obstacles affect even short local paths between probes. An authored collider can
provide `get_acoustic_material()` or an `acoustic_material` metadata Resource; otherwise it receives a
safe generic-solid transmission curve. The dev world includes an **Acoustic Test House** beside the
warehouse at `(12, 0, -5)`. Carry the warehouse radio to its marked **RADIO** pad and stand on
**LISTEN** to compare the small divider, then move through the open doorway or around an exterior wall.

Place at least one `AcousticProbe3D` inside every acoustically important room, hall or tunnel. Its
`environment_influence_radius` controls how far the sampled response reaches; zero derives a radius
from the probe connection distance. Disable `sample_reflections` for routing-only outdoor probes,
or use `reverb_scale` as a final art-direction adjustment. Prefer setting realistic band absorption
and scattering on the room surfaces before changing the scale.

The industrial test building uses a generated eight-probe room grid per floor plus probes at the real
ramp endpoints. This keeps nearest-probe segments on the correct storey and makes the stair route's
length follow the physical ramps. Reflection rays for this denser grid are still rebuild-only. Player
audio listeners sit at the body-centred head position; the forward aim/grab origin is deliberately not
used, so looking around changes panning direction without moving the authoritative ears.

The client applies a per-voice six-band EQ, persistent low/high-pass filters and a persistent
`AudioEffectReverb`. Packet version 3 carries the derived room size, damping, spread, pre-delay and
feedback alongside the wet send and the optional bounded pressure-arrival payload. Continuous voices
ignore that impulse-only payload and converge the audible room response locally, so walking through a
doorway morphs the tail rather than switching an indoor/outdoor preset on a network tick. The renderer
deliberately keeps Godot's `spread` topology fixed at runtime: Godot realizes stereo spread by changing
only the right reverb network's comb/all-pass delay lengths, and resizing those populated rings emits a
right-channel impulse. Geometry still controls wet energy, decay colour, pre-delay, filtering, and the
apparent source; a stable decorrelation width removes the click without selecting a special bunker case.
One-shot reverb processing is bypassed when the wet signal is silent. Godot otherwise keeps an
unused bus alive for two seconds below its default -60 dB channel threshold and then deactivates it
in one block. During that grace interval its Freeverb-derived comb return can become sparse and
noise-like. Every rack therefore watches its post-effect peak only after the source stops driving it;
the useful tail stays untouched down to that same -60 dB engine threshold (or its baked RT60 upper
bound), then one allocation-free 24 dB/s bus envelope moves only the residue to -80 dB before the
engine cutoff. A new source resets the dormant envelope before playback, so it never inherits
attenuation from a previous voice.

Continuous client voices use frame-rate-independent exponential position, volume, EQ, and filter
convergence. The server combines simultaneous transmitted and diffracted routes in the energy domain:
scalar powers add, EQ amplitudes combine by squared energy, and room/filter parameters use the same
energy weights. This removes the old latency/loss winner threshold that could jump between a quiet
early wall path and a stronger doorway path. Full and partial material coverage share one volume/EQ
representation, so separately interpolated DSP controls cannot reveal a hidden branch at exactly
100 percent occlusion. Physical speed-of-sound delay remains intentional only for a newly arriving
wave.
