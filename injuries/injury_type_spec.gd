class_name InjuryTypeSpec
extends Resource
## Numbers for one injury type (scratch, laceration…). Sub-resource of
## InjuryProfile.

## Health lost per second while bleeding (0 = never bleeds).
@export var bleed_rate: float = 0.0
## Seconds before the bleeding stops on its own (0 = only a bandage stops it).
@export var bleed_seconds: float = 0.0
## Pain points (the pain stat is the capped sum over injuries).
@export var pain: float = 10.0
## Seconds to heal (unbandaged).
@export var heal_seconds: float = 600.0
## Chance the wound carries the zombie infection when a zombie inflicts it.
@export_range(0.0, 1.0) var infection_chance: float = 0.0
## Speed multiplier while this wound is on a leg (1 = no effect).
@export_range(0.1, 1.0) var leg_speed_multiplier: float = 1.0
## Maximum stamina points lost while the wound is open.
@export var max_stamina_penalty: float = 0.0
