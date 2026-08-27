class_name PhysicalSurface
extends RefCounted

## One semantic material tag drives movement and impact audio. Keep the legacy footstep tag
## readable while authored scenes migrate; hot-path cue selection returns interned names only.

const META := &"physical_surface"
const LEGACY_FOOTSTEP_META := &"footstep_surface"

const CONCRETE := &"concrete"
const METAL := &"metal"
const WOOD := &"wood"
const STONE := &"stone"
const SOIL := &"soil"


static func normalize(value: Variant, fallback := CONCRETE) -> StringName:
	var surface: StringName
	if value is StringName:
		# Authored metadata uses interned names, so the per-physics-tick floor lookup takes
		# this branch without allocating a temporary String.
		surface = value
	elif value is String:
		surface = StringName((value as String).to_lower())
	else:
		return fallback
	match surface:
		CONCRETE, METAL, WOOD, STONE, SOIL:
			return surface
	return fallback


static func from_collider(collider: Object, fallback := CONCRETE) -> StringName:
	if collider == null:
		return fallback
	if collider.has_meta(META):
		return normalize(collider.get_meta(META), fallback)
	return normalize(collider.get_meta(LEGACY_FOOTSTEP_META, fallback), fallback)


static func apply_to(collider: Object, surface_value: Variant) -> StringName:
	var surface := normalize(surface_value)
	collider.set_meta(META, surface)
	# Compatibility for older movement code and third-party scenes authored before the
	# unified surface contract.
	collider.set_meta(LEGACY_FOOTSTEP_META, surface)
	return surface


static func footstep_sound_id(surface_value: Variant) -> StringName:
	match normalize(surface_value):
		METAL:
			return &"footstep_metal"
		WOOD:
			return &"footstep_wood"
		STONE:
			return &"footstep_stone"
		SOIL:
			return &"footstep_soil"
	return &"footstep_concrete"


static func jump_sound_id(surface_value: Variant) -> StringName:
	match normalize(surface_value):
		METAL:
			return &"jump_metal"
		WOOD:
			return &"jump_wood"
		STONE:
			return &"jump_stone"
		SOIL:
			return &"jump_soil"
	return &"jump_concrete"


static func landing_sound_id(surface_value: Variant) -> StringName:
	match normalize(surface_value):
		METAL:
			return &"landing_metal"
		WOOD:
			return &"landing_wood"
		STONE:
			return &"landing_stone"
		SOIL:
			return &"landing_soil"
	return &"landing_concrete"

