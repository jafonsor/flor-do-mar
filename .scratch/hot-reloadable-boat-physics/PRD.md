# PRD: Hot Reloadable Boat Physics and Engagement Setup

Status: ready-for-agent

## Problem Statement

The current tactical combat loop is useful as a first tracer bullet, but the core feel of ship movement is still hard-coded. Sail state maps directly to constant speed, heading commands rotate ships instantly, broadside tuning values are fixed in code, and the local scenario always uses the same ship definitions.

The developer needs a way to tune the first movement physics quickly while the local client is running. They also need ship definitions to become runtime configuration so a large boat and a small boat can feel and look different without recompiling. The design must preserve the existing command-based, fixed-tick combat architecture so the same model can later support a remote authoritative server.

## Solution

Add runtime TOML configuration for global physics and boat kinds. The local client loads this configuration on startup, validates it, starts a default engagement, and in dev mode polls for config changes every 500ms. Valid config changes hot reload into the running app. Invalid hot reloads print detailed diagnostics to the server console and keep the last valid config active.

The first physics pass focuses on movement: acceleration, deceleration, max speed, battle speed, turn rate, and per-boat low-speed turning authority. A ship has both a current heading and a target heading. Heading commands update the target heading, and the ship turns toward it over time. Sail commands update the target speed, and the ship accelerates or decelerates toward that speed over time. Movement values are configured as per-second values, while the simulation remains fixed-tick.

Add a setup overlay opened with Escape. The default engagement starts automatically. Pressing Escape pauses the engagement and opens the setup screen. The setup screen lets the developer choose the player boat kind and enemy boat kind from the loaded boat configs. Pressing Launch Engagement restarts the engagement using the selected setup. The roster shape is locked during an engagement; for this first pass the roster is one player boat and one enemy boat.

## User Stories

1. As a developer, I want boat movement values to live in config files, so that I can tune ship feel without editing Haskell code.
2. As a developer, I want config changes to hot reload in dev mode, so that I can iterate on movement values while watching the battle.
3. As a developer, I want hot reload polling to run every 500ms, so that config edits feel responsive.
4. As a developer, I want invalid hot reloads to keep the last valid config active, so that a typo does not break the running engagement.
5. As a developer, I want invalid startup config to fail fast, so that the game never starts from an undefined configuration.
6. As a developer, I want validation errors to print to the server console with file location and explanation, so that I can fix config mistakes quickly.
7. As a developer, I want config validation to report parser errors with line and column when available, so that syntax mistakes are easy to locate.
8. As a developer, I want config validation to report semantic field errors in plain English, so that invalid values are actionable.
9. As a developer, I want the physics tick duration to be configurable, so that I can tune the pace of the simulation.
10. As a developer, I want hot reloading tick duration to update the client tick cadence, so that pacing changes apply immediately after a valid reload.
11. As a player, I want a ship to accelerate toward its sail target speed, so that movement has momentum.
12. As a player, I want a ship to decelerate toward its sail target speed, so that slowing down feels physical rather than instant.
13. As a player, I want Sails Furled to target zero speed, so that furling sails eventually stops the boat.
14. As a player, I want Battle Sails to target a configured battle speed, so that maneuvering speed can differ from full travel speed.
15. As a player, I want Full Sails to target configured max speed, so that committing to speed has a clear effect.
16. As a player, I want heading commands to set a target heading, so that the ship turns over time instead of snapping instantly.
17. As a player, I want broadside firing arcs to use the current physical heading, so that combat checks reflect where the hull actually points.
18. As a player, I want the battle view to show current heading and target heading, so that I can see both the ship's orientation and helm intent.
19. As a developer, I want target heading to be represented in snapshots, so that rendering does not need to read simulation internals.
20. As a developer, I want current speed to be represented in snapshots, so that the UI can expose movement state.
21. As a developer, I want boat size to come from boat config, so that big and small boats are visually distinct.
22. As a player, I want the large boat to render larger than the small boat, so that boat choice is obvious in the tactical battle view.
23. As a developer, I want each boat kind to define hull, movement, size, and broadside tuning, so that the main tuning surface is externalized.
24. As a developer, I want boat config IDs to match their asset names, so that copy-paste mistakes are caught during validation.
25. As a developer, I want the default engagement to start automatically, so that running the client immediately shows the combat loop.
26. As a developer, I want the default engagement to use a big player boat and a small enemy boat, so that the two configured boat kinds are exercised immediately.
27. As a player, I want Escape to pause the engagement and open setup, so that I can adjust the next engagement without time advancing.
28. As a player, I want the setup overlay to choose player and enemy boat kinds, so that I can compare big versus small combinations.
29. As a player, I want Launch Engagement to restart the fight using selected boat kinds, so that roster changes are explicit.
30. As a developer, I want boat kind selection to be locked for the current engagement, so that hot reload does not silently replace one kind with another mid-fight.
31. As a developer, I want live boats to stay linked to their boat kind config, so that valid config edits affect matching live boats during the fight.
32. As a developer, I want live instance state to stay separate from boat config, so that hot reload does not reset damage, speed, reload, position, or heading.
33. As a developer, I want max hull changes to preserve damage taken, so that changing hull config does not heal or re-damage boats arbitrarily.
34. As a developer, I want deleted or invalid config during hot reload to keep the game running, so that experimentation is low risk.
35. As a developer, I want config files to be runtime assets, so that production can read them at startup even if hot reload is dev-only.
36. As a developer, I want wind to default to zero for now, so that wind does not complicate the first movement tuning pass.
37. As a developer, I want the enemy boat to keep simple fixed heading intent for now, so that movement physics can be tuned before adding AI.
38. As a future multiplayer implementer, I want this feature to preserve the command and snapshot model, so that later remote control can reuse the same combat boundary.

