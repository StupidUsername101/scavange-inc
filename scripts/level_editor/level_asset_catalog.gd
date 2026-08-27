class_name LevelAssetCatalog
extends RefCounted

## Runtime catalog for the level editor. The purchased packs include the same
## models as GLB, FBX, and OBJ; GLB is the project's preferred imported format,
## so indexing it alone prevents thousands of duplicate entries.

const ASSET_ROOT := "res://assets"
const CATEGORY_WALLS := "Architecture / Walls & Openings"
const CATEGORY_FLOORS := "Architecture / Floors & Roofs"
const CATEGORY_ACCESS := "Architecture / Stairs & Platforms"
const CATEGORY_STRUCTURE := "Architecture / Structural Pieces"
const CATEGORY_TUNNELS := "Architecture / Tunnels"
const CATEGORY_BUILDINGS := "Architecture / Buildings"
const CATEGORY_BARRIERS := "Barriers & Fences"
const CATEGORY_INDUSTRIAL := "Industrial & Machinery"
const CATEGORY_FURNITURE := "Furniture"
const CATEGORY_LIGHTING := "Lighting"
const CATEGORY_ELECTRONICS := "Electronics & Controls"
const CATEGORY_STORAGE := "Storage & Containers"
const CATEGORY_TREES := "Nature / Trees & Logs"
const CATEGORY_PLANTS := "Nature / Plants"
const CATEGORY_TERRAIN := "Nature / Rocks & Terrain"
const CATEGORY_VEHICLES := "Vehicles"
const CATEGORY_WEAPONS := "Weapons & Tools"
const CATEGORY_SUPPLIES := "Supplies & Pickups"
const CATEGORY_DECOR := "Decor & Debris"
const CATEGORY_OTHER := "Other Props"

const FUNCTIONAL_CATEGORY_ORDER := [
	CATEGORY_WALLS,
	CATEGORY_FLOORS,
	CATEGORY_ACCESS,
	CATEGORY_STRUCTURE,
	CATEGORY_TUNNELS,
	CATEGORY_BUILDINGS,
	CATEGORY_BARRIERS,
	CATEGORY_INDUSTRIAL,
	CATEGORY_FURNITURE,
	CATEGORY_LIGHTING,
	CATEGORY_ELECTRONICS,
	CATEGORY_STORAGE,
	CATEGORY_TREES,
	CATEGORY_PLANTS,
	CATEGORY_TERRAIN,
	CATEGORY_VEHICLES,
	CATEGORY_WEAPONS,
	CATEGORY_SUPPLIES,
	CATEGORY_DECOR,
	CATEGORY_OTHER,
]

static var _cached_entries: Array[Dictionary] = []


static func entries(refresh := false) -> Array[Dictionary]:
	if refresh or _cached_entries.is_empty():
		_cached_entries = _scan_directory(ASSET_ROOT)
	return _cached_entries


static func category_names(catalog: Array[Dictionary]) -> PackedStringArray:
	var unique: Dictionary[String, bool] = {}
	for entry: Dictionary in catalog:
		unique[str(entry.get("category", "Other"))] = true
	var result := PackedStringArray()
	for category: String in FUNCTIONAL_CATEGORY_ORDER:
		if unique.has(category):
			result.append(category)
	return result


static func filter_entries(
	catalog: Array[Dictionary],
	query: String,
	category := "All assets"
) -> Array[Dictionary]:
	var normalized_query := query.strip_edges().to_lower()
	var result: Array[Dictionary] = []
	for entry: Dictionary in catalog:
		if category != "All assets" and str(entry.get("category", "")) != category:
			continue
		if (
			not normalized_query.is_empty()
			and not str(entry.get("search_text", "")).contains(normalized_query)
		):
			continue
		result.append(entry)
	return result


static func is_valid_asset_path(path: String) -> bool:
	return (
		path.begins_with(ASSET_ROOT + "/")
		and path.get_extension().to_lower() == "glb"
		and _has_valid_glb_header(path)
	)


