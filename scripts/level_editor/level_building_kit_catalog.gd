class_name LevelBuildingKitCatalog
extends RefCounted

## Semantic view over purchased modular-structure filenames. The source packs
## encode compatible construction families in tokens such as HR, HS, and RG,
## but exposing those raw names made the editor feel like an asset dump.

const ROLE_WALL := &"wall"
const ROLE_DOORWAY := &"doorway"
const ROLE_WINDOW := &"window"
const ROLE_FLOOR := &"floor"
const ROLE_ROOF := &"roof"
const ROLE_STAIRS := &"stairs"
const ROLE_PILLAR := &"pillar"
const ROLE_BEAM := &"beam"
const ROLE_TRIM := &"trim"

const SOCKET_WALL_SEGMENT := &"wall_segment"
const SOCKET_PLANAR := &"planar"
const SOCKET_VERTICAL := &"vertical"
const SOCKET_LINEAR := &"linear"
const SOCKET_DETAIL := &"detail"

const ROLE_ORDER: Array[StringName] = [
	ROLE_WALL,
	ROLE_DOORWAY,
	ROLE_WINDOW,
	ROLE_FLOOR,
	ROLE_ROOF,
	ROLE_STAIRS,
	ROLE_PILLAR,
	ROLE_BEAM,
	ROLE_TRIM,
]

const FAMILY_TOKENS: Array[String] = [
	"rtx", "rgx", "hr", "hs", "rg", "rx", "mh", "bx", "hy",
	"hc", "hl", "ax", "ac", "ay",
]


static func describe(asset_path: String) -> Dictionary:
	if not is_building_asset(asset_path):
		return {}
	var raw_name := asset_path.get_file().get_basename().to_lower()
	var role := role_for_name(raw_name)
	var kit_id := kit_for_path(asset_path, raw_name)
	var socket := socket_for_role(role)
	var role_index := ROLE_ORDER.find(role)
	if role_index < 0:
		role_index = ROLE_ORDER.size()
	return {
		"building_kit": kit_id,
		"building_role": role,
		"building_socket": socket,
		"building_role_label": role_label(role),
		"building_group_path": "building-kit://%s/%02d_%s" % [
			kit_id,
			role_index,
			role,
		],
		"building_group_name": "BUILDING KIT %s  /  %s" % [
			kit_id,
			role_label(role).to_upper(),
		],
	}


static func is_building_asset(asset_path: String) -> bool:
	var lower := asset_path.to_lower()
	return (
		lower.contains("/modular structures/")
		or lower.contains("/modular retro fps kit/")
	)


static func kit_for_path(asset_path: String, raw_name := "") -> String:
	var name := raw_name.to_lower()
	if name.is_empty():
		name = asset_path.get_file().get_basename().to_lower()
	var tokens := _tokens(name)
	for family: String in FAMILY_TOKENS:
		if tokens.has(family):
			return family.to_upper()
	var lower_path := asset_path.to_lower()
	if lower_path.contains("/modular retro fps kit/"):
		return "RETRO"
	if lower_path.contains("/psx mega pack ii"):
		return "MP2"
	if lower_path.contains("/psx mega pack/"):
		return "MP1"
	return "GENERIC"


static func role_for_name(raw_name: String) -> StringName:
	var name := raw_name.to_lower()
	if name.begins_with("doorway") or name.begins_with("garage_door_frame"):
		return ROLE_DOORWAY
	if name.begins_with("window"):
		return ROLE_WINDOW
	if name.begins_with("wall") or name.contains("_wall_"):
		return ROLE_WALL
	if name.begins_with("floor") or name.contains("floor_ceiling"):
		return ROLE_FLOOR
	if name.begins_with("roof") or name.contains("_roof_"):
		return ROLE_ROOF
	if (
		name.begins_with("stair")
		or name.begins_with("step")
		or name.begins_with("ramp")
		or name.begins_with("ladder")
	):
		return ROLE_STAIRS
	if name.begins_with("pillar") or name.begins_with("column"):
		return ROLE_PILLAR
	if name.begins_with("beam") or name.contains("_beam_"):
		return ROLE_BEAM
	return ROLE_TRIM


