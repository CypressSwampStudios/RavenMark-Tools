# RavenMark — Build Notes

Build date: 2026-07-06. Written by Claude Code at the end of the initial one-pass build.

**None of this has been tested in a live WoW client.** That isn't possible from a coding session — there is no in-client verification here. Treat this as a complete, structurally sound first draft; budget a real testing pass (see the suggested order at the bottom) and expect the client's Lua error output to surface something.

---

## 1. Files created

| File | What it is |
|---|---|
| `LibStub/LibStub.lua` | Canonical public-domain LibStub (see §2.1) |
| `LibRavenExport-1.0/LibRavenExport-1.0.lua` | Record schema + SavedVariables persistence |
| `LibRavenChrome-1.0/LibRavenChrome-1.0.lua` | Visual skin: panels, rows, chips, tabs, buttons, checkboxes |
| `LibRavenDock-1.0/LibRavenDock-1.0.lua` | Docking, slots, strip, drag/snap, callbacks, standalone fallback |
| `RavenMarkCore/RavenMarkCore.toc` | Core TOC |
| `RavenMarkCore/Core.lua` | Bootstrap, DB defaulting, `/rmcore` |
| `RavenMarkCore/Rail.lua` | The Rail frame, tabs, badges |
| `RavenMarkCore/Options.lua` | Settings canvas panel |
| `RavenMarkRoster/RavenMarkRoster.toc` | Roster TOC |
| `RavenMarkRoster/Roster.lua` | GROUP_ROSTER_UPDATE watcher, snapshots |
| `RavenMarkRoster/RosterUI.lua` | Roster panel |
| `RavenMarkAttendance/RavenMarkAttendance.toc` | Attendance TOC |
| `RavenMarkAttendance/Attendance.lua` | ENCOUNTER_START/END watcher, pull counters |
| `RavenMarkAttendance/AttendanceUI.lua` | Pull log panel + session summary |
| `RavenMarkLoot/RavenMarkLoot.toc` | Loot TOC |
| `RavenMarkLoot/Loot.lua` | CHAT_MSG_LOOT parsing + ENCOUNTER_LOOT_RECEIVED |
| `RavenMarkLoot/LootUI.lua` | Loot history panel |
| `RavenMarkBench/RavenMarkBench.toc` | Bench TOC |
| `RavenMarkBench/Bench.lua` | Manual bench state, persistence |
| `RavenMarkBench/BenchUI.lua` | Bench toggle panel |
| `RavenMarkReady/RavenMarkReady.toc` | Ready TOC |
| `RavenMarkReady/Ready.lua` | Manual readiness scan, editable buff table |
| `RavenMarkReady/ReadyUI.lua` | Readiness panel + check button |
| `*/Libs/**` | Embedded copies of the four lib files, per WoW convention |
| `.luarc.json` | Declares WoW API globals for lua-language-server (editor-only) |
| `README.md`, `BUILD_NOTES.md` | Docs |

## 2. Decisions made on genuine ambiguities

1. **LibStub is embedded.** The spec says "no LibStub-hosted third-party libraries beyond the three we're writing ourselves" while also specifying that our three libraries are LibStub-versioned. LibStub itself is the ~40-line public-domain versioning stub that makes that possible; it's embedded in every `Libs/` folder and loaded first in each TOC. It is not a dependency risk in the Ace3 sense — it's the standard mechanism the spec's own duplication argument ("LibStub means only the newest copy runs") relies on.
2. **`Export:Init(db, source)` takes an explicit source name.** The spec shows `Export:Init(RavenMarkRosterDB)`, but the library is one shared instance across five addons, so a bare Init can't know which addon's records table it was handed. Each addon passes its own name; `Emit` also routes each record type to its owning addon via an internal map, so the envelope's `source` field is always correct even if another addon calls Emit for a type it doesn't own.
3. **Slot capacity semantics.** "Only left-upper/left-lower support two simultaneously expanded panels; anything else queues into strip" was read as: at most **two panels expanded at once**, auto-assigned to left-upper/left-lower; right-upper/right-lower exist as valid positions (RequestDock accepts them, snap targets include them) but the global two-panel cap still applies, and anything past it queues into the strip. When an expanded slot frees, the oldest strip occupant is promoted. Clicking a strip module's tab when both slots are full evicts the longest-docked panel.
4. **Default visibility.** With Core installed, modules dock (and therefore show) on login per their saved state. Standalone, module windows start hidden and are opened with their slash command (`/rmroster`, `/rmatt`, `/rmloot`, `/rmbench`, `/rmready`) — less intrusive than five floating windows appearing on first login.
5. **Bench→Roster sync.** Addons can't reach each other's private namespaces, so Roster exposes one global function (`RavenMarkRoster_QueueSnapshot`) that Bench calls after a toggle to keep Roster's chips in sync. Bench reads `RavenMarkRosterDB.lastSnapshot` (Roster keeps its latest snapshot there) rather than re-implementing roster reading, with a minimal direct group scan as the standalone fallback.
6. **raidId survives the session, not a /reload.** Per spec the current raidId lives in-memory only, so a mid-raid `/reload` mints a fresh raidId and one raid night's records split across two ids. Downstream tooling should be prepared to merge raidIds with close timestamps and the same instance suffix. Persisting it (with an expiry) is a clean v1.1 fix if this bites.

