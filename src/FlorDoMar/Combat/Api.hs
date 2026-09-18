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
  , shipSnapshotMaxHull :: Int
  , shipSnapshotHull :: Int
  , shipSnapshotRenderedLength :: Double
  , shipSnapshotRenderedWidth :: Double
  , shipSnapshotReload :: Int
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
combatSnapshotFromStateWith broadsideTuningForShip scenario state =
  CombatSnapshot
    { combatSnapshotScenario = scenario
    , combatSnapshotTick = combatTick state
    , combatSnapshotWind = windSnapshot (combatWind state)
    , combatSnapshotShips =
        [ shipSnapshot (combatPlayer state)
        , shipSnapshot (combatEnemy state)
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

shipSnapshot :: Ship -> ShipSnapshot
shipSnapshot ship =
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
    , shipSnapshotMaxHull = shipMaxHull ship
    , shipSnapshotHull = shipHull ship
    , shipSnapshotRenderedLength = shipRenderedLength ship
    , shipSnapshotRenderedWidth = shipRenderedWidth ship
    , shipSnapshotReload = shipReload ship
    }

pointDistance :: Point -> Point -> Double
pointDistance from to =
  sqrt (((pointX to - pointX from) ** 2) + ((pointY to - pointY from) ** 2))
