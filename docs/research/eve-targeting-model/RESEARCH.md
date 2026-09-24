# EVE Online: targeting vs. hit resolution — mechanics reference

Research for the Flor do Mar combat model. Question: how does EVE actually decide
whether a shot hits, and does it ever model a shot being blocked or intercepted by a
ship in the line of fire?

**Status legend**
- **[CONFIRMED-CCP]** — stated by CCP / Fenris in first-party material.
- **[CONFIRMED-WIKI]** — EVE University Wiki (community-maintained, official EVE Partner wiki, but not CCP).
- **[CONFIRMED-COMMUNITY]** — multiple independent community sources, no first-party statement.
- **[UNCERTAIN]** — no adequate source found; treat as a hypothesis.
- **[INFERENCE]** — my reasoning from confirmed facts, not directly stated by a source.

**Sourcing posture.** Every formula and mechanic below was traced to a primary source where
one exists. Two things are worth flagging up front because they are widely mis-stated online:

1. **CCP has never published a lock-time formula.** Their own support article is prose only.
   The `arcsinh²` formula everyone uses is community-derived (§2.2).
2. **Defender missiles do not shoot down missiles**, and have not since December 2016 — they
   shoot down *bombs* (§3.2). Almost every secondary summary still gets this wrong.

The load-bearing primary sources are CCP's 2011 turret-effects dev blog (§3.1) and CCP
Larrikin's 2016 defender-missile post (§3.2, §4.3). Where a claim rests only on community
consensus, it is marked and the reason is given.

---

## 0. The one-paragraph answer

In EVE, **locking a target fully determines who takes damage**. The uncertainty is
*whether* a shot lands, never *whom* it lands on. Turrets are not projectiles in the
mechanical sense at all: the server computes a hit probability from a formula, rolls one
random number, and that same number decides both hit/miss and damage quality. The client
then draws an effect to match the server's decision. There is no ray, no collision test,
no occlusion, and no cover. Interception *does* exist in EVE — but at the **projectile**
layer: smartbombs shoot down missiles and bombs in flight, defender missiles shoot down
bombs, and bombs destroy each other. Never at the ship layer. Nothing can body-block
anything.

---

## 1. Turret hit resolution

