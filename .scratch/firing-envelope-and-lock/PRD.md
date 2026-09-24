# PRD: Automatic Fire and the Firing Envelope

Status: ready-for-agent

## Problem Statement

Firing is manual per volley. The player picks a side and presses a button: `FireBroadside attacker target side` names both the target and the side, the client hardcodes `EnemyShip`, and two buttons in the control panel are the entire interface. The simulation never asks *what is actually out there along my guns* — it asks whether a named ship happens to be inside a 45-degree wedge, and if so applies fixed damage.

That model has three problems. The player has no way to express *who they are fighting* separately from *when they shoot*. There is no way to express a firing intention that outlives the current instant, so the only way to fight is to keep pressing a button. And nothing on the battle view tells the player where their guns actually reach, so range and arc decisions are invisible even though the rules depend on them entirely.

The design intent is EVE-inspired tactical combat where positioning is the skill, not reflexes. In that model the player's job is to steer the hull so the enemy sits in a firing envelope while staying out of the enemy's. The current interface does not let them see or act on that intent.

## Solution

Replace manual per-volley fire with a **locked target plus a fire-at-will order**.

The player **clicks an enemy ship to lock it** and clicks it again to unlock; the client never sends a lock on the player's own hull, and the simulation refuses one. The player separately **toggles fire at will** from a gun panel above the canvas. Guns fire themselves: a volley leaves on the next tick whenever a ship's guns are permitted to fire, are loaded, and the locked target lies inside one broadside's firing envelope. The side that fires is whichever side can reach — there is no port or starboard control.

**One reload covers both broadsides**, so one toggle permits both. Disengaging during a reload stops further volleys, including the volley the crew was already preparing, and a ship cannot be ordered to fire again until that reload finishes. Guns reload whether or not they are permitted to fire, so disengaging costs tempo in one direction only. Both sides play by the same rules: the enemy autopilot locks and orders fire at will through the same commands a player uses.

The battle view shows **firing envelopes** as sectors that follow each hull's heading, drawn only for a ship that is locked, with both of that ship's broadsides shown at once. A wedge changes colour when the locked target is inside it, and fills as the shared reload progresses. The gun panel carries a **reload circle** that animates smoothly and shows armed state by colour.

Gun range becomes **48 world units** (three lengths of the big ship) instead of 100, and the battle camera zooms to 0.6 so a whole engagement fits on screen. The enemy's orbit centre moves to the arena centre `(0, 40)` so it circles in view rather than straddling the top edge of the canvas.

## User Stories

