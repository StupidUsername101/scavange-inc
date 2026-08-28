class_name FieldlinkDisplayState
extends RefCounted

## Small, validated display state that is safe to replicate with the player's
## physical Fieldlink pose. Device data remains authoritative and private to the
## player operating it; nearby players only need the visible navigation page.

const PAGE_HOME: StringName = &"home"
const PAGE_SCANNER: StringName = &"scanner"


static func sanitize_page(value: Variant) -> StringName:
	var page := StringName(str(value))
	return page if page == PAGE_SCANNER else PAGE_HOME


static func make_replication_packet(
	player_id: int,
	open_value: bool,
	page_value: Variant
) -> Dictionary:
	return {
		"player_id": player_id,
		"open": open_value,
		"page": sanitize_page(page_value),
	}


static func sanitize_replication_packet(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var packet := value as Dictionary
	var player_id := SafeVariant.integral_int_or(
		packet.get("player_id", -1),
		-1
	)
	if player_id < 0:
		return {}
	return make_replication_packet(
		player_id,
		SafeVariant.strict_bool_or(packet.get("open", false), false),
		packet.get("page", PAGE_HOME)
	)
