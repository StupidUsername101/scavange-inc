class_name SteamJoinCommand
extends RefCounted

const CONNECT_LOBBY_ARGUMENT := "+connect_lobby"
const CONNECT_LOBBY_ASSIGNMENT_PREFIX := CONNECT_LOBBY_ARGUMENT + "="

#######################################################
# Builds and parses the single, data-only command accepted from Steam's Join Game flow.
#######################################################


static func build(lobby_id: int) -> String:
	if lobby_id <= 0:
		return ""
	return "%s %d" % [CONNECT_LOBBY_ARGUMENT, lobby_id]


static func parse_command_line(command_line: String) -> int:
	if command_line.is_empty():
		return 0
	return parse_arguments(command_line.split(" ", false))


static func parse_arguments(arguments: PackedStringArray) -> int:
	for argument_index: int in range(arguments.size()):
		var argument := arguments[argument_index].strip_edges()
		if argument == CONNECT_LOBBY_ARGUMENT:
			if argument_index + 1 >= arguments.size():
				return 0
			return _parse_lobby_id(arguments[argument_index + 1])

		if argument.begins_with(CONNECT_LOBBY_ASSIGNMENT_PREFIX):
			return _parse_lobby_id(
				argument.trim_prefix(CONNECT_LOBBY_ASSIGNMENT_PREFIX)
			)
	return 0


static func _parse_lobby_id(value: String) -> int:
	var normalized := value.strip_edges()
	if normalized.length() >= 2:
		if normalized.begins_with('"') and normalized.ends_with('"'):
			normalized = normalized.substr(1, normalized.length() - 2)
	if not normalized.is_valid_int():
		return 0
	var parsed_id := int(normalized)
	return parsed_id if parsed_id > 0 else 0
