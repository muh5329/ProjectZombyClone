OBJECTIVE

Build a playable 3D isometric survival sandbox in Godot inspired by the systemic gameplay of Project Zomboid.

The player must survive in a persistent zombie-infested world by:

- Exploring towns, suburbs, farms, forests, industrial areas, and wilderness.
- Entering and searching buildings.
- Looting physical containers such as cabinets, shelves, refrigerators, cars, corpses, crates, and backpacks.
- Managing hunger, thirst, fatigue, health, injuries, temperature, stamina, and encumbrance.
- Fighting zombies using melee weapons, firearms, and environmental tactics.
- Avoiding noise and managing zombie attraction.
- Barricading and fortifying buildings.
- Crafting tools, weapons, survival equipment, furniture, and structures.
- Farming, cooking, fishing, trapping, and gathering resources.
- Driving and maintaining vehicles.
- Establishing safehouses and eventually survivor settlements.
- Surviving a world that continues to change even while the player is elsewhere.

Engine:
Godot 4.x

Primary language:
GDScript

Visual direction:
3D world presented through an isometric / elevated camera.

Start with extremely simple blockout graphics and placeholder assets.
Gameplay systems take priority over final visuals.

Do NOT attempt to build the entire game simultaneously.

Build a small, completely playable survival sandbox first and expand outward through verified vertical slices.


==================================================
CORE DESIGN PRINCIPLES
==================================================

The game should prioritize:

1. SYSTEMIC GAMEPLAY

Systems should interact with each other rather than being isolated scripted events.

Examples:

Rain ->
player gets wet ->
temperature drops ->
clothing becomes important ->
wet clothes must dry ->
cold affects stamina and survival.

Breaking a window ->
creates noise ->
nearby zombies investigate ->
broken glass becomes a hazard ->
window can later be barricaded.

Gunshot ->
large noise event ->
zombies from surrounding simulation cells become interested ->
local zombie density changes.

Generator ->
powers house ->
produces noise ->
requires fuel ->
may attract zombies.

Food ->
has calories and nutrition ->
can spoil ->
can be refrigerated ->
can be cooked ->
can cause sickness if unsafe.


2. EMERGENT SURVIVAL STORIES

The game should create situations through systems rather than scripted missions.

The player should naturally experience stories such as:

- Running out of fuel far from home.
- Breaking into a pharmacy while zombies surround the building.
- Losing electricity and needing a generator.
- Becoming injured during a supply run.
- Finding a working vehicle but lacking the correct tools.
- Creating a fortified farmhouse.
- Losing a safehouse and relocating.
- Rescuing or recruiting another survivor.


3. PERSISTENT WORLD

Changes made to the world should persist.

Examples:

- Opened containers remain opened.
- Loot remains removed.
- Dropped items remain.
- Zombies can remain dead.
- Barricades remain constructed.
- Vehicles remain where they were parked.
- Buildings remain damaged.
- Crops continue growing.
- Player-built structures persist.


4. DATA-DRIVEN ARCHITECTURE

Items, weapons, recipes, zombies, buildings, containers, vehicles, occupations,
traits, status effects, and loot tables should be represented primarily through
resources/data rather than hardcoded logic.


==================================================
FIRST PLAYABLE TARGET
==================================================

Before building the full game, create ONE small playable neighborhood.

The initial map should contain approximately:

- 8-12 houses
- 1 convenience store
- 1 warehouse
- 1 gas station
- several roads
- forest around the perimeter
- approximately 30-50 zombies

The first vertical slice must allow the player to:

1. Walk and sprint.
2. Enter buildings.
3. Open doors.
4. Break/open windows.
5. Search containers.
6. Pick up items.
7. Equip a melee weapon.
8. Fight zombies.
9. Take damage.
10. Become hungry and thirsty.
11. Eat and drink.
12. Carry inventory with weight limits.
13. Kill zombies.
14. Loot zombie corpses.
15. Barricade a door or window.
16. Sleep or rest.
17. Save the game.
18. Reload and see the same world state.

Do not expand the world until this loop works reliably.


==================================================
INPUTS AND STATE
==================================================

Use:

- Existing Godot project
- Current project files
- Reference screenshots
- Reference gameplay videos
- Existing progress documentation
- Generated assets
- Blender MCP where appropriate
- Image generation for concept/reference assets
- Automated Godot tests where practical
- Godot web builds for rapid gameplay verification where supported

