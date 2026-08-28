class_name CharacterContactLayers
extends RefCounted

## Collision roles used by authoritative character movement and presentation-only contact probes.
## Existing world geometry remains on layer 1 and therefore needs no migration. A structure can put
## simplified ramps/hulls on MOVEMENT_SURFACE while exposing real treads or small details only on
## FOOT_CONTACT_DETAIL; CharacterBody3D masks should never include the detail-only layer.

const MOVEMENT_SURFACE := 1
const FOOT_CONTACT_DETAIL := 1 << 8
const FOOT_CONTACT_QUERY := MOVEMENT_SURFACE | FOOT_CONTACT_DETAIL
