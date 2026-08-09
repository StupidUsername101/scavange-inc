@tool
class_name LimbDefinition
extends Resource

#######################################################
# Defines the serialized limb configuration shared by gameplay, inspection, and replication
# systems.
#######################################################

enum Slot {
	LEFT_ARM,
	RIGHT_ARM,
	LEFT_LEG,
	RIGHT_LEG,
}

@export var display_name := "Limb"
@export var slot := Slot.LEFT_ARM

@export_group("Body-parts Shop")
@export var shop_buyable := false
@export_range(0, 100000, 1, "or_greater") var shop_price := 0
@export var shop_category_path := PackedStringArray()
@export_multiline var shop_description := ""
@export_file("*.tres") var shop_item_path := ""

@export_group("Contributions")
@export_range(0.0, 10.0, 0.05, "or_greater") var grab_strength := 0.0
@export_range(0.0, 10.0, 0.05, "or_greater") var movement := 0.0
@export_range(0.0, 10.0, 0.05, "or_greater") var jumping := 0.0