Maintain:

docs/MASTER_PLAN.md
docs/PROGRESS.md
docs/ARCHITECTURE.md
docs/SYSTEMS.md
docs/KNOWN_ISSUES.md

After EVERY gauntlet round update PROGRESS.md with:

- Goal of the round
- What changed
- Files changed
- Systems added
- Tests performed
- Screenshots / evidence
- Bugs discovered
- Bugs fixed
- Failed approaches
- Current verifier score
- Highest-priority remaining issue
- Recommended next action


==================================================
METRIC / VERIFIER
==================================================

A feature is NOT complete merely because the code exists.

Each feature must be verified in the running game.

Evaluate each round using:

FUNCTIONALITY
0-10

Does the feature actually work?

SYSTEM INTEGRATION
0-10

Does the feature interact correctly with existing systems?

SURVIVAL DEPTH
0-10

Does the system create meaningful survival decisions?

ARCHITECTURE
0-10

Is the implementation modular and extensible?

PERFORMANCE
0-10

Does the feature remain performant at realistic scale?

UX / FEEDBACK
0-10

Can the player understand what happened and why?

BUG RESISTANCE
0-10

Does it survive edge cases and repeated testing?


A round passes only when:

- No critical errors occur.
- No major regressions are introduced.
- The system works inside actual gameplay.
- Independent verification confirms the expected behavior.


==================================================
GAUNTLET PROCESS
==================================================

Repeat:

1. Inspect the entire current project state.

2. Read:

   docs/MASTER_PLAN.md
   docs/PROGRESS.md
   docs/KNOWN_ISSUES.md

3. Run the game before making changes.

4. Identify the highest-impact missing or broken feature.

5. Select ONE coherent improvement.

6. Create a short implementation plan.

7. Delegate isolated tasks to subagents where useful.

8. Implement the change.

9. Run the game.

10. Test the real gameplay scenario.

11. Attempt to break the implementation.

12. Run an independent critic/reviewer.

13. Compare against the verifier criteria.

14. Fix discovered problems.

15. Run the test again from a clean state.

16. Update documentation.

17. Commit only when the feature passes.

Then begin the next round.


==================================================
CRITIC AGENTS
==================================================

Use independent critics throughout development.


GAMEPLAY CRITIC

Ask:

- Is surviving interesting?
- Are meaningful choices occurring?
- Does the mechanic create emergent situations?
- Is there enough risk/reward?
- Does the player have multiple solutions?


SYSTEMS CRITIC

Inspect interactions between:

- inventory
- combat
- zombies
- needs
- crafting
- buildings
- sound
- vehicles
- weather
- electricity
- farming
- injuries


ARCHITECTURE CRITIC

Look for:

- God objects
- tightly coupled nodes
- duplicated code
- hardcoded items
- hardcoded recipes
- circular dependencies
- systems that cannot be tested independently


PERFORMANCE CRITIC

Test:

- hundreds of zombies
- thousands of world objects
- many loot containers
- large maps
- simulation outside the player's immediate area


UI/UX CRITIC

Verify that the player understands:

- health
- hunger
- thirst
- stamina
- inventory weight
- weapon condition
- injuries
- zombie danger
- interaction possibilities


PROJECT ZOMBOID-LIKE EXPERIENCE CRITIC

Do NOT simply check visual similarity.

Evaluate whether the game captures the important systemic qualities:

- dangerous exploration
- scarcity
- persistent consequences
- detailed inventory
- vulnerability
- environmental interaction
- base fortification
- zombie pressure
- preparation before expeditions
- long-term survival progression


==================================================
PROJECT ARCHITECTURE
==================================================

Suggested structure:

res://

  core/
      game_manager.gd
      event_bus.gd
      save_manager.gd
      time_manager.gd
      world_manager.gd

  player/
      player.gd
      player_controller.gd
      player_interaction.gd
      player_combat.gd

  characters/
      character.gd
      stats_component.gd
      health_component.gd
      movement_component.gd

  zombies/
      zombie.gd
      zombie_ai.gd
      zombie_senses.gd
      zombie_navigation.gd
      zombie_spawner.gd

  ai/
      state_machine/
      behavior/
      perception/

  inventory/
      inventory.gd
      inventory_slot.gd
      equipment.gd
      container.gd

  items/
      item_data.gd
      weapon_data.gd
      food_data.gd
      medical_item_data.gd

  combat/
      weapon.gd
      melee_weapon.gd
      firearm.gd
      damage_system.gd

  survival/
      hunger_system.gd
      thirst_system.gd
      fatigue_system.gd
      temperature_system.gd
      sickness_system.gd

  injuries/
      injury.gd
      bleeding.gd
      fracture.gd
      infection.gd
      treatment.gd

  interaction/
      interactable.gd
      door.gd
      window.gd
      furniture.gd

  buildings/
      building.gd
      room.gd
      barricade.gd

  crafting/
      crafting_system.gd
      recipe.gd

  world/
      world_chunk.gd
      chunk_manager.gd
      world_streamer.gd

  simulation/
      simulation_manager.gd
      zombie_population_sim.gd
      offscreen_simulation.gd

  vehicles/
      vehicle.gd
      vehicle_controller.gd
      vehicle_damage.gd
      vehicle_inventory.gd

  farming/
      crop.gd
      farming_system.gd

  weather/
      weather_manager.gd

  electricity/
      electrical_grid.gd
      generator.gd

  audio/
      sound_event.gd
      sound_manager.gd

  npc/
      survivor.gd
      survivor_ai.gd

  ui/
      hud/
      inventory/
      health/
      crafting/

  data/
      items/
      weapons/
      recipes/
      zombies/
      loot_tables/
      vehicles/

  maps/

  assets/

  tests/

  docs/


==================================================
PLAYER CONTROLLER
==================================================

Create a responsive isometric survival controller.

Player capabilities:

- Walk
- Jog
- Sprint
- Sneak
- Aim
- Attack
- Push
- Interact
- Vault low obstacles
- Climb through windows
- Open/close doors
- Carry objects

Movement should account for:

- stamina
- injury
- carried weight
- terrain
- status effects

Avoid making movement feel like an action-RPG.

The player should feel like a vulnerable human rather than a superhero.


==================================================
CAMERA
==================================================

Use an elevated isometric camera.

Support:

- rotation around the player
- several zoom levels
- smooth follow
- occlusion handling

When the player enters buildings:

- hide/fade obstructing roofs
- hide/fade front walls where necessary
- preserve visibility of interior rooms

Buildings must remain visually readable.


==================================================
WORLD INTERACTION SYSTEM
==================================================

Develop a universal interaction framework.

Interactable examples:

- doors
- windows
- cabinets
- refrigerators
- shelves
- corpses
- vehicles
- beds
- ovens
- sinks
- toilets
- generators
- lights
- crates

Possible actions should be provided by the object itself.

Example:

Window actions:

Open
Close
Smash
Climb Through
Remove Broken Glass
Barricade
Unbarricade

Do NOT hardcode every interaction into Player.gd.


==================================================
INVENTORY SYSTEM
==================================================

Build a container-based inventory system.

Items contain:

- ID
- display name
- icon
- category
- weight
- stack size
- condition
- metadata

Container examples:

- player inventory
- backpack
- cabinet
- refrigerator
- vehicle trunk
- corpse
- crate

Support:

- drag/drop
- transfer
- stacking
- splitting stacks
- equipment
- nested containers where reasonable

Encumbrance affects player performance.


==================================================
LOOT SYSTEM
==================================================

Loot should come from data-driven loot tables.

Example:

Kitchen cabinet:
food
cooking equipment
containers

Garage:
tools
mechanical parts
fuel-related equipment

Pharmacy:
medicine
bandages
painkillers

Police station:
weapons
ammunition
protective equipment

Loot tables should support:

- rarity
- location
- building type
- room type
- container type
- world age


==================================================
ZOMBIE AI
==================================================

Zombies require:

STATES

Idle
Wander
Investigate
Chase
Attack
Search
LostTarget
Stunned
Dead

SENSES

Vision
Hearing
Proximity

Zombies should respond to sound events.

Examples:

footstep = tiny radius
running = low radius
broken window = medium radius
alarm = very large radius
gunshot = enormous radius


==================================================
SOUND PROPAGATION
==================================================

Create a gameplay sound-event system separate from normal audio playback.

Example:

SoundEvent:
position
radius
intensity
category
duration

Zombie AI listens for sound events.

This system should support:

- footsteps
- doors
- windows
- melee combat
- firearms
- alarms
- vehicles
- generators
- explosions