static func _scan_directory(root_path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pending := PackedStringArray([root_path])
	while not pending.is_empty():
		var directory_path := pending[pending.size() - 1]
		pending.resize(pending.size() - 1)
		for child_directory: String in DirAccess.get_directories_at(directory_path):
			if child_directory.begins_with("."):
				continue
			pending.append(directory_path.path_join(child_directory))
		for file_name: String in DirAccess.get_files_at(directory_path):
			if file_name.get_extension().to_lower() != "glb":
				continue
			var path := directory_path.path_join(file_name)
			if not _has_valid_glb_header(path):
				continue
			var raw_name := file_name.get_basename()
			var display_name := _display_name(raw_name)
			var pack := _pack_for_path(path)
			var category := _functional_category(path, raw_name)
			result.append({
				"asset_id": StringName(path.trim_prefix(ASSET_ROOT + "/").get_basename()),
				"asset_path": path,
				"display_name": display_name,
				"category": category,
				"category_rank": FUNCTIONAL_CATEGORY_ORDER.find(category),
				"semantic_stem": _semantic_sort_stem(raw_name, category),
				"kind_rank": _semantic_kind_rank(raw_name, category),
				"pack": pack,
				"search_text": (
					display_name + " " + category + " " + pack + " " + path
				).to_lower(),
			})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var category_order := int(a.get("category_rank", 999)) - int(
			b.get("category_rank", 999)
		)
		if category_order != 0:
			return category_order < 0
		var stem_order := str(a.get("semantic_stem", "")).naturalnocasecmp_to(
			str(b.get("semantic_stem", ""))
		)
		if stem_order != 0:
			return stem_order < 0
		var kind_order := int(a.get("kind_rank", 99)) - int(
			b.get("kind_rank", 99)
		)
		if kind_order != 0:
			return kind_order < 0
		var name_order := str(a.get("display_name", "")).naturalnocasecmp_to(
			str(b.get("display_name", ""))
		)
		if name_order != 0:
			return name_order < 0
		return str(a.get("asset_path", "")).naturalnocasecmp_to(
			str(b.get("asset_path", ""))
		) < 0
	)
	return result


static func _pack_for_path(path: String) -> String:
	var relative := path.trim_prefix(ASSET_ROOT + "/")
	var components := relative.split("/", false)
	if components.is_empty():
		return "Other"
	if components[0] == "environment" and components.size() > 1:
		return components[1]
	if components[0] == "third_party" and components.size() > 1:
		return _display_name(components[1])
	return _display_name(components[0])


static func _functional_category(path: String, raw_name: String) -> String:
	var lower_path := path.to_lower()
	if lower_path.contains("/weapons & tools/"):
		return CATEGORY_WEAPONS
	if lower_path.contains("/buildings/"):
		return CATEGORY_BUILDINGS
	if lower_path.contains("/furniture/"):
		return CATEGORY_FURNITURE
	if lower_path.contains("/lighting/") or lower_path.contains("/light sources/"):
		return CATEGORY_LIGHTING
	if lower_path.contains("/doors & gates/"):
		return CATEGORY_WALLS
	if lower_path.contains("/electronics & misc/"):
		return CATEGORY_ELECTRONICS

	if _has_any_token(raw_name, [
		"lamp", "light", "lantern", "chandelier", "torch", "candle", "bulb",
	]):
		return CATEGORY_LIGHTING
	if _has_any_token(raw_name, [
		"doorway", "wall", "walls", "window", "windows", "door", "gate", "arch", "arc",
	]):
		return CATEGORY_WALLS
	if _has_any_token(raw_name, ["floor", "ceiling", "roof"]):
		return CATEGORY_FLOORS
	if _has_any_token(raw_name, [
		"stair", "stairs", "step", "steps", "ramp", "platform", "catwalk", "walkway", "bridge", "ladder",
	]):
		return CATEGORY_ACCESS
	if _has_any_token(raw_name, [
		"beam", "pillar", "column", "support", "foundation", "scaffold", "frame",
	]):
		return CATEGORY_STRUCTURE
	if _has_any_token(raw_name, ["tunnel", "shaft", "manhole"]):
		return CATEGORY_TUNNELS
	if _has_any_token(raw_name, [
		"building", "house", "warehouse", "bunker", "garage", "shed", "tower", "hangar",
	]):
		return CATEGORY_BUILDINGS
	if _has_any_token(raw_name, [
		"fence", "barricade", "barrier", "railing", "bars", "bollard",
	]):
		return CATEGORY_BARRIERS
	if _has_any_token(raw_name, [
		"pipe", "pipes", "valve", "boiler", "machine", "machinery", "generator", "tank", "vent", "duct", "fan", "pump", "engine", "conveyor",
	]):
		return CATEGORY_INDUSTRIAL
	if _has_any_token(raw_name, [
		"chair", "armchair", "sofa", "couch", "bench", "bed", "table", "desk", "cabinet", "shelf", "shelves", "locker", "wardrobe", "stool",
	]):
		return CATEGORY_FURNITURE
	if _has_any_token(raw_name, [
		"computer", "monitor", "screen", "television", "tv", "radio", "phone", "keyboard", "button", "buttons", "switch", "lever", "circuit", "capacitor", "terminal", "antenna", "speaker", "camera",
	]):
		return CATEGORY_ELECTRONICS
	if _has_any_token(raw_name, [
		"box", "crate", "container", "barrel", "bucket", "basket", "case", "chest", "bin", "dumpster", "pallet", "sack", "bag",
	]):
		return CATEGORY_STORAGE
	if _has_any_token(raw_name, [
		"tree", "trees", "trunk", "stump", "log", "branch", "pine", "palm",
	]):
		return CATEGORY_TREES
	if _has_any_token(raw_name, [
		"plant", "plants", "grass", "bush", "shrub", "flower", "fern", "weed", "wheat", "reed", "vine", "mushroom",
	]):
		return CATEGORY_PLANTS
	if _has_any_token(raw_name, [
		"rock", "rocks", "stone", "boulder", "cliff", "terrain", "ground", "asphalt", "dirt", "sand", "snow",
	]):
		return CATEGORY_TERRAIN
	if _has_any_token(raw_name, [
		"car", "truck", "vehicle", "van", "bus", "forklift", "trailer", "wheel", "tire", "tyre",
	]):
		return CATEGORY_VEHICLES
	if _has_any_token(raw_name, [
		"gun", "rifle", "pistol", "weapon", "ammo", "bullet", "knife", "axe", "hammer", "wrench", "screwdriver", "bat", "sword", "grenade", "mine", "tool",
	]):
		return CATEGORY_WEAPONS
	if _has_any_token(raw_name, [
		"food", "drink", "bottle", "can", "canned", "bandage", "medkit", "medicine", "battery", "cash", "coin", "key", "book", "tape", "item",
	]):
		return CATEGORY_SUPPLIES
	if lower_path.contains("/decals/") or _has_any_token(raw_name, [
		"decal", "debris", "trash", "rubble", "brick", "paper", "poster", "sign", "graffiti", "blood", "carpet", "curtain",
	]):
		return CATEGORY_DECOR
	if lower_path.contains("/modular structures/") or lower_path.contains("/structures/"):
		return CATEGORY_STRUCTURE
	return CATEGORY_OTHER


