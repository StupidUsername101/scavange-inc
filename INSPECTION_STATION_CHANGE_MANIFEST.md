# Inspection station change manifest

This build was made directly from the user-provided `scavange-inc(1).zip`.

- Source archive SHA-256: `a6f392f47ccf1b4ae24ba0ad834cb24ac7022f44e5a0a9d5828dcb557e366956`
- Station world position: `Vector3(-5, 0, -2)`
- Controls: hold a loose drone part with `E` and left-click the station to
  inspect it. Left-click the cradle to eject it. Left-click terminal boxes to
  zoom into their grouped values and use the upper-left back box to zoom out.

## Added

- `scenes/server/drone_inspection_station.tscn`
- `scenes/proxy/drone_inspection_station.tscn`
- `scripts/server/drone_inspection_station.gd`
- `scripts/client/drone_inspection_station_proxy.gd`
- `scripts/drones/inspection/drone_part_inspection_interface.gd`
- Seven type-specific resources under `resources/drones/inspection/`

## Modified

- `scripts/server/server.gd`
- `scripts/client/client.gd`
- `scenes/server/server_world.tscn`
- `scenes/proxy/world.tscn`

The server owns insertion/ejection, the docked part, and each player's current
terminal path. Terminal state is replicated to every client. Core, battery,
propeller, AI chip, weapon, manipulator arm, and generic attachment documents
are selected through station-owned inspection-interface resources. Documents
use recursive grouped nodes, so every terminal box can contain deeper boxes.