==================================================
ZOMBIE POPULATION SIMULATION
==================================================

Do not instantiate every zombie in the world.

Separate:

ACTIVE ZOMBIES

Fully simulated zombies near the player.

SIMULATED ZOMBIES

Cheap population representation outside the active area.

Allow zombie populations to:

- migrate
- follow large sounds
- redistribute
- form groups
- move between simulation cells

Only instantiate full CharacterBody3D zombies close to the player.


==================================================
COMBAT
==================================================

Implement:

Melee:

- swing arc
- weapon reach
- stamina cost
- push
- knockback
- knockdown
- weapon durability

Firearms:

- aim
- recoil
- accuracy
- ammunition
- reload
- condition
- extremely loud sound events

Examples of melee weapons:

Baseball bat
Hammer
Crowbar
Axe
Knife
Pipe
Machete

Do not make combat excessively powerful.

Even small groups of zombies should remain dangerous.


==================================================
HEALTH AND INJURY
==================================================

Use body-region injuries.

Regions can include:

Head
Torso
Left Arm
Right Arm
Left Hand
Right Hand
Left Leg
Right Leg
Left Foot
Right Foot

Possible injuries:

Scratch
Laceration
Deep Wound
Bleeding
Burn
Fracture
Bite

Treatment can involve:

Bandaging
Disinfecting
Suturing
Splinting
Medication
Rest


==================================================
SURVIVAL NEEDS
==================================================

Implement interconnected:

Hunger
Thirst
Fatigue
Stamina
Temperature
Wetness
Pain
Stress
Sickness

These should change behavior rather than simply displaying meters.


==================================================
CRAFTING
==================================================

Recipes are data-driven.

Recipe:

Inputs
Tools
Skill requirement
Time requirement
Outputs

Examples:

Makeshift bandage
Campfire
Wooden barricade
Spear
Rain collector
Storage crate
Fishing equipment


==================================================
BUILDINGS
==================================================

Buildings require:

- exterior walls
- interior walls
- rooms
- doors
- windows
- roofs
- containers
- furniture

Buildings should understand room boundaries.

This later enables:

- temperature simulation
- indoor/outdoor detection
- lighting
- electricity
- zombie navigation
- sound attenuation


==================================================
BARRICADING
==================================================

Allow:

- wooden plank barricades
- furniture blocking doors
- window fortification
- stronger upgrades later

Zombies should physically attack barricades.

Barricades have:

health
material
noise generated while constructing
required tools
required resources


==================================================
SKILLS
==================================================

Potential skills:

Fitness
Strength
Carpentry
Cooking
Farming
First Aid
Mechanics
Electrical
Fishing
Foraging
Aiming
Reloading

Actions generate experience.

Skills should unlock efficiency or capabilities rather than only numerical bonuses.


==================================================
CRAFTING / SURVIVAL PROGRESSION
==================================================

Example early progression:

Loot food
↓
Find basic weapon
↓
Secure temporary shelter
↓
Gather tools
↓
Barricade house
↓
Establish water supply
↓
Establish renewable food
↓
Acquire vehicle
↓
Explore farther
↓
Establish generator
↓
Build permanent base


==================================================
VEHICLES
==================================================

Vehicles should eventually include:

- fuel
- battery
- engine
- tires
- storage
- condition
- keys
- doors
- windows

Vehicles produce significant noise.

They should enable longer expeditions but create new problems:

Fuel
Maintenance
Breakdowns
Zombie attraction
Road blockages


==================================================
FARMING
==================================================

Support:

Till soil
Plant
Water
Growth
Disease
Harvest

Growth progresses using world time.

Plants must continue growing even when their map chunk is unloaded.


==================================================
WORLD TIME
==================================================

Implement:

Minutes
Hours
Days
Months
Seasons

World time affects:

- lighting
- farming
- food spoilage
- weather
- temperature
- zombie behavior
- world deterioration


==================================================
WORLD STREAMING
==================================================

Eventually divide the world into streamed cells/chunks.

Example:

World
   ↓
Region
   ↓
Cell
   ↓
Chunk

Nearby chunks:
fully loaded

Medium distance:
simplified simulation

Far away:
abstract data simulation

Persistent state must survive loading/unloading.


==================================================
SAVE SYSTEM
==================================================

Never serialize entire scenes blindly.

