class_name FourLimbAttachmentFeed
extends Node3D

const SLOT_COUNT = FourLimbBodyDefinition.ATTACHMENT_SLOT_COUNT
const CATEGORY_FEATURE_COUNT = FourLimbAttachmentStateProvider.CATEGORY_FEATURE_COUNT
const PAYLOAD_FEATURE_COUNT = FourLimbAttachmentStateProvider.PAYLOAD_FEATURE_COUNT
const FEATURES_PER_SLOT = 3 + CATEGORY_FEATURE_COUNT + PAYLOAD_FEATURE_COUNT

#######################################################
# Owns fixed attachment anchors on the physical core and turns arbitrary future attachment
# providers into a stable, bounded observation tensor.
#######################################################

var slot_definitions: Array[FourLimbAttachmentSlotDefinition] = []
var anchors: Array[Marker3D] = []
var providers: Dictionary[int, FourLimbAttachmentStateProvider] = {}


func configure(definitions: Array[FourLimbAttachmentSlotDefinition]) -> void:
	slot_definitions = definitions.duplicate()
	_build_anchors()


func can_install_provider(
	slot_index: int,
	provider: FourLimbAttachmentStateProvider
) -> bool:
	return (
		slot_index >= 0
		and slot_index < anchors.size()
		and is_instance_valid(provider)
		and _provider_is_allowed(slot_index, provider)
	)


func install_provider(
	slot_index: int,
	provider: FourLimbAttachmentStateProvider
) -> bool:
	if not can_install_provider(slot_index, provider):
		return false
	# One physical attachment can occupy exactly one stable feed slot. Moving a provider to a
	# different mount must remove its stale dictionary entry first, otherwise its mass and
	# observation payload would be counted twice.
	for existing_slot_value: Variant in providers.keys():
		var existing_slot = int(existing_slot_value)
		if existing_slot != slot_index and provider_for_slot(existing_slot) == provider:
			providers.erase(existing_slot)
	uninstall_provider(slot_index)
	var anchor = anchors[slot_index]
	if provider.get_parent() != null:
		provider.reparent(anchor, false)
	else:
		anchor.add_child(provider)
	provider.transform = Transform3D.IDENTITY
	providers[slot_index] = provider
	return true


func uninstall_provider(slot_index: int) -> FourLimbAttachmentStateProvider:
	var provider = providers.get(slot_index) as FourLimbAttachmentStateProvider
	providers.erase(slot_index)
	if is_instance_valid(provider) and provider.get_parent() != null:
		provider.reparent(self, true)
	return provider


func provider_for_slot(slot_index: int) -> FourLimbAttachmentStateProvider:
	return providers.get(slot_index) as FourLimbAttachmentStateProvider


func total_contributed_mass() -> float:
	var result = 0.0
	for provider_value: FourLimbAttachmentStateProvider in providers.values():
		if is_instance_valid(provider_value) and is_finite(provider_value.contributed_mass_kg):
			result += maxf(provider_value.contributed_mass_kg, 0.0)
	return result


func collision_rids_for_body_queries() -> Array[RID]:
	var result: Array[RID] = []
	for provider_value: FourLimbAttachmentStateProvider in providers.values():
		if not is_instance_valid(provider_value):
			continue
		for rid: RID in provider_value.collision_rids_for_body_queries():
			if rid.is_valid() and not result.has(rid):
				result.append(rid)
	return result


func capture_model_feed(context: Dictionary = {}) -> Dictionary:
	# Read each provider exactly once so a future gun cannot report one ammo/cooldown state in
	# the diagnostics and a different state in the tensor from the same body snapshot.
	var features = PackedFloat64Array()
	features.resize(SLOT_COUNT * FEATURES_PER_SLOT)
	features.fill(0.0)
	var states: Array[Dictionary] = []
	for slot_index in range(SLOT_COUNT):
		var offset = slot_index * FEATURES_PER_SLOT
		var definition = (
			slot_definitions[slot_index]
			if slot_index < slot_definitions.size()
			else null
		)
		var provider = provider_for_slot(slot_index)
		var installed = is_instance_valid(provider)
		var functional = provider.is_operational() if installed else false
		var categories = (
			provider.ml_category_features()
			if installed
			else PackedFloat64Array()
		)
		var payload = (
			provider.ml_observation_payload(context)
			if installed
			else PackedFloat64Array()
		)
		var contributed_mass = (
			maxf(provider.contributed_mass_kg, 0.0)
			if installed and is_finite(provider.contributed_mass_kg)
			else 0.0
		)
		if installed:
			features[offset] = 1.0
			features[offset + 1] = 1.0 if functional else 0.0
			features[offset + 2] = clampf(contributed_mass / 50.0, 0.0, 1.0)
			for category_index in range(mini(categories.size(), CATEGORY_FEATURE_COUNT)):
				var category_value = categories[category_index]
				features[offset + 3 + category_index] = (
					clampf(category_value, 0.0, 1.0)
					if is_finite(category_value)
					else 0.0
				)
			var payload_offset = offset + 3 + CATEGORY_FEATURE_COUNT
			for feature_index in range(mini(payload.size(), PAYLOAD_FEATURE_COUNT)):
				var value = payload[feature_index]
				features[payload_offset + feature_index] = (
					clampf(value, -1.0, 1.0) if is_finite(value) else 0.0
				)
		states.append({
			"slot_index": slot_index,
			"slot_name": definition.slot_name if definition != null else "Slot %d" % slot_index,
			"installed": installed,
			"functional": functional,
			"contributed_mass_kg": contributed_mass,
			"attachment_type_id": provider.attachment_type_id if installed else "",
			"attachment_tags": Array(provider.attachment_tags) if installed else [],
			"category_features": Array(categories),
			"payload": Array(payload),
		})
	return {"features": features, "states": states}


func observation_features(context: Dictionary = {}) -> PackedFloat64Array:
	return capture_model_feed(context).get("features", PackedFloat64Array())


func state_snapshot(context: Dictionary = {}) -> Array[Dictionary]:
	return capture_model_feed(context).get("states", [])


func _provider_is_allowed(
	slot_index: int,
	provider: FourLimbAttachmentStateProvider
) -> bool:
	if slot_index < 0 or slot_index >= slot_definitions.size():
		return true
	var definition = slot_definitions[slot_index]
	if definition == null or definition.allowed_tags.is_empty():
		return true
	for tag: String in provider.attachment_tags:
		if definition.allowed_tags.has(tag):
			return true
	return false


func _build_anchors() -> void:
	# Reconfiguration must never destroy installed gameplay attachments. Detach them from the
	# old anchors first, then rebuild the stable slot nodes and let the owner reinstall them.
	for provider_value: FourLimbAttachmentStateProvider in providers.values():
		if is_instance_valid(provider_value) and provider_value.get_parent() != self:
			provider_value.reparent(self, true)
	for anchor: Marker3D in anchors:
		if is_instance_valid(anchor):
			anchor.queue_free()
	anchors.clear()
	providers.clear()
	for slot_index in range(SLOT_COUNT):
		var marker = Marker3D.new()
		marker.name = "AttachmentSlot%d" % slot_index
		var definition = (
			slot_definitions[slot_index]
			if slot_index < slot_definitions.size()
			else null
		)
		marker.transform = (
			definition.core_offset if definition != null else Transform3D.IDENTITY
		)
		add_child(marker)
		anchors.append(marker)
