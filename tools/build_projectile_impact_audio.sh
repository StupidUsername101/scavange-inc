#!/usr/bin/env bash
set -euo pipefail

# Builds short mono projectile excitations from the licensed Rust & Blood source vault. Material
# character is intentionally left to PhysicalImpactResponse; these files stay short so automatic
# fire cannot reserve the spatial voice pool for long silent tails.

SOURCE_ROOT="assets/sounds/effects/Rust & Blood - SFX Library/OGG/Sound Effects"
OUTPUT_ROOT="assets/third_party/pizza_doggy/audio/rust_and_blood/projectile_impacts"
mkdir -p "$OUTPUT_ROOT"

render_impact() {
	local source_path="$1"
	local output_path="$2"
	local filter_chain="$3"
	ffmpeg -y -v error -i "$source_path" -ac 1 -ar 44100 \
		-af "$filter_chain" -c:a libvorbis -q:a 5 "$output_path"
}

for index in 1 2 3; do
	concrete_source="$SOURCE_ROOT/Impact & Break/Concrete/impact_concrete_ufx_${index}.ogg"
	render_impact "$concrete_source" "$OUTPUT_ROOT/projectile_impact_9mm_${index}.ogg" \
		"atrim=0:0.44,asetpts=PTS-STARTPTS,highpass=f=105,lowpass=f=12500,acompressor=threshold=-18dB:ratio=2.2:attack=2:release=45,loudnorm=I=-14:TP=-1.2:LRA=6,afade=t=out:st=0.3:d=0.14,alimiter=limit=0.78:attack=1:release=20:level=false,volume=-2dB"
	render_impact "$concrete_source" "$OUTPUT_ROOT/projectile_impact_556_${index}.ogg" \
		"atrim=0:0.34,asetpts=PTS-STARTPTS,highpass=f=240,lowpass=f=18000,acompressor=threshold=-20dB:ratio=2.8:attack=1:release=35,loudnorm=I=-12:TP=-1:LRA=5,afade=t=out:st=0.23:d=0.11,alimiter=limit=0.78:attack=1:release=20:level=false,volume=-2dB"
done

for index in 1 2; do
	wood_source="$SOURCE_ROOT/Impact & Break/Wood/impact_wood_ufx_${index}.ogg"
	render_impact "$wood_source" "$OUTPUT_ROOT/projectile_impact_nail_${index}.ogg" \
		"atrim=0:0.38,asetpts=PTS-STARTPTS,highpass=f=80,lowpass=f=8500,acompressor=threshold=-17dB:ratio=2:attack=3:release=55,loudnorm=I=-16:TP=-1.5:LRA=7,afade=t=out:st=0.25:d=0.13,alimiter=limit=0.78:attack=1:release=20:level=false,volume=-2dB"
done

for index in 2 3 4; do
	metal_source="$SOURCE_ROOT/Impact & Break/Metal/impact_metal_ufx_${index}.ogg"
	render_impact "$metal_source" "$OUTPUT_ROOT/projectile_impact_coil_$((index - 1)).ogg" \
		"atrim=0:0.58,asetpts=PTS-STARTPTS,highpass=f=55,lowpass=f=10500,equalizer=f=260:t=q:w=0.8:g=3,acompressor=threshold=-20dB:ratio=3:attack=2:release=70,loudnorm=I=-11:TP=-1:LRA=5,afade=t=out:st=0.4:d=0.18,alimiter=limit=0.78:attack=1:release=20:level=false,volume=-2dB"
done
