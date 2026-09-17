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
  , shipSnapshotName :: Text
  , shipSnapshotPosition :: Point
  , shipSnapshotHeading :: Heading
  , shipSnapshotSails :: SailState
  , shipSnapshotHull :: Int
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
combatSnapshotFromState scenario state =
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
          , engagementPlayerPortBroadside = canFireBroadside state PlayerShip EnemyShip Port
          , engagementPlayerStarboardBroadside = canFireBroadside state PlayerShip EnemyShip Starboard
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
    , shipSnapshotName = shipName (shipId ship)
    , shipSnapshotPosition = shipPosition ship
    , shipSnapshotHeading = shipHeading ship
    , shipSnapshotSails = shipSails ship
    , shipSnapshotHull = shipHull ship
    , shipSnapshotReload = shipReload ship
    }

shipName :: ShipId -> Text
shipName identity =
  case identity of
    PlayerShip -> "Player caravela"
    EnemyShip -> "Enemy caravela"

pointDistance :: Point -> Point -> Double
pointDistance from to =
  sqrt (((pointX to - pointX from) ** 2) + ((pointY to - pointY from) ** 2))
