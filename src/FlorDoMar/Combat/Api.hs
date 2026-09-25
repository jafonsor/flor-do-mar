{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Combat.Api
  ( CombatApi (..)
  , CombatApiError (..)
  , CombatSnapshot (..)
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
  -- | The broadside tuning the simulation validates volleys against, travelling
  -- with the ship exactly as 'shipSnapshotMovementPhysics' does. A client draws
  -- the firing envelope from this record rather than joining the loaded config
  -- by boat kind, so a config hot reload cannot make the drawn envelope and the
  -- enforced one drift apart mid-battle.
  , shipSnapshotBroadsideTuning :: BroadsideTuning
  , shipSnapshotMaxSpeed :: Double
  , shipSnapshotMaxHull :: Int
  , shipSnapshotHull :: Int
  , shipSnapshotRenderedLength :: Double
  , shipSnapshotRenderedWidth :: Double
  -- | The shared reload's remaining ticks. The total it counts down from is
  -- published beside it, so a reload readout cannot be misread as a fraction of
  -- the wrong denominator.
  , shipSnapshotReloadTicksRemaining :: Int
  , shipSnapshotReloadTicksTotal :: Int
  , shipSnapshotLockedTarget :: Maybe ShipId
  , shipSnapshotFirePermission :: Bool
  -- | Whether each broadside's firing envelope currently holds the locked
  -- target — \"target inside\" in the glossary. It is geometry alone, computed
  -- by the same predicate 'canFireBroadsideWith' uses for its range and arc
  -- steps, so a loaded side that has been turned away and a reloading side that
  -- still bears both read truthfully. A ship with no lock, or one whose lock
  -- names a ship the scenario does not carry, holds nothing on either side.
  , shipSnapshotPortHoldsTarget :: Bool
  , shipSnapshotStarboardHoldsTarget :: Bool
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
        [ shipSnapshot tickSeconds movementForShip broadsideTuningForShip state (combatPlayer state)
        , shipSnapshot tickSeconds movementForShip broadsideTuningForShip state (combatEnemy state)
        ]
    , combatSnapshotStatus = combatStatus state
    }

windSnapshot :: Wind -> WindSnapshot
windSnapshot wind =
  WindSnapshot
    { windSnapshotDirection = windDirection wind
    , windSnapshotSpeed = windSpeed wind
    }

shipSnapshot :: Double -> (Ship -> MovementPhysics) -> (Ship -> BroadsideTuning) -> CombatState -> Ship -> ShipSnapshot
shipSnapshot tickSeconds movementForShip broadsideTuningForShip state ship =
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
    , shipSnapshotBroadsideTuning = tuning
    , shipSnapshotMaxSpeed = movementMaxSpeed movement
    , shipSnapshotMaxHull = shipMaxHull ship
    , shipSnapshotHull = shipHull ship
    , shipSnapshotRenderedLength = shipRenderedLength ship
    , shipSnapshotRenderedWidth = shipRenderedWidth ship
    , shipSnapshotReloadTicksRemaining = shipReload ship
    , shipSnapshotReloadTicksTotal = broadsideTuningReloadTicks tuning
    , shipSnapshotLockedTarget = shipLockedTarget ship
    , shipSnapshotFirePermission = shipFirePermission ship
    , shipSnapshotPortHoldsTarget = holdsTarget Port
    , shipSnapshotStarboardHoldsTarget = holdsTarget Starboard
    }
 where
  movement = movementForShip ship
  tuning = broadsideTuningForShip ship
  lockedTarget = lockedTargetShip state ship
  holdsTarget side =
    case lockedTarget of
      Just target -> broadsideGeometry tuning ship target side == EnvelopeHoldsTarget
      Nothing -> False

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
    , shipReload = shipSnapshotReloadTicksRemaining snapshot
    , shipLockedTarget = shipSnapshotLockedTarget snapshot
    , shipFirePermission = shipSnapshotFirePermission snapshot
    }