1. As a player, I want to lock one enemy by clicking it, so that I can say who I am fighting without also deciding when to shoot.
2. As a player, I want to unlock by clicking the locked ship again, so that releasing a target is the same gesture as taking one.
3. As a player, I want a hover marker on a ship that would lock if clicked, so that the lock gesture is discoverable before I commit to it.
4. As a player, I want a marker on the ship I have locked, so that I can always tell which ship my guns are pointed at.
5. As a player, I want clicking my own ship to do nothing, so that I cannot lock myself.
6. As a player, I want to drag on open water to issue a navigation order, so that the lock gesture does not cost me the navigation gesture.
7. As a player, I want dragging from an enemy hull to still issue a navigation order, so that the new gesture does not steal an existing one.
8. As a player, I want one button that permits my guns to fire, so that I control whether I am shooting.
9. As a player, I want my guns to fire by themselves once permitted, so that I can concentrate on positioning.
10. As a player, I want the guns to choose the broadside that can reach, so that I do not have to manage sides.
11. As a player, I want a volley to leave on the next tick when my target is in reach, so that the payoff for good positioning is immediate.
12. As a player, I want to disengage during a reload and have no further volleys fire, so that I can stop shooting without waiting.
13. As a player, I want re-engaging blocked until the reload finishes, so that the cooldown cannot be gamed by toggling.
14. As a player, I want my guns to keep reloading while disengaged, so that disengaging does not cost me the next volley's readiness.
15. As a player, I want to see a firing envelope for each of my broadsides, so that I know where my guns reach.
16. As a player, I want the envelopes to follow my hull as it turns, so that the drawn area is the truth about my guns.
17. As a player, I want the envelope to change colour when my locked target is inside it, so that I can see when a volley is about to leave.
18. As a player, I want the envelope to fill as the reload progresses, so that I read reload state where I am already looking.
19. As a player, I want a reload circle in the gun panel, so that I have a precise readout for timing my order.
20. As a player, I want the circle to show armed state by colour immediately, so that I know my order was received.
21. As a player, I want to see the enemy's firing envelopes once it has locked me, so that I can steer out of them.
22. As a player, I want both of the enemy's broadsides drawn at once, so that I can see which side threatens me.
23. As a player, I want to see a whole engagement on screen, so that I can make range decisions about space I can actually see.
24. As a player, I want ships to stay large enough to read while the whole engagement fits, so that the tactical view stays legible.
25. As a player, I want the enemy to fight by the same rules I do, so that the fight is fair and the mechanics are learnable from watching it.
26. As a player, I want the enemy to circle in the middle of the view, so that I can read its movement while fighting it.
27. As a developer, I want the lock and the firing order to be separate commands, so that the two player questions — who, and whether — stay separate in the model.
28. As a developer, I want the client to draw the envelope from the same tuning values the simulation validates against, so that the drawn area cannot lie about the real one.
29. As a developer, I want the enemy to fire through the same command path as the player, so that bugs in firing are not hidden behind a special enemy path.
30. As a developer, I want the model to preserve the command-and-snapshot boundary, so that later remote authoritative play reuses it unchanged.

## Implementation Decisions

- **Targeting is a fire-control solution.** A ship holds at most one locked target, stored on the ship. Guns cannot fire without a lock.
- **Two commands replace one.** `FireBroadside` goes away. Lock and unlock are one command carrying a target id; the guns' permission is a separate command carrying a boolean.
- **The lock is a command processed on the next tick**, not an instant client-side state change. No acquisition delay beyond that tick; per-target acquisition differences are deferred.
- **The simulation refuses a self-lock.** The guard belongs in the domain, not only in the input layer, because the existing guard chain has no such check and geometry currently blocks self-damage only by accident of the arc maths.
- **Firing is evaluated as a tick phase.** On each tick, for each ship: if permitted to fire, loaded, and the locked target is inside one broadside's envelope, fire that broadside. The phase reuses the existing broadside check rather than introducing a second predicate.
- **The volley phase runs after the tick's commands and before the tick's movement.** Its damage belongs to the tick it fired on, so that tick's snapshot shows it and `finishIfTerminal` still runs straight after the phase, and the envelope test uses the post-command, pre-movement geometry — the state the client last drew — rather than positions the player has not seen yet. Volleys within one tick resolve **simultaneously**: every shot is computed against the state at the start of the phase before any is applied, so neither ship can disable the other out of its own shot. The enemy fires through this same phase.
- **One reload per ship**, shared by both broadsides, decremented at the top of the tick, before that tick's commands are applied. A reload that reaches zero on a tick leaves the guns loaded for that same tick, so an arm order applied on the tick the reload completes is accepted and can catch that tick's volley; from the player's side a volley leaves on the tick after they arm. Disengaging clears permission and prevents a volley on the tick the reload completes; it does not cancel the reload. Re-engaging while the reload counter is above zero — its value after the tick's decrement — is rejected.
- **Both sides use the same commands.** The enemy autopilot issues a lock and a fire-at-will order through the normal command path.
- **Enemy behaviour stays dumb for this pass.** It locks the player once (after a short configurable delay from scenario start, not on tick 0), orders fire at will, and keeps orbiting its centre. It never disengages. No range-keeping or positioning logic.
- **Both sides start disengaged.** Neither starts with permission to fire.
- **Firing sides are disjoint by construction.** The half-angle validation tightens from `<= 180` to `<= 90` degrees, so the two broadsides cannot overlap and one volley always has exactly one candidate side. The shipped value of 45 is unaffected.
- **Centre-to-centre geometry** for both the angular test and the range test. Hull-aware tests are deferred.
- **Gunnery tuning travels in the snapshot.** `ShipSnapshot` gains the per-ship broadside tuning — practical range, firing arc degrees, reload ticks — mirroring how `shipSnapshotMovementPhysics` already travels, so the client draws the envelope from the same values the simulation enforces rather than joining against a config dynamic that hot reloads.
- **Per-ship firing state replaces the player-versus-enemy engagement read model.** The hardcoded `PlayerShip`/`EnemyShip` port and starboard checks go away, replaced by per-ship state the client reads: locked target, permission, reload progress, and which side, if any, currently holds the target.
- **The gun panel is screen-anchored HTML above the canvas.** The overlay container passes pointer events through; only its controls capture them, or it would swallow the canvas mousedown/move/up stream that navigation depends on.
- **Click and drag are separated at release.** A press on a hull that releases without movement toggles the lock. A press that moves issues a navigation order. The existing gesture model already distinguishes these, since a plain click leaves the selected speed unset.
- **Hit-testing uses a screen-space radius** around each ship centre, computed from the existing screen-to-battle conversion, so hulls stay clickable as zoom changes.
- **The reload circle animates smoothly; the wedges step per tick.** The circle lives in the DOM and needs no frame loop. No per-frame clock is introduced, and none of the canvas animation machinery changes.
- **One shared reload fill**, drawn identically on both of a ship's wedges, matching the one shared cooldown.
- **Two reticles, same size, different colour**: a hover circle on a lockable ship and a ring on the locked ship. No dashed line to the target in this pass.
- **Envelope colours** use the existing hull palette — player blue, enemy red — with one shared highlight when the locked target is inside, and a desaturated treatment when the guns are disengaged.
- **Range becomes 48 world units** in both boat configs (three lengths of the big ship) and **camera zoom becomes 0.6**, so a whole engagement fits with hulls still legible. The camera centre stays at the arena centre.
- **The enemy orbit centre moves to `(0, 40)`**, the same point the camera is centred on, so its orbit ring sits in view instead of straddling the top edge of the canvas.
- **A shot passes through anything in its line.** No occlusion, no interception, no intervening-ship logic of any kind. This is a deliberate non-goal, not an oversight.

