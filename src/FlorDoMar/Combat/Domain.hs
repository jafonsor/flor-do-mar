{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Combat.Domain
  ( BroadsideCheck (..)
  , BroadsideSide (..)
  , BroadsideTuning (..)
  , CombatCommand (..)
  , CombatState (..)
  , EnemyOrbitAutopilot (..)
  , Heading (..)
  , MovementPhysics (..)
  , NavigationOrder (..)
  , NavigationPlan (..)
  , Point (..)
  , SailState (..)
  , ScenarioOutcome (..)
  , ScenarioStatus (..)
  , Ship (..)
  , ShipId (..)
  , TrajectorySample (..)
  , Wind (..)
  , broadsideDamage
  , broadsideRange
  , canFireBroadside
  , canFireBroadsideWith
  , caravelaDuel
  , legacyBroadsideTuning
  , legacyMovementPhysics
  , enemyOrbitRadius
  , issueNavigationOrder
  , moveShip
  , navigationArrivalRadius
  , navigationHeadingCorrectionSeconds
  , planActiveNavigation
  , planNavigation
  , reloadTicks
  , targetYawRate
  , tickCombat
  , tickCombatWith
  , tickCombatWithTuning
  )
where

import Data.Text (Text)

data ShipId
  = PlayerShip
  | EnemyShip
  deriving stock (Eq, Show)

data Point = Point
  { pointX :: Double
  , pointY :: Double
  }
  deriving stock (Eq, Show)

newtype Heading = Heading
  { headingDegrees :: Double
  }
  deriving stock (Eq, Show)

data SailState
  = SailsFurled
  | BattleSails
  | FullSails
  deriving stock (Eq, Show)

data BroadsideSide
  = Port
  | Starboard
  deriving stock (Eq, Show)

data Wind = Wind
  { windDirection :: Heading
  , windSpeed :: Double
  }
  deriving stock (Eq, Show)

data MovementPhysics = MovementPhysics
  { movementBattleSpeed :: Double
  , movementMaxSpeed :: Double
  , movementAcceleration :: Double
  , movementDeceleration :: Double
  , movementTurnRate :: Double
  , movementIdealTurnSpeed :: Double
  , movementYawAcceleration :: Double
  }
  deriving stock (Eq, Show)

-- | A command-time commitment. The requested waypoint is retained for
-- diagnostics, while execution always follows the fixed reachable waypoint.
data NavigationOrder = NavigationOrder
  { navigationRequestedWaypoint :: Point
  , navigationReachableWaypoint :: Point
  , navigationPostWaypointSpeed :: Double
  }
  deriving stock (Eq, Show)

data TrajectorySample = TrajectorySample
  { trajectorySampleTickOffset :: Int
  , trajectorySamplePosition :: Point
  , trajectorySampleHeading :: Heading
  , trajectorySampleSpeed :: Double
  , trajectorySampleYawRate :: Double
  }
  deriving stock (Eq, Show)

-- | The selected, executable trajectory. Candidate paths remain an internal
-- detail of the planner.
data NavigationPlan = NavigationPlan
  { navigationPlanRequestedWaypoint :: Point
  , navigationPlanReachableWaypoint :: Point
  , navigationPlanWasClamped :: Bool
  , navigationPlanArrivalSpeed :: Double
  -- | The planner stopped before arrival to protect the simulation from an
  -- unbounded projection. This is a safety/test fallback, never a new
  -- reachable waypoint.
  , navigationPlanReachedSafetyCap :: Bool
  , navigationPlanSamples :: [TrajectorySample]
  }
  deriving stock (Eq, Show)

data BroadsideTuning = BroadsideTuning
  { broadsideTuningRange :: Double
  , broadsideTuningDamage :: Int
  , broadsideTuningReloadTicks :: Int
  , broadsideTuningFiringArcDegrees :: Double
  }
  deriving stock (Eq, Show)

data Ship = Ship
  { shipId :: ShipId
  , shipBoatKind :: Text
  , shipDisplayName :: Text
  , shipPosition :: Point
  , shipHeading :: Heading
  , shipTargetHeading :: Heading
  , shipSails :: SailState
  , shipCurrentSpeed :: Double
  , shipTargetSpeed :: Double
  , shipCurrentYawRate :: Double
  , shipNavigationOrder :: Maybe NavigationOrder
  , shipMaxHull :: Int
  , shipDamageTaken :: Int
  , shipHull :: Int
  , shipRenderedLength :: Double
  , shipRenderedWidth :: Double
  , shipReload :: Int
  }
  deriving stock (Eq, Show)

data ScenarioStatus
  = ScenarioRunning
  | ScenarioFinished ScenarioOutcome
  deriving stock (Eq, Show)

data ScenarioOutcome
  = Winner ShipId
  | MutualDestruction
  deriving stock (Eq, Show)

data CombatState = CombatState
  { combatTick :: Int
  , combatWind :: Wind
  , combatPlayer :: Ship
  , combatEnemy :: Ship
  , combatEnemyOrbitAutopilot :: EnemyOrbitAutopilot
  , combatStatus :: ScenarioStatus
  }
  deriving stock (Eq, Show)

-- | Enemy behavior state owns only the orbit center and waypoint sequence.
-- Each selected waypoint is still submitted through 'IssueNavigationOrder'.
data EnemyOrbitAutopilot = EnemyOrbitAutopilot
  { enemyOrbitCenter :: Point
  , enemyOrbitNextWaypointIndex :: Int
  }
  deriving stock (Eq, Show)

data CombatCommand
  = SetHeading ShipId Heading
  | SetTargetSpeed ShipId Double
  | IssueNavigationOrder ShipId Point
  | SetNavigationPostWaypointSpeed ShipId Double
  -- | Compatibility for the pre-navigation controls. New movement code should
  -- issue 'SetTargetSpeed' directly.
  | SetSails ShipId SailState
  | FireBroadside ShipId ShipId BroadsideSide
  deriving stock (Eq, Show)

data BroadsideCheck
  = BroadsideReady
  | ScenarioAlreadyFinished ScenarioOutcome
  | AttackerDisabled ShipId
  | TargetDisabled ShipId
  | BroadsideReloading Int
  | TargetOutOfRange Double
  | TargetOutsideFiringArc Double
  deriving stock (Eq, Show)

broadsideRange :: Double
broadsideRange = 100

broadsideDamage :: Int
broadsideDamage = 25

reloadTicks :: Int
reloadTicks = 3

caravelaDuel :: CombatState
caravelaDuel =
  CombatState
    { combatTick = 0
    , combatWind = Wind {windDirection = Heading 0, windSpeed = 0}
    , combatPlayer =
        caravela
          PlayerShip
          Point {pointX = 0, pointY = 0}
          (Heading 0)
    , combatEnemy =
        caravela
          EnemyShip
          Point {pointX = 0, pointY = 80}
          (Heading 180)
    , combatEnemyOrbitAutopilot = enemyOrbitAutopilotAt (Point {pointX = 0, pointY = 80})
    , combatStatus = ScenarioRunning
    }

tickCombat :: [CombatCommand] -> CombatState -> CombatState
tickCombat = tickCombatWith 1 (const caravelaMovement)

tickCombatWith :: Double -> (Ship -> MovementPhysics) -> [CombatCommand] -> CombatState -> CombatState
tickCombatWith tickSeconds movementForShip =
  tickCombatWithTuning tickSeconds movementForShip (const legacyBroadsideTuning)

tickCombatWithTuning :: Double -> (Ship -> MovementPhysics) -> (Ship -> BroadsideTuning) -> [CombatCommand] -> CombatState -> CombatState
tickCombatWithTuning tickSeconds movementForShip broadsideTuningForShip commands state =
  case combatStatus state of
    ScenarioFinished _ -> clearDisabledNavigation state
    ScenarioRunning ->
      let
        commanded =
          foldl
            (applyCommand tickSeconds movementForShip broadsideTuningForShip)
            (coolDownReloads state {combatTick = combatTick state + 1})
            commands
        resolved = finishIfTerminal commanded
       in
        case combatStatus resolved of
          ScenarioFinished _ -> resolved
          ScenarioRunning ->
            finishIfTerminal $
              issueEnemyOrbitOrder tickSeconds movementForShip broadsideTuningForShip $
                moveShips tickSeconds movementForShip $
                  issueEnemyOrbitOrder tickSeconds movementForShip broadsideTuningForShip resolved

canFireBroadside :: CombatState -> ShipId -> ShipId -> BroadsideSide -> BroadsideCheck
canFireBroadside = canFireBroadsideWith (const legacyBroadsideTuning)

canFireBroadsideWith :: (Ship -> BroadsideTuning) -> CombatState -> ShipId -> ShipId -> BroadsideSide -> BroadsideCheck
canFireBroadsideWith broadsideTuningForShip state attackerId targetId side =
  case combatStatus state of
    ScenarioFinished outcome -> ScenarioAlreadyFinished outcome
    ScenarioRunning ->
      let
        attacker = selectShip attackerId state
        target = selectShip targetId state
        tuning = broadsideTuningForShip attacker
        range = distance (shipPosition attacker) (shipPosition target)
        arcDelta = broadsideArcDelta attacker target side
       in
        if shipHull attacker <= 0
          then AttackerDisabled attackerId
          else
            if shipHull target <= 0
              then TargetDisabled targetId
              else
                if shipReload attacker > 0
                  then BroadsideReloading (shipReload attacker)
                  else
                    if range > broadsideTuningRange tuning
                      then TargetOutOfRange range
                      else
                        if arcDelta > broadsideTuningFiringArcDegrees tuning
                          then TargetOutsideFiringArc arcDelta
                          else BroadsideReady

caravela :: ShipId -> Point -> Heading -> Ship
caravela identity position heading =
  Ship
    { shipId = identity
    , shipBoatKind = "caravela"
    , shipDisplayName =
        case identity of
          PlayerShip -> "Player caravela"
          EnemyShip -> "Enemy caravela"
    , shipPosition = position
    , shipHeading = normalizeHeading heading
    , shipTargetHeading = normalizeHeading heading
    , shipSails = BattleSails
    , shipCurrentSpeed = movementBattleSpeed caravelaMovement
    , shipTargetSpeed = movementBattleSpeed caravelaMovement
    , shipCurrentYawRate = 0
    , shipNavigationOrder = Nothing
    , shipMaxHull = 100
    , shipDamageTaken = 0
    , shipHull = 100
    , shipRenderedLength = 10
    , shipRenderedWidth = 4
    , shipReload = 0
    }

applyCommand :: Double -> (Ship -> MovementPhysics) -> (Ship -> BroadsideTuning) -> CombatState -> CombatCommand -> CombatState
applyCommand tickSeconds movementForShip broadsideTuningForShip state command =
  case command of
    SetHeading identity heading ->
      updateNavigatingShip identity (\ship -> ship {shipTargetHeading = normalizeHeading heading}) state
    SetTargetSpeed identity speed ->
      updateNavigatingShip identity (setTargetSpeed movementForShip speed) state
    IssueNavigationOrder identity requestedWaypoint ->
      updateNavigatingShip identity (issueNavigationOrder tickSeconds movementForShip requestedWaypoint) state
    SetNavigationPostWaypointSpeed identity speed ->
      updateNavigatingShip identity (setNavigationPostWaypointSpeed movementForShip speed) state
    SetSails identity sails ->
      updateNavigatingShip
        identity
        ( \ship ->
            (setTargetSpeed movementForShip (sailSpeed (movementForShip ship) sails) ship)
              { shipSails = sails
              }
        )
        state
    FireBroadside attackerId targetId side ->
      case canFireBroadsideWith broadsideTuningForShip state attackerId targetId side of
        BroadsideReady ->
          let tuning = broadsideTuningForShip (selectShip attackerId state)
           in updateShip attackerId (\ship -> ship {shipReload = broadsideTuningReloadTicks tuning}) $
                updateShip targetId (applyBroadsideDamage (broadsideTuningDamage tuning)) state
        _ -> state

applyBroadsideDamage :: Int -> Ship -> Ship
applyBroadsideDamage damage ship =
  ship
    { shipDamageTaken = damageTaken
    , shipHull = max 0 (shipMaxHull ship - damageTaken)
    }
 where
  -- Keep legacy states manually constructed with only shipHull intact.
  damageTaken = max (shipDamageTaken ship) (shipMaxHull ship - shipHull ship) + damage

coolDownReloads :: CombatState -> CombatState
coolDownReloads =
  updateBothShips (\ship -> ship {shipReload = max 0 (shipReload ship - 1)})

moveShips :: Double -> (Ship -> MovementPhysics) -> CombatState -> CombatState
moveShips tickSeconds movementForShip =
  updateBothShips (\ship -> moveShip tickSeconds (movementForShip ship) ship)

moveShip :: Double -> MovementPhysics -> Ship -> Ship
moveShip tickSeconds movement ship =
  clearArrivedNavigation tickSeconds movement ship advancedShip
 where
  navigatingShip = setNavigationHeading ship
  advancedShip =
    navigatingShip
      { shipPosition = advancePoint (shipPosition navigatingShip) currentHeading (currentSpeed * tickSeconds)
    , shipHeading = currentHeading
    , shipCurrentSpeed = currentSpeed
    , shipCurrentYawRate = currentYawRate
    }
  currentHeading = advanceHeading (shipHeading navigatingShip) currentYawRate tickSeconds
  currentSpeed = approach (shipCurrentSpeed navigatingShip) (shipTargetSpeed navigatingShip) speedDelta
  currentYawRate = approach (shipCurrentYawRate navigatingShip) (targetYawRate movement navigatingShip) yawRateDelta
  speedDelta = tickSeconds * if shipTargetSpeed navigatingShip >= shipCurrentSpeed navigatingShip then movementAcceleration movement else movementDeceleration movement
  yawRateDelta = tickSeconds * movementYawAcceleration movement

caravelaMovement :: MovementPhysics
caravelaMovement =
  MovementPhysics
    { movementBattleSpeed = 4
    , movementMaxSpeed = 7
    , movementAcceleration = 7
    , movementDeceleration = 7
    , movementTurnRate = 360
    , movementIdealTurnSpeed = 4
    , movementYawAcceleration = 720
    }

legacyMovementPhysics :: MovementPhysics
legacyMovementPhysics = caravelaMovement

-- | The deliberately fixed first-playable orbit radius. It is independent of
-- boat configuration so the initial behavior stays legible while tuning ships.
enemyOrbitRadius :: Double
enemyOrbitRadius = 24

enemyOrbitWaypointCount :: Int
enemyOrbitWaypointCount = 8

enemyOrbitAutopilotAt :: Point -> EnemyOrbitAutopilot
enemyOrbitAutopilotAt center =
  EnemyOrbitAutopilot
    { enemyOrbitCenter = center
    , enemyOrbitNextWaypointIndex = 0
    }

issueEnemyOrbitOrder :: Double -> (Ship -> MovementPhysics) -> (Ship -> BroadsideTuning) -> CombatState -> CombatState
issueEnemyOrbitOrder tickSeconds movementForShip broadsideTuningForShip state
  | shipHull enemy <= 0 = state
  | shipNavigationOrder enemy /= Nothing = state
  | otherwise =
      applyCommand tickSeconds movementForShip broadsideTuningForShip advancedAutopilot (IssueNavigationOrder EnemyShip waypoint)
 where
  enemy = combatEnemy state
  autopilot = combatEnemyOrbitAutopilot state
  waypoint = enemyOrbitWaypoint autopilot
  advancedAutopilot =
    state
      { combatEnemyOrbitAutopilot =
          autopilot {enemyOrbitNextWaypointIndex = enemyOrbitNextWaypointIndex autopilot + 1}
      }

enemyOrbitWaypoint :: EnemyOrbitAutopilot -> Point
enemyOrbitWaypoint autopilot =
  Point
    { pointX = pointX center + enemyOrbitRadius * cos radians
    , pointY = pointY center + enemyOrbitRadius * sin radians
    }
 where
  center = enemyOrbitCenter autopilot
  radians = 2 * pi * fromIntegral (enemyOrbitNextWaypointIndex autopilot `mod` enemyOrbitWaypointCount) / fromIntegral enemyOrbitWaypointCount

legacyBroadsideTuning :: BroadsideTuning
legacyBroadsideTuning =
  BroadsideTuning
    { broadsideTuningRange = broadsideRange
    , broadsideTuningDamage = broadsideDamage
    , broadsideTuningReloadTicks = reloadTicks
    , broadsideTuningFiringArcDegrees = broadsideArcDegrees
    }

sailSpeed :: MovementPhysics -> SailState -> Double
sailSpeed movement sails =
  case sails of
    SailsFurled -> 0
    BattleSails -> movementBattleSpeed movement
    FullSails -> movementMaxSpeed movement

setTargetSpeed :: (Ship -> MovementPhysics) -> Double -> Ship -> Ship
setTargetSpeed movementForShip requestedSpeed ship =
  ship {shipTargetSpeed = clamp 0 (movementMaxSpeed (movementForShip ship)) requestedSpeed}

issueNavigationOrder :: Double -> (Ship -> MovementPhysics) -> Point -> Ship -> Ship
issueNavigationOrder tickSeconds movementForShip requestedWaypoint ship =
  cruisingShip
    { shipNavigationOrder =
        Just
          NavigationOrder
            { navigationRequestedWaypoint = requestedWaypoint
            , navigationReachableWaypoint = navigationPlanReachableWaypoint plan
            , navigationPostWaypointSpeed = navigationPlanArrivalSpeed plan
            }
    }
 where
  movement = movementForShip ship
  cruisingShip = ensureNavigationCruiseSpeed movement ship
  plan = planNavigation tickSeconds movement cruisingShip requestedWaypoint

ensureNavigationCruiseSpeed :: MovementPhysics -> Ship -> Ship
ensureNavigationCruiseSpeed movement ship
  | shipTargetSpeed ship <= 0 =
      ship {shipTargetSpeed = min (movementMaxSpeed movement) (movementBattleSpeed movement)}
  | otherwise = ship

-- | While a waypoint is active, drag speed belongs to that order and only
-- applies after arrival. Once it has cleared, the same gesture changes the
-- ship's current target speed instead.
setNavigationPostWaypointSpeed :: (Ship -> MovementPhysics) -> Double -> Ship -> Ship
setNavigationPostWaypointSpeed movementForShip requestedSpeed ship =
  case shipNavigationOrder ship of
    Nothing -> setTargetSpeed movementForShip requestedSpeed ship
    Just order ->
      ship
        { shipNavigationOrder =
            Just order {navigationPostWaypointSpeed = clampedSpeed}
        }
 where
  clampedSpeed = clamp 0 (movementMaxSpeed (movementForShip ship)) requestedSpeed

-- | Produce the exact selected trajectory that repeated 'moveShip' calls will
-- execute. Command-time callers persist its reachable waypoint; later ticks
-- only re-plan motion toward that fixed point.
planNavigation :: Double -> MovementPhysics -> Ship -> Point -> NavigationPlan
planNavigation tickSeconds movement ship requestedWaypoint =
  navigationPlanForOrder tickSeconds movement ship planningOrder
 where
  reachableWaypoint = reachableNavigationWaypoint movement ship requestedWaypoint
  planningOrder =
    NavigationOrder
      { navigationRequestedWaypoint = requestedWaypoint
      , navigationReachableWaypoint = reachableWaypoint
      , navigationPostWaypointSpeed = shipTargetSpeed ship
      }

-- | Re-plan an active order from the latest actual ship state while preserving
-- the reachable waypoint committed when that order was issued.
planActiveNavigation :: Double -> MovementPhysics -> Ship -> Maybe NavigationPlan
planActiveNavigation tickSeconds movement ship =
  if shipHull ship <= 0
    then Nothing
    else fmap (navigationPlanForOrder tickSeconds movement ship) (shipNavigationOrder ship)

navigationPlanForOrder :: Double -> MovementPhysics -> Ship -> NavigationOrder -> NavigationPlan
navigationPlanForOrder tickSeconds movement ship planningOrder =
  NavigationPlan
    { navigationPlanRequestedWaypoint = navigationRequestedWaypoint planningOrder
    , navigationPlanReachableWaypoint = navigationReachableWaypoint planningOrder
    , navigationPlanWasClamped = navigationReachableWaypoint planningOrder /= navigationRequestedWaypoint planningOrder
    , navigationPlanArrivalSpeed = arrivalSpeed
    , navigationPlanReachedSafetyCap = reachedSafetyCap
    , navigationPlanSamples = reverse samplesReversed
    }
 where
  planningShip = ship {shipNavigationOrder = Just planningOrder}
  (samplesReversed, arrivalSpeed, reachedSafetyCap) = collectTrajectory plannerSafetyTickLimit 0 [trajectorySample 0 planningShip] planningShip

  collectTrajectory remaining offset samples current
    | shipNavigationOrder current == Nothing = (samples, shipCurrentSpeed current, False)
    | remaining <= 0 = (samples, shipCurrentSpeed current, True)
    | otherwise =
        let next = moveShip tickSeconds movement current
            nextOffset = offset + 1
         in collectTrajectory (remaining - 1) nextOffset (trajectorySample nextOffset next : samples) next

navigationArrivalRadius :: Double
navigationArrivalRadius = 1

-- | Whether the ship's movement this tick brought its track close enough to the
-- waypoint to count as arrival.
--
-- A ship commits to one heading for a whole tick and only then re-aims, so it
-- approaches a waypoint along a polygon whose chords pass the waypoint by some
-- distance. How large that miss can be is governed by the ship's turning circle:
-- the ship is on a circle of radius @r@ centred one radius to its side, and the
-- waypoint can only be approached as closely as that circle's geometry allows.
--
-- With 'navigationArrivalRadius' alone (1 world unit) a ship on a wide turn can
-- never satisfy the test. Against the shipped runtime config (battle_speed 4,
-- turn_rate 30 deg\/s, turning radius 7.64) a ship closed no closer than 2.08
-- units and orbited its waypoint forever, so it never cleared its order and the
-- enemy orbit autopilot could never advance past its first waypoint.
--
-- The tolerance is therefore the turning radius scaled by how nearly the ship is
-- already travelling at the waypoint. A ship pointed straight at its waypoint
-- needs almost no turn and must arrive accurately; a ship on a hard orbit cannot
-- do better than its circle allows and is accepted. Everything in between
-- interpolates on the sine of the required heading change, which is exactly the
-- miss a chord of that turn produces.
--
-- 'navigationArrivalRadius' stays the floor so that arrival never becomes
-- sloppier than it has always been.
arrivalRequiredHeading :: Ship -> Point -> Double
arrivalRequiredHeading ship waypoint =
  degreesToRadians (abs (normalizeSigned (headingDegrees (shipHeading ship) - bearingDegrees)))
 where
  bearingDegrees = headingDegrees (bearingBetween (shipPosition ship) waypoint)
  normalizeSigned degrees
    | degrees > 180 = degrees - 360
    | degrees < -180 = degrees + 360
    | otherwise = degrees

arrivalTolerance :: Double -> MovementPhysics -> Ship -> Point -> Double
arrivalTolerance tickSeconds movement ship waypoint =
  max
    navigationArrivalRadius
    (turnRadius * sin (min (pi / 2) (arrivalRequiredHeading ship waypoint)))
 where
  turnRadius = turningRadiusAtBattleSpeed tickSeconds movement ship

navigationStepReachedApproach :: Double -> MovementPhysics -> Ship -> Ship -> Point -> Bool
navigationStepReachedApproach tickSeconds movement before after waypoint =
  pointToSegmentDistance waypoint (shipPosition before) (shipPosition after)
    <= arrivalTolerance tickSeconds movement before waypoint

-- | The radius of the tightest turn the ship can hold at battle speed.
turningRadiusAtBattleSpeed :: Double -> MovementPhysics -> Ship -> Double
turningRadiusAtBattleSpeed _ movement ship =
  minimumTurningRadius movement ship {shipCurrentSpeed = movementBattleSpeed movement}

plannerSafetyTickLimit :: Int
plannerSafetyTickLimit = 2000

trajectorySample :: Int -> Ship -> TrajectorySample
trajectorySample offset ship =
  TrajectorySample
    { trajectorySampleTickOffset = offset
    , trajectorySamplePosition = shipPosition ship
    , trajectorySampleHeading = shipHeading ship
    , trajectorySampleSpeed = shipCurrentSpeed ship
    , trajectorySampleYawRate = shipCurrentYawRate ship
    }

reachableNavigationWaypoint :: MovementPhysics -> Ship -> Point -> Point
reachableNavigationWaypoint movement ship requestedWaypoint
  | requestedDistance >= minimumDistance = requestedWaypoint
  | otherwise = advancePoint (shipPosition ship) requestedBearing minimumDistance
 where
  requestedDistance = distance (shipPosition ship) requestedWaypoint
  requestedBearing =
    if requestedDistance <= 0
      then shipHeading ship
      else bearingBetween (shipPosition ship) requestedWaypoint
  minimumDistance = max navigationArrivalRadius (minimumTurningRadius movement ship + navigationArrivalRadius)

minimumTurningRadius :: MovementPhysics -> Ship -> Double
minimumTurningRadius movement ship
  | maximumYawRateRadians <= 0 = 0
  | otherwise = shipCurrentSpeed ship / maximumYawRateRadians
 where
  maximumYawRateRadians =
    degreesToRadians
      (movementTurnRate movement * rudderAuthority movement (shipCurrentSpeed ship))

setNavigationHeading :: Ship -> Ship
setNavigationHeading ship =
  case shipNavigationOrder ship of
    Nothing -> ship
    Just order ->
      ship
        { shipTargetHeading = bearingBetween (shipPosition ship) (navigationReachableWaypoint order)
        }

-- | Clear an active navigation order once the ship has reached its waypoint.
-- 'before' carries the order and the pre-move state used to size the arrival
-- tolerance; 'after' is the moved ship that receives the cleared order.
clearArrivedNavigation :: Double -> MovementPhysics -> Ship -> Ship -> Ship
clearArrivedNavigation tickSeconds movement before after =
  case shipNavigationOrder before of
    Nothing -> after
    Just order
      | navigationStepReachedApproach
          tickSeconds
          movement
          before
          after
          (navigationReachableWaypoint order) ->
          after
            { shipNavigationOrder = Nothing
            , shipTargetSpeed = navigationPostWaypointSpeed order
            }
      | otherwise -> after

pointToSegmentDistance :: Point -> Point -> Point -> Double
pointToSegmentDistance point segmentStart segmentEnd
  | segmentLengthSquared <= 0 = distance point segmentStart
  | otherwise = distance point closestPoint
 where
  segmentX = pointX segmentEnd - pointX segmentStart
  segmentY = pointY segmentEnd - pointY segmentStart
  segmentLengthSquared = segmentX ** 2 + segmentY ** 2
  projection =
    clamp
      0
      1
      ( ((pointX point - pointX segmentStart) * segmentX + (pointY point - pointY segmentStart) * segmentY)
          / segmentLengthSquared
      )
  closestPoint =
    Point
      { pointX = pointX segmentStart + projection * segmentX
      , pointY = pointY segmentStart + projection * segmentY
      }

-- | The turn rate the ship aims for this tick.
--
-- The command is proportional to the heading error and saturates at full rudder
-- authority, so it tapers as the ship closes on its target bearing. Commanding
-- full authority for any error above the deadband makes the loop a relay: yaw
-- inertia then carries the ship past its bearing at least
-- @w^2 \/ (2 * yaw_acceleration)@ degrees, and because a waypoint-bearing always
-- rotates back toward the ship, it overshoots the other way on the next stroke.
-- Against the shipped config that sustained a limit cycle (turning left and
-- right along the whole approach) instead of one committed curve.
--
-- 'navigationHeadingCorrectionSeconds' is the time the ship would take to null
-- the current error at full authority, so the gain is its reciprocal and the
-- closed-loop damping @1 \/ (2 * sqrt (yaw_acceleration \/ correctionSeconds))@
-- is independent of speed.
targetYawRate :: MovementPhysics -> Ship -> Double
targetYawRate movement ship
  | abs headingDelta <= headingArrivalEpsilon = 0
  | otherwise = clamp (-authority) authority (headingDelta / navigationHeadingCorrectionSeconds)
  where
    headingDelta = normalizeSignedDegrees (headingDegrees (shipTargetHeading ship) - headingDegrees (shipHeading ship))
    authority = movementTurnRate movement * rudderAuthority movement (shipCurrentSpeed ship)

-- | Heading correction horizon for navigation steering. Larger values turn
-- earlier and more gently; smaller values approach a relay and re-introduce
-- overshoot. Two seconds keeps most of the approach inside the proportional
-- band while still using full rudder for large errors.
navigationHeadingCorrectionSeconds :: Double
navigationHeadingCorrectionSeconds = 2

rudderAuthority :: MovementPhysics -> Double -> Double
rudderAuthority movement speed =
  clamp 0 1 (speed / movementIdealTurnSpeed movement)

advanceHeading :: Heading -> Double -> Double -> Heading
advanceHeading heading yawRate tickSeconds =
  normalizeHeading (Heading (headingDegrees heading + yawRate * tickSeconds))

headingArrivalEpsilon :: Double
headingArrivalEpsilon = 0.001

approach :: Double -> Double -> Double -> Double
approach current target maximumChange
  | current < target = min target (current + maximumChange)
  | otherwise = max target (current - maximumChange)

clamp :: Double -> Double -> Double -> Double
clamp lower upper value = max lower (min upper value)

finishIfTerminal :: CombatState -> CombatState
finishIfTerminal state =
  clearDisabledNavigation $
    let
      playerDisabled = shipHull (combatPlayer state) <= 0
      enemyDisabled = shipHull (combatEnemy state) <= 0
     in
      state
        { combatStatus =
            case (playerDisabled, enemyDisabled) of
              (False, False) -> ScenarioRunning
              (True, True) -> ScenarioFinished MutualDestruction
              (True, False) -> ScenarioFinished (Winner EnemyShip)
              (False, True) -> ScenarioFinished (Winner PlayerShip)
        }

selectShip :: ShipId -> CombatState -> Ship
selectShip identity state =
  case identity of
    PlayerShip -> combatPlayer state
    EnemyShip -> combatEnemy state

updateShip :: ShipId -> (Ship -> Ship) -> CombatState -> CombatState
updateShip identity update state =
  case identity of
    PlayerShip -> state {combatPlayer = update (combatPlayer state)}
    EnemyShip -> state {combatEnemy = update (combatEnemy state)}

-- | Disabled ships no longer accept any movement intent. Keeping that rule at
-- the command boundary also covers clients that are temporarily behind the
-- latest terminal snapshot.
updateNavigatingShip :: ShipId -> (Ship -> Ship) -> CombatState -> CombatState
updateNavigatingShip identity update state =
  updateShip identity (\ship -> if shipHull ship <= 0 then ship else update ship) state

clearDisabledNavigation :: CombatState -> CombatState
clearDisabledNavigation =
  updateBothShips clearNavigationWhenDisabled

clearNavigationWhenDisabled :: Ship -> Ship
clearNavigationWhenDisabled ship
  | shipHull ship <= 0 = ship {shipNavigationOrder = Nothing}
  | otherwise = ship

updateBothShips :: (Ship -> Ship) -> CombatState -> CombatState
updateBothShips update state =
  state
    { combatPlayer = update (combatPlayer state)
    , combatEnemy = update (combatEnemy state)
    }

advancePoint :: Point -> Heading -> Double -> Point
advancePoint point heading speed =
  let
    radians = degreesToRadians (headingDegrees heading)
   in
    Point
      { pointX = pointX point + speed * cos radians
      , pointY = pointY point + speed * sin radians
      }

distance :: Point -> Point -> Double
distance from to =
  sqrt (((pointX to - pointX from) ** 2) + ((pointY to - pointY from) ** 2))

broadsideArcDelta :: Ship -> Ship -> BroadsideSide -> Double
broadsideArcDelta attacker target side =
  angularDistance
    (broadsideHeading (shipHeading attacker) side)
    (bearingBetween (shipPosition attacker) (shipPosition target))

broadsideHeading :: Heading -> BroadsideSide -> Heading
broadsideHeading (Heading degrees) side =
  normalizeHeading $
    Heading $
      case side of
        Port -> degrees + 90
        Starboard -> degrees - 90

broadsideArcDegrees :: Double
broadsideArcDegrees = 45

bearingBetween :: Point -> Point -> Heading
bearingBetween from to =
  normalizeHeading $
    Heading $
      radiansToDegrees $
        atan2
          (pointY to - pointY from)
          (pointX to - pointX from)

angularDistance :: Heading -> Heading -> Double
angularDistance (Heading left) (Heading right) =
  abs (normalizeSignedDegrees (right - left))

normalizeHeading :: Heading -> Heading
normalizeHeading (Heading degrees) =
  Heading (normalizeDegrees degrees)

normalizeDegrees :: Double -> Double
normalizeDegrees degrees =
  let
    wrapped = degrees - 360 * fromIntegral (floor (degrees / 360) :: Int)
   in
    if wrapped < 0 then wrapped + 360 else wrapped

normalizeSignedDegrees :: Double -> Double
normalizeSignedDegrees degrees =
  let
    wrapped = normalizeDegrees degrees
   in
    if wrapped > 180 then wrapped - 360 else wrapped

degreesToRadians :: Double -> Double
degreesToRadians degrees = degrees * pi / 180

radiansToDegrees :: Double -> Double
radiansToDegrees radians = radians * 180 / pi