## 3. Flagged as uncertain against the 12.0.7 API surface

Check these first when testing in-client — they're the likeliest breakage points:

1. **`## Interface: 120007`** — used as instructed. Verify with `/dump select(4, GetBuildInfo())` in-client; hotfix patches tick this forward often.
2. **`Settings.RegisterCanvasLayoutCategory` / `Settings.RegisterAddOnCategory`** (`RavenMarkCore/Options.lua`) — the modern Dragonflight+ registration path. The call is guarded: if the API is missing/renamed, Core prints a notice and `/rmcore` still covers everything. If it silently registers but the panel misbehaves, this is the spot.
3. **`ENCOUNTER_LOOT_RECEIVED`** (`RavenMarkLoot/Loot.lua`) — assumed arg order `(encounterID, itemID, itemLink, quantity, playerName, className)`. The RegisterEvent call is pcall-guarded so a renamed event can't break the addon; the CHAT_MSG_LOOT path covers loot regardless. If personal loot shows up doubled or missing, verify this event's name and args.
4. **`GetLootMethod()`** — may be defunct in the personal-loot era. Wrapped in pcall with `"personal"` as the fallback `lootMode`.
5. **Spec-of-others is NOT available without inspect.** `GetSpecialization`/`GetSpecializationInfo` only cover the player. Everyone else would need the async `NotifyInspect` + `INSPECT_READY` flow (rate-limited, unreliable mid-raid) — deliberately out of v1 scope. Roster records `spec` only for the player and `nil` for others; no fake data. The panel falls back to showing assigned role.
6. **Durability of other players is not readable.** `GetInventoryItemDurability` works for the player only. Ready checks flask/food buffs for the whole group but durability for the player alone.
7. **Aura scanning range.** Aura reads on raid units only work for units in range/loaded; out-of-range or offline members can false-flag as missing consumables. Offline members are skipped via `UnitIsConnected`; range is not detectable cheaply and is accepted as a v1 limitation.
8. **`UnitAura` vs `C_UnitAuras`** — modern clients removed `UnitAura`; Ready uses `C_UnitAuras.GetAuraDataByIndex` first with a `UnitAura` fallback.
9. **`texture:SetGradient` signature** — the ColorMixin form (`SetGradient("HORIZONTAL", CreateColor(...), CreateColor(...))`) is used, guarded with a solid-color fallback if either the method or `CreateColor` is missing.
10. **Ready's consumable list is a placeholder.** `NS.CONSUMABLE_BUFFS` at the top of `Ready.lua` ships with the last-verified retail flask names (The War Within tier) plus `"Well Fed"`. **These are almost certainly stale for Midnight** — it's an obvious, editable table and updating it is the expected first customization.
11. **CHAT_MSG_LOOT patterns** are generated at runtime from the client's own `LOOT_ITEM`, `LOOT_ITEM_SELF`, `LOOT_ITEM_MULTIPLE`, `LOOT_ITEM_SELF_MULTIPLE` globals, so they're locale-safe — but only those four forms are handled. Pushed/rolled variants (`LOOT_ITEM_PUSHED_SELF` etc.) aren't parsed in v1.
12. **Cross-realm name forms.** `GetRaidRosterInfo` returns `Name-Realm` for cross-realm members, plain `Name` otherwise. Bench keys its state by whatever the roster snapshot contains; a same-name-different-realm collision in a cross-realm raid is theoretically possible.
13. **Frame scale in snap math.** Snap distance is computed in unscaled screen coordinates; if a module frame's effective scale differs from the Rail's, the threshold will feel slightly off. Cosmetic at worst.

## 4. Suggested in-client test order

1. **Core alone.** Confirm the Rail renders (electric-blue lit edge, corner brackets), drags when unlocked, `/rmcore lock|unlock|reset` works, position survives `/reload`, and the options panel appears under Settings → AddOns → RavenMark.
2. **Core + Roster.** Confirm Roster auto-docks into `left-upper`, the tab appears on the Rail, and joining/leaving a party fires snapshots (rows with class-colored bars). Check `RavenMarkRosterDB.records` accumulates `roster_snapshot` records after logout.
3. **Roster standalone** (disable Core). Confirm `/rmroster` opens a floating, draggable window and its position survives `/reload`.
4. **Docking mechanics.** Drag a docked panel off the Rail (it should float), drag it back within ~40px of an open slot (snap preview should appear, release to snap). Collapse via tab click; confirm the strip appears under the Rail and clicking a strip cell re-expands.
5. **Attendance.** Any encounter works — a normal dungeon boss fires ENCOUNTER_START/END. Confirm a pull row appears with kill/wipe and duration, and pull numbers increment per boss.
6. **Loot.** Kill anything in a group that drops an item. Confirm the item appears with its real quality color and the recipient is right. Watch for doubled entries (dedupe window is 5s) — if personal loot doubles, see §3.3.
7. **Bench.** Toggle someone, `/reload`, confirm the state held and Roster's chip shows BENCH.
8. **Ready.** With and without a flask, hit Check Readiness; confirm flags and the clear count. Then update `NS.CONSUMABLE_BUFFS` for current-tier names.
9. **All six together**, then export sanity: log out and verify each addon's SavedVariables file contains well-formed records sharing one raidId for the night.
