# RavenMark

A small suite of raid-ops addons for World of Warcraft — roster, attendance, loot, bench, and pre-pull readiness, each useful on its own, and all of them dock together into one custom HUD if you run more than one.

Built clean-room from scratch. Non-combat only, so none of it is touched by Midnight's combat-state API restrictions.

## The suite

| Addon | Does |
|---|---|
| **RavenMark Core** | The dock shell (`the Rail`). Optional — everything else works standalone without it. |
| **RavenMark Roster** | Live raid/group snapshots — who's in, spec, role, active/bench. |
| **RavenMark Attendance** | Attendance tied to the actual pull, not just "was in group at some point." |
| **RavenMark Loot** | Clean loot history. Item, recipient, source. No DKP math. |
| **RavenMark Bench** | Officer-curated standby tracking, visible over time. |
| **RavenMark Ready** | Pre-pull flask/food/durability check, on demand. |

Install just the one you need, or run all six and dock them into a single HUD along the Rail — drag any module off to float it, drag it back near the Rail to snap it back in.

## Status

Early. This is a first build pass and has not yet been verified in a live client — expect rough edges. See `BUILD_NOTES.md` for what's been flagged as needing a closer look, and open an issue if something's broken.

## Installation

1. Download or clone this repo.
2. Copy whichever addon folder(s) you want (`RavenMarkCore`, `RavenMarkRoster`, etc.) into `World of Warcraft/_retail_/Interface/AddOns/`.
3. Each folder is fully self-contained — no separate library download needed.
4. Relaunch or `/reload`.

Retail only, current Midnight patch line.

## Architecture, briefly

Every module is built on three small shared libraries, embedded in each addon folder:

- **`LibRavenDock-1.0`** — handles docking into the Rail, or falls back to a normal floating window if Core isn't installed.
- **`LibRavenExport-1.0`** — every module writes structured records (roster snapshots, encounters, loot, bench changes, readiness checks) into a common schema, threaded together by a shared `raidId` per lockout.
- **`LibRavenChrome-1.0`** — the shared visual skin, so every panel looks and feels like one suite instead of five separate addons bolted together.

Data stays local to SavedVariables — WoW addons have no networking capability, so there's no phone-home, no telemetry, nothing leaving your machine.

## Design

Dark, sci-fi command-bridge aesthetic. Electric blue accents, chrome-silver text, corner-bracket panel styling.

## Why this exists

RavenMark is a standalone project, not tied to any paid product. It's built and maintained because the raid-ops addon space has a lot of great tools that quietly went unmaintained, and there's room for a modern, actively-supported take.

## Credits

Built by **CypressSwampStudios**. Not a fork or continuation of any existing addon — RavenMark's feature set is inspired by gaps in the raid-tracking addon space generally, but every line here is original.

## License

TBD — will be published before the first public release. RavenMark will always remain free to use, per Blizzard's addon policy.

## Contributing

Issues and PRs welcome once the first tagged release is out. If you hit a bug testing an early build, open an issue with your client version and the exact error text from `/console scriptErrors 1`.
