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
