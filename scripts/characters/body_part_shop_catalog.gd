extends RefCounted
class_name BodyPartShopCatalog

const LIMB_DIRECTORY := "res://resources/limbs"

#######################################################
# Discovers buyable limb resources and organizes them into the recursive body-parts shop
# catalog.
#######################################################

static func load_buyable_limbs() -> Array[LimbDefinition]:
	var result: Array[LimbDefinition] = []
	_collect_buyable_limbs(LIMB_DIRECTORY, result)
	result.sort_custom(
		func(left: LimbDefinition, right: LimbDefinition) -> bool:
			return (
				left.display_name.naturalnocasecmp_to(right.display_name)
				< 0
			)
	)
	return result


static func build_document(
	limbs: Array[LimbDefinition]
) -> Dictionary:
	var root := {
		"title": "Body-parts shop",
		"subtitle": "Certified employee replacement program",
		"values": [
			{"label": "Stock", "value": "%d limbs" % limbs.size()},
			{"label": "Fulfillment", "value": "Pickup pad"},
			{"label": "Purchase", "value": "Left click"},
			{"label": "Catalog", "value": "Corporate"},
		],
		"children": [],
		"node_kind": "root",
	}

	for limb: LimbDefinition in limbs:
		if limb == null or not limb.shop_buyable:
			continue
		_insert_limb(root, limb)

	_finalize_node(root)
	return root


static func find_limb_by_path(
	limbs: Array[LimbDefinition],
	resource_path: String
) -> LimbDefinition:
	for limb: LimbDefinition in limbs:
		if limb != null and limb.resource_path == resource_path:
			return limb
	return null


static func is_limb_leaf(node: Dictionary) -> bool:
	return (
		str(node.get("node_kind", "")) == "limb"
		and not str(node.get("limb_path", "")).is_empty()
	)


static func get_slot_name(slot: int) -> String:
	match slot:
		LimbDefinition.Slot.LEFT_ARM:
			return "Left arm"
		LimbDefinition.Slot.RIGHT_ARM:
			return "Right arm"
		LimbDefinition.Slot.LEFT_LEG:
			return "Left leg"
		LimbDefinition.Slot.RIGHT_LEG:
			return "Right leg"
	return "Unknown socket"


static func _collect_buyable_limbs(
	directory_path: String,
	result: Array[LimbDefinition]
) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_error(
			"Body-parts shop cannot open catalog: %s" % directory_path
		)
		return

	var subdirectories := directory.get_directories()
	subdirectories.sort()
	for subdirectory: String in subdirectories:
		_collect_buyable_limbs(
			directory_path.path_join(subdirectory),
			result
		)

	var files := directory.get_files()
	files.sort()
	for file_name: String in files:
		if not file_name.ends_with(".tres"):
			continue
		var resource := load(directory_path.path_join(file_name))
		var limb := resource as LimbDefinition
		if limb != null and limb.shop_buyable:
			result.append(limb)


static func _insert_limb(root: Dictionary, limb: LimbDefinition) -> void:
	var current := root
	var categories = limb.shop_category_path
	if categories.is_empty():
		categories = _get_default_category_path(limb.slot)

	for category_label: String in categories:
		var clean_label := category_label.strip_edges()
		if clean_label.is_empty():
			continue
		current = _get_or_create_category(current, clean_label)

	var children: Array = current.get("children", [])
	children.append(_build_limb_leaf(limb))
	current["children"] = children


static func _get_or_create_category(
	parent: Dictionary,
	title: String
) -> Dictionary:
	var children: Array = parent.get("children", [])
	for child_value: Variant in children:
		var child: Dictionary = child_value
		if (
			str(child.get("node_kind", "")) == "category"
			and str(child.get("title", "")) == title
		):
			return child

	var category := {
		"title": title,
		"subtitle": "Open catalog group",
		"values": [],
		"children": [],
		"node_kind": "category",
	}
	children.append(category)
	parent["children"] = children
	return category


static func _build_limb_leaf(limb: LimbDefinition) -> Dictionary:
	var contribution_values: Array[Dictionary] = []
	if (
		limb.slot == LimbDefinition.Slot.LEFT_ARM
		or limb.slot == LimbDefinition.Slot.RIGHT_ARM
	):
		contribution_values.append({
			"label": "Grip contribution",
			"value": "%.2f" % limb.grab_strength,
		})
	else:
		contribution_values.append({
			"label": "Movement contribution",
			"value": "%.2f" % limb.movement,
		})
		contribution_values.append({
			"label": "Jump contribution",
			"value": "%.2f" % limb.jumping,
		})

	var values: Array[Dictionary] = [
		{"label": "Socket", "value": get_slot_name(limb.slot)},
		{"label": "Price", "value": "%d CR" % limb.shop_price},
		{"label": "Fulfillment", "value": "Immediate pickup"},
	]
	values.append_array(contribution_values)

	return {
		"title": limb.display_name,
		"subtitle": (
			limb.shop_description
			if not limb.shop_description.is_empty()
			else "Replacement limb"
		),
		"values": values,
		"children": [],
		"node_kind": "limb",
		"limb_path": limb.resource_path,
		"price": limb.shop_price,
		"socket": int(limb.slot),
		"item_path": limb.shop_item_path,
	}


static func get_category_products(
	document: Dictionary,
	category_index: int
) -> Array[Dictionary]:
	var categories: Array = document.get("children", [])
	if category_index < 0 or category_index >= categories.size():
		return []
	var result: Array[Dictionary] = []
	_collect_limb_leaves(categories[category_index], result)
	return result


static func _collect_limb_leaves(
	node: Dictionary,
	result: Array[Dictionary]
) -> void:
	if is_limb_leaf(node):
		result.append(node)
		return
	for child_value: Variant in node.get("children", []):
		_collect_limb_leaves(child_value, result)


static func _finalize_node(node: Dictionary) -> int:
	var children: Array = node.get("children", [])
	children.sort_custom(
		func(left_value: Variant, right_value: Variant) -> bool:
			var left: Dictionary = left_value
			var right: Dictionary = right_value
			var left_is_leaf := (
				str(left.get("node_kind", "")) == "limb"
			)
			var right_is_leaf := (
				str(right.get("node_kind", "")) == "limb"
			)
			if left_is_leaf != right_is_leaf:
				return not left_is_leaf
			return (
				str(left.get("title", "")).naturalnocasecmp_to(
					str(right.get("title", ""))
				)
				< 0
			)
	)
	node["children"] = children

	var limb_count := 0
	for child_value: Variant in children:
		var child: Dictionary = child_value
		if str(child.get("node_kind", "")) == "limb":
			limb_count += 1
		else:
			limb_count += _finalize_node(child)

	if str(node.get("node_kind", "")) == "category":
		node["subtitle"] = (
			"%d compatible replacement%s"
			% [limb_count, "" if limb_count == 1 else "s"]
		)
		node["values"] = [
			{"label": "Available", "value": str(limb_count)},
			{"label": "Open", "value": "Left click"},
		]
	return limb_count


static func _get_default_category_path(
	slot: LimbDefinition.Slot
) -> PackedStringArray:
	match slot:
		LimbDefinition.Slot.LEFT_ARM, LimbDefinition.Slot.RIGHT_ARM:
			return PackedStringArray(["Arms", "Unsorted"])
		LimbDefinition.Slot.LEFT_LEG, LimbDefinition.Slot.RIGHT_LEG:
			return PackedStringArray(["Legs", "Unsorted"])
	return PackedStringArray(["Other"])
