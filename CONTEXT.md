# Flor do Mar Context

Flor do Mar is a naval battle game set in the 15th- and 16th-century Indian Ocean, focused on tactical ship combat between historical maritime powers.

## Product Direction

The player commands a single ship in tactical real-time combat. Moment to moment, the player reads the wind, maneuvers for position, chooses when to fire or board, and triggers crew-member abilities at decisive moments.

The combat model is inspired by EVE Online more than arcade action games. The player wins through range control, heading, speed, firing arcs, reload timing, target selection, loadout choices, and ability timing rather than reflex aiming.

This is also an architectural choice. Flor do Mar favors command-based real-time combat because it can be simulated through a server-like API, tested locally, synchronized predictably, and later moved to an authoritative multiplayer server.

## First Playable Scope

The first playable tracer bullet is a minimal duel:

- One Portuguese caravela versus one Portuguese caravela
- Open water
- Same hull, same guns, same starting crew
- Fixed-tick combat simulation
- Local server-like combat API
- Browser client implemented with Haskell Reflex
- WebGL battle rendering behind a Reflex-friendly wrapper
- Player can issue a heading or sail command
- Player can fire one broadside when range and firing arc allow it
- Broadside damage is fixed hull damage after a reload cooldown
- A ship wins when the opposing ship's hull integrity reaches zero

This scenario exists to prove the architecture and combat loop, not historical variety, balance, campaign structure, or visual polish.

## Technology Direction

Flor do Mar uses Haskell for all first-party code.

The browser client is built with Reflex / reflex-dom. WebGL is used for the tactical battle view, but it should sit behind a small rendering layer at the edge of the system. The combat simulation should not depend on the browser or WebGL.

The frontend should talk to combat through a server-like API. Early development uses an in-process local implementation so scenarios are easy to test and play. Later multiplayer can replace that local implementation with real API calls to an authoritative server while preserving the same command and snapshot model.

## Core Terms

- **Combat simulation**: The authoritative combat rules and state transition logic.
- **Combat API**: The boundary used by the frontend to start scenarios, submit commands, and observe combat state.
- **Local Combat API**: An in-process implementation of the Combat API used for local playtests and frontend development.
- **Remote Combat API**: A future networked implementation of the same API for multiplayer.
- **Scenario**: A predefined combat setup, including ships, positions, wind, and initial state.
- **Command**: Player intent submitted to the Combat API, such as issuing a navigation order or firing a broadside.
- **Navigation order**: A movement command that tells a ship which waypoint to reach and what speed to target after reaching it. Avoid: direct steering.
- **Autopilot**: A non-player behavior that issues navigation orders using the same movement model available to player commands. Avoid: special enemy movement.
- **Orbit**: An autopilot pattern that keeps issuing navigation orders around a fixed center point.
- **Waypoint**: A point in battle space that a navigation order asks a ship to reach. Avoid: target point, destination.
- **Arrival radius**: The area around a waypoint where a ship is considered to have reached it. Avoid: exact point arrival.
- **Post-waypoint speed**: The speed a navigation order targets after the ship reaches its waypoint. It is continuous from stopped to the ship's maximum speed, and may be chosen explicitly or inherit the ship's arrival speed.
- **Speed ring**: A tactical battle view marker anchored to the reachable waypoint that compares expected or selected post-waypoint speed with the ship's maximum speed. Avoid: max speed circle, speed circle.
- **Projected trajectory**: The expected path a ship will follow from its current movement state under a navigation order. It should account for speed and maneuvering limits, and should match actual movement unless battle conditions change before or during execution.
- **Kinematically constrained trajectory planner**: The movement planner that produces projected trajectories within a ship's speed, acceleration, deceleration, rudder authority, and turn-radius limits. Avoid: direct cursor path, candidate-only steering.
- **Turn speed**: The fastest speed at which a ship can follow the required curve toward a waypoint. It is constrained by the ship's turn rate and maximum speed.
- **Rudder authority**: How strongly a ship can change heading at a given speed. It may be absent when stopped, strongest around the ship's ideal turn speed, and limited by the ship's turning characteristics at high speed.
- **Yaw inertia**: Resistance to changes in a ship's turn rate. A ship accelerates into and out of its maximum yaw rate instead of changing turn rate instantly, and may retain ship-specific handling factors even if mass is modeled later.
- **Ideal turn speed**: The speed where a ship has full rudder authority. Above this speed the ship may still move faster, but its turning radius grows.
- **Snapshot**: A read model of combat state suitable for UI rendering.
- **Tactical battle view**: The player-facing representation of combat used to read ship positions, headings, range, and battle state.
- **Tick**: The fixed simulation step. Commands are applied on ticks.
- **Caravela**: The first ship type used by the minimal playable scenario.
- **Hull integrity**: The initial win/loss resource. A ship is disabled when hull integrity reaches zero.
- **Broadside**: A firing action that applies hull damage if the target is within range and firing arc.
- **Firing arc**: The permitted angle from which a broadside can hit a target.
- **Reload cooldown**: The delay before the same broadside can be fired again.
- **Wind**: A tactical environmental factor that affects movement and positioning.
- **Crew ability**: A future activated ability provided by a crew member.
- **Loadout**: The ship configuration chosen before battle, eventually including hull, guns, sails, rigging, officers, crew, cargo, and special capabilities.

## Deferred Concepts

These matter to the full game, but are out of scope for the first tracer bullet:

- Boarding resolution
- Crew casualties
- Morale
- Capture
- Ammunition types
- Critical hits
- Projectile travel time
- Accuracy modeling
- Historical faction asymmetry
- Ship loadout UI
- Campaign, economy, persistence, accounts, matchmaking, and multiplayer infrastructure

## Design Constraints

- Preserve simulation and rendering separation.
- Keep the combat command model compatible with future server synchronization.
- Prefer deterministic or replayable scenarios for testing.
- Do not make the first slice reflex-heavy or aim-based.
- Use Portuguese caravela versus Portuguese caravela as the initial scenario until the core loop is working.
