# ADR-0001: Haskell Reflex Browser Client With Local Combat API

Status: Accepted

Date: 2026-09-16

## Context

Flor do Mar is a browser-targeted naval combat game inspired by EVE Online-style command combat rather than reflex-heavy arcade combat. The project needs to prove a tactical combat loop while preserving a path to future multiplayer synchronization.

Fast-paced direct-control combat would make server synchronization harder and would push important behavior into client-side timing and reflex input. A command-based model allows the game to validate intent, apply commands on simulation ticks, and share authoritative snapshots.

The project also wants local playtest scenarios early, before any real multiplayer server exists.

## Decision

Use Haskell for all first-party code.

Build the browser client with Reflex / reflex-dom. Render the tactical battle view with WebGL through a small Reflex-friendly wrapper at the edge of the frontend.

Keep the combat simulation independent from rendering and browser APIs.

Expose combat through a server-like Combat API. Early development will use an in-process `LocalCombatApi` implementation. A future multiplayer mode can replace it with `RemoteCombatApi` backed by real server calls while preserving the command and snapshot model.

Combat simulation should advance on a fixed tick. Player commands are submitted to the API and applied by the simulation on ticks.

## Consequences

- The UI can be developed and tested against local scenarios before multiplayer exists.
- Combat rules can be tested outside the browser.
- The same API shape can support a future authoritative server.
- The first implementation must be disciplined about boundaries: Reflex and WebGL should consume snapshots and submit commands, not own combat rules.
- Some up-front architecture work is required before the first scene feels playable.
