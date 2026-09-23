class_name GameClock
extends RefCounted
## Pure calendar maths for world time (Round 7). Time is a float count of
## GAME minutes since the world's start instant; the start instant is a
## calendar position (month, day, hour, minute) from TimeConfig. Months use
## real (non-leap) lengths; seasons are northern-hemisphere meteorological
## (Dec-Feb winter, Mar-May spring, Jun-Aug summer, Sep-Nov autumn).
## Everything is static so it is unit-tested without the TimeManager.

const MINUTES_PER_HOUR := 60
const MINUTES_PER_DAY := 1440
const MONTH_DAYS: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const MONTH_NAMES: Array[String] = ["January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"]
const SEASONS: Array[StringName] = [&"winter", &"spring", &"summer", &"autumn"]


## Minutes into the current day (0 ≤ m < 1440) of the absolute minute
## [total] when the world started at [start_minute_of_day].
static func minute_of_day(total: float, start_minute_of_day: float = 0.0) -> float:
	return fposmod(total + start_minute_of_day, MINUTES_PER_DAY)


## Hour 0..23.
static func hour_of(total: float, start_minute_of_day: float = 0.0) -> int:
	return int(minute_of_day(total, start_minute_of_day)) / MINUTES_PER_HOUR


## Minute 0..59 of the hour.
static func minute_of(total: float, start_minute_of_day: float = 0.0) -> int:
	return int(minute_of_day(total, start_minute_of_day)) % MINUTES_PER_HOUR


## Fractional hour 0..24 (lighting curves).
static func hour_float(total: float, start_minute_of_day: float = 0.0) -> float:
	return minute_of_day(total, start_minute_of_day) / float(MINUTES_PER_HOUR)


## Whole days elapsed since the start day (0 on the first day). A day
## rolls over at midnight, not 24 h after the start.
static func days_elapsed(total: float, start_minute_of_day: float = 0.0) -> int:
	return int(floor((total + start_minute_of_day) / MINUTES_PER_DAY))


## Calendar date {month: 1..12, day: 1..31} [days] days after
## ([start_month], [start_day]). Wraps over years.
static func date_after(start_month: int, start_day: int, days: int) -> Dictionary:
	var m := clampi(start_month, 1, 12) - 1
	var d := clampi(start_day, 1, MONTH_DAYS[m]) - 1 + maxi(days, 0)
	while d >= MONTH_DAYS[m]:
		d -= MONTH_DAYS[m]
		m = (m + 1) % 12
	return {"month": m + 1, "day": d + 1}


## &"winter" / &"spring" / &"summer" / &"autumn" for a month 1..12.
static func season_of(month: int) -> StringName:
	return SEASONS[(clampi(month, 1, 12) % 12) / 3]


## "08:10".
static func format_time(hour: int, minute: int) -> String:
	return "%02d:%02d" % [hour, minute]


## "07/12" (MM/DD, like the PZ clock).
static func format_date(month: int, day: int) -> String:
	return "%02d/%02d" % [month, day]


## Outdoor air temperature (°C) for a month and hour: a seasonal mean
## (coldest mid-January, warmest mid-July) plus a daily sine (coolest at
## 03:00, warmest at 15:00). Display only until weather exists.
static func temperature_c(month: int, hour_f: float) -> float:
	# Seasonal mean: 1 °C in January … 24 °C in July (cosine over the year).
	var season := -cos((float(clampi(month, 1, 12)) - 1.0) / 12.0 * TAU)
	var mean := 12.5 + 11.5 * season
	var daily := sin((hour_f - 9.0) / 24.0 * TAU)  # −1 at 03:00 … +1 at 15:00
	return mean + 5.0 * daily


static func c_to_f(c: float) -> float:
	return c * 9.0 / 5.0 + 32.0