Store persistent world state as data.

Save:

Player
Inventory
Needs
Health
Skills
Containers
Destroyed objects
Doors/windows
Barricades
Vehicles
Zombie populations
Dropped items
Crops
World time
Weather
Generators
Building state


==================================================
NPC SURVIVORS
==================================================

Add only after the fundamental survival loop works.

NPC states may include:

Idle
Follow
Loot
Attack
Flee
Eat
Drink
Sleep
Heal
Work
Guard

NPCs may eventually:

- join the player
- establish bases
- trade
- become hostile
- form survivor groups


==================================================
WORLD EXPANSION
==================================================

Expand the world incrementally.

Biome / region examples:

Suburb
Downtown
Industrial zone
Rural farmland
Forest
Highway
Trailer park
Small town
Military checkpoint
Campground

Do NOT build a giant empty map first.

Every new region should introduce meaningful survival opportunities.


==================================================
ASSET PIPELINE
==================================================

PHASE 1

Primitive meshes.

Characters = capsules / simple models
Buildings = boxes
Cars = simple blocks
Furniture = primitives

PHASE 2

Use ImageGen to establish consistent concept art.

Create reference sheets for:

- survivors
- zombies
- buildings
- furniture
- vehicles
- weapons
- environment props

PHASE 3

Use Blender MCP to generate/recreate optimized 3D assets.

PHASE 4

Replace placeholders incrementally.

Never stop gameplay development waiting for final art.


==================================================
DEVELOPMENT PHASES
==================================================

PHASE 1 — SURVIVAL MICRO-SLICE

Player
Camera
House
Zombie
Melee
Loot
Inventory
Hunger
Thirst


PHASE 2 — NEIGHBORHOOD

Multiple houses
Containers
Loot tables
Doors/windows
Barricades
Zombie spawning
Saving


PHASE 3 — SYSTEMIC SURVIVAL

Injuries
Medicine
Cooking
Food spoilage
Sleep
Weather
Temperature


PHASE 4 — BASE BUILDING

Carpentry
Crafting
Barricading
Furniture
Storage
Power
Water


PHASE 5 — VEHICLES

Driving
Fuel
Storage
Damage
Maintenance


PHASE 6 — WORLD

Chunk streaming
Larger map
Zombie population simulation
Persistent world


PHASE 7 — LONG-TERM SURVIVAL

Farming
Fishing
Foraging
Generators
Seasons
World deterioration


PHASE 8 — NPC SURVIVORS

Survivor AI
Recruitment
Trading
Groups
Settlement jobs


==================================================
FIRST 10 GAUNTLET ROUNDS
==================================================

ROUND 1
Player + isometric camera.

ROUND 2
One enterable house with doors and windows.

ROUND 3
Basic zombie AI.

ROUND 4
Melee combat and player health.

ROUND 5
Interactable containers and loot.

ROUND 6
Inventory and equipment.

ROUND 7
Hunger/thirst + consumable food.

ROUND 8
Sound propagation + zombie hearing.

ROUND 9
Barricading windows and doors.

ROUND 10
Saving and restoring the entire micro-world.


After Round 10:

STOP.

Perform a complete vertical-slice review before expanding.


==================================================
FINAL ACCEPTANCE TEST
==================================================

Start a completely fresh game.

The player must be able to:

Spawn in a house.

Search the kitchen.

Find food.

Equip a backpack.

Find a weapon.

Hear zombies outside.

Open or climb through a window.

Explore another building.

Fight or evade zombies.

Become hungry and thirsty.

Eat and drink.

Become injured.

Treat the injury.

Carry supplies home.

Barricade the safehouse.

Sleep.

Save.

Exit.

Reload.

Confirm:

- player state persisted
- inventory persisted
- killed zombies persisted
- looted containers persisted
- barricades persisted
- world time persisted


If any critical part fails, the vertical slice does not pass.


==================================================
BOUNDARIES
==================================================

Allowed:

read
inspect
plan
create
edit
refactor
test
run
benchmark
render
generate placeholder assets
generate reference assets
update documentation

Do not:

delete important existing systems without justification
replace working systems merely for style preference
expand scope while critical systems remain broken
hide errors
fake test results
mark features complete without running them


==================================================
STOP CONDITION
==================================================

Do not declare the project complete based on the number of implemented features.

The gauntlet ends only when:

- the core survival loo