## Implementation Decisions

- Preserve the existing architectural boundary: combat simulation owns authoritative rules and state transitions; the Reflex client submits commands and renders snapshots.
- Preserve fixed-tick simulation. Player commands are still applied through the combat API and take effect on ticks.
- Introduce runtime TOML config assets for global physics and boat kinds.
- Global physics config includes `tick_seconds`.
- Boat config includes stable id, display name, body values, movement values, and combat values.
- Body values include max hull, rendered length, and rendered width.
- Movement values include battle speed, max speed, acceleration, deceleration, turn rate, and minimum turn speed factor.
- Combat values include broadside range, broadside damage, reload ticks, and firing arc degrees.
- Movement speed values are expressed in world units per second.
- Acceleration and deceleration are expressed in world units per second squared.
- Turn rate is expressed in degrees per second.
- The heading arrival epsilon is a small code constant, not a config field.
- `minimum_turn_speed_factor` belongs to boat config because low-speed turning authority is part of boat feel.
- Wind remains structurally present but defaults to zero and does not need a configurable movement factor in this pass.
- Config IDs must match the corresponding boat config asset name.
- Startup config load is strict. Invalid or missing required config at startup prints diagnostics and exits.
- Dev hot reload uses simple polling every 500ms rather than a filesystem watcher dependency.
- Hot reload updates the active config store only after parsing and validation both succeed.
- Hot reload failures keep the last valid config active.
- Validation diagnostics are printed to the server console where the local client is running.
- Diagnostics should include filename, line and column for parser errors when available, field path for semantic errors, an explanation, and a fix hint where practical.
- The local client enables dev hot reload for the local playtest workflow.
- Production runtime can read config once at startup without polling.
- Combat state stores live instance state separately from config data.
- Live ship instances reference a boat kind. The selected boat kind is fixed for the engagement.
- Live boat config values are resolved from the current valid config by boat kind on each tick or at an equivalent authoritative simulation seam.
- Live instance state includes position, current heading, target heading, sail state, current speed, reload state, and damage taken.
- Current hull is derived from the current boat kind max hull minus damage taken, clamped at zero.
- If max hull changes during hot reload, the live boat keeps damage taken and recalculates current hull from the new max hull.
- `SetHeading` updates target heading rather than current heading.
- Current heading turns toward target heading by at most the effective turn rate for the tick.
- Effective turn rate uses boat turn rate, tick seconds, current movement state, and the boat's minimum turn speed factor.
- Firing arc checks use current physical heading, not target heading.
- Sail commands update sail state, which determines target speed.
- Sails Furled targets zero speed.
- Battle Sails targets configured battle speed.
- Full Sails targets configured max speed.
- Current speed moves toward target speed using acceleration or deceleration according to tick seconds.
- Ship movement advances from current heading and current speed over tick seconds.
- Snapshots expose boat kind, display name, max hull, current hull, current speed, current heading, target heading, length, width, sail state, position, reload, and status needed by the UI.
- The battle renderer uses snapshot length and width for ship body scale.
- The battle renderer shows a target heading marker in addition to the current heading marker.
- The setup screen is an overlay, not a separate route.
- The default engagement starts automatically when the client launches.
- Escape toggles the setup overlay and pauses simulation while open.
- Hot reload continues while the setup overlay is open.
- Pressing Launch Engagement restarts the engagement using the selected player and enemy boat kinds.
- The first setup UI supports exactly one player boat and one enemy boat.
- The first setup UI offers the configured big and small boat kinds.
- Do not introduce a controller API yet. More complex AI, remote-player control, and controller abstractions are deferred until AI behavior becomes more meaningful.
- Enemy behavior for this pass is simple fixed heading intent with the same movement physics as the player.