static func socket_for_role(role: StringName) -> StringName:
	if role == ROLE_WALL or role == ROLE_DOORWAY or role == ROLE_WINDOW:
		return SOCKET_WALL_SEGMENT
	if role == ROLE_FLOOR or role == ROLE_ROOF:
		return SOCKET_PLANAR
	if role == ROLE_PILLAR:
		return SOCKET_VERTICAL
	if role == ROLE_BEAM or role == ROLE_STAIRS:
		return SOCKET_LINEAR
	return SOCKET_DETAIL


static func role_label(role: StringName) -> String:
	match role:
		ROLE_WALL: return "Walls"
		ROLE_DOORWAY: return "Doorways"
		ROLE_WINDOW: return "Windows"
		ROLE_FLOOR: return "Floors & Ceilings"
		ROLE_ROOF: return "Roofs"
		ROLE_STAIRS: return "Stairs & Access"
		ROLE_PILLAR: return "Pillars"
		ROLE_BEAM: return "Beams"
		_: return "Trim & Misc"


static func kit_ids(catalog: Array[Dictionary]) -> PackedStringArray:
	var seen: Dictionary[String, bool] = {}
	for entry: Dictionary in catalog:
		var kit_id := str(entry.get("building_kit", ""))
		if not kit_id.is_empty():
			seen[kit_id] = true
	var result := PackedStringArray(seen.keys())
	result.sort()
	# Complete shell kits deserve the first positions; the remaining families
	# are still useful as deliberately mixed façade/roof/support sets.
	for preferred: String in ["HS", "HR"]:
		var index := result.find(preferred)
		if index >= 0:
			result.remove_at(index)
			result.insert(0, preferred)
	return result


static func compatible_entries(
	catalog: Array[Dictionary],
	kit_id: String,
	socket: StringName
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in catalog:
		if (
			str(entry.get("building_kit", "")) == kit_id
			and entry.get("building_socket", &"") == socket
		):
			result.append(entry)
	return result


static func default_entry(
	catalog: Array[Dictionary],
	kit_id: String,
	role: StringName
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for entry: Dictionary in catalog:
		if (
			str(entry.get("building_kit", "")) == kit_id
			and entry.get("building_role", &"") == role
		):
			candidates.append(entry)
	if role == ROLE_FLOOR or role == ROLE_ROOF:
		var shell_candidates: Array[Dictionary] = []
		for candidate: Dictionary in candidates:
			if _is_shell_candidate(candidate, role):
				shell_candidates.append(candidate)
		candidates = shell_candidates
	if candidates.is_empty() and (role == ROLE_FLOOR or role == ROLE_ROOF):
		# Several façade families intentionally share HR slabs and roof pieces.
		for entry: Dictionary in catalog:
			if (
				str(entry.get("building_kit", "")) == "HR"
				and entry.get("building_role", &"")
				== (ROLE_FLOOR if role == ROLE_FLOOR else ROLE_ROOF)
				and _is_shell_candidate(entry, role)
			):
				candidates.append(entry)
	if candidates.is_empty() and role == ROLE_ROOF:
		return default_entry(catalog, kit_id, ROLE_FLOOR)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _default_rank(a, role) < _default_rank(b, role)
	)
	return candidates[0]


static func _is_shell_candidate(entry: Dictionary, role: StringName) -> bool:
	var name := str(entry.get("asset_path", "")).get_file().get_basename().to_lower()
	if role == ROLE_FLOOR:
		return not name.contains("slope") and not name.contains("hole")
	if role == ROLE_ROOF:
		# Corners, side caps, pitched middle pieces, and full warehouse crowns are
		# useful by hand, but cannot tile an arbitrary rectangular shell cleanly.
		return (
			not name.contains("warehouse")
			and not name.contains("corner")
			and not name.contains("side")
			and not name.contains("angle")
		)
	return true


static func _default_rank(entry: Dictionary, role: StringName) -> String:
	var name := str(entry.get("asset_path", "")).get_file().get_basename().to_lower()
	var penalty := 5
	if role == ROLE_WALL and name.match("wall_*_1"):
		penalty = 0
	elif role == ROLE_FLOOR and name.match("floor_ceiling_*_1"):
		penalty = 0
	elif role == ROLE_ROOF and name.contains("roof_small"):
		penalty = 0
	elif not name.contains("hole") and not name.contains("broken"):
		penalty = 2
	return "%02d_%s" % [penalty, name]


static func _tokens(value: String) -> PackedStringArray:
	return PackedStringArray(
		value.replace("-", "_").replace(" ", "_").split("_", false)
	)
