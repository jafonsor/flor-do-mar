{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Combat.Api
  ( CombatApi (..)
  , CombatApiError (..)
  , CombatSnapshot (..)
  , EngagementSnapshot (..)
  , ScenarioId (..)
  , ScenarioSummary (..)
  , ShipSnapshot (..)
  , WindSnapshot (..)
  , caravelaDuelScenario
  , caravelaDuelScenarioId
  , combatSnapshotFromState
  , combatSnapshotFromStateWith
  , combatSnapshotFromStateWithPlanning
  , planNavigationForSnapshot
  , shipFromSnapshot
  )
where

import Data.Text (Text)
import FlorDoMar.Combat.Domain

newtype ScenarioId = ScenarioId
  { unScenarioId :: Text
  }
  deriving stock (Eq, Show)

data ScenarioSummary = ScenarioSummary
  { scenarioSummaryId :: ScenarioId
  , scenarioSummaryName :: Text
  }
  deriving stock (Eq, Show)

data CombatApi m = CombatApi
  { combatApiListScenarios :: m [ScenarioSummary]
  , combatApiStartScenario :: ScenarioId -> m (Either CombatApiError CombatSnapshot)
  , combatApiSubmitCommand :: CombatCommand -> m (Either CombatApiError CombatSnapshot)
  , combatApiAdvanceTick :: m (Either CombatApiError CombatSnapshot)
  , combatApiObserveSnapshot :: m (Either CombatApiError CombatSnapshot)
  }

data CombatApiError
  = CombatScenarioNotFound ScenarioId
  | CombatBoatKindNotFound Text
  | CombatScenarioNotStarted
  deriving stock (Eq, Show)

data CombatSnapshot = CombatSnapshot
  { combatSnapshotScenario :: ScenarioSummary
  , combatSnapshotTick :: Int
  , combatSnapshotTickSeconds :: Double
  , combatSnapshotWind :: WindSnapshot
  , combatSnapshotShips :: [ShipSnapshot]
  , combatSnapshotEngagement :: EngagementSnapshot
  , combatSnapshotStatus :: ScenarioStatus
  }
  deriving stock (Eq, Show)

data WindSnapshot = WindSnapshot
  { windSnapshotDirection :: Heading
  , windSnapshotSpeed :: Double
  }
  deriving stock (Eq, Show)

data ShipSnapshot = ShipSnapshot
  { shipSnapshotId :: ShipId
  , shipSnapshotBoatKind :: Text
  , shipSnapshotName :: Text
  , shipSnapshotDisplayName :: Text
  , shipSnapshotPosition :: Point
  , shipSnapshotHeading :: Heading
  , shipSnapshotTargetHeading :: Heading
  , shipSnapshotSails :: SailState
  , shipSnapshotCurrentSpeed :: Double
  , shipSnapshotTargetSpeed :: Double
  , shipSnapshotCurrentYawRate :: Double
  , shipSnapshotNavigationOrder :: Maybe NavigationOrder
  , shipSnapshotActiveNavigationPlan :: Maybe NavigationPlan
  , shipSnapshotMovementPhysics :: MovementPhysics
  , shipSnapshotMaxSpeed :: Double
  , shipSnapshotMaxHull :: Int
  , shipSnapshotHull :: Int
  , shipSnapshotRenderedLength :: Double
  , shipSnapshotRenderedWidth :: Double
  , shipSnapshotReload :: Int
  , shipSnapshotLockedTarget :: Maybe ShipId
  , shipSnapshotFirePermission :: Bool
  }
  deriving stock (Eq, Show)

data EngagementSnapshot = EngagementSnapshot
  { engagementRange :: Double
  , engagementPlayerPortBroadside :: BroadsideCheck
  , engagementPlayerStarboardBroadside :: BroadsideCheck
  }
  deriving stock (Eq, Show)

caravelaDuelScenarioId :: ScenarioId
caravelaDuelScenarioId = ScenarioId "caravela-duel"

caravelaDuelScenario :: ScenarioSummary
caravelaDuelScenario =
  ScenarioSummary
    { scenarioSummaryId = caravelaDuelScenarioId
    , scenarioSummaryName = "Portuguese caravela duel"
    }

combatSnapshotFromState :: ScenarioSummary -> CombatState -> CombatSnapshot
combatSnapshotFromState = combatSnapshotFromStateWith (const legacyBroadsideTuning)

combatSnapshotFromStateWith :: (Ship -> BroadsideTuning) -> ScenarioSummary -> CombatState -> CombatSnapshot
combatSnapshotFromStateWith =
  combatSnapshotFromStateWithPlanning 1 (const legacyMovementPhysics)

combatSnapshotFromStateWithPlanning :: Double -> (Ship -> MovementPhysics) -> (Ship -> BroadsideTuning) -> ScenarioSummary -> CombatState -> CombatSnapshot
combatSnapshotFromStateWithPlanning tickSeconds movementForShip broadsideTuningForShip scenario state =
  CombatSnapshot
    { combatSnapshotScenario = scenario
    , combatSnapshotTick = combatTick state
    , combatSnapshotTickSeconds = tickSeconds
    , combatSnapshotWind = windSnapshot (combatWind state)
    , combatSnapshotShips =
        [ shipSnapshot tickSeconds movementForShip (combatPlayer state)
        , shipSnapshot tickSeconds movementForShip (combatEnemy state)
        ]
    , combatSnapshotEngagement =
        EngagementSnapshot
          { engagementRange = pointDistance (shipPosition (combatPlayer state)) (shipPosition (combatEnemy state))
          , engagementPlayerPortBroadside = canFireBroadsideWith broadsideTuningForShip state PlayerShip EnemyShip Port
          , engagementPlayerStarboardBroadside = canFireBroadsideWith broadsideTuningForShip state PlayerShip EnemyShip Starboard
          }
    , combatSnapshotStatus = combatStatus state
    }

windSnapshot :: Wind -> WindSnapshot
windSnapshot wind =
  WindSnapshot
    { windSnapshotDirection = windDirection wind
    , windSnapshotSpeed = windSpeed wind
    }

shipSnapshot :: Double -> (Ship -> MovementPhysics) -> Ship -> ShipSnapshot
shipSnapshot tickSeconds movementForShip ship =
  ShipSnapshot
    { shipSnapshotId = shipId ship
    , shipSnapshotBoatKind = shipBoatKind ship
    , shipSnapshotName = shipDisplayName ship
    , shipSnapshotDisplayName = shipDisplayName ship
    , shipSnapshotPosition = shipPosition ship
    , shipSnapshotHeading = shipHeading ship
    , shipSnapshotTargetHeading = shipTargetHeading ship
    , shipSnapshotSails = shipSails ship
    , shipSnapshotCurrentSpeed = shipCurrentSpeed ship
    , shipSnapshotTargetSpeed = shipTargetSpeed ship
    , shipSnapshotCurrentYawRate = shipCurrentYawRate ship
    , shipSnapshotNavigationOrder = shipNavigationOrder ship
    , shipSnapshotActiveNavigationPlan = planActiveNavigation tickSeconds movement ship
    , shipSnapshotMovementPhysics = movement
    , shipSnapshotMaxSpeed = movementMaxSpeed movement
    , shipSnapshotMaxHull = shipMaxHull ship
    , shipSnapshotHull = shipHull ship
    , shipSnapshotRenderedLength = shipRenderedLength ship
    , shipSnapshotRenderedWidth = shipRenderedWidth ship
    , shipSnapshotReload = shipReload ship
    , shipSnapshotLockedTarget = shipLockedTarget ship
    , shipSnapshotFirePermission = shipFirePermission ship
    }
 where
  movement = movementForShip ship

-- | Preview planning starts from the snapshot's actual ship state, using the
-- same domain planner and result shape as an active navigation order.
planNavigationForSnapshot :: CombatSnapshot -> ShipId -> Point -> Maybe NavigationPlan
planNavigationForSnapshot snapshot identity requestedWaypoint = do
  ship <- findSnapshotShip identity snapshot
  if combatSnapshotStatus snapshot /= ScenarioRunning || shipSnapshotHull ship <= 0
    then Nothing
    else
      pure $
        planNavigation
          (combatSnapshotTickSeconds snapshot)
          (shipSnapshotMovementPhysics ship)
          (shipFromSnapshot ship)
          requestedWaypoint

findSnapshotShip :: ShipId -> CombatSnapshot -> Maybe ShipSnapshot
findSnapshotShip identity = go . combatSnapshotShips
 where
  go snapshots =
    case snapshots of
      ship : remaining
        | shipSnapshotId ship == identity -> Just ship
        | otherwise -> go remaining
      [] -> Nothing

shipFromSnapshot :: ShipSnapshot -> Ship
shipFromSnapshot snapshot =
  Ship
    { shipId = shipSnapshotId snapshot
    , shipBoatKind = shipSnapshotBoatKind snapshot
    , shipDisplayName = shipSnapshotDisplayName snapshot
    , shipPosition = shipSnapshotPosition snapshot
    , shipHeading = shipSnapshotHeading snapshot
    , shipTargetHeading = shipSnapshotTargetHeading snapshot
    , shipSails = shipSnapshotSails snapshot
    , shipCurrentSpeed = shipSnapshotCurrentSpeed snapshot
    , shipTargetSpeed = shipSnapshotTargetSpeed snapshot
    , shipCurrentYawRate = shipSnapshotCurrentYawRate snapshot
    , shipNavigationOrder = shipSnapshotNavigationOrder snapshot
    , shipMaxHull = shipSnapshotMaxHull snapshot
    , shipDamageTaken = shipSnapshotMaxHull snapshot - shipSnapshotHull snapshot
    , shipHull = shipSnapshotHull snapshot
    , shipRenderedLength = shipSnapshotRenderedLength snapshot
    , shipRenderedWidth = shipSnapshotRenderedWidth snapshot
    , shipReload = shipSnapshotReload snapshot
    , shipLockedTarget = shipSnapshotLockedTarget snapshot
    , shipFirePermission = shipSnapshotFirePermission snapshot
    }

pointDistance :: Point -> Point -> Double
pointDistance from to =
  sqrt (((pointX to - pointX from) ** 2) + ((pointY to - pointY from) ** 2))
