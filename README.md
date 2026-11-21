# Carnage Karts (Godot 4)

Six cute critters, low-poly cel-shaded kart racing, very messy finishes. This is the Godot 4 version of the [browser game](https://github.com/corysyx/critter-carnage-karts).

**Play in your browser:** https://corysyx.github.io/carnage-karts-godot/

## Open the project

1. Install **Godot 4.7** (standard build, no .NET needed).
2. In the Project Manager, choose **Import**, pick this folder's `project.godot`, then **Run** (F5).

It uses the **Compatibility** renderer so the same project runs on desktop, phones and the web.

## Menus and modes

**Play → mode → critter → track → race.** Settings are on the title screen.

| Mode | What it is |
|---|---|
| Quick Race | One race on any track against five critters. |
| Grand Prix | All four tracks in a row; 10, 8, 6, 4, 2, 1 points per race, then a final podium. |
| Time Trial | Just you, no items. Best time per track is saved. |

**Critters** each have their own speed, acceleration and handling (see `scripts/critters.gd`).

**Tracks** (`scripts/tracks.gd`): Meadow Loop, Candy Canyon, Frosty Peaks, Sunset Shores. Each is generated from a seed and dressed by its theme (terrain shape, colours, trees, sky). Add a track by copying an entry and changing its seed and colours.

**Settings** (saved): gore, AI difficulty, laps (1 to 5), sound volume, CRT filter, anti-aliasing, shadows.

## Controls

| | Keyboard | Phone |
|---|---|---|
| Drive | W / Up (gas), S / Down (brake) | Always drives itself; hold **BRAKE** |
| Steer | A D / Left Right | Touch anywhere on the left half and slide |
| Drift: press to hop, hold + steer to slide; release on blue / orange / pink sparks for a mini / super / ultra mini-turbo. Steer into the bend to charge faster and tighten the line, away to widen it; braking cancels | Shift / C | **DRIFT** |
| Use item | Space / X | **ITEM** |
| Aim item forward / back | hold Up / Down while firing | push the joystick up / down |
| Swap item slot | Q / Tab | tap a slot at the top |
| Back to track | R | automatic |
| Pause | P / Esc | **II** |

## Items

| Item | What it does |
|---|---|
| Carrot Rocket | Homes in on the racer ahead (or behind, if aimed back). Gory. |
| Buzz Saw | Flies straight and ricochets off fences. Gory. |
| Spike Mine | Dropped behind, or lobbed ahead. Gory. |
| Slime Puddle | Spins out whoever hits it. |
| Sugar Rush | Speed boost. |
| Bubble Shield | Blocks one hit. |

You can carry two items. Gore can be set to Off, On or Extra on the menu.

## How it's built

Everything is generated from a seed when the game starts. There are no model or texture files yet.

| File | What it does |
|---|---|
| `scripts/tracks.gd` | The four track themes. |
| `scripts/world_gen.gd` | Spline track, terrain, road and kerbs, picket fences, lakes (open edges only along big lakes), trees, distant hills and clouds. Also answers ground-height and distance-from-road questions for physics. |
| `scripts/critters.gd` | The six low-poly critters and karts, built from simple shapes. |
| `scripts/kart.gd` | Arcade kart physics, fence collision, jumps, water, laps, AI steering and model animation. |
| `scripts/race.gd` | Game flow, camera, item boxes, weapons and projectiles, AI item use. |
| `scripts/gore.gd` | Blood, chunks, eyeballs, sparks, splashes, and blood pools and tyre tracks that stay on the road. |
| `scripts/hud.gd` | HUD, menus, results, CRT overlay and touch controls. |
| `shaders/toon.gdshader` | Cel shading: banded light, optional faceted normals, grazing-angle ink. |
| `shaders/outline.gdshader` | Ink outline shells around models. |
| `shaders/ink_post.gdshader` | Screen-space ink lines from the depth buffer. |
| `assets/sfx/el/` | Sound effects generated with ElevenLabs (several takes per sound, picked at random). |
| `tools/make_sfx.py` | Synthesises the sound effects into `assets/sfx/` (`python3 tools/make_sfx.py`, needs numpy). |

Run a headless simulated race: `godot --headless --fixed-fps 60 -- --autotest --mode=quick|gp|tt --map=0..3`

## Editor add-ons (included)

These are editor tools for dressing levels and are not part of the game build.

- **[ProtonScatter](https://github.com/HungryProton/scatter)** (MIT): paint or scatter trees, rocks and props over terrain and along paths.
- **[Godot Asset Placer](https://github.com/levinzonr/godot-asset-placer)** (MIT): a palette for browsing and placing 3D assets (for example models made with Meshy) in the editor.

## Updating the web build

**Project → Export → Web → Export Project** writes straight into `docs/`. Commit and push, and GitHub Pages updates in about a minute. The build is single-threaded, so it needs no special server headers.

## Credits

Font: [Fredoka](https://github.com/hafontia/Fredoka-One), SIL Open Font License (`assets/fonts/OFL.txt`).
