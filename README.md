# Voxel Voyager

A low-poly voxel space exploration game made in Godot 4.7. You fly a small ship around a procedural galaxy of tiny spherical voxel planets. Land anywhere and walk around on foot. Mine ore and crack asteroids, then sell what you collect at trade outposts and spend the credits on ship upgrades. Buy a warp drive to reach other stars, and decode five ancient beacons to find the Architect's Core.

All art and audio are generated in code. The project has no asset files.

## Run

```bash
godot --path .            # play
tests/run.sh              # headless test suite
godot --path . res://tests/tour.tscn   # scripted smoke tour, screenshots in /tmp/vv_shots
```

## Controls

| Ship | |
|---|---|
| Mouse | Steer (pitch and yaw) |
| W / S | Thrust forward / back |
| A / D | Strafe |
| Space / Ctrl | Up / down |
| Q / E | Roll |
| Shift | Boost (burns fuel fast) |
| Left click | Laser: cracks asteroids, fights drones, drills terrain |
| R (hold, aim at a planet) | Scan: shows resources and reveals the beacon's light beam |
| G | Galaxy map / warp |
| F | Dock at an outpost, or step outside after landing |

| On foot | |
|---|---|
| WASD, Shift | Walk, sprint |
| Space | Jump; hold in the air for the jetpack |
| Left click (hold) | Mine the block under the crosshair |
| Right click | Place a block (costs 1 stone) |
| F | Board the ship / activate a beacon |

H toggles the help panel. Esc pauses.

## Gameplay loop

- **Planets**: there are six biomes: verdant, desert, frozen, volcanic, crystalline and barren. Each one has its own gravity, ore mix and atmosphere. You can only breathe on verdant worlds. Anywhere else your suit oxygen runs down.
- **Ore**: stone, iron, ice, gold and crystal. You get it by mining on foot, by drilling with the ship laser, or by shooting asteroids. The ship's tractor field pulls in the floating chunks.
- **Trade outposts**: every system has one. Docking there autosaves the game. At the outpost you can sell ore, refuel, repair, and buy upgrades: engines, fuel tanks, hull, cargo hold, mining laser and warp drive.
- **Dangers**: flying close to the star overheats the hull. Hard crashes also do damage. Outside the home system, sentry drones shoot at you. If the hull breaks, your ship is towed back to the outpost and you lose your cargo. When the fuel tank is empty, emergency thrusters still give you 35% thrust, so you can never get stranded.
- **Goal**: each beacon you decode gives you one signal fragment and 150 credits. Once you have five, the "???" star on the galaxy map becomes the Architect's Core. Land there and wake the monolith.

## Code map

| File | Role |
|---|---|
| `scripts/world.gd` | Root controller. Builds the system and switches between modes: title, ship, on foot, docked, map, warp, pause. |
| `scripts/galaxy.gd` | Deterministic galaxy. Each system is generated from its grid cell. |
| `scripts/voxel_planet.gd` | Spherical voxel terrain. Chunks are meshed on worker threads, and mining or building re-meshes them. |
| `scripts/voxel_mesher.gd` | Builds cube faces, provides the shared vertex-colour material, and generates the voxel blobs used for asteroids. |
| `scripts/ship.gd`, `scripts/player.gd` | Flight and on-foot controllers, including radial gravity, auto-step and the jetpack. |
| `scripts/game_state.gd` | `Game` autoload: economy, upgrades, progress, voxel edits, and the JSON save. |
| `scripts/sfx.gd` | `Sfx` autoload: synthesised sound effects. |
| `scripts/hud.gd`, `shop_panel.gd`, `galaxy_map.gd`, `menus.gd`, `ui_theme.gd` | UI. |
| `scripts/station.gd`, `asteroid.gd`, `drone.gd`, `pickup.gd` | Space objects. |

Saves go to `user://voxel_voyager_save.json`. The save holds only progress and the blocks you changed, because the universe itself is regenerated from seeds.