## Testing Decisions

- **Test at the pure tick transition and the local combat API seams**, which is where the existing combat tests already sit. No browser DOM tests.
- **Domain tests**: a lock is stored and is cleared by an unlock; a self-lock is refused; a lock on an absent ship is refused; a volley fires on the tick after permission is granted when the target is in reach; the tick that empties the reload fires, and an arm order applied on that same tick is accepted; no volley fires when the target is outside the envelope, when the guns are reloading, when permission is absent, or when no target is locked; the fired side is the one that can reach, and the other side does not fire; both broadsides share one reload; disengaging during a reload prevents the volley that would otherwise leave on the tick the reload completes; re-engaging during a reload is rejected; the reload counter still reaches zero while disengaged; a ship cannot lock itself; two ships that can each disable the other in one tick both land their volleys; a volley is judged against the pre-movement geometry the client last drew.
- **Config tests**: firing arc validation rejects a half-angle above 90 degrees and accepts the shipped 45, using the existing fixture pattern.
- **Snapshot tests**: per-ship state exposes lock, permission, reload ticks remaining, total reload ticks, practical range, and firing arc degrees; the old player-versus-enemy engagement checks are gone.
- **Render scene tests**: a wedge node exists per side for a locked ship and not for an unlocked one; the wedge geometry matches the snapshot's range and arc; the fill follows reload progress; the target-inside highlight appears for whichever side holds the target; the hover and locked rings appear on the correct ship; the camera's zoom and centre match the new values. Note that existing render tests assert an exact mesh count and match on the ring and stroke constructors, so they will need updating alongside these.
- **First manual verification, before writing much code**: reduce the range and the zoom, then sail the player into the enemy's reach and confirm the enemy's envelope appears and the numbers are readable at 0.6. This is the riskiest assumption in the whole change — that a 96-unit envelope and a 16-unit hull are legible on a 760 by 428 canvas at once — and every visual decision downstream depends on it.
- **Second manual verification**: the full loop in the browser — click to lock, drag to navigate, toggle fire at will, watch a volley leave when the hull comes into reach, disengage mid-reload and confirm no further volley fires.
- Run `cabal build flor-do-mar-client` after client changes and `cabal test combat-test` for the suite.

