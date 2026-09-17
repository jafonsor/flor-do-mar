# PRD: Project Kickoff

Status: ready-for-agent

## Summary

Build the first playable architecture slice of Flor do Mar: a Haskell Reflex browser client starts a local combat scenario through a server-like API, renders two Portuguese caravelas in WebGL, advances a fixed-tick simulation, accepts a heading or sail command, and resolves a broadside when range and firing arc allow it.

## Problem

Flor do Mar needs to prove its core architecture before expanding into historical factions, loadouts, crew abilities, or multiplayer. The important risk is not content volume; it is whether a browser-based Haskell Reflex client can drive and render a server-shaped naval combat simulation in a way that remains testable and replaceable by a future networked server.

## Target User

The initial target user is the developer-playtester. They need a minimal playable scenario that makes the combat loop visible and debuggable.

## Goals

- Establish the Haskell project structure for a Reflex browser client and shared combat model.
- Define a server-like Combat API boundary.
- Implement a local in-process Combat API for playtests.
- Model a fixed-tick tactical naval simulation.
- Render a minimal combat scene in WebGL from simulation snapshots.
- Let the player command one caravela against another caravela.
- Resolve broadside damage using range, firing arc, fixed damage, and reload cooldown.
- End the scenario when one ship's hull integrity reaches zero.

## Non-Goals

- No multiplayer server.
- No accounts, matchmaking, persistence, or deployment pipeline.
- No campaign, economy, trade, exploration, or strategic map.
- No loadout editor in the first slice.
- No crew ability implementation in the first slice.
- No boarding, morale, capture, crew casualties, critical hits, or ammunition types.
- No historically varied ship roster.
- No advanced visuals beyond proving that the WebGL wrapper can render the battle state.

## First Playable Scenario

The minimal scenario is one Portuguese caravela versus another Portuguese caravela in open water.

Both ships start with the same hull, same guns, and same crew assumptions. One ship is player-commanded. The opposing ship can be static or controlled by a minimal bot until a better opponent behavior is useful.

The scenario ends when one ship's hull integrity reaches zero.

## Gameplay Loop

1. Start the local caravela duel scenario.
2. The simulation advances on fixed ticks.
3. The player observes ship positions, headings, wind, range, hull integrity, and reload state.
4. The player submits a heading or sail command.
5. The player fires a broadside when the target is within range and firing arc.
6. The simulation applies fixed hull damage after validating range, arc, and reload cooldown.
7. The scenario reports victory or defeat when a hull reaches zero.

## Architecture

All first-party code should be Haskell.

The browser client should be implemented with Reflex / reflex-dom. Reflex manages UI state, user commands, subscriptions, and playtest controls.

WebGL should be wrapped by a small Reflex-friendly rendering layer. The renderer consumes combat snapshots and sends UI interaction events back to Reflex, but the combat simulation should not depend on WebGL or browser APIs.

The Combat API should be designed as if it could be remote:

- Start or load a scenario.
- Submit player commands.
- Observe snapshots or events.
- Report terminal scenario state.

Early development uses `LocalCombatApi`, an in-process implementation of that boundary. Future multiplayer can replace it with `RemoteCombatApi` backed by real server calls.

## Acceptance Criteria

- A developer can open the browser client and start the caravela duel scenario.
- The scene shows two ships in a WebGL-rendered tactical view.
- The simulation advances at a fixed tick rate.
- The player can alter their ship's heading or sail state through the Reflex UI.
- The player can fire a broadside only when range, firing arc, and reload constraints allow it.
- A successful broadside applies fixed hull damage.
- The UI shows hull integrity and scenario end state.
- Combat simulation tests can run without a browser.
- The frontend talks to combat through the Combat API boundary, not by directly mutating simulation internals.

## Open Questions

- Which Haskell browser toolchain should be used for the initial Reflex setup?
- What minimal WebGL abstraction is idiomatic enough for Reflex while staying small?
- Should the first opponent be stationary, scripted, or a very small bot?
- What tick rate should the first simulation use?
- What coordinate system and unit scale should the combat model use?
