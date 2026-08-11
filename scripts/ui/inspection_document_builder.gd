class_name InspectionDocumentBuilder
extends RefCounted

#######################################################
# Shared construction helpers for scanner/inspection documents. Inspection producers should own
# their domain wording and values, not each maintain another copy of the document wire format.
#######################################################


static func node(
	title: String,
	subtitle: String = "",
	values: Array = [],
	children: Array = []
) -> Dictionary:
	return {
		"title": title,
		"subtitle": subtitle,
		"values": values,
		"children": children,
	}


static func stat(label: String, value: String) -> Dictionary:
	return {
		"label": label,
		"value": value,
	}


static func percent_stat(label: String, value: float) -> Dictionary:
	return stat(label, "%.0f%%" % (clampf(value, 0.0, 1.0) * 100.0))
