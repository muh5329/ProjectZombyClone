# Asset credits

Every third-party asset in the project must be listed here with its
author, source URL and licence. Only **CC0** or **CC-BY** assets whose
licence is verifiable for that specific asset are allowed; no
Mixamo-derived files, no "free for personal use", no unknown licences.
Project Zomboid (The Indie Stone) is used **only as a visual style
reference** (`docs/reference/`, screenshots for comparison, not shipped
as game content); none of its models, textures or sounds are copied.

## Third-party assets

_None._ As of Round 8.5 the project ships no downloaded models,
textures, fonts or sounds.

## Procedural / original content (owned by the project)

| Content | Where | How it is made |
|---|---|---|
| People and zombies (mesh, skeleton, skin weights) | `characters/models/humanoid_builder.gd` | Generated in GDScript from primitives (prisms, ellipsoids, boxes) at runtime |
| Clothing / outfits | `data/characters/outfits/*.tres` | Hand-written colour + style data |
| Character and zombie animations (31 clips) | `characters/models/character_animations.gd` | Keyframes computed in code |
| Vehicles (sedan, wagon, pickup, van, police, fire pickup) | `vehicles/vehicle_builder.gd`, `data/vehicles/*.tres` | Generated in GDScript (profile extrusion + boxes / cylinders) |
| Buildings, props, ground shader, UI | `buildings/`, `world/`, `assets/materials/`, `ui/` | Original code / blockout primitives (Rounds 1–8) |

Round 8.5 decision: a search for CC0 rigged low-poly humans / cars was
skipped in favour of the fully owned procedural route (see
`docs/rounds/ROUND8_5_BUILDER_NOTES.md`): one consistent style, outfits
as data, per-outfit shared meshes for the 200-zombie budget, and zero
licence risk.
