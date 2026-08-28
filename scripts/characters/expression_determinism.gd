class_name ExpressionDeterminism
extends RefCounted

## Stateless integer mixing shared by replicated presentation systems. It provides stable
## character variation without allocating RNG instances or depending on call order.

static func ratio(value: int) -> float:
	var hashed := value & 0x7fffffff
	hashed = int((hashed ^ (hashed >> 16)) * 0x45d9f3b) & 0x7fffffff
	hashed = int((hashed ^ (hashed >> 16)) * 0x45d9f3b) & 0x7fffffff
	hashed = hashed ^ (hashed >> 16)
	return float(hashed & 0xffff) / 65535.0
