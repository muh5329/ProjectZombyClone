class_name MedicalData
extends ItemData
## First-aid items. InjuryComponent looks for the best dressing
## (bandage_quality > 0) in the character's `inventory` (ItemContainer).

## 0 = not a dressing. 1 = clean bandage; a rag is 0.5 (heals slower).
@export_range(0.0, 1.0) var bandage_quality: float = 0.0
## Chance that a wound dressed with this starts bleeding again after
## [rebleed_after] seconds (makeshift dressings: rag 0.5).
@export_range(0.0, 1.0) var rebleed_chance: float = 0.0
@export var rebleed_after: float = 60.0
## Disinfecting strength 0..1 (cleans wounds; used from Round 7 on).
@export_range(0.0, 1.0) var disinfectant: float = 0.0
## Pain removed when taken (painkillers).
@export var pain_relief: float = 0.0
## Fixes a fracture (splint).
@export var splints: bool = false
