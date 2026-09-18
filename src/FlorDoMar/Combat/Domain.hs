{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Combat.Domain
  ( BroadsideCheck (..)
  , BroadsideSide (..)
  , BroadsideTuning (..)
  , CombatCommand (..)
  , CombatState (..)
  , Heading (..)
  , MovementPhysics (..)
  , Point (..)
  , SailState (..)
  , ScenarioOutcome (..)
  , ScenarioStatus (..)
  , Ship (..)
  , ShipId (..)
  , Wind (..)
  , broadsideDamage
  , broadsideRange
  , canFireBroadside
  , canFireBroadsideWith
  , caravelaDuel
  , legacyBroadsideTuning
  , reloadTicks
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
  , movementMinimumTurnSpeedFactor :: Double
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
  , combatStatus :: ScenarioStatus
  }
  deriving stock (Eq, Show)

data CombatCommand
  = SetHeading ShipId Heading
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
    ScenarioFinished _ -> state
    ScenarioRunning ->
      let
        commanded =
          foldl
            (applyCommand broadsideTuningForShip)
            (coolDownReloads state {combatTick = combatTick state + 1})
            commands
        resolved = finishIfTerminal commanded
       in
        case combatStatus resolved of
          ScenarioFinished _ -> resolved
          ScenarioRunning -> finishIfTerminal (moveShips tickSeconds movementForShip resolved)

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
    , shipMaxHull = 100
    , shipDamageTaken = 0
    , shipHull = 100
    , shipRenderedLength = 10
    , shipRenderedWidth = 4
    , shipReload = 0
    }

applyCommand :: (Ship -> BroadsideTuning) -> CombatState -> CombatCommand -> CombatState
applyCommand broadsideTuningForShip state command =
  case command of
    SetHeading identity heading ->
      updateShip identity (\ship -> ship {shipTargetHeading = normalizeHeading heading}) state
    SetSails identity sails ->
      updateShip identity (\ship -> ship {shipSails = sails}) state
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
  ship
    { shipPosition = advancePoint (shipPosition ship) currentHeading (currentSpeed * tickSeconds)
    , shipHeading = currentHeading
    , shipCurrentSpeed = currentSpeed
    }
 where
  currentHeading = turnToward (shipHeading ship) (shipTargetHeading ship) (effectiveTurnDegrees tickSeconds movement ship)
  currentSpeed = approach (shipCurrentSpeed ship) (targetSpeed movement (shipSails ship)) speedDelta
  speedDelta = tickSeconds * if targetSpeed movement (shipSails ship) >= shipCurrentSpeed ship then movementAcceleration movement else movementDeceleration movement

caravelaMovement :: MovementPhysics
caravelaMovement =
  MovementPhysics
    { movementBattleSpeed = 4
    , movementMaxSpeed = 7
    , movementAcceleration = 7
    , movementDeceleration = 7
    , movementTurnRate = 360
    , movementMinimumTurnSpeedFactor = 1
    }

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

targetSpeed :: MovementPhysics -> SailState -> Double
targetSpeed = sailSpeed

effectiveTurnDegrees :: Double -> MovementPhysics -> Ship -> Double
effectiveTurnDegrees tickSeconds movement ship =
  movementTurnRate movement
    * tickSeconds
    * ( movementMinimumTurnSpeedFactor movement
          + ((1 - movementMinimumTurnSpeedFactor movement) * min 1 (shipCurrentSpeed ship / movementMaxSpeed movement))
      )

turnToward :: Heading -> Heading -> Double -> Heading
turnToward current target maximumTurn =
  if abs delta <= headingArrivalEpsilon || abs delta <= maximumTurn
    then normalizeHeading target
    else normalizeHeading (Heading (headingDegrees current + signum delta * maximumTurn))
 where
  delta = normalizeSignedDegrees (headingDegrees target - headingDegrees current)

headingArrivalEpsilon :: Double
headingArrivalEpsilon = 0.001

approach :: Double -> Double -> Double -> Double
approach current target maximumChange
  | current < target = min target (current + maximumChange)
  | otherwise = max target (current - maximumChange)

finishIfTerminal :: CombatState -> CombatState
finishIfTerminal state =
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
