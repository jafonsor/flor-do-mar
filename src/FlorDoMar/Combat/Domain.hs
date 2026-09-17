{-# LANGUAGE DerivingStrategies #-}

module FlorDoMar.Combat.Domain
  ( BroadsideCheck (..)
  , BroadsideSide (..)
  , CombatCommand (..)
  , CombatState (..)
  , Heading (..)
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
  , caravelaDuel
  , reloadTicks
  , tickCombat
  )
where

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

data Ship = Ship
  { shipId :: ShipId
  , shipPosition :: Point
  , shipHeading :: Heading
  , shipSails :: SailState
  , shipHull :: Int
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
    , combatWind = Wind {windDirection = Heading 45, windSpeed = 12}
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
tickCombat commands state =
  case combatStatus state of
    ScenarioFinished _ -> state
    ScenarioRunning ->
      let
        commanded =
          foldl
            applyCommand
            (coolDownReloads state {combatTick = combatTick state + 1})
            commands
        resolved = finishIfTerminal commanded
       in
        case combatStatus resolved of
          ScenarioFinished _ -> resolved
          ScenarioRunning -> finishIfTerminal (moveShips resolved)

canFireBroadside :: CombatState -> ShipId -> ShipId -> BroadsideSide -> BroadsideCheck
canFireBroadside state attackerId targetId side =
  case combatStatus state of
    ScenarioFinished outcome -> ScenarioAlreadyFinished outcome
    ScenarioRunning ->
      let
        attacker = selectShip attackerId state
        target = selectShip targetId state
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
                    if range > broadsideRange
                      then TargetOutOfRange range
                      else
                        if arcDelta > broadsideArcDegrees
                          then TargetOutsideFiringArc arcDelta
                          else BroadsideReady

caravela :: ShipId -> Point -> Heading -> Ship
caravela identity position heading =
  Ship
    { shipId = identity
    , shipPosition = position
    , shipHeading = normalizeHeading heading
    , shipSails = BattleSails
    , shipHull = 100
    , shipReload = 0
    }

applyCommand :: CombatState -> CombatCommand -> CombatState
applyCommand state command =
  case command of
    SetHeading identity heading ->
      updateShip identity (\ship -> ship {shipHeading = normalizeHeading heading}) state
    SetSails identity sails ->
      updateShip identity (\ship -> ship {shipSails = sails}) state
    FireBroadside attackerId targetId side ->
      case canFireBroadside state attackerId targetId side of
        BroadsideReady ->
          updateShip attackerId (\ship -> ship {shipReload = reloadTicks}) $
            updateShip targetId (\ship -> ship {shipHull = max 0 (shipHull ship - broadsideDamage)}) state
        _ -> state

coolDownReloads :: CombatState -> CombatState
coolDownReloads =
  updateBothShips (\ship -> ship {shipReload = max 0 (shipReload ship - 1)})

moveShips :: CombatState -> CombatState
moveShips =
  updateBothShips moveShip

moveShip :: Ship -> Ship
moveShip ship =
  ship {shipPosition = advancePoint (shipPosition ship) (shipHeading ship) (sailSpeed (shipSails ship))}

sailSpeed :: SailState -> Double
sailSpeed sails =
  case sails of
    SailsFurled -> 0
    BattleSails -> 4
    FullSails -> 7

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
