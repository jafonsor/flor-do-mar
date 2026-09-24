# EVE Online: "why doesn't my shot hit the ship in front of me?" — community and developer discussion of line-of-fire occlusion

## Bottom line

- EVE models **no line-of-fire occlusion between ships**. Turrets, missiles and drones resolve against the locked target only; hulls, asteroids, stations and wrecks never block fire. There is **no cover mechanic** in the "block incoming damage with geometry" sense. The single geometric protection in the game is the POS forcefield, and CCP enforces it as a rules/exploit boundary rather than a physics simulation.
- **No CCP dev blog, patch note or forum reply was found stating that occlusion is or is not modelled**, and the recurring official-forum requests for it ([2006](https://eve-search.com/thread/296173-0/author/Praesus_Lecti) → [2023](https://forums.eveonline.com/t/collision-physics-is-absolutly-necessary-for-a-hardcore-game-like-eve/410606)) carry **zero CCP posts**. The "server can't afford the raycasts" explanation is a *player* argument, not a documented CCP statement.
- The complaint is real and long-running, but concentrated on the official forums (Player Features & Ideas). The loudest modern statement is the 2023 "Collision Physics" thread.

## 1. Player threads asking for exactly this

Official EVE forums (current Discourse + the pre-2017 archive mirrored by eve-search):

- **2006** — [Solid Objects & Line of Sight](https://eve-search.com/thread/296173-0/author/Praesus_Lecti): asks why objects are solid for collision but not for shooting/targeting; eve-search reports "Show CCP posts - 0 post(s)".
- **2009** — [Anti-blob solution? (Line-of-Sight firing)](https://eve-search.com/thread/1000872-0/author/Jacmert_Corra'Halcyon): proposes an LoS requirement as an anti-blob fix, debates O(n²) ray cost and friendly fire. 0 CCP posts.
- **2009** — [Take cover!!!! Into that asteroid!](https://eve-search.com/thread/976459-0/author/Maxsim%20Goratiev): "asteroids stop bullets", hostiles in front take the hit so people "hide behind dreads". 0 CCP posts.
- **2011** — [Objects in space impeding weapon fire](https://eve-search.com/thread/36037-1/page/1): "as long as the target is lockable and in range, you can shoot it". 0 CCP posts.
- **2014** — [Fleet formations / weapons fire line of sight](https://eve-search.com/thread/326825-1/page/all): "No longer can you just fire through 15 of your buddies and only hit your target." 0 CCP posts.
- **2017** — [Line of Sight \[How close are we?\]](https://forums.eveonline.com/t/line-of-sight-how-close-are-we/22369): "damage of a gun/missile/etc. applies to the first object between you and your target".
- **2019** — Russian forum, [Объекты не прозрачны для выстрелов](https://forums.eveonline.com/t/topic/201126) ("objects are not transparent to shots").
- **2022** — [Objects obstrcuting line of sight?](https://forums.eveonline.com/t/objects-obstrcuting-line-of-sight/350354): stations/asteroids don't block weapons or warp destabilisation; "could I not use cover to avoid gankers?".
- **2023** — [Collision Physics is absolutly necessary for a hardcore game like EvE](https://forums.eveonline.com/t/collision-physics-is-absolutly-necessary-for-a-hardcore-game-like-eve/410606) (see §4).

**Reddit: not verifiable in this environment.** `reddit.com` HTML/JSON returns login walls or HTTP 403, and API mirrors are rate-limited; the one r/Eve search feed that loaded matched "line of sight" only inside an unrelated war write-up. **UNCERTAIN — no on-point r/Eve thread was confirmed by fetch.** Search engines do surface r/Eve accuracy threads such as [Why am I missing?](https://www.reddit.com/r/Eve/comments/g41r6a/why_am_i_missing/) and [Constantly missing targets](https://www.reddit.com/r/Eve/comments/1uif75/constantly_missing_targets/), but these discuss tracking/RNG, not occlusion.

## 2. What the mechanics actually do

- **Turrets are a probability roll on the locked target, not a projectile.** The chance-to-hit equation uses only range/falloff and angular velocity/signature radius — there is no third-body term — and there is no travelling shot to intercept ([EVE University, Turret mechanics](https://wiki.eveuniversity.org/Turret_mechanics)).
- **Missiles are real objects but ignore intervening hulls.** They fly at the locked target and detonate on crossing its signature radius ([EVE University, Missile mechanics](https://wiki.eveuniversity.org/Missile_mechanics)). They can only be stopped by being *shot down*: smartbombs/bombs/guided bombs damage missile entities ("Firewalling"), and defender launchers intercept bombs ([EVE University, Missiles](https://wiki.eveuniversity.org/Missiles)). No ship can body-block a missile.
- **Drones/fighters** engage the owner's locked target with no LOS check. A player in the [2019 Russian thread](https://forums.eveonline.com/t/topic/201126) claims drone collisions are not calculated at all — plausible, community-only.
- **Only untargeted/AoE weapons hit something other than the locked target**: smartbombs, bombs, doomsday AoE and vorton chain arcs. CCP's [Crimewatch dev blog](https://www.eveonline.com/news/view/introducing-the-new-and-improved-crimewatch) defines smartbombs as "non-targeted weapons" that generate a Weapons flag, and being hit by a smartbomb as flag-triggering; vorton chains can zap a third party who becomes suspect mid-cycle ([forum thread](https://forums.eveonline.com/t/green-safety-and-vorton-chain-targeting-a-working-as-designed-interaction-that-behaves-like-a-bug/515780/7)).
- **Titan doomsdays:** conflicting community claims — "line-of-sight type weapons" ([Shooting without target lock](https://forums.eveonline.com/t/shooting-without-target-lock/181195/4)) vs "Titan DD's account for volume. They go through anything in the way." ([2017 thread](https://forums.eveonline.com/t/line-of-sight-how-close-are-we/22369)). **UNCERTAIN — community claim, no primary source found.**

## 3. Ships pass through each other; no collision damage

Ships bump/bounce, never take collision damage: "you cant crash into objects no matter your speed to mass ratio, you just magically bounce right off everything" ([2023 OP](https://forums.eveonline.com/t/collision-physics-is-absolutly-necessary-for-a-hardcore-game-like-eve/410606)). Asteroids use oversized spherical collision hulls that visibly mismatch the model, documented in a [2022 thread](https://forums.eveonline.com/t/asteroid-hitbox-large/364431/1) where a pilot died stuck on a rock.

## 4. The 2023 "Collision Physics" thread — and the CCP reply check

- OP (Clavine South, 25 Jun 2023) states outright: weapons shoot through stations, other ships, asteroids and debris; "there is no option to use strategy with cover/concealment and line of sight… **There is literally no line of sight that you can break?!?!?**"; later, "**There is literally ZERO _Line of Sight_ calculations being performed**".
- Direct agreement: Anthony FatTony Amico — "Yup completely valid POV I 100% agree. Kind of silly to see laser fire go right through ships XD".
- Counter-position: Tipa Riot — "Nope, there isn't [a hit box / line of sight]. What you see is a clever rendered illusion of the client. In fact only points (actually spheres) in space with some parameters are interacting."
- **CCP reply: none.** No CCP/blue post appears on pages 1–2 (posts 1–40), and the forum search API returns **zero** posts for `topic:410606 @ccp` ([search.json](https://forums.eveonline.com/search.json?q=topic%3A410606%20%40ccp)). The only semi-official voice is **Brisc Rubal, a CSM member (player-elected, not CCP)**: "sure, it would be great to have line of sight and the like, but there's zero chance it will ever end up in this game… changing the fundamentals of how the game works… is the quickest way to lose the existing player base."

## 5. Friendly fire, safety settings, suspect flags

- Safety settings (green / partial / red) block actions that would create Suspect/Criminal status; Alphas in highsec cannot disable safety ([EVE University, Safety settings](https://wiki.eveuniversity.org/Safety_settings), citing CCP's Crimewatch dev blog). This is **legality, not geometry**: the game gates illegal *targets*, never illegal *firing lines*.
- CCP's [Corp Little Things & Friendly Fire Control](https://www.eveonline.com/news/view/corp-little-things-friendly-fire-control) (Tiamat, Feb 2015, CCP Punkturis) gave corps a legal/illegal friendly-fire toggle — framed entirely as CONCORD, security status and Suspect/Criminal flags.
- So friendly fire exists only when you *shoot* a friendly, never because a friendly drifted into your line of fire. The 2014 thread's worry that LoS would create "a new grief tactic… flying in front of someone's turret… to trigger concord" is speculation about a hypothetical ([link](https://eve-search.com/thread/326825-1/page/all)).

## 6. Is there ANY cover mechanic in EVE?

- **POS forcefields are the one hard cover.** CCP: "Forcefields around a POS are intended to be impenetrable with no way to target or damage anyone outside of them when inside the field, nor take any damage or be targeted when inside the field by someone outside of it" ([CCP exploit notification](https://concord-killmail.eveonline.com/de/news/view/exploit-notification-attacking-while-inside-pos-forcefields)). Firing through one is an exploit.
- Everything else called "cover" is concealment or positioning, not damage blocking: celestials for D-scan/overview ambiguity, gate camps, bouncing off celestials (a motion trick), docking, tethering, cloaking, off-grid safes.
- Asteroids/structures/wrecks give **zero** protection: "They aren't going to block anything. All weapons and effects go right through them…" ([Asteroid Hitbox Large](https://forums.eveonline.com/t/asteroid-hitbox-large/364431/1)). The 2023 OP adds that wrecks can be locked and shot but never block.
- **Historical:** missiles once had crude obstacle collision and it was removed. "Missiles USED to have a bit of collision detection… This, also, was a lot of extra computations, and was removed" ([2009](https://eve-search.com/thread/976459-0/author/Maxsim%20Goratiev)); "half your missiles would hit a roid instead of your target, or hit your loot containers. And it was also too easy to get concorded in highsec by mistake. It was removed for these reasons" ([2014](https://eve-search.com/thread/326825-1/page/all)). A [2004 thread](https://eve-search.com/thread/91662-0/author/ElDiabloRojo) describes the old arcing launch that let a pilot "make a missile dodge a nearby obsticle, e.g. a friendly ship or an asteroid". **UNCERTAIN — strong community consensus, no CCP patch note located.**

## Quotes worth using

1. Praesus Lecti, 2006 — "Why are object (ships, stations, gates, asteroids, debris, etc) only solid when it comes to collision detection but not solid when it comes to blocking someone's ability to shoot at me and/or target me?" — [eve-search](https://eve-search.com/thread/296173-0/author/Praesus_Lecti)
2. Jacmert Corra'Halcyon, 2009 — "there's one element of realism that's missing in EVE - namely, it's currently possible to shoot **_through_** ships." — [eve-search](https://eve-search.com/thread/1000872-0/author/Jacmert_Corra'Halcyon)
3. QuakeGod, 2022 — "There is no reason to be that close to them… They aren't going to block anything. All weapons and effects go right through them…" — [EVE forums](https://forums.eveonline.com/t/asteroid-hitbox-large/364431/1)
4. Tipa Riot, 2023 — "Nope, there isn't [any hit box or line of sight]. What you see is a clever rendered illusion of the client. In fact only points (actually spheres) in space with some parameters are interacting." — [EVE forums](https://forums.eveonline.com/t/collision-physics-is-absolutly-necessary-for-a-hardcore-game-like-eve/410606/20)
5. CCP, 2025 — "Forcefields around a POS are intended to be impenetrable with no way to target or damage anyone outside of them when inside the field, nor take any damage or be targeted when inside the field by someone outside of it." — [EVE Online](https://concord-killmail.eveonline.com/de/news/view/exploit-notification-attacking-while-inside-pos-forcefields)

## Uncertainty log

- **Reddit is unverified** (login walls/403/rate limits). Treat any r/Eve-specific claim as unconfirmed.
- **No CCP statement found** saying occlusion was considered and rejected. The absence of a dev post is evidence of silence, not of a decision; CCP's 2018–2019 "no ray tracing" style arguments come from players claiming industry knowledge.
- A [2019 Russian-thread](https://forums.eveonline.com/t/topic/201126) claim that CCP's creative director periodically raises LOS at EVE events has **no primary source** — community claim.
- Titan doomsday LOS/piercing behaviour: contradictory community claims, no primary source.