static func _semantic_sort_stem(raw_name: String, category: String) -> String:
	var ignored_tokens: PackedStringArray
	match category:
		CATEGORY_WALLS:
			ignored_tokens = PackedStringArray([
				"wall", "walls", "doorway", "door", "doors", "window", "windows", "gate", "arch", "arc", "frame", "top", "part", "side", "elevator", "garage", "double", "single",
			])
		CATEGORY_FLOORS:
			ignored_tokens = PackedStringArray(["floor", "ceiling", "roof"])
		CATEGORY_ACCESS:
			ignored_tokens = PackedStringArray([
				"stair", "stairs", "step", "steps", "ramp", "platform", "catwalk", "walkway", "bridge", "ladder",
			])
		CATEGORY_STRUCTURE:
			ignored_tokens = PackedStringArray([
				"beam", "pillar", "column", "support", "foundation", "scaffold", "frame",
			])
		CATEGORY_TUNNELS:
			ignored_tokens = PackedStringArray(["tunnel", "shaft", "manhole"])
		_:
			return raw_name.to_lower()
	var result := PackedStringArray()
	for token: String in _normalized_tokens(raw_name):
		if not ignored_tokens.has(token):
			result.append(token)
	return "_".join(result) if not result.is_empty() else raw_name.to_lower()


static func _semantic_kind_rank(raw_name: String, category: String) -> int:
	if category == CATEGORY_WALLS:
		if _has_any_token(raw_name, ["wall", "walls"]):
			return 0
		if _has_any_token(raw_name, ["doorway"]):
			return 1
		if _has_any_token(raw_name, ["door", "doors"]):
			return 2
		if _has_any_token(raw_name, ["window", "windows"]):
			return 3
		if _has_any_token(raw_name, ["gate"]):
			return 4
		return 5
	return 0


static func _has_any_token(raw_name: String, candidates: Array) -> bool:
	var tokens := _normalized_tokens(raw_name)
	for candidate: String in candidates:
		if tokens.has(candidate):
			return true
	return false


static func _normalized_tokens(raw_name: String) -> PackedStringArray:
	return PackedStringArray(
		raw_name.to_lower().replace("-", "_").replace(" ", "_").split(
			"_",
			false
		)
	)


static func _display_name(raw_name: String) -> String:
	return raw_name.replace("_", " ").replace("-", " ").capitalize()


static func _has_valid_glb_header(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 20:
		return false
	var magic := file.get_32()
	var version := file.get_32()
	var declared_length := file.get_32()
	return (
		magic == 0x46546C67
		and version == 2
		and declared_length <= file.get_length()
	)
