# ADR-0008: Fire At Will Drives Automatic Fire

Status: Accepted

Date: 2026-09-24

## Context

Firing was manual per volley: `FireBroadside attacker target side` named the target
*and* the side, and the client offered two buttons, "Fire port" and "Fire starboard",
both hardcoding `EnemyShip`. The intended model is a fire-control solution instead —
the player locks one target, and the guns fire themselves when that target is
reachable.

The trigger was designed against how the reference games actually behave, and the
finding was that neither is a template for the other half:

- **EVE Online has no line-of-fire geometry at all.** A turret is a statistical
  oracle: one random number decides hit or miss and the damage quality together, a
  miss is drawn on the target's own bounding sphere, and locking a target fully
  determines who takes damage. It keeps a per-volley activation decision precisely
  because *whether* the shot lands is the uncertain thing.
- **Both age-of-sail wargames hard-block instead.** *Wooden Ships & Iron Men*: "if
  the 'closest ship' happens to be a land hex, friendly ship, surrendered or
  captured ship, or a hulk, the field of fire is blocked and the ship may not fire
  that broadside in that turn." *Sails of Glory*: "a ship may not fire through the
  base of another ship, enemy or allied." In both, a friendly hull is a blocker
  rather than a casualty.
- **EVE did once model occlusion and removed it**, reportedly because ally-blocking
  caused accidental friendly-fire deaths in high security space. This one is
  community consensus with no patch note behind it, and it is marked uncertain in
  [the research](../research/eve-targeting-model/RESEARCH.md) — treat it as a
  cautionary anecdote, not as evidence.

So the reference model keeps the manual choice and has no geometry; the genre-native
model has geometry and refuses the shot. Manual per-volley fire in a game that also
has real arcs and ranges would add a timing decision on top of a positioning
decision, which `CONTEXT.md` rules out: the first slice must not be reflex-heavy or
aim-based.

## Decision

**The fire control is a toggle, not a trigger.** The player locks a target and orders
fire at will; a volley leaves on the next tick whenever the loaded guns' firing
envelope contains the locked target.

- **The side is not chosen.** Whichever broadside can reach the target is the one
  that fires, so there is no port/starboard control.
- **The trigger is per ship, not per side.** One reload covers both broadsides, and
  one toggle permits both.
- **The reload is the whole of the delay.** Disengaging during a reload stops
  further volleys — including the one the crew was already preparing — and a ship
  cannot be ordered to fire again until that reload finishes. No separate crew
  reaction lag was added: the cooldown already provides the delay.
- **Guns reload whether or not they are permitted to fire.** Disengaging costs
  tempo in one direction only: a ship that re-arms is as ready as it would have been.
- **Both sides follow the same rules.** The enemy autopilot locks and orders fire at
  will through the same command path a player uses, per the existing Autopilot rule
  in `CONTEXT.md`.

## Considered Options

- **Manual per-volley trigger, EVE-style.** Rejected: it layers an input-timing
  decision over a positioning decision in a game whose thesis is that positioning is
  the skill, and `CONTEXT.md`'s design constraints forbid a reflex-heavy first slice.
- **No toggle — locking alone fires.** Rejected: it leaves the player with no control
  over firing whatsoever, so the question the design is built around — "fire now, or
  hold for a better angle" — has no answer available to them.
- **Refusing a blocked shot, the wargame model.** Not decided here. The occlusion
  question is still open, and this ADR does not settle it: the fire-at-will rule as
  written has no room for "unless another hull is in the line".

## Consequences

- **The reload circle becomes the player's timing instrument.** It is the only thing
  the player has to read to know when a volley leaves, which is why it is drawn in
  the DOM above the canvas where it can animate smoothly.
- **The toggle has no advantage today, and that is accepted deliberately.** With no
  ammunition, no falloff and no cost to firing, the optimal play is to arm once and
  never touch the button. It earns its keep when damage falloff and energy or
  ammunition limits arrive, which `CONTEXT.md` lists under Deferred Concepts.
- **Firing state becomes part of the ship, not the command.** `Ship` gains a locked
  target and a fire-at-will flag; `CombatCommand` gains lock and fire-at-will
  commands; `FireBroadside` with its explicit attacker, target and side goes away.
- **The old fire buttons do not survive.** "Fire port" and "Fire starboard" are
  replaced by one fire-at-will control, and `EngagementSnapshot`'s hardcoded
  `PlayerShip`→`EnemyShip` port/starboard checks are replaced by per-ship state.