Source: [EVE University Wiki — Turret mechanics](https://wiki.eveuniversity.org/Turret_mechanics)
(page last edited 2026-01-02; `Turret_damage` redirects here). **[CONFIRMED-WIKI]**

### 1.1 Chance to hit

```
                                   ┌                                               2                                     2 ┐
                                   │  ( Angular velocity × 40,000 m )      ( max(0, Distance − Optimal) )                  │
Chance to hit  =  0.5 ^            │  ─────────────────────────────   +   ──────────────────────────                    │
                                   │  ( Turret tracking × Signature )     (        Falloff        )                     │
                                   └                                                                                 ┘
```

The entire parenthesised expression is the exponent. Result is a probability in `[0, 1]`.

| Term | Meaning |
|---|---|
| `Angular velocity` | rad/s — relative motion of attacker/target expressed as an angle |
| `Turret tracking` | the turret's tracking value (rad/s); "how well the turret can hit a moving target" |
| `Signature` | target signature radius (m) — bigger is easier to track |
| `40,000 m` | the former "turret signature resolution" constant, folded into the tracking number to simplify the displayed stat. Mechanics unchanged. |
| `Distance` | range in metres |
| `Optimal` | turret optimal range |
| `Falloff` | turret accuracy falloff |
| `max(0, …)` | inside optimal range the range term is zero, so it contributes nothing |

Because the form is `x^(a+b) = x^a · x^b`, the **tracking term and the range term are
independent and multiply**. Design consequence: you can reason about them separately, and
there is no interaction between "too far" and "too fast".

**Useful reference values [CONFIRMED-WIKI]:**
- `optimal + falloff` ⇒ 50% hit chance.
- `optimal + 2×falloff` ⇒ 6.25% hit chance.
- At `optimal + falloff/2` ⇒ ≈ −20% average damage; at `optimal + falloff` ⇒ ≈ −60%
  average damage. **Average damage falls faster than hit chance** (see 1.3).
- Zero angular velocity ⇒ tracking term is 1 ⇒ 100% hit chance at any range inside optimal,
  *regardless of tracking stat or target size*. This is why a battleship can one-shot a
  stationary frigate, and why "burning straight at the enemy" is a beginner's death.
- Doubling tracking, doubling target signature, or halving angular velocity have **exactly
  the same effect** on hit chance.

**Tracking-vs-angular-velocity cheat table [CONFIRMED-WIKI]** (angular velocity giving a
given hit chance, as a function of turret tracking `T` and target signature `S`):

| Hit chance from tracking | Angular velocity (rad/s) |
|---|---|
| 50% | `T × S / 40000` |
| 60% | `T × S / 47000` |
| 70% | `T × S / 56000` |
| 80% | `T × S / 70000` |
| 90% | `T × S / 103000` |
| 100% | `0` |

**Known modelling caveat, stated by the wiki itself [CONFIRMED-WIKI]:** "The equation is
not fully realistic, as it only considers the relative movement between the attacker and
the target, and does not take into account any rotation of the attacking ship."

### 1.2 One random number drives everything

This is the most important structural fact in EVE's turret model
**[CONFIRMED-WIKI]**:

- The game draws **one** random number `x ∈ [0, 1)`.
- **Hit test:** by convention, the shot hits iff `x < chance_to_hit`.
- **Damage quality:** the *same* `x` is added to `0.49` to give the damage multiplier.

```
x = rand(0, 1)

                ⎧ x + 0.49   if x ≥ 0.01
Damage mult. =  ⎨
                ⎩ 3.00       if x < 0.01     ← "wrecking hit"
```

Consequences, all [CONFIRMED-WIKI]:
- A normal hit deals **50%–149%** of paper damage.
- `x < 0.01` is a **wrecking hit** for exactly **300%** of base damage, which **ignores
  tracking and signature radius entirely**.
- The misses are precisely the rolls that *would have been the biggest hits*. Low `x` means
  both "easy to hit" and "low damage" — so damage and accuracy are coupled by construction.
- If hit chance ≤ 1%, **only misses and wrecking hits can occur**.
- At 100% hit chance the normal-hit multiplier is uniform on 50%–149%, plus a 1% spike at
  300%.

### 1.3 Hit-quality table and average damage

Hit quality labels shown in the combat log **[CONFIRMED-WIKI]**:

| Hit description | Random damage modifier |
|---|---|
| Grazes | 0.500–0.625 |
| Glances off | 0.625–0.750 |
| Hits | 0.750–1.000 |
| Penetrates | 1.000–1.250 |
| Smashes | 1.250–1.490 |
| Wrecks | 3.000 |

Normalised DPS (fraction of paper DPS actually applied) **[CONFIRMED-WIKI]**:

```
Normalized DPS = 0.5 × min( Hit_chance² + 0.98 × Hit_chance + 0.0501 ,  6 × Hit_chance )
```

Worked example from the wiki: at **70% hit chance** the damage band has already shrunk to
**50%–119%** for non-wrecking hits, giving **61.3%** of base damage on average, not 70%.
At 50% hit chance you get **40%** of paper DPS. **[CONFIRMED-WIKI]**

### 1.4 Weapon grouping does not merge the roll

- Grouped weapons are **still resolved as separate turret shots**; the combined damage
  distribution is a sum of independent rolls. Evidence given: firing a group deep into
  falloff lets you tell when one, two, or more guns hit. **[CONFIRMED-WIKI]**
- CCP's weapon-grouping dev blog confirms grouping is a *UI/management* feature: "this
  feature only stays a way of displaying turrets/launchers in the module panel, it does not
  physically group weapons together in the fitting screen"; "it will not be possible to
  attack multiple targets with the grouped bank."
  [CCP — Weapon Grouping (2008-10-23)](https://www.eveonline.com/news/view/weapon-grouping) **[CONFIRMED-CCP]**

### 1.5 Term definitions

| Term | Definition | Source |
|---|---|---|
| **Tracking speed** | Turret stat, rad/s. Smaller/short-range turrets track faster than larger/long-range ones. Compared against angular velocity scaled by target signature. | [Turret mechanics](https://wiki.eveuniversity.org/Turret_mechanics) |
| **Angular velocity** | `ω = v_transversal / d`. Rate of change of the bearing to the target, rad/s. Symmetric: both ships have the same angular velocity to each other. | [Turret mechanics](https://wiki.eveuniversity.org/Turret_mechanics) |
| **Transversal velocity** | The component of relative velocity perpendicular to the line of sight (`= ω × d`). The raw m/s input; angular velocity is the range-normalised version the formula actually uses. | [Turret mechanics](https://wiki.eveuniversity.org/Turret_mechanics) |
| **Signature radius** | "How big a ship appears on sensors" — the ship's effective footprint in metres. Governs lock time, turret tracking, missile damage, bomb damage, probe detection. **Smartbombs are the one weapon system unaffected by sig radius.** | [Signature radius](https://wiki.eveuniversity.org/Signature_radius) |
| **Signature resolution** | The `40,000 m` legacy constant expressing the target size a turret was designed for. Merged into the tracking stat; to use the old form, replace `40,000` with `Turret Signature Resolution`. Old→new conversion: `tracking_new = tracking_old × 40,000 / Optimal_Signature_Resolution`. **Distinct from scan resolution** (see §2). | [Turret mechanics](https://wiki.eveuniversity.org/Turret_mechanics) |
| **Optimal range** | Range within which distance has **no** effect on hit chance. | [Turret mechanics](https://wiki.eveuniversity.org/Turret_mechanics) |
| **Falloff (accuracy falloff)** | Begins at the end of optimal. Measures how fast hit chance decays with extra distance; contributes `0.5^(...)` on its own identical curve to tracking. | [Turret mechanics](https://wiki.eveuniversity.org/Turret_mechanics) |

Indicative signature radii **[CONFIRMED-WIKI]**, [Signature radius](https://wiki.eveuniversity.org/Signature_radius):
Capsule/Shuttle 25 m · Frigate 38 m · Destroyer 65 m · Cruiser 120 m · Battlecruiser 270 m ·
Battleship 400 m · Dreadnought 11,200 m · Titan 23,397 m.
(Named hull examples from the turret page: Tormentor 35 m, Thrasher 56 m, Caracal 125 m,
Brutix 305 m, Tempest 360 m.)
**MWD increases signature radius by 500%** while active — the central tradeoff of
speed-tanking.

### 1.6 Verification — the formulas reproduce every published example

**[INFERENCE — my arithmetic, but it independently confirms the community formulas.]**
I implemented §1.1–§1.3 and checked every worked example the wiki publishes. All reproduce:

| Check | Formula output | Wiki's stated figure |
|---|---|---|
| Medium autocannon (tracking 50) vs cruiser (150 m sig) at 0.073 rad/s | **90.0%** | 90% ✓ |
| Same gun vs frigate (50 m sig) at 0.073 rad/s | **38.8%** | 39% ✓ |
| Hit chance at `optimal + falloff` | **50.00%** | 50% ✓ |
| Hit chance at `optimal + 2×falloff` | **6.25%** | 6.25% ✓ |
| Normalised DPS at 50% hit chance | **39.5%** | ~40% ✓ |
| Normalised DPS at 70% hit chance | **61.3%** | 61.3% ✓ (exact) |
| Damage-band ceiling at 70% hit chance | **1.19×** | 119% ✓ |

This is the strongest available evidence that the EVE University formulas are correct: they
are internally consistent and reproduce every independent example the source gives, including
the two derived quantities (normalised DPS, damage-band shrinkage) that a transcription error
would break. **Confidence in §1 is high.** The formulas are still community-derived rather
than CCP-published — but they behave exactly as the game is documented to behave.

---

## 2. What exactly is "the target" in EVE?

**Locking a target is a prerequisite for acting, not a guarantee of hitting.** The lock
answers *"which object am I acting on"*. The hit roll (or the missile's flight) then answers
*"did the action succeed"*. These are entirely separate systems with different inputs —
and the confusion between them is the single most common modelling mistake when copying EVE.

### 2.1 The locking process **[CONFIRMED-WIKI]**

[EVE University Wiki — Targeting](https://wiki.eveuniversity.org/Targeting)

Three distinct states: **unlocked → locking (timer running) → locked**. A countdown timer
animates around the object; only on reaching zero is the target locked and modules
activatable. Module activation requires the *locked* state.

Two paths to lock:
- **Active targeting** — select via overview / click in space / radial menu / `CTRL`
  (default target key, `SHIFT+CTRL` to untarget). The target is alerted.
- **Passive targeting** — fit a **Passive Targeter** (mid slot) and activate it, then click
  the target. Lets you run *non-aggressive* modules (cargo scanner, ship scanner) without
  alerting the target. The only silent lock path. **[CONFIRMED-WIKI]**

### 2.2 Lock time formula

```
                        40,000 m
Targeting time  =  ─────────────────────────
                   Scan resolution × arcsinh²(Signature radius)
```

- `Scan resolution` — your ship's sensor stat, in **mm**.
- `Signature radius` — the target's, in **m**.

**Sourcing caveat, and it is important. [CONFIRMED-CCP for the absence]** CCP's own
["Locking Times" support article](https://support.eveonline.com/hc/en-us/articles/207110329-Locking-Times)
(dated 2024-07-15) is **five paragraphs of prose with no formula and no variable
definitions**. It says only that locking time "depends upon the Scan Resolution of their
ship and the Signature Radius of the target", that high scan resolution locks fast, that
high target sig radius is locked fast, that large ships are slow-locking and easy to lock,
that extreme scan resolution produces an "**Insta Lock**", and that both stats are modified
by modules/rigs. The live URL also returns Cloudflare 403 to automated fetch; verified via
[Wayback snapshots](https://web.archive.org/web/20250322014429/https://support.eveonline.com/hc/en-us/articles/207110329-Locking-Times),
which I read independently and which the sub-investigation confirmed separately.

**Therefore: there is no CCP-published lock-time equation.** The `arcsinh²` formula above is
**community-derived [CONFIRMED-WIKI]**, universally used but not first-party. Cite it as
such.

**Direction check — get the arrangement right.** `arcsinh²(sig)` belongs in the
**denominator**: bigger target ⇒ *faster* lock, which is the whole point of the mechanic.
The frequently-mis-transcribed form `(40,000 / ScanRes) × arcsinh²(Sig)` inverts the
significance of signature radius and is wrong.

**I verified the formula numerically** against the wiki's own worked examples
(**[INFERENCE — my arithmetic, on community-sourced constants]**):

| Case | Formula output | Wiki's stated figure |
|---|---|---|
| Kestrel (600 mm) locking Typhoon (≈340 m sig) | **1.57 s** | ~1.5 s ✓ |
| Omen (≈310 mm) locking a Shuttle (25 m) | **8.4 s** | ~9 s ✓ |
| Typhoon (150 mm) locking a Shuttle (25 m) | **17.4 s** | ~23 s ✗ |
| Typhoon (150 mm) locking a Kestrel (35 m) | **14.8 s** | ~19 s ✗ |

Monotonicity is correct in both directions (higher scan resolution ⇒ faster; higher
signature ⇒ faster). **The two Typhoon-to-small-ship figures in the wiki's prose do not
reconcile with its own formula** — most likely stale example data predating a stat change,
plus whole-second rounding. Trust the formula; do not quote the 19 s / 23 s anecdotes as
derived results. **[UNCERTAIN — flagged.]**

**Worked feel (treat as indicative only):** a frigate locks a battleship in a couple of
seconds; a battleship takes on the order of 15–25 s to lock a small frigate; interceptors
such as the Stiletto lock almost anything in under 2 s. **[CONFIRMED-WIKI for the shape,
UNCERTAIN for exact seconds.]**

**Scan resolution modifiers [CONFIRMED-WIKI]:** Sensor Booster (mid, scriptable),
Signal Amplifier (+10% T1 / +15% T2), Targeting System Subcontroller rig,
Zainou 'Gypsy' Signature Analysis implants (1–6%), Remote Sensor Boosters from fleetmates.
Skill: **Signature Analysis**, 5% faster locking per level.
Penalties: **cloaking devices −50% scan resolution** (covert ops cloaks exempt),
**warp core stabilisers −50%**.

### 2.3 Scan resolution ≠ turret signature resolution

This is the trap the wiki calls out, and it matters for our design vocabulary.

| | **Scan resolution** | **Turret signature resolution** |
|---|---|---|
| Belongs to | the **ship's sensors** | the **weapon** |
| Unit | mm | m |
| Used in | **lock time only** | the turret hit-chance equation (`40,000 m` term) |
| Affects hit chance? | **No** | Yes |
| Affects lock time? | Yes | **No** |

Compounding the confusion: **both** formulas contain the constant `40,000`. In turret maths
`40,000 m` *is* the legacy optimal signature resolution, now folded into the tracking stat
(`tracking_new = tracking_old × 40,000 / Optimal_Signature_Resolution`). In the lock formula
it is an unrelated scaling constant. The genuine shared input is the **target's signature
radius**, which both systems consume — that is the real source of the mix-up.
**[CONFIRMED-WIKI]**

### 2.4 Maximum locked targets **[CONFIRMED-WIKI]**

- **Base: 2** with no skills.
- `Target Management` (1x): **+1 per level**, capped by hull.
- `Advanced Target Management` (3x, requires Target Management V): **+1 per level**.
- **Practical hard cap: 12** (both skills at V, in a hull that supports it).
- Effective limit = `min(2 + TargetMgmt + AdvTargetMgmt, hullMaxTargets + module bonuses)`.
- Hull examples: **Merlin 5**, **Typhoon 7**, **Golem 10**. T3 strategic cruisers depend on
  fitted subsystems.
- Modules: **Signal Amplifier** (low) +1 T1 / +2 T2; **Auto Targeting System** (high)
  +2 T1 / +3 T2.
- `Multitasking` is a **legacy skill** (pre-2013), replaced rather than retained
  **[UNCERTAIN — indirect evidence only]**.

### 2.5 Targeting range **[CONFIRMED-WIKI]**

- Base from hull `maxTargetRange`. `Long Range Targeting` +5%/level (max +25%).
  Signal Amplifier +25%/+30%. Sensor Booster (scriptable). Ionic Field Projector rigs.
  Zainou 'Gypsy' Long Range Targeting implants. Remote Sensor Boosters from fleetmates.
  Warp core stabilisers heavily reduce it.
- **Hard cap: 300 km** for all ships except carriers/supercarriers; **490 km** for Upwell
  structures. "Targeting range cannot go beyond these limits regardless of how many bonuses
  are applied."

### 2.6 What breaks a lock **[CONFIRMED-WIKI]**

- **ECM** — a successful jam makes the victim **lose all current locks except the jammer**,
  and prevents locking anything other than the jammer for the module cycle (**20 s**).
  Jam chance = `ECM strength / sensor strength`, rolled binomially for multiple jammers;
  jam strength falls off like turret falloff (50% at optimal+falloff).
- **Remote sensor dampening** — reduces the victim's targeting range (and scan resolution
  with the right script); the lock break is a *consequence* of the range reduction, not a
  direct lock deletion.
- **Warping** — all locks drop.
- **Target destroyed.**
- **Target leaves max targeting range** — **[UNCERTAIN]**: universally stated by the
  community and implied by dampener usage, but no first-party statement found.
- **Cloaking** (self or target).

---

## 3. Is a shot ever blocked or intercepted by a third ship?

### 3.1 Turrets: no occlusion, and the shot is not a ray at all — **[CONFIRMED-CCP]**

The decisive first-party source is CCP's dev blog on turret miss effects:

> [CCP — "Turret Effects: I don't always miss, but when I do... I do it with style." (CCP Choloepus, 2011-11-18)](https://www.eveonline.com/news/view/turret-effects-i-don-t-always-miss-but-when-i-do...i-do-it-with-style.)

Key statements, verbatim:

- "the effects from these turrets will soon **visibly fail to hit your target when the
  server decides that the shot went astray**." — The server decides hit/miss first; the
  client renders an effect to match. **The visual is downstream of the probability roll.**
- "Shots which miss are picking a point to aim at based on the **bounding sphere of the
  target**" — a miss is drawn on/around the *intended target*, so a miss cannot be rendered
  as hitting a different ship.
- "**Missiles aren't affected.** The mechanics of (and code for) missile combat is very much
  a different kettle of squamous betentacled beasties."
- "**Only shots fired by or at your ship will get this treatment.** The larger fleet battle
  around you will look like the current situation on TQ." — For third-party shots in a large
  fight, the client has **no hit/miss information at all** and plays cosmetic animations.
  This is direct evidence that turret firing visuals are not authoritative simulation.
- The blog also enumerates the inputs to the turret roll, including "**signature
  radius/resolution**", confirming both are live attributes in the pipeline.

**[INFERENCE]** Therefore, in EVE:
- There is no line-of-fire ray to intersect anything.
- A shot at ship A can never damage ship B.
- No ship can body-block a turret shot, deliberately or accidentally.
- The only way to "protect" an ally from turret fire is to reduce the shooter's hit chance
  against them (sig/speed/EWAR) or to break the lock — never to interpose.

### 3.2 Where EVE *does* model interception: the projectile layer — **[CONFIRMED-CCP]**

EVE has real, physically travelling objects — **missiles** and **bombs** — and those *can*
be intercepted. This is the sharpest design lesson in the whole system: interception exists
in EVE, but it intercepts **ordnance**, never **ships**.

**Defender missiles — and the important correction.** Defender missiles **do not shoot down
missiles** any more; since the December 2016 release they shoot down **bombs**:

> [CCP Larrikin, "Sticky: [December] Defender Missiles", EVE Online forums, 2016-11-25](https://eve-search.com/thread/501519-1/author/CCP%20Larrikin)

Verbatim from the CCP post **[CONFIRMED-CCP]**:
- "Defender Missiles **will no longer shoot down missiles aimed at you**. Instead they will
  launch at a **random bomb** (non-structure) within its flight range. **A single defender
  missile will kill any bomb.**"
- Skill: `Defender Missiles` gives 10%/level to defender missile velocity; "No other skills
  will effect Defender Missiles."
- Launcher: "It may only be fit to **Destroyer class vessels** (Destroyers, Interdictors,
  Command Destroyers and Tactical Destroyers). Once activated, it will scan local space for
  any bombs, and if it finds one within range, launch a defender missile to intercept it.
  **If it doesn't find any bombs within range, it will still cycle.** The Defender Launcher I
  has a **120 second reactivation timer**." No launcher hardpoint needed; 10 CPU, 2 PG, 50 GJ.
  Command Destroyers get a 50% role bonus to the reactivation timer.
- Defender Missile I: base range 30 km (45 km at max skills), flight time 3 s.
- **Target selection is random, and side-blind:** asked whether defenders distinguish
  friendly from non-friendly bombs — "**They do not**, they target a random bomb within
  intercept range. It does not consider friendly or non-friendly bombs." Asked whether it
  picks the closest — "**Its truly random.**"
- Structural guided bombs: "Nope." Not interceptable.
- Guidance disruptors do not work on defender missiles.

**Bombs** [EVE University Wiki — Bombs](https://wiki.eveuniversity.org/Bombs) **[CONFIRMED-WIKI]**:
- "ranged, **untargeted**, area-of-effect (AoE) weapons", restricted to stealth bombers and
  Upwell structures, **banned in empire space** (null sec / wormhole only).
- "on stealth bombers they are **unguided, do not require a locked target** to be launched,
  and depend on the **launching ship's orientation** to aim."
- Travel in a straight line from the launcher, **detonating at 30 km** from the launch point.
  Damage bombs 2,500 m/s × 12 s; Void/Lockbreaker 4,000 m/s × 7.5 s; Focused Void
  2,000 m/s × 15 s.
- "Upon detonation, bombs cause damage or other disrupting effects to **all ships within a
  15 km radius** of the detonation. These effects are **indiscriminate, and are applied to
  all ships within the blast zone, including any allies and even the launching ship.**"
- "Like missiles, bombs have very few hit points, and **can be destroyed by defender
  missiles, smartbombs, and even other bombs.**"
- "the interference of **friendly bombs** can be a very real concern during larger fleet
  operations."
- Lockbreaker Bombs apply ECM jamming to **all** ships in the area — "they should be used
  with care."

So EVE's interception stack is: **bombs ← defender missiles / smartbombs / other bombs**.
Nothing intercepts a turret shot, and nothing intercepts a *ship*.

**Smartbombs are EVE's real missile defence — "firewalling".** Missiles are genuine objects
with structure HP:

> "While these entities are not visible on the overview nor selectable, they **can** decloak
> ships, and have structure hp that can be damaged or even be destroyed by area-of-effect
> damages like Smartbombs, Bombs, and Guided Bombs."
> — [Missiles](https://wiki.eveuniversity.org/Missiles) **[CONFIRMED-WIKI]**

> "This feature also enabled a strategy known as **'Firewalling'**, in which multiple
> smartbombs are used to block out and destroy incoming missiles… it can greatly reduce a
> fleet's incoming (and outgoing) missile damage."
> — [Missiles](https://wiki.eveuniversity.org/Missiles) / [Smartbombs](https://wiki.eveuniversity.org/Smartbombs)

Pilots are warned to "avoid destroying their missiles with their smartbombs by avoiding
fitting or activating them at the same time" — **your own AoE shoots down your own
ordnance.** *(The source's "(and outgoing)" phrasing is odd; treat the outgoing half as
[UNCERTAIN].)*

**Structural finding:** EVE has an anti-**bomb** ship module (Defender Launcher, destroyers
only), anti-**bomb** structure rigs, and an anti-**everything-nearby** module (smartbomb). It
has **no dedicated anti-missile system** for player-launched missiles other than smartbomb
firewalling — a direct consequence of Defender Missiles being reassigned to bombs in 2016.

**A structure module that *sounds* like point defence but is unverified.** The **Standup
Point Defense Battery** is an Upwell Area Denial Module: 12 s activation, 1,500 GJ,
**2,500 m area-of-effect radius**, 200 charges of *Standup Flak Round I* per cycle,
"Banned in High Sec Space: true"; fits Fortizar/Keepstar/Azbel/Sotiyo/Tatara
([EVE Ref SDE mirror](https://everef.net/types/35926)). **[UNCERTAIN]** whether it explicitly
intercepts incoming missiles/bombs or simply deals 2,500 m-radius AoE damage — the SDE
exposes an AoE radius and no missile-interception attribute, and no CCP statement or wiki
page confirms anti-missile behaviour either way. **Do not claim it as point defence.**

### 3.3 Weapons that *do* hit unintended targets **[CONFIRMED-WIKI]**

Turret shots and missiles never hit a third party. These do:

| Weapon | Mechanism | Friendly fire? |
|---|---|---|
| **Smartbomb** | Untargeted AoE originating from your own ship; ~10 km class ceiling (T1 practical: micro 2 km, small 3 km, medium 4 km, large 5 km). Damage ignores sig radius and speed; mitigated only by resistances and absence from the blast. | **Yes** — "Both friends and foes are damaged"; **your own drones too**. Sole exception: the activating ship. Does not damage wrecks or Upwell structures. Needs **red safety** in highsec. Cannot fire near stations/stargates/accel gates. |
| **Bomb** | Untargeted, orientation-aimed, straight line, detonates at 30 km, 15 km sphere. Damage bombs 2,500 m/s × 12 s. Fixed 400 m explosion radius, sig-scaled, **speed-independent**. Banned in empire space (allowed in fully-corrupted lowsec). | **Yes** — "including any allies and even the launching ship". 99.8% resistance to their own damage type, so bomber wings standardise on one type to avoid destroying each other's bombs. |
| **Vorton Projector** | Chain lightning from the locked target, arcing to **up to nine additional random ships or drones within 10 km of the primary**. Does **not** chain onward from bounced entities. **Never hits the firing ship.** Uses missile damage mechanics (explosion radius/velocity), not tracking. | Safety-gated: "with full safeties enabled will only bounce to legal targets" — but bounces can initiate Limited Engagements "even if they were not targeted". **[UNCERTAIN]** whether it damages fleetmates in null/wormhole. |
| **Standup Guided Bomb** | Structure weapon, **targeted** (gunner picks a ship), 20 km AoE, 2,800 (light) / 9,600 (heavy) omni. "If that ship warps off before it is hit, the bomb just continues to drift in space until its maximum flight time of 400 seconds ends" — so it can catch others. | **[UNCERTAIN]** — not stated in sources found. |
| **Titan Lance / Reaper / Bosonic Field Generator** | Explicit AoE *templates*: Lance 2.5 km radius × 200 km line; Reaper 5 km radius sweeping beam; Boson 30 km cone. All emit a **10 km, 35,000 GJ energy-neutralising pulse** when charging. | **Yes** — the pulse "affects friend and foe alike". AoE superweapons cannot be activated in lowsec. |
| **Doomsday (single-target)** | 1,000,000 (1,500,000 max skills) damage to one capital after a 9 s delay. Targeted, **no intervening-object check**. | No. |

**The Titan Lance is worth flagging in a design discussion precisely because it *looks* like
line-of-fire geometry while being nothing of the sort**: it is a fixed 200 km × 2.5 km damage
template that hits everything inside it, with no occlusion and no friendly filter. A player
watching it would reasonably assume EVE models a beam. It does not.
[EVE Uni Wiki — Titans](https://wiki.eveuniversity.org/Titans)

### 3.4 The "why doesn't my shot hit the ship in front of me" question

See §7 for the community thread evidence. Short version: players do raise it, the
observation is correct, and CCP's answer is structural — the model has no notion of line of
fire to begin with.

---

## 4. Missiles vs turrets for target switching / lost locks / target death mid-flight

### 4.1 Turrets

Turrets resolve **at the moment the module cycle completes**, against the locked target's
state then. There is no projectile in flight to lose. **[INFERENCE from §1.2 + §3.1]**
The turret formula is evaluated with the current distance/angular velocity/signature of the
locked target; what matters is whether a valid lock exists and where the target is at
resolution time.

### 4.2 Missiles are real objects with travel time **[CONFIRMED-CCP]**

From [Missile mechanics](https://wiki.eveuniversity.org/Missile_mechanics) **[CONFIRMED-WIKI]**:
- "There is **no way to control the path of a missile once it has been launched**. It will
  point itself at its target and follow the target until it hits or runs out of fuel."
- "If it encounters the target during that time, it will explode — otherwise it will
  **vanish**." Missiles have a fuel/flight time (max distance ≈ speed × seconds of fuel).
- A missile "does not so much 'hit' a ship as explode near it" — when the missile crosses the
  target's signature radius it detonates, and damage is then computed by the explosion
  formula. Missiles therefore reach the target even if the *shooter's* lock has since been
  broken. **[INFERENCE: the wiki states missiles home on the target and are uncontrollable;
  nothing in the source conditions impact on the shooter retaining a lock.]**
- Missile damage uses the target's **absolute velocity**, not angular velocity:

```
Damage = D × min( 1 ,  S/E ,  ( (S/E) × (Ve/Vt) )^drf )
```

`S` = target sig radius, `E` = missile explosion radius, `Ve` = explosion velocity,
`Vt` = target velocity, `D` = base damage, `drf` = damage reduction factor (undisclosed in
game; published by CCP in the [content creation toolkit](https://community.eveonline.com/community/content-creation/toolkit/)).

- Practical form: damage begins to drop when `Vt > S × (Ve/E)`, the missile's "minimum
  velocity factor".
- **Missiles always do *some* damage on arrival** — never a clean miss, unlike turrets.

### 4.3 Target destroyed or off-grid before impact — definitive CCP answer **[CONFIRMED-CCP]**

Asked directly what happens if a defender missile's bomb is destroyed by another defender:

> "The defender missile **won't re-target** another bomb. It will **wander off into the
> distance like all missiles fired at something that is destroyed or leaves grid before the
> missile hits. Lost, and alone :(**"
> — [CCP Larrikin, 2016-11-25](https://eve-search.com/thread/501519-1/author/CCP%20Larrikin)

This is the general rule for **all** missiles, stated by a CCP game designer: **no
retargeting, no proximity detonation on whatever is nearby — the missile is simply wasted.**
A missile cannot accidentally hit a different ship that happens to be in its path.

### 4.4 Shooter warping removes its own missiles **[CONFIRMED-WIKI]**

> "To prevent the obvious exploit of launching missiles and then warping out before the
> missiles connect, **if a ship enters warp, all of the missiles it has in-flight vanish
> immediately.**"
> — [Missiles](https://wiki.eveuniversity.org/Missiles)

Consequence: "especially at long range, missile ships must stay on grid until all of their
fired missiles have landed, to avoid losing damage." Called out as most acute for stealth
bombers making torpedo runs.

### 4.5 Turret vs missile contrast, for design purposes

| | Turret | Missile |
|---|---|---|
| Resolution | Instant roll at cycle end | Travelling object, impact later |
| Can miss entirely | Yes (probabilistic) | **No** — always applies *some* damage |
| Damage variability | Random 50–149%, 3× wrecking | Deterministic from geometry/velocity |
| Key defensive stat | Angular velocity + sig radius | Absolute velocity + sig radius |
| EWAR counter | Tracking disruptor | Guidance disruptor |
| Target dies mid-flight | N/A (already resolved) | Missile wasted, no retarget (CCP) |
| Shooter warps | N/A | Own in-flight missiles vanish |
| Can be intercepted | No | Not by any current mechanic (defenders only hit bombs) **[UNCERTAIN — see §3.2; no current anti-missile system found]** |

---

## 5. Target destroyed, out of range, auto-targeting, and "assist"

### 5.1 Locks drop; weapons do not retarget **[CONFIRMED-CCP / CONFIRMED-WIKI]**

There is **no auto-relock and no target switching.** When a locked target is destroyed or
leaves range, the lock is gone. Missiles already in flight get no new target — CCP's rule,
quoted in full in §4.3: they *"wander off into the distance like all missiles fired at
something that is destroyed or leaves grid before the missile hits."*
A turret rack simply goes **Inactive** and must be manually re-activated on a new target.

**[UNCERTAIN — flag before citing]** Does an already-started turret cycle complete and land
its shot if the target dies mid-cycle? The standard community answer is **yes, the cycle
completes regardless**, sourced only to a [2006 EVE-O thread](https://eve-search.com/thread/381938-0/page/all)
("every weapon has a cycle time, so when a shot is fired it'll wait to complete the cycle,
regardless if the target is still there or not"), and EVE University Wiki does **not**
document it. Treat as high-confidence but not properly verified.

**The documented exception worth stealing [CONFIRMED-WIKI]:** Triglavian **Entropic
Disintegrators** "will deactivate if their target leaves optimal range. If a disintegrator
deactivates for any reason, its damage bonus is **reset to 0**"
([Turrets](https://wiki.eveuniversity.org/Turrets)). This is EVE's one weapon whose cycle
state is explicitly bound to the target relationship — players use ECM drones specifically
to "break the damage ramp-up on a Triglavian entropic disintegrator"
([Electronic warfare](https://wiki.eveuniversity.org/Electronic_warfare)). It is the cleanest
first-class example of *losing the target visibly costing you something*.

### 5.2 Auto-targeting: two entirely separate systems **[CONFIRMED-WIKI / CONFIRMED-CCP-data]**

**(a) Auto Targeting System (module).** High slot. "Targets any hostile ship within range on
activation." Grants **+2 (T1) / +3 (T2)** to max locked targets. T1: 50 km range, 5 s
activation, 8 GJ, requires Target Management I. T2: 60 km, 5 s, 10 GJ, requires Target
Management IV. Sources:
[ATS I](https://newedenencyclopedia.net/type/1182-Auto%20Targeting%20System%20I.html),
[ATS II](https://newedenencyclopedia.net/type/1436-Auto%20Targeting%20System%20II.html),
[Targeting](https://wiki.eveuniversity.org/Targeting). Rarely used — it eats a high slot and
removes target prioritisation; some pilots fit it purely for the +2 target bonus.

**(b) Auto-Targeting (FoF) missiles.** These genuinely fire without a lock:

> "When fired, an Auto-Targeting Missile will locate and target the **nearest enemy ship or
> drone that has previously fired on you**. Auto-targeting missiles **do not require the user
> to be locked on** to the targets they engage; however as they cannot be deliberately aimed,
> deal less damage, and have a hard maximum range beyond which they will not acquire targets,
> auto-targeting missiles are usually passed over in favour of regular missiles."
> — [Missiles](https://wiki.eveuniversity.org/Missiles) **[CONFIRMED-WIKI]**

The `Auto-Targeting Missiles` skill is 3x and **not trainable by Alpha clones**
([Skills:Missiles](https://wiki.eveuniversity.org/Skills:Missiles)). Published DRF/MVF
values: AT Light 0.604 / 4.25, AT Heavy 0.682 / 0.579, AT Cruise 0.882 / 0.209
([Missile mechanics](https://wiki.eveuniversity.org/Missile_mechanics)).
**[UNCERTAIN]** whether FoF acquires neutrals/NPCs, or only entities that have aggressed you.

This is the one place in EVE where the answer to "who does the shot hit?" is genuinely
*not* the locked target — and it is deliberately made worse (lower damage, hard acquisition
range) so that it stays a niche fallback rather than a strategy.

### 5.3 Drone assist / guard / aggressive — EVE's real "assist" **[CONFIRMED-WIKI]**

> "**Assist**: If you give this command your drones will assist a member of your fleet, and
> will engage whatever target they are attacking." "**Guard**: Similar to Assist, except that
> your drones will engage whatever ships **attacks** the fleet member you order your drones to
> guard."
> — [Drones](https://wiki.eveuniversity.org/Drones)

- **To order a drone onto a specific target you must yourself have that target locked** —
  but once ordered, drones pursue the target beyond control range and regardless of whether
  you still hold the lock. **[CONFIRMED-WIKI]**
- **Drone control range: 20 km base**, +5 km/level Drone Avionics, +3 km/level Advanced Drone
  Avionics ⇒ **60 km at both V**; +20 km (+24 km T2) per Drone Link Augmentor; +15/20 km from
  the Drone Control Range Augmentor rig. Drones shut down beyond **500 km**, or if the host
  ship warps. **[CONFIRMED-WIKI]**
- Assist/Guard is set by the **last command only**; any new order overwrites it and drones
  revert to default (orbit you)
  ([forum thread](https://forums.eveonline.com/t/drone-assist-and-manuel-targeting/345821)).
- **Nerf history [CONFIRMED-CCP]:** from December 2020, the **Aggressive** drone setting
  "respond only to direct offensive actions taken by another Capsuleer (player) or their
  controlled drones" — so drones set to aggressive **no longer auto-attack NPCs**, and
  assist/guard stopped working for NPC-killing
  ([CCP_Paradox — Upcoming Changes to Drone Aggression](https://forums.eveonline.com/t/upcoming-changes-to-drone-aggression/281713)).
- **Auto Attack** (drone cog menu, default **Disabled**): when enabled, drones attack any
  entity aggressing them or the ship, using "the same targeting logic as auto-targeting
  missiles", and only react to hostiles that aggressed *after* launch. Focus fire applies
  only with Auto Attack enabled. **[CONFIRMED-WIKI]**
- **[UNCERTAIN]** Whether assist works against player targets in all security classes; a 2024
  player report of it failing in highsec/lowsec was attributed by other players to aggression
  timers rather than a general disable
  ([forum thread](https://forums.eveonline.com/t/drone-assist-doesnt-attack-other-capsuleers/465376)).

**Design note:** drone assist is EVE's *delegated fire* mechanic, and it is interesting
precisely because it is the inverse of occlusion — a second ship's weapons key off *your*
target selection. It is the closest EVE comes to "fleet focus fire" as a modelled mechanic
rather than a social convention.

---

## 6. Friendly fire between fleet members

### 6.1 The rules are about *legality*, not damage immunity — **[CONFIRMED-CCP]**

CCP's own explanation of aggression rules:

> [CCP_Aurora, "Can I shoot or not?" (2020)](https://devtrackers.gg/eveonline/p/9ed335ec-can-i-shoot-or-not) — mirrored from the official EVE dev tracker.

- 1.0–0.5 (highsec): "you cannot shoot unless they're either suspect (yellow flashing),
  criminal (red flashing), have a limited engagement with you (cyan flashing), or at war
  with you (red star flashing)." Safety set to yellow prevents accidental CONCORD;
  safety red lets you shoot illegally and "concord will respond after a few seconds and
  destroy you (there is no avoiding this)."
- 0.4–0.1 (lowsec): "you can shoot anyone safely as long as you're not on a gate or a
  station." Committing a crime on a gate/station makes the structure guns shoot back.
- "In 0.0 and lower (including wormhole space) **you can shoot whoever you'd like with no
  repercussions**."
- Defensive rights: "if someone is shooting at you already you're legally allowed to defend
  yourself... However **simply having a target lock on you is not enough**."

None of this is damage immunity. It is a flag/CONCORD system layered on top of a model in
which **any ship can damage any other ship**.

### 6.2 Corporation "friendly fire" setting **[CONFIRMED-CCP]**

> [CCP Punkturis — "Corp Little Things & Friendly Fire Control" (2015-02-09)](https://www.eveonline.com/news/view/corp-little-things-friendly-fire-control)

- CEOs/directors can configure whether **friendly fire within the corporation is legal**,
  with a 24-hour activation delay and public visibility of the setting.
- "When friendly fire is set to **legal**, aggression between two corp-mates will behave
  exactly as it does now in a player corp" — i.e. **you really do damage them**.
- "When set to **Illegal**, aggressive acts will follow the same rules as they currently do
  in NPC corporations: attacks will invoke CONCORD (in high sec), trigger a security status
  penalty and also a Criminal/Suspect flag."
- "Duels, kill-rights, outlaw flagging and similar situational events will always provide a
  way to legally attack corp-mates, and will override the friendly fire setting."
- "In null-sec and wormhole space, **everyone is always a valid target**, so nothing will
  change here."
- **Existing player corporations defaulted to friendly fire being LEGAL.**
- Design motivation stated: to give corps an intermediate risk setting between "anyone can
  legally shoot you" and "don't join a corp at all".

**Critically, the gate is the *corporation*, not the *fleet*.** Nothing in any source found
indicates that being in the same fleet grants damage immunity. **[INFERENCE / partly
UNCERTAIN — see §6.4.]**

### 6.3 Summary: friendly fire is per-weapon, not global

See §3.3 for the full mechanics table. The shape of it:

| Weapon | Hits allies? |
|---|---|
| **Turrets** | **Never** — only ever the locked target. |
| **Missiles** | **Never** — only the intended target; wasted if it dies. |
| **Smartbombs** | **Yes** — everything in radius except the firing ship, including your own drones. |
| **Bombs** | **Yes** — "including any allies and even the launching ship." |
| **Lockbreaker Bombs** | **Yes** — ECM burst to all ships in the AoE. |
| **Vorton chains** | Safety-filtered to "legal targets"; friendly behaviour in null/wormhole **[UNCERTAIN]**. |
| **Defender missiles** | Side-blind by design: "It does not consider friendly or non-friendly bombs." |
| **Titan AoE superweapons** | **Yes** — the charging pulse "affects friend and foe alike". |

**EVE's dial is per weapon type, not a single global toggle.** That is the transferable idea.

### 6.4 Fleet membership grants no damage immunity — **[CONFIRMED-WIKI]**

**There is no hard game rule preventing damage to a fleetmate.** Fleet membership is an
organisational and overview construct. The only gate is *legality*.

Positive evidence:
- Drones: "Note that your drones will engage whatever you order them to, **including your
  other drones or your fleetmates**." ([Drones](https://wiki.eveuniversity.org/Drones))
- Logistics guidance: "it's important to avoid accidentally shooting corporation members in
  mixed fleets, **since that can be a legal action in and by itself if the corporation has
  friendly fire enabled** (which most corporations have)."
  ([Remote assistance](https://wiki.eveuniversity.org/Remote_assistance))
- Nullsec/wormhole: CCP — "everyone is always a valid target."

Fleet membership *discourages* friendly fire socially and via overview icons, but does not
prevent it mechanically.

**Practical answer to "can you shoot your own fleetmate?"** Yes. In nullsec/wormhole always.
In lowsec at the cost of a Suspect flag. In highsec, only if they are flashy
(suspect/criminal/outlaw/war target/duel/limited engagement) or a corp-mate in a corp with
friendly fire set to Legal (the default) — otherwise CONCORD destroys you. **Fleet membership
by itself changes nothing.**

**Safety settings are an action-prevention gate, not damage immunity**
([Safety settings](https://wiki.eveuniversity.org/Safety_settings)) **[CONFIRMED-WIKI]**:
- **Enable safety (green)** — "prevent all actions that would give you suspect or criminal
  status". The game simply refuses the action and throws an error into the combat log.
- **Partial safety (yellow)** — prevents criminal-status actions, allows suspect-status ones.
- **Disable safety (red)** — allows both.
- Default is green. Alpha clones in highsec cannot set red. Upwell-structure controllers in
  highsec cannot set yellow or red.

So with green safety in highsec you *cannot activate* an offensive module on a friendly — but
that is a legality guard rail keyed to the **target's flag status**, not to the firing line
and not to fleet membership. There is no geometry in the check.

**The one genuine hard block on a friendly action found anywhere in EVE** (worth noting
because it shows what a *real* rule looks like): while a warp disruption field generator is
active, the ship "suffers a 50% increase to its signature radius, and **cannot be targeted by
allied remote repairs or capacitor transmitters**" ([Tackling](https://wiki.eveuniversity.org/Tackling)).
That is a module-state restriction, not a fleet rule.

### 6.5 Remaining uncertainty

- **[UNCERTAIN]** whether a Vorton Projector chain can damage fleetmates in nullsec/wormhole.
  Safety settings filter bounces to "legal targets", and in null/wormhole every ship is a
  valid target — so on the documented mechanic nothing would exclude friendlies — but no
  source states the friendly case explicitly. Do not assert it.
- **[UNCERTAIN]** whether the Standup Point Defense Battery intercepts missiles (§3.2).
- **[UNCERTAIN]** Titan doomsday LOS/piercing behaviour: contradictory community claims
  ("line-of-sight type weapons" vs "Titan DD's account for volume. They go through anything
  in the way"), no primary source.

---

## 7. "The thing in front of you" — does the turret fire a ray?

**No.** This is answered at the CCP level by §3.1 and corroborated by fifteen years of
player complaints.

### 7.1 The conceptual model, precisely [INFERENCE, grounded in §3.1]

- A turret is not a ray, a projectile, or a swept volume. It is a **statistical oracle**.
- Range and tracking produce a scalar probability. A die is rolled. Damage is looked up from
  the same roll. An effect is drawn afterwards.
- "What is in front of you" is therefore **not represented in the model at all**. The only
  spatial inputs are *distance to the locked target* and *relative angular motion of the
  locked target*. There is no third-body term anywhere in the equation.
- Cover does not exist in EVE in any form — not asteroids, not stations, not other ships.
  The absence is confirmed by the mechanics and by unanimous community consensus, though no
  CCP statement says the words "cover does not exist".

One player's formulation of it is unusually precise and worth quoting:

> "Nope, there isn't [any hit box or line of sight]. **What you see is a clever rendered
> illusion of the client. In fact only points (actually spheres) in space with some
> parameters are interacting.**
> — Tipa Riot, [EVE forums, 2023](https://forums.eveonline.com/t/collision-physics-is-absolutly-necessary-for-a-hardcore-game-like-eve/410606/20)

### 7.2 The complaint is real and long-running **[CONFIRMED-COMMUNITY]**

The "why doesn't my shot hit the ship in front of me" issue has been raised repeatedly on the
official forums, always with **zero CCP participation**:

| Year | Thread | Claim |
|---|---|---|
| 2006 | [Solid Objects & Line of Sight](https://eve-search.com/thread/296173-0/author/Praesus_Lecti) | "Why are object (ships, stations, gates, asteroids, debris, etc) only solid when it comes to collision detection but not solid when it comes to blocking someone's ability to shoot at me and/or target me?" |
| 2009 | [Anti-blob solution? (Line-of-Sight firing)](https://eve-search.com/thread/1000872-0/author/Jacmert_Corra'Halcyon) | "it's currently possible to shoot **through** ships" |
| 2009 | [Take cover!!!! Into that asteroid!](https://eve-search.com/thread/976459-0/author/Maxsim%20Goratiev) | proposal to let asteroids/hostiles-in-front absorb fire |
| 2011 | [Objects in space impeding weapon fire](https://eve-search.com/thread/36037-1/page/1) | "as long as the target is lockable and in range, you can shoot it" |
| 2014 | [Fleet formations / weapons fire line of sight](https://eve-search.com/thread/326825-1/page/all) | "No longer can you just fire through 15 of your buddies and only hit your target" |
| 2017 | [Line of Sight \[How close are we?\]](https://forums.eveonline.com/t/line-of-sight-how-close-are-we/22369) | damage "applies to the first object between you and your target" |
| 2022 | [Objects obstrcuting line of sight?](https://forums.eveonline.com/t/objects-obstrcuting-line-of-sight/350354) | "could I not use cover to avoid gankers?" |
| 2023 | [Collision Physics is absolutly necessary…](https://forums.eveonline.com/t/collision-physics-is-absolutly-necessary-for-a-hardcore-game-like-eve/410606) | see below |

The 2023 thread is the loudest modern statement:

> "weapons shoot right through objects including stations, other ships, space objects,
> asteroids, debris, **there is no option to use strategy with cover/concealment and line of
> sight.** You cant use other ships as cover/concealment, you cant use asteroids, stations,
> planets, moons, suns… **There is literally no line of sight that you can break?!?!?**"

Direct agreement in-thread from Anthony FatTony Amico: "Kind of silly to see laser fire go
right through ships XD".

**No CCP reply exists.** Pages 1–2 carry no blue post, and the forum search API returns zero
`@ccp` posts for that topic. The only quasi-official voice is CSM member **Brisc Rubal**
(player-elected, *not* CCP): "sure, it would be great to have line of sight and the like,
but **there's zero chance it will ever end up in this game**… changing the fundamentals of
how the game works… is the quickest way to lose the existing player base."
**[CONFIRMED-COMMUNITY]**

**Corollary for us:** the "server can't afford the raycasts" explanation is a *player*
argument, not a documented CCP position. CCP has never publicly stated why occlusion is
absent. **[UNCERTAIN — absence of evidence, not evidence of a decision.]**

### 7.3 The one exception: POS forcefields **[CONFIRMED-CCP]**

EVE has exactly **one** hard cover mechanic, and it is a special-cased rules boundary, not
simulated geometry:

> "Forcefields around a POS are intended to be **impenetrable** with no way to target or
> damage anyone outside of them when inside the field, nor take any damage or be targeted
> when inside the field by someone outside of it."
> — [CCP exploit notification, "Attacking while inside POS forcefields"](https://concord-killmail.eveonline.com/de/news/view/exploit-notification-attacking-while-inside-pos-forcefields)

Firing through a forcefield is classified as an **exploit**. This is the design pattern worth
noting: when EVE wanted a cover-like effect, it implemented it as a *flag on a volume*, not as
line-of-fire geometry.

### 7.4 Historically, missiles *did* collide with obstacles — and it was removed **[UNCERTAIN]**

Multiple community reports (no CCP patch note located) say early EVE missiles had crude
obstacle collision which was deliberately stripped out:

> "Missiles USED to have a bit of collision detection… **This, also, was a lot of extra
> computations, and was removed**" — [2009](https://eve-search.com/thread/976459-0/author/Maxsim%20Goratiev)
>
> "half your missiles would hit a roid instead of your target, or hit your loot containers.
> And it was also **too easy to get concorded in highsec by mistake**. It was removed for
> these reasons." — [2014](https://eve-search.com/thread/326825-1/page/all)

A [2004 thread](https://eve-search.com/thread/91662-0/author/ElDiabloRojo) describes the old
arcing launch that let a pilot "make a missile dodge a nearby obsticle, e.g. **a friendly
ship** or an asteroid". **Flag as UNCERTAIN — strong, consistent community consensus but no
primary source.** If true, it is the single most instructive data point in this whole
research: EVE *tried* projectile occlusion, found that friendly-blocking caused accidental
highsec CONCORD deaths, and removed the feature.

### 7.5 Collision is movement, not fire **[CONFIRMED-COMMUNITY]**

- Ships **bump/bounce** but never take collision damage: "you cant crash into objects no
  matter your speed to mass ratio, you just magically bounce right off everything."
- Asteroids use oversized spherical collision hulls that visibly mismatch the model — enough
  that a pilot died stuck on a rock ([2022 thread](https://forums.eveonline.com/t/asteroid-hitbox-large/364431/1)).
- Asteroids/structures/wrecks give **zero** fire protection: "They aren't going to block
  anything. All weapons and effects go right through them…"
- "Bubbles" and "gate camps" are **warp denial (tackle)** — an entirely different axis from
  cover. Do not conflate them.

---

## 8. Glossary — terms a designer might borrow

| Term | What EVE means by it | Why it is worth borrowing |
|---|---|---|
| **Target lock** | An explicit, timed, slot-limited acquisition of a specific object; prerequisite for almost every offensive and support action. | Clean separation of *permission to act* from *success of the act*. |
| **Lock time / targeting time** | `40,000 m / (Scan resolution × arcsinh²(Signature radius))`. Scan res in mm, sig radius in m. **[CONFIRMED-WIKI]** Community-derived; CCP's own article is qualitative only (see §2). | Gives target size and sensor quality a defensive role independent of damage. |
| **Max locked targets** | Per-hull cap on simultaneous locks. Base **2** for an untrained pilot; `Target Management` +1/level and `Advanced Target Management` +1/level up to the hull cap ⇒ **12** at both V. Hull examples: Merlin 5, Golem 10. Modules: Auto Targeting System +2/+3, Signal Amplifier +1/+2. **[CONFIRMED-WIKI]** | Forces triage: you cannot engage everything you can see. |
| **Angular velocity** | `ω = v_transversal / d`, rad/s. The range-normalised relative motion that the tracking term consumes. Symmetric between the two ships. | The single most elegant idea in the model: the *same* geometry is a defensive asset to the small fast ship and an offensive one to the big slow one. |
| **Transversal velocity** | The perpendicular component of relative velocity, in m/s. The raw quantity; angular velocity is what the formula uses. | Good UX term — pilots can read it on the overview without doing geometry. |
| **Tracking disruptor** | EWAR module reducing an enemy turret's tracking speed and/or optimal+falloff. Unscripted does both; scripts double one at the expense of the other. **Always succeeds**; effect scales with range using the same curve as turret hit chance (100% inside optimal, 50% at optimal+falloff). Amarr specialty. **[CONFIRMED-WIKI]**, [Electronic warfare](https://wiki.eveuniversity.org/Electronic_warfare) | A counter that attacks *accuracy* rather than *hit points* — a whole defensive axis that isn't "more armour". |
| **Optimal** | Range band where distance does not affect hit chance. | Creates a real "preferred engagement envelope". |
| **Falloff** | Post-optimal decay band; 50% at optimal+falloff. | Soft range limit that degrades gracefully instead of a hard cutoff. |
| **Wrecking hit** | The `x < 0.01` special case: exactly 300% damage, ignoring tracking and signature. | Deliberate, rare, memorable spike; makes low-probability shots *exciting* rather than merely unlikely. |
| **Grazing hit / "Grazes"** | The lowest normal band, 0.500–0.625×. Full ladder: Grazes / Glances off / Hits / Penetrates / Smashes / Wrecks. | One roll produces both a hit/miss verdict *and* a readable narrative label. |
| **Signature radius** | Sensor footprint in metres; governs lock time, turret tracking, missile/bomb damage. | A single defensive scalar that unifies "hard to lock", "hard to track", "hard to damage". |
| **Signature resolution** | The 40,000 m legacy constant = target size the gun was designed for. Now folded into the tracking stat. **Not the same as scan resolution.** | Lets you express "this gun is built for big targets" without a separate damage-vs-size table. |
| **Scan resolution** | Ship sensor stat (mm) governing how fast it locks; **does not affect turret hit chance.** | Cleanly separates *sensor* performance from *weapon* performance. |
| **Weapon grouping** | UI bundling of identical weapons into one button. Does **not** merge the hit roll — grouped guns still resolve independently — and a group cannot split fire across targets. **[CONFIRMED-CCP + CONFIRMED-WIKI]** | Reduces clicks without reducing the model's granularity. |
| **Cycle time** | Module activation duration (the turret's rate of fire). Damage lands on cycle completion, not on the firing animation. **[CONFIRMED-WIKI for the damage math; the "lands on completion" timing is INFERENCE]** | Decouples the animation from the resolution; makes server-authoritative combat easy to reason about. |
| **"Shots fired" vs "damage applied"** | **Informal, not a formal EVE term [UNCERTAIN — no primary source].** The real distinction it names: *paper DPS* (ammo × damage multiplier ÷ cycle time, shown in the fitting window) versus *applied DPS* (what actually lands, after hit chance and random damage rolls). Because of the coupling in §1.2, applied DPS falls faster than hit chance — 50% hit chance ⇒ ~40% of paper DPS. **[CONFIRMED-WIKI]** | The gap between the number on the stat sheet and the number that matters is where all the tactical texture lives. |

**Additional EVE terms this research turned up, worth knowing before borrowing the model:**

| Term | What EVE means by it | Note for designers |
|---|---|---|
| **Firewalling** | Using multiple smartbombs to shoot down incoming missiles, because missiles are real objects with structure HP. **[CONFIRMED-WIKI]** | EVE's only working anti-missile defence — and it is an emergent side-effect of AoE, not a designed system. |
| **Defender missile** | Destroyer-only module that intercepts a **random, side-blind bomb** within range. One defender kills one bomb. 120 s reactivation. **[CONFIRMED-CCP]** | A counter-weapon that deliberately ignores friend/foe. Cheap to understand, brutal to use near allies. |
| **Drone Assist / Guard** | Delegated fire: your drones attack whatever the assisted fleetmate attacks (Assist) or whatever attacks them (Guard). **[CONFIRMED-WIKI]** | EVE's closest thing to fleet focus-fire as a *mechanic*; the alternative is social coordination. |
| **Entropic Disintegrator** | Triglavian turret whose damage ramps while it stays on target; "will deactivate if their target leaves optimal range. If a disintegrator deactivates for any reason, its damage bonus is **reset to 0**". **[CONFIRMED-WIKI]** | EVE's one weapon whose cycle state is bound to the target relationship — proof the engine *can* model "losing the target costs you", it just chooses not to for ordinary guns. |
| **POS forcefield** | A volume which is genuinely impenetrable; firing through it is a **CCP-classified exploit**. **[CONFIRMED-CCP]** | EVE's only real cover, implemented as a rules flag on a volume rather than as geometry. |

---

---

## 9. Design implications for a command-based naval game

My synthesis, not sourced. Flagged **[INFERENCE]** throughout.

1. **The core trick is separating *who* from *whether*.** EVE makes target selection fully
   deterministic (the lock decides who takes damage, always) and puts all uncertainty into
   *whether the shot lands*. This is what makes "a selected target is not guaranteed to be
   hit" feel fair rather than arbitrary — the player's decision (whom to shoot) is always
   honoured; only the outcome is stochastic. **Recommend copying this split exactly.**

2. **One random number for both hit/miss and damage quality is the highest-value idea here.**
   It costs one RNG draw, produces a binary outcome *and* a six-step narrative ladder
   (grazes → glances off → hits → penetrates → smashes → wrecks), and creates a genuinely
   exciting tail event (the 300% wrecking hit) that a two-roll system would dilute. It also
   removes the "I hit but did no damage" awkwardness: hits always do *something*.

3. **The `0.5^(a+b)` form with independent terms is unusually tunable.** Because tracking and
   range contribute additively in the exponent, designers can tune one axis without
   disturbing the other, and the same curve shape governs both. Doubling any of tracking,
   signature, or halving angular velocity has *identical* effect — a clean symmetry that
   makes the system explicable to players.

4. **Aspect and bearing map naturally onto a sailing-ship model.** EVE's signature radius is
   "how big you look"; for an age-of-sail game the direct analogue is **presented profile** —
   a ship broadside-on is a large, easy target; bow- or stern-on is small. Likewise
   **angular velocity** (rate of change of bearing) maps to deflection: a target crossing
   your line of fire is hard to hit; one closing or fleeing is easy, *regardless of speed*.
   This gives a rich tactical triangle — heading, speed, and aspect — using EVE's exact
   maths, and it rewards the historical naval manoeuvre of "crossing the T".

5. **EVE's warning about occlusion is the single most useful finding for us.** EVE *did*
   model projectiles colliding with obstacles, and removed it — reportedly because half your
   missiles hit asteroids or your own loot containers, and because it made accidental
   highsec CONCORD deaths far too easy **[UNCERTAIN — community consensus, no CCP patch
   note]**. Combined with the fact that EVE has never added line-of-fire blocking despite
   20 years of requests, the lesson is: **incidental interception by allies is a
   player-hostility generator.** In a command-based game where the player does not aim, it
   is worse — it punishes the player for something they cannot control or even see.

6. **If we want screening, make it an order, not an accident.** The design space EVE left
   empty is deliberate, legible interception: a formation or order that *intends* to put a
   hull between an ally and incoming fire. That preserves the fantasy (a frigate
   interposing itself) while keeping causality attributable to a decision. This is the
   opposite of an emergent raycast that silently eats a shot.

7. **EVE's AoE weapons show the escape hatch.** If incidental friendly damage is desired for
   *some* weapons, EVE models it cleanly and legibly per weapon type: smartbombs hit
   everything nearby including your own drones; bombs hit allies and the launcher; turrets
   and missiles never hit a third party. **Friendly fire exists per weapon, not
   globally** — a much better dial than a single "friendly fire on/off" switch.

8. **Timers, not immunity, are how EVE gates friendly fire.** Safety settings and CONCORD
   punish illegal shots rather than preventing damage. For a single-player or co-op naval
   game this probably does not transfer — but the underlying pattern (make the *cost* of a
   bad shot legible: crew morale, standing, a court-martial) is worth considering if we ever
   want friendly fire to be possible but discouraged.



---

## Sources

First-party (CCP / Fenris):
- [CCP Choloepus — "Turret Effects: I don't always miss, but when I do... I do it with style." (2011-11-18)](https://www.eveonline.com/news/view/turret-effects-i-don-t-always-miss-but-when-i-do...i-do-it-with-style.) — server decides hit/miss, client renders after; misses aim at target's bounding sphere; missiles are different code; third-party shots carry no hit/miss data.
- [CCP Ytterbium — "Weapon Grouping" (2008-10-23)](https://www.eveonline.com/news/view/weapon-grouping) — grouping is display-only, cannot split fire.
- [CCP Punkturis — "Corp Little Things & Friendly Fire Control" (2015-02-09)](https://www.eveonline.com/news/view/corp-little-things-friendly-fire-control) — corp-level friendly-fire legality toggle; default legal; nullsec/wormhole always valid targets.
- [CCP_Aurora — "Can I shoot or not?" (2020)](https://devtrackers.gg/eveonline/p/9ed335ec-can-i-shoot-or-not) — system-security-dependent aggression rules and Safety settings.
- [CCP Larrikin — "Sticky: [December] Defender Missiles" (2016-11-25)](https://eve-search.com/thread/501519-1/author/CCP%20Larrikin) — defenders now intercept bombs, random side-blind targeting, and *"like all missiles fired at something that is destroyed or leaves grid before the missile hits"*.
- [CCP support — "Locking Times" (2024-07-15)](https://support.eveonline.com/hc/en-us/articles/207110329-Locking-Times) — **qualitative only, contains no formula**; live URL returns Cloudflare 403, read via [Wayback snapshot](https://web.archive.org/web/20250322014429/https://support.eveonline.com/hc/en-us/articles/207110329-Locking-Times).
- [CCP content creation toolkit / SDE](https://community.eveonline.com/community/content-creation/toolkit/) — where missile `drf` values are published.

EVE University Wiki (community, high trust):
- [Turret mechanics](https://wiki.eveuniversity.org/Turret_mechanics) (a.k.a. Turret damage) — chance-to-hit and damage formulas, hit-quality table, weapon grouping.
- [Missile mechanics](https://wiki.eveuniversity.org/Missile_mechanics) — explosion radius/velocity, DRF table, damage formula.
- [Missiles](https://wiki.eveuniversity.org/Missiles) — defender missiles, auto-targeting missiles, in-flight missiles vanish on warp, firewalling.
- [Targeting](https://wiki.eveuniversity.org/Targeting) — lock time formula, max locked targets, targeting range.
- [Signature radius](https://wiki.eveuniversity.org/Signature_radius) — size table, modifiers, MWD penalty.
- [Bombs](https://wiki.eveuniversity.org/Bombs) — AoE mechanics, indiscriminate damage, interception by defenders/smartbombs/bombs.
- [Smartbombs](https://wiki.eveuniversity.org/Smartbombs) — radius, friend-or-foe damage, highsec red-safety requirement, own-drones damage.
- [Electronic warfare](https://wiki.eveuniversity.org/Electronic_warfare) — tracking disruptors, guidance disruptors, ECM.
- [Weapons](https://wiki.eveuniversity.org/Weapons) — turrets fire "a stream of stuff… in a straight line" and "reach their targets immediately" (visual framing).
- [Turrets](https://wiki.eveuniversity.org/Turrets) — Entropic Disintegrator deactivation/reset behaviour.
- [Vorton Projectors](https://wiki.eveuniversity.org/Vorton_Projectors) — 9-target chain within 10 km, safety-setting interaction.
- [Guided Bombs](https://wiki.eveuniversity.org/Guided_Bombs) — targeted structure bombs, 20 km AoE, 400 s drift.
- [Titans](https://wiki.eveuniversity.org/Titans) — Lance/Reaper/Boson AoE templates, 10 km neutralising pulse, doomsday.
- [Safety settings](https://wiki.eveuniversity.org/Safety_settings) — green/yellow/red semantics, action prevention.
- [Timers](https://wiki.eveuniversity.org/Timers) — Crimewatch, Suspect/Criminal/Limited Engagement/Weapons timers by security class.
- [Tackling](https://wiki.eveuniversity.org/Tackling) — bubbles, points/scrams/webs; the remote-rep block while a disruption field is active.
- [Drones](https://wiki.eveuniversity.org/Drones) — Assist / Guard / Aggressive / Auto Attack, control range.
- [Remote assistance](https://wiki.eveuniversity.org/Remote_assistance) — remote reps inherit timers; mixed-fleet friendly-fire caution.
- [Skills:Targeting](https://wiki.eveuniversity.org/Skills:Targeting), [Skills:Missiles](https://wiki.eveuniversity.org/Skills:Missiles) — skill effects and caps.

Community forums and archives:
- [EVE Online forums — "Collision Physics is absolutly necessary for a hardcore game like EvE" (2023)](https://forums.eveonline.com/t/collision-physics-is-absolutly-necessary-for-a-hardcore-game-like-eve/410606) — players confirming weapons pass through ships and no cover/LOS exists; **no CCP reply** (verified via forum search API).
- [EVE Online forums — "Objects obstrcuting line of sight?" (2022)](https://forums.eveonline.com/t/objects-obstrcuting-line-of-sight/350354)
- [EVE Online forums — "Objects obstrcuting line of sight?" / asteroid hitboxes (2022)](https://forums.eveonline.com/t/asteroid-hitbox-large/364431/1) — "All weapons and effects go right through them."
- [eve-search archive — "Solid Objects & Line of Sight" (2006)](https://eve-search.com/thread/296173-0/author/Praesus_Lecti), ["Anti-blob solution? (Line-of-Sight firing)" (2009)](https://eve-search.com/thread/1000872-0/author/Jacmert_Corra'Halcyon), ["Take cover!!!! Into that asteroid!" (2009)](https://eve-search.com/thread/976459-0/author/Maxsim%20Goratiev), ["Fleet formations / weapons fire line of sight" (2014)](https://eve-search.com/thread/326825-1/page/all) — the historical record, including the claim that missile obstacle-collision was removed.
- [EVE Online forums — "Question about Defender Missiles" (2024)](https://forums.eveonline.com/t/question-about-defender-missiles/463153)
- [CCP exploit notification — "Attacking while inside POS forcefields"](https://concord-killmail.eveonline.com/de/news/view/exploit-notification-attacking-while-inside-pos-forcefields) — EVE's one hard cover mechanic.

SDE mirrors and data:
- [EVE Ref — Standup Point Defense Battery I](https://everef.net/types/35926), [Standup Flak Round I](https://everef.net/types/63195), [Bomb Launcher I](https://everef.net/types/27914), [Standup XL-Set Integrated Fighter and PD Network I](https://everef.net/types/37270)
- [New Eden Encyclopedia — Typhoon](https://newedenencyclopedia.net/type/644-Typhoon.html)
- [CCP patch notes 20.03](https://www.eveonline.com/news/view/patch-notes-version-20-03)

**Raw research artifacts** (full sub-investigations, kept for provenance):
- [`parts/community-los-discussion.md`](parts/community-los-discussion.md)
- [`parts/interception-friendly-fire.md`](parts/interception-friendly-fire.md)
- [`parts/comparable-games.md`](parts/comparable-games.md)

---

## Appendix: comparable games — does a shot pass through an intervening ship?

Full citations in [`parts/comparable-games.md`](parts/comparable-games.md).
Verdicts: **PASSES THROUGH** · **COLLIDES** · **BLOCKED-ABSORBED** · **NOT MODELED** ·
**UNCERTAIN**.

### Verdict table

| Game | Verdict | One-line reason |
|---|---|---|
| **Homeworld 1/2/Remastered** | **PASSES THROUGH** (default) | Projectiles don't collide with friendlies; a per-weapon `iCheckLineOfFire` flag is an opt-in *pre-fire* gate, documented with the example set to `0`. |
| **Homeworld 3** | **COLLIDES** (community) | AI runs a pre-fire `LineTraceSingle`; a modder's read of shipped data says homing bullets "can still hit anything along the way". |
| **Nebulous: Fleet Command** | **COLLIDES** | Ships "will happily fire at a friendly ship if they happen wander into the line of fire"; guarding fighters "end up being shot by it. Repeatedly." |
| **Rule the Waves 1/2/3** | **NOT MODELED** (guns) / **COLLIDES** (torpedoes) | Gunnery is a per-salvo hit roll with no shell entity. Torpedoes are real and *do* intersect ships. |
| **Sails of Glory** | **BLOCKED** | "A ship may not fire through the base of another ship, **enemy or allied**." |
| **Wooden Ships & Iron Men** | **BLOCKED** | An intervening friendly means "the field of fire is blocked and the ship may not fire that broadside in that turn." |
| **Blackwake** | **UNCERTAIN** | Config has separate *Friendly Fire* (players) and *Friendly Ship Damage* switches — suggests blocking when on, unverified. |
| **Naval Action** | **COLLIDES** (inference) | Friendly fire is *rule*-prohibited rather than engine-impossible ⇒ mechanically possible. |
| **Sea of Thieves** | **NOT MODELED** | Crew damage is structurally absent; a friendly-fire option is still an unimplemented feature request on Rare's own forums. |
| **AC IV: Black Flag** | **UNCERTAIN** | Only third-party guides exist; Ubisoft publishes no naval-combat documentation. |
| **World of Warships** | **BLOCKED-ABSORBED** | "all armament types can still hit allied ships… you still won't be able to launch torpedoes at an enemy through an allied ship" — but zero damage. |
| **World of Tanks** | **BLOCKED-ABSORBED** | Team damage disabled; an ally in the way takes a non-penetrating mark. One exception: HE "will just go right through" an allied gun. |
| **Sins of a Solar Empire / II** | **BLOCKED-ABSORBED** (missiles) | Dev journal lists PD/evasion/fuel as missile failure modes, not third-party collision; a community wiki claims otherwise. Contested. |
| **Stellaris** | **NOT MODELED** | Official hit formula is `Accuracy − Evasion`; no travel-time, projectile entity, or collision term. |
| **EVE Online** | **PASSES THROUGH** | See §1–§3. Nothing body-blocks anything. |

### The most important finding for Flor do Mar

**The two age-of-sail tabletop games both HARD-BLOCK, and for the same reason.** They are the
closest genre analogues to our game, and both chose to make an intervening hull forbid the
shot outright rather than absorb it:

- **Wooden Ships & Iron Men** (Basic Game VIII.A.4): the target must be "the closest in number
  of hexes to the firing ship of all ships in the field of fire", and "**If the 'closest
  ship' happens to be a land hex, friendly ship, surrendered or captured ship, or a hulk, the
  field of fire is blocked and the ship may not fire that broadside in that turn.**"
  Friendly fire is therefore *structurally impossible* — a friendly hull is a blocker, not a
  casualty. Raking remains positional: a ship "directly in front of the target ship's bow or
  directly behind the target ship's stern… may fire a rake".
  ([WS&IM rules](https://mtorpey.github.io/wooden-ships/))

- **Sails of Glory**: "A ship may not fire through the base of another ship, **enemy or
  allied**. If it is impossible to reach the target point without crossing another ship's
  base, line of sight is blocked." The optional *Forced Targeting* rule adds that a broadside
  must engage the nearest target on that side, and "if the nearest ship is an ally, the
  battery cannot fire." Friendly fire arises only via collision damage, never gunfire.
  ([Sails of Glory rulebook](https://www.rebel.pl/repository/files/instrukcje/Sails_of_Glory_PL.pdf))

**Both games resolve the "who is in the way" problem as a legality check on the shot, not as
a damage-transfer.** That is a third option between EVE's "ignore geometry entirely" and
Nebulous' "shoot your friends in the back". It is also the cheapest to implement and the
easiest for a player to understand — and it keeps the decision attributable to the player,
which matters enormously in a command-based game where they cannot aim.

### Design patterns worth borrowing

- **Make the line-of-fire test a pre-fire gate, not a physics rule.** Homeworld's
  `iCheckLineOfFire` and HW3's `BTT_CheckLineOfFire` trace decide *whether to shoot*, not
  whether a projectile is consumed. Cheap, per-weapon tunable, no per-projectile bookkeeping.
- **Hard-block at the targeting layer when you want zero ambiguity** — the WS&IM and Sails of
  Glory approach. Best fit for a command-based, no-manual-aim game.
- **Scope the block to the irreversible/slow weapon.** RtW applies the "Friendly ship is in
  line of fire!" guard only to torpedoes, not to guns that can be recalled or that fire
  again in seconds. A good precedent for treating a costly, telegraphed weapon differently
  from a rapid one.
- **Keep the hull a real collision body but zero the damage** (WoWS): preserves screening
  geometry and lane discipline without enabling griefing.
- **Give automated point defence a friendly-safety cutoff radius.** Nebulous' PD stops
  engaging anti-craft missiles once they close on your own craft "so that they don't
  accidentally blow up your own fighters" — a small, legible rule that removes the worst
  frustration case.

### Notable negatives

- **Sea of Thieves** proves the flip side: with crew damage structurally absent, a
  friendly-fire *option* is still an open feature request with 41.5k views and no developer
  implementation. Absence of friendly fire is not automatically a solved problem — players
  asked for it anyway.
- **Rule the Waves** models smoke as a line-of-sight obstruction for gunnery ("will degrade
  gunnery when firing through it, regardless of which ship the smoke is coming from") but
  **never ships**. If Flor do Mar wants a "something in the air" accuracy modifier, smoke is
  a period-appropriate and well-precedented alternative to hull occlusion.
- **Stellaris** is the cautionary case for a purely statistical model: `Accuracy − Evasion`
  with no spatial term at all is simple, but produces no positioning gameplay beyond
  range-keeping.
