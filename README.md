# roblox-qwop

A multiplayer, QWOP-style ragdoll running **race**. Everyone in the server runs
on one shared, side-scrolling track and the first to flop across the finish line
wins. Built with [Rojo](https://github.com/rojo-rbx/rojo).

## Controls

| Key | Action |
| --- | --- |
| **Q** | right thigh forward / left thigh back |
| **W** | left thigh forward / right thigh back |
| **O** | right knee flex / left knee extend |
| **P** | left knee flex / right knee extend |
| **R** | respawn your runner at the start of your lane (mid-race rescue) |

Alternating **Q/W** and **O/P** produces a stumbling gait — the chaos is the point.

## How it plays

The server runs a continuous race loop for whoever is present:

```
Intermission  ->  Countdown (3-2-1)  ->  Racing  ->  Results  ->  (repeat)
```

- Each player gets their own rig in a separate **Z lane**, so runners never
  collide but all stay visible from the side camera.
- The camera frames the whole pack when runners are bunched (the usual case)
  and falls back to following you if the pack spreads past what fits on screen.
- The HUD shows the race phase / countdown, your distance, and a live
  leaderboard.

## Project layout

| Path | Role |
| --- | --- |
| [src/shared/Config.luau](src/shared/Config.luau) | All tuning: rig sizes, motor torques, key map, race timing, camera. Server and client both read it. |
| [src/server/RigBuilder.luau](src/server/RigBuilder.luau) | Assembles a runner from parts: hip/knee `HingeConstraint` motors, welded feet/head, an `AlignOrientation` plane-lock, and a collision group so a rig never collides with itself or others. |
| [src/server/init.server.luau](src/server/init.server.luau) | Game manager: race state machine, track + finish line, per-player rigs, network ownership, remotes. |
| [src/client/init.client.luau](src/client/init.client.luau) | Reads input and drives the local rig's hinges, the adaptive side camera, and the HUD/leaderboard. |

### The rig

`Torso -> (Right/Left) Thigh -> Calf -> Foot`, plus a Head. Hips and knees are
velocity-driven hinge motors (axis = world Z); feet and head are rigid welds.
The torso's `AlignOrientation` pins it to its X-Y running plane so the runner can
pitch and fall forward/back but not topple sideways or spin. Each player owns the
network physics of their own rig, so input has no latency.

### Swapping in custom art

The rig is built from primitive `Part`s on purpose. To drop in custom character
assets later, keep the part **names**, the `Hinges` folder, and the tag/attribute
wiring in `RigBuilder`, and replace (or parent meshes under) the visual parts.

## Getting started

Build the place file:

```bash
rojo build -o "roblox-qwop.rbxlx"
```

Open `roblox-qwop.rbxlx` in Roblox Studio, then live-sync with:

```bash
rojo serve
```

Tune feel in `Config.luau` (motor torques/speeds, hinge limits, lane spacing,
race timing). Physics constants are starting points — expect to adjust torques
and limits in Studio.

## Tooling notes

This project is Luau. The workspace `.vscode/settings.json` makes
[luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) the sole language server
and silences the plain-Lua servers (sumneko, the deprecated robloxlsp), which
otherwise flag valid Luau syntax (`+=`, `continue`, type annotations) as errors.
