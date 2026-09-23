class_name TimeConfig
extends Resource
## World-time tuning (data/world/time_config.tres), read by the TimeManager
## autoload. Game time is counted in minutes since the start instant.

@export_group("Start")
## Calendar position of minute 0 (PZ-like: 1 July, 07:00).
@export_range(1, 12) var start_month: int = 7
@export_range(1, 31) var start_day: int = 1
@export_range(0, 23) var start_hour: int = 7
@export_range(0, 59) var start_minute: int = 0

@export_group("Rate")
## Game minutes per real second at 1× (1.0 → a day lasts 24 real minutes).
@export var minutes_per_second: float = 1.0
## Engine.time_scale of each speed step: pause, 1×, 2×, 4× (F5-F8, , .).
@export var speed_steps: Array[float] = [0.0, 1.0, 2.0, 4.0]

@export_group("Sleep")
## Game minutes per real second while sleeping (20 → 8 h in 24 real s).
@export var sleep_minutes_per_second: float = 20.0
## Engine.time_scale while sleeping: zombies keep simulating (8 → an 8 h
## night gives them 192 s of simulated time; the tick count per real
## second is unchanged, so this costs no extra CPU), the rest of the
## speed-up is a direct game-time skip.
@export var sleep_engine_time_scale: float = 8.0
## A sleep never lasts longer than this many REAL seconds (safety cap).
@export var sleep_max_real_seconds: float = 600.0


func start_minute_of_day() -> float:
	return float(start_hour * 60 + start_minute)