## Testing Decisions

- Tests should focus on externally visible behavior: snapshots, command effects, config loading results, validation diagnostics, and render scene output.
- The highest existing simulation seam is the pure combat tick transition. Movement physics should be tested through this seam with in-memory valid config values.
- The highest existing API seam is the local combat API. Engagement startup, command queuing, tick advancement, and snapshots should continue to be tested through this boundary.
- Add config loader tests at the new config loading seam. These tests should cover successful startup load, parse failure, validation failure, id mismatch, missing required config, and last-valid behavior during hot reload.
- Add tests that heading commands update target heading immediately while current heading changes gradually over ticks.
- Add tests that firing arc checks continue to use current heading.
- Add tests that sail commands change target speed behavior and current speed approaches the configured target through acceleration or deceleration.
- Add tests that movement values are interpreted per second by verifying behavior under different tick durations.
- Add tests that hot reloading tick seconds affects the local client's tick interval at the integration seam if the tick interval is extracted into testable logic.
- Add tests that boat config changes apply to live boats of the same kind without changing live instance state.
- Add tests that changing max hull preserves damage taken and recalculates current hull correctly.
- Add tests that invalid hot reload keeps the last valid config and does not mutate active combat state.
- Add tests that startup invalid config fails rather than silently falling back.
- Add snapshot tests for current speed, target heading, boat kind, size, and derived hull fields.
- Extend existing render-scene tests to assert configured ship size and the target heading marker.
- Existing combat tests provide prior art for testing pure domain behavior, local combat API behavior, and render-scene conversion without browser DOM tests.
- Avoid testing Reflex DOM mechanics directly unless setup overlay state is extracted into a pure model. If extracted, test pause, Escape toggle, selected boat kinds, and launch restart behavior through that pure model.
- Manual verification should include running the local client, editing valid boat TOML values, confirming movement and size update, entering invalid TOML, confirming console diagnostics, and confirming the engagement keeps running with the last valid config.

## Out of Scope

- Multiple boats per side.
- Target selection UI.
- Multi-target broadside logic.
- Collision physics.
- Projectile travel time.
- Wind-driven movement effects.
- Complex enemy AI.
- A boat controller API for AI or remote players.
- Multiplayer networking.
- Historical realism or historically accurate ship classes.
- Boarding, morale, crew casualties, capture, ammunition types, critical hits, and loadout UI.
- Production-grade filesystem watcher integration.
- Persisting setup choices across app launches.

## Further Notes

- The project already favors EVE-style command combat rather than reflex-heavy arcade control. This feature should deepen that direction by making ship movement feel physical while preserving deterministic, testable fixed-tick combat.
- The setup overlay is for engagement setup and dev iteration. It should not become a campaign/loadout screen in this PRD.
- The first configured boat kinds are intentionally mechanical: big and small. They are not historical classes yet.
- The PRD assumes the current combat API and pure tick transition remain the main test seams, with a new config loading seam added for TOML parsing, validation, and hot reload state.