## Out of Scope

- **Occlusion.** A shot passes through any ship in its line. No intervening-ship logic, no friendly fire, no blocked-shot refusal.
- Per-side reload. One reload covers both broadsides.
- Per-target lock acquisition varied by size, speed, or camouflage.
- Damage or precision falloff over range; effective range as distinct from practical range.
- Energy or ammunition limits on firing.
- Projectile travel time.
- Accuracy modelling of any kind.
- Hull-aware angular or range tests.
- A per-frame animation clock; canvas animation stays snapshot-driven.
- Auto-zoom that adapts to the engagement. The zoom is a fixed new value for now.
- Realistic unit scale. 48 units is three big-ship lengths by decision, not a fidelity claim.
- Enemy positioning logic, range-keeping, or any AI beyond lock, arm, and orbit.
- Multiple ships per side, target selection among several enemies, or any change to the two-ship roster.

## Further Notes

- **The toggle has no advantage today, deliberately.** With no ammunition, no falloff and no cost to firing, the optimal play is to arm once and never touch the button. The control earns its keep when damage falloff and energy or ammunition limits arrive. This was decided with eyes open; see `docs/adr/0008-fire-at-will-drives-automatic-fire.md`.
- **The occlusion decision is the one that will come back.** `Fire at will` as specified has no room for *"unless another hull is in the line"*, so adding blocking later will revise the firing rule rather than extend it. The research behind that decision, including the finding that both age-of-sail wargames hard-block while EVE has no geometry at all, is in `docs/research/eve-targeting-model/RESEARCH.md`.
- **The vocabulary is already written.** `CONTEXT.md` has a Targeting and Gunnery section covering locked target, lock, firing arc, firing envelope, target inside, fire at will, and practical range. Implement against those terms, and do not invent parallel ones.
- **Real cannon range is much longer than 48 units.** A caravela was 20 to 30 metres and 16th-century naval guns fought at hundreds of metres. The reduction serves screen legibility and pacing, not history, and the historical argument points the other way — so it should not be used later to justify increasing range.
- **The wedge will step, not slide.** Reload advances once per tick, so the fill has four states. If that reads as broken beside the smoothly animating circle, the fix is a per-frame clock, which is an architectural change in `ADR-0007` territory and deserves its own decision rather than being added under a UI change.

## Issues

In dependency order. Each one is meant to leave the tree building and the suite passing.

**Building is not playing.** Between issue 01 and issue 06 nothing can fire at all: issue 01 deletes `FireBroadside`, which takes the client's fire buttons out of the tree with it, and the gun panel that replaces them only lands in issue 06. Issues 02 to 05 are domain, config, snapshot and AI work. That gap is intended — do not add a bridging control to keep firing alive in the meantime, and do not weaken issue 01 to avoid it.

1. [Model locked targets and fire permission](./issues/01-model-locked-targets-and-fire-permission.md)
2. [Fire volleys automatically from a tick phase](./issues/02-fire-volleys-automatically.md)
3. [Reduce gun range and fit the engagement on screen](./issues/03-reduce-range-and-fit-engagement-on-screen.md)
4. [Expose per-ship gunnery state in the snapshot](./issues/04-expose-per-ship-gunnery-state.md)
5. [Enemy locks and fires through the same commands](./issues/05-enemy-locks-and-fires-through-the-same-commands.md)
6. [Gun panel and click to lock](./issues/06-gun-panel-and-click-to-lock.md)
7. [Draw the firing envelope](./issues/07-draw-the-firing-envelope.md)
