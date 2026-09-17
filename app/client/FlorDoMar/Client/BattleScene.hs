{-# LANGUAGE DerivingStrategies #-}

module FlorDoMar.Client.BattleScene
  ( BattleScene (..)
  , ShipMarker (..)
  , battleSceneFromSnapshot
  )
where

import Data.Text (Text)
import FlorDoMar.Combat

data BattleScene = BattleScene
  { battleSceneShips :: [ShipMarker]
  , battleSceneRange :: Double
  , battleSceneStatus :: ScenarioStatus
  }
  deriving stock (Eq, Show)

data ShipMarker = ShipMarker
  { markerName :: Text
  , markerPosition :: Point
  , markerHeading :: Heading
  , markerHull :: Int
  , markerIsPlayer :: Bool
  }
  deriving stock (Eq, Show)

battleSceneFromSnapshot :: CombatSnapshot -> BattleScene
battleSceneFromSnapshot snapshot =
  BattleScene
    { battleSceneShips = fmap shipMarker (combatSnapshotShips snapshot)
    , battleSceneRange = engagementRange (combatSnapshotEngagement snapshot)
    , battleSceneStatus = combatSnapshotStatus snapshot
    }

shipMarker :: ShipSnapshot -> ShipMarker
shipMarker ship =
  ShipMarker
    { markerName = shipSnapshotName ship
    , markerPosition = shipSnapshotPosition ship
    , markerHeading = shipSnapshotHeading ship
    , markerHull = shipSnapshotHull ship
    , markerIsPlayer = shipSnapshotId ship == PlayerShip
    }
