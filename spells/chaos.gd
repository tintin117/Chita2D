class_name Chaos extends RefCounted
## Loaded Dice (Chaos Lord passive): every cast rolls one multiplier in [LO, HI] and it scales that cast: the basic's
## damage, Rift Bolt's damage AND stun, Stillwake's length. The roll comes from the caster's rng, which Player._net_cast
## reseeds from the cast's own seed, so every peer rolls the same number. The roll pops over his head.

const LO := 0.5
const HI := 3.5

static func roll(caster: Node2D, lo := LO, hi := HI) -> float:
	var r := 1.0
	if "rng" in caster:
		r = caster.rng.randf_range(lo, hi)
	if caster.has_method("float_text"):
		var k := clampf((r - lo) / maxf(hi - lo, 0.01), 0.0, 1.0)
		caster.float_text("x%.1f" % r, Color(0.6, 0.6, 0.75).lerp(Color(1.0, 0.3, 0.95), k), 15 + roundi(k * 12.0))
	return r
