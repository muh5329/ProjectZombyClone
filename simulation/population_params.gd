class_name PopulationParams
extends Resource
## Numbers of the off-screen zombie population simulation (Round 12;
## data/simulation/default_population.tres). Speeds are metres per GAME
## minute (at 1× a game minute is a real second, so 0.9 m/min matches a
## real zombie shambling toward a noise).

## County population (start pack + rural groups + fill) for a 768 m world;
## scaled by area and clamped to [total_min, total_max].
@export var total_at_768: int = 900
@export var total_min: int = 600
@export var total_max: int = 1200
## Group sizes of the fill population.
@export var group_min: int = 1
@export var group_max: int = 6
## Chebyshev chunk radius around the start left to the layout's start
## pack (no fill there: a breather, as in Round 11).
@export var start_radius: int = 2
@export_group("Movement (m / game minute)")
@export var wander_speed: float = 0.25
@export var migrate_speed: float = 0.5
@export var investigate_speed: float = 0.9
## A wander group farther than this from its nearest attractor (town /
## hamlet / farm centre) drifts back toward it.
@export var attractor_radius: float = 110.0
## Chance per game hour that a wandering group sets off to another
## attractor (migration).
@export var migrate_chance_per_hour: float = 0.03
## Game minutes a group keeps investigating a noise before wandering.
@export var investigate_minutes: float = 90.0
@export_group("Groups")
## Groups closer than this (same state) merge, up to [max_group].
@export var merge_radius: float = 6.0
@export var max_group: int = 24
## Wandering groups larger than this may split (chance per game hour).
@export var split_size: int = 12
@export var split_chance_per_hour: float = 0.2
@export_group("Sound")
## A sound reaches the sim through its category's sim_carry (SoundCategory):
## groups within radius × sim_carry (× indoor_factor when made inside a
## building) walk toward it. Zombies follow zombies: groups within
## [relay_radius] of an attracted group follow too, up to [relay_hops]
## hops and [max_attracted] relayed zombies per sound (nearest first;
## every group in direct reach turns).
@export var indoor_factor: float = 0.5
@export var relay_radius: float = 45.0
@export var relay_hops: int = 3
@export var max_attracted: int = 60
## Longest simulated step (game minutes); bigger advances are sub-stepped.
@export var max_step_minutes: float = 20.0
