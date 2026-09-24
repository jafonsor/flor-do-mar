# Intervening-Ship Shot Blocking: Comparable Games Survey

Does a shot *not* aimed at a ship physically in the line of fire pass through it, collide with it, or get blocked — or is the situation unmodelled? Plus: is friendly fire possible, and is the projectile a real entity or a hitscan roll? Primary sources preferred; community sources are labelled. Unverified claims are marked **UNCERTAIN — no primary source found**; my own reasoning is marked INFERENCE.

## 1. Homeworld / HW2 / Homeworld Remastered / Homeworld 3

**Verdict: PASSES THROUGH (HW1/HW2/HWRM by default) / COLLIDES (HW3, community-sourced).**

HW2's `.wepn` API exposes a per-weapon flag that only exists because projectiles *don't* collide with friendlies on their own: `iCheckLineOfFire` — "If enabled, the weapon checks for friendlies in the way **before firing**." The documented example sets it to `0`. That is a pre-fire gate, not a collision rule ([KarosGraveyard `StartWeaponConfig`](https://github.com/hwrm/KarosGraveyard/wiki/Function;-StartWeaponConfig)) — INFERENCE: bolts fly through friendly hulls unless a modder opts in. The same API splits projectile types: `"InstantHit"` — "damage or other effects take place immediately upon firing", used for beams — versus `"Bullet"` (unguided travelling projectile); ion cannons are the canonical `Fixed`-mount `InstantHit` beam ([same](https://github.com/hwrm/KarosGraveyard/wiki/Function;-StartWeaponConfig)). A second flag confirms beams pass *through* hulls: `iInstantHitThreshold` — "If the target has less than this health, the beam will go through the target ship" ([same](https://github.com/hwrm/KarosGraveyard/wiki/Function;-StartWeaponConfig)). Both models coexist: steered weapons guarantee a hit percentage "based on the accuracy table within the weapon", while ballistic weapons "aim directly at the target and fire… whether it hits or not is subject to bullet speed, target speed, weapon range and target behavior" ([`setBallistics`](https://github.com/hwrm/KarosGraveyard/wiki/Function;-setBallistics)). Community consensus: HW1 used collision physics, HW2 was chance-based, and HW2 shipped a friendly-fire game option ([community, Steam](https://steamcommunity.com/app/244160/discussions/0/612823460267247769)).

HW3: an extracted shipped blueprint, `BTT_CheckLineOfFire` (`/Game/AI/HumanAI/`), runs a `LineTraceSingle` and writes a `HasLineOfFire` blackboard key — again a **pre-fire** trace ([community-published UE dump](https://blueprintue.com/blueprint/qeuvrpht/)). A modder's read of shipped data: bullets "have a chance of 'locking on'… **They can still hit anything along the way**" ([community, Steam](https://steamcommunity.com/app/1840080/discussions/0/6895657216192251341/)). HW3 friendly fire: **UNCERTAIN — no primary source found.**

## 2. Nebulous: Fleet Command

**Verdict: COLLIDES.**

Ships "will happily fire at a friendly ship if they happen wander into the line of fire"; guarding fighters "end up being shot by it. Repeatedly." ([community, Steam](https://steamcommunity.com/app/887570/discussions/3/568163851454993947/)) — friendly fire is geometric, not a legality flag. Point defence is *active* interception: PD has an Area mode, PD missiles intercept incoming missiles, and "ship PD turrets will stop shooting at anti-craft missiles once they get too close to your craft, so that they don't accidentally blow up your own fighters" — an explicit friendly-safety cutoff radius. Auto-PD also "fires your missiles into rocks a LOT", so munition-terrain collision is modelled ([community, Steam](https://steamcommunity.com/app/887570/discussions/0/603020523905005464/)). Official Hooded Horse wiki pages returned HTTP 403 to every fetch: **UNCERTAIN — no primary source found** for interception formulae.

## 3. Rule the Waves 1 / 2 / 3

**Verdict: NOT MODELED.**

Gunnery is a per-salvo hit roll, not a shell entity. The official RTW3 manual's *Gunnery* section lists accuracy inputs verbatim — fire-control technology, crew quality, both ships turning, previous salvo on target, sea state, **smoke interference**, damage, range, multiple firers, target evading, twilight, glare; target size, speed and aspect appear only for torpedoes ([RTW3 manual](https://ftp.matrixgames.com/pub/RuletheWaves3/Rule%20the%20Waves%203%20Manual%20EBOOK.pdf)). RTW2 v1.16 confirms the abstraction: "once a ship has a straddle or hit, it will go to rapid fire with both higher ROF and hit chances until it fails to straddle" ([RTW2 manual v1.16](http://www.navalwarfare.net/files/SAI/RTW2_Game_Manual_116.pdf)). Shells as in-flight objects: **UNCERTAIN — no primary source found.** "Line of fire" in the manual is AI *positioning* preference only; the sole modelled line-of-sight obstruction is **smoke, never ships** — funnel smoke "will degrade gunnery when firing through it, regardless of which ship the smoke is coming from" ([RTW3 manual](https://ftp.matrixgames.com/pub/RuletheWaves3/Rule%20the%20Waves%203%20Manual%20EBOOK.pdf)).

Friendly fire exists where bodies are real: official patch notes deliberately enabled friendly collisions ("ships in line abreast formation can now collide with friendly ships in the same division", [whatsnew v01.00.19](https://ftp.matrixgames.com/pub/RuletheWaves3/whatsnew.pdf)), and torpedoes "continue straight ahead… If they intersect a ship, a hit check is made depending on target size and angle" ([dev Torpedo Dev Diary](https://www.matrixgames.com/news/rule-the-waves-3-torpedo-dev-diary)). A torpedo-only launch guard exists — "Friendly ship is in line of fire!" — though the AI fired through the battle line anyway ([community, Matrix forums](https://forums.matrixgames.com/viewtopic.php?t=401121)); AI DDs missing a crippled enemy inside your formation "could easily hit one of your own guys" ([community, Matrix forums](https://forums.matrixgames.com/viewtopic.php?t=399718)). Main turrets have per-mount firing arcs; a raking / crossing-the-T bonus is **UNCERTAIN — no primary source found.**

## 4. Sails of Glory

**Verdict: BLOCKED — friendly ships block line of sight outright.**

From the rulebook PDF published by Rebel.pl, the official regional publisher: "A ship may not fire through the base of another ship, **enemy or allied**. If it is impossible to reach the target point without crossing another ship's base, line of sight is blocked" — the firer must choose another arc or target ([Sails of Glory rulebook](https://www.rebel.pl/repository/files/instrukcje/Sails_of_Glory_PL.pdf)). Blocking is by base footprint, not centreline. The optional *Forced Targeting* rule adds that a broadside must engage the nearest target on that side, and "if the nearest ship is an ally, the battery cannot fire" ([same](https://www.rebel.pl/repository/files/instrukcje/Sails_of_Glory_PL.pdf)). Friendly fire arises only via collision damage between allied ships, never gunfire.

## 5. Wooden Ships & Iron Men

**Verdict: BLOCKED — an intervening friendly forbids the shot entirely.**

Digitized 2nd-edition rules, *Basic Game VIII.A.4*: the target "must be the closest in number of hexes to the firing ship of all ships in the field of fire"; and "**If the 'closest ship' happens to be a land hex, friendly ship, surrendered or captured ship, or a hulk, the field of fire is blocked and the ship may not fire that broadside in that turn.**" ([WS&IM rules](https://mtorpey.github.io/wooden-ships/)) The Advanced Game repeats it with per-section variants ("Ships cannot fire the stern section at a target in field 4 if there is a closer target in field 2 or 4") ([same](https://mtorpey.github.io/wooden-ships/)). Friendly fire is structurally impossible — a friendly hull is a blocker, not a casualty. Raking is positional: a ship "directly in front of the target ship's bow or directly behind the target ship's stern… may fire a rake" ([same](https://mtorpey.github.io/wooden-ships/)). Resolution is a Hit Determination Table roll.

## 6. Blackwake

**Verdict: UNCERTAIN.**

The shipped `server.cfg` Config Editor has independent switches, where "**Friendly Fire** affects players, while **Friendly Ship Damage** controls damage to allied ships" — plus a separate player-collision toggle ([host knowledgebase describing the config file](https://my.logicservers.com/knowledgebase/3930/How-to-change-friendly-fire-and-gameplay-settings-in-Blackwake.html)). INFERENCE: separate player/hull damage flags suggest a friendly body or hull in the line of fire stops a cannonball when friendly damage is on — but I found no source for intervening-entity handling with it off, nor for whether cannonballs are simulated. **UNCERTAIN — no primary source found.**

## 7. Naval Action

**Verdict: COLLIDES (INFERENCE).**

The pinned official *Articles of War* (official Steam discussions, later appended to by a `[developer]` account): "**blocking your allies on purpose is against the rules**… **Friendly fire is not allowed with two exceptions** — Return fire on false flag enemies…; Loot stealers" ([official Steam forums](https://steamcommunity.com/app/311310/discussions/22/2953753908248337940/)). Friendly fire being rule-prohibited rather than engine-impossible means it is mechanically possible, so a friendly hull in the way is hit. Whether the ball is consumed by that hull is **UNCERTAIN — no primary source found**; the "blocking" clause concerns ramming/station-keeping, not gunnery.

## 8. Sea of Thieves

**Verdict: NOT MODELED.**

The top thread on Rare's own forums is a *feature request* — "Friendly Fire – Player Option – Allow Damage from Crew On/Off" — noting the option "doesn't exist"; 39 posts, 41.5k views, no developer implementation ([official forums](https://www.seaofthieves.com/community/forums/topic/180045)). INFERENCE: with crew damage structurally absent, an intervening crewmate cannot be a blocking casualty; shots pass through. Cannonballs do have real geometry — a player reports a sloop mast breaking on a "physical miss", i.e. hitbox mismatch, not abstraction ([official forums](https://www.seaofthieves.com/community/forums/topic/172879/cannonball-and-chainshot-hitboxes)). Whether a ball collides with the firing ship's own hull or crew: **UNCERTAIN — no primary source found.** Official site pages were WAF-blocked; forum threads were read via a text proxy.

## 9. Assassin's Creed IV: Black Flag

**Verdict: UNCERTAIN — no primary source found.**

Searches returned only third-party guides ([Gamepressure](https://www.gamepressure.com/assassinscreediv/naval-battles/z158a3), [Eurogamer](https://www.eurogamer.net/assassins-creed-black-flag-resynced-naval-combat-explained)); none document whether an allied or neutral hull blocks cannon fire, whether friendly fire exists, or whether cannonballs are simulated. Ubisoft publishes no naval-combat design documentation. Do not assert either way.

## 10. Brief: WoWS / WoT and space 4X

**World of Warships — BLOCKED-ABSORBED (no damage).** Official Update 0.10.5: "You can no longer damage or destroy allied ships… **At the same time, all armament types can still hit allied ships. This means that you still won't be able to launch torpedoes at an enemy through an allied ship.**" ([official announcement](https://store.steampowered.com/news/posts/?feed=steam_community_announcements&appids=552990&enddate=1623828694)) — allies are real collision bodies that block shell and torpedo lanes but take zero damage.

**World of Tanks — BLOCKED-ABSORBED (no damage).** Official Update 1.6 disabled team damage; "If you hit an ally, you will only scratch their paint with a non-penetrating or ricochet mark", with the named case being "an ally driving into your reticle during your shot". One pass-through exception: "if a HE shell meets an allied vehicle's gun, it will just go right through" ([official Wargaming news](https://worldoftanks.asia/en/news/general-news/1-6-team-damage/)).

**Sins of a Solar Empire / Sins II — BLOCKED-ABSORBED for missiles / PASSES THROUGH for projectiles and beams.** Official dev journal: "Missiles must strike their target in order to deal damage", with failure modes listed as PD, evasion and fuel — *not* third-party collision ([Stardock dev journal](https://www.stardock.net/article/537751/)). A community wiki contradicts this, stating a missile colliding with a non-target still explodes and damages it, so large hulls serve "as a shield" for allies behind them ([community, Sins II JP wiki](https://wikiwiki.jp/sinsii/%E6%88%A6%E9%97%98%E5%87%A6%E7%90%86)). Friendly fire is abilities-only per a developer-tagged post: "friendly fire is limited to few abilities, such as Argonev Starbase explosion" ([developer statement, Steam](https://steamcommunity.com/app/1575940/discussions/1/599638172337457919/)).

**Stellaris — NOT MODELED.** Official hit formula is `Accuracy − Evasion`, Tracking cancelling evasion — no travel-time, projectile-entity or collision term in hit resolution ([official wiki](https://stellaris.paradoxwikis.com/Space_warfare)). The only interception system is point-defence *weapons* ([official wiki](https://stellaris.paradoxwikis.com/Weapon_components)); `collision_radius` is documented purely as "the radius other ships will try to avoid colliding with" ([official wiki](https://stellaris.paradoxwikis.com/Ship_modding)). No friendly-fire article or modifier exists.

**EVE Online — PASSES THROUGH.** Turrets are instant ("turret shots impact and damage their targets in the same moment as they are fired"); missiles are real entities with structure HP that detonate only on crossing "the signature radius of its target" ([community, EVE University Wiki](https://wiki.eveuniversity.org/Missiles)). Missiles stop only via fuel exhaustion or being *destroyed* — smartbomb firewalling or Defender Missiles ([same](https://wiki.eveuniversity.org/Missiles)). Friendly fire is legality, not physics: green/yellow/red safety settings govern suspect/criminal status ([community, EVE University Wiki](https://wiki.eveuniversity.org/Safety_settings)). CCP support articles returned HTTP 403: **UNCERTAIN — no primary source found** for CCP's own wording.

---

## Design patterns worth borrowing

- **Make the line-of-fire test a pre-fire gate, not a physics rule.** Homeworld's `iCheckLineOfFire` and HW3's `BTT_CheckLineOfFire` trace decide *whether to shoot*, not whether a projectile is consumed ([KarosGraveyard](https://github.com/hwrm/KarosGraveyard/wiki/Function;-StartWeaponConfig), [blueprintUE](https://blueprintue.com/blueprint/qeuvrpht/)). Cheap, per-weapon tunable, no per-projectile bookkeeping.
- **Hard-block at the targeting layer when you want zero ambiguity.** WS&IM's "closest ship" rule and Sails of Glory's base-footprint LOS bar the shot outright ([WS&IM](https://mtorpey.github.io/wooden-ships/), [SoG](https://www.rebel.pl/repository/files/instrukcje/Sails_of_Glory_PL.pdf)). RtW applies the same guard only to the irreversible weapon ("Friendly ship is in line of fire!" for torpedoes) — a good precedent for scoping the block ([Matrix forums](https://forums.matrixgames.com/viewtopic.php?t=401121)).
- **Keep the hull a real collision body but zero the damage.** WoWS's "still won't be able to launch torpedoes at an enemy through an allied ship" preserves screening geometry and torpedo-lane discipline without enabling griefing ([official](https://store.steampowered.com/news/posts/?feed=steam_community_announcements&appids=552990&enddate=1623828694)).
- **Prefer active interception with a time-in-envelope model over geometric blocking.** Sins II: the longer a missile sits inside PD range and arc, the more shots it eats; PD at the midpoint doubles engagement time; counter-play is saturation and armoured decoys ([Stardock](https://www.stardock.net/article/537751/)).
- **Give automated point defence a friendly-safety cutoff radius.** Nebulous' PD ceases fire on anti-craft missiles once they close on your own craft so it "doesn't accidentally blow up your own fighters" ([community, Steam](https://steamcommunity.com/app/887570/discussions/0/603020523905005464/)).
