{-# LANGUAGE DerivingStrategies #-}

-- | The gun panel's view model: everything the panel shows, read off the
-- snapshot and the player's outstanding order, with no DOM in it.
--
-- The panel is the only place the client holds a state of its own — the order a
-- click asked for, shown before the tick that processes it — and that state is
-- kept honest here: it lives only until a later tick has published a snapshot,
-- so a request the simulation refuses cannot leave the control showing a lie.
module FlorDoMar.Client.GunPanel
  ( FireAtWillRequest (..)
  , FireAtWillRequestUpdate (..)
  , GunPanelState (..)
  , applyFireAtWillRequestUpdate
  , gunPanelState
  , reloadProgress
  , settleFireAtWillRequest
  )
where

import FlorDoMar.Combat

-- | The fire-at-will state a player asked for, and the tick they asked on.
--
-- The tick is what bounds the optimistic display: a snapshot from a later tick
-- has either applied the order or refused it, and either way the panel stops
-- showing the request.
data FireAtWillRequest = FireAtWillRequest
  { fireAtWillRequestArmed :: Bool
  , fireAtWillRequestTick :: Int
  }
  deriving stock (Eq, Show)

-- | One step of the request's life: a click sets it, a snapshot decides it.
data FireAtWillRequestUpdate
  = FireAtWillRequested FireAtWillRequest
  | FireAtWillSnapshot CombatSnapshot
  deriving stock (Eq, Show)

-- | Everything the panel draws.
data GunPanelState = GunPanelState
  { gunPanelTick :: Int
  -- ^ The tick the snapshot is on, carried so a click can stamp its request with
  -- the tick it was made against.
  , gunPanelArmed :: Bool
  -- ^ The state the toggle and the circle's colour show: the requested state
  -- until a tick has had the chance to apply it, then the snapshot's own.
  , gunPanelToggleEnabled :: Bool
  -- ^ Arming is only possible with the guns loaded; disengaging is always
  -- possible; and a refused arming cannot be attempted at all.
  , gunPanelReloadProgress :: Double
  -- ^ Zero at the instant a volley starts the reload, one when the guns are
  -- loaded.
  , gunPanelReloadTicksRemaining :: Int
  , gunPanelReloadTicksTotal :: Int
  , gunPanelReloadSweepSeconds :: Double
  -- ^ The tick length the sweep interpolates over, so the circle slides between
  -- the snapshots the simulation actually publishes.
  , gunPanelLockTarget :: Maybe ShipId
  -- ^ The ship the lock control acts on: the hovered one if there is one,
  -- otherwise the locked one. Nothing means the control does not appear, so a
  -- lock action is never offered with no target.
  , gunPanelLockReleases :: Bool
  -- ^ Whether that control takes the lock or lets it go.
  }
  deriving stock (Eq, Show)

-- | Fold one update into the outstanding request.
applyFireAtWillRequestUpdate :: FireAtWillRequestUpdate -> Maybe FireAtWillRequest -> Maybe FireAtWillRequest
applyFireAtWillRequestUpdate update current =
  case update of
    FireAtWillRequested request -> Just request
    FireAtWillSnapshot snapshot -> settleFireAtWillRequest snapshot current

-- | The outstanding request after a snapshot arrives.
--
-- It is dropped as soon as the snapshot comes from a tick later than the one it
-- was made on — whether that tick applied it or refused it. Both outcomes are
-- correct by the same rule: the request has been decided, so the panel shows the
-- snapshot. A request the next tick cannot satisfy therefore reverts instead of
-- sticking.
settleFireAtWillRequest :: CombatSnapshot -> Maybe FireAtWillRequest -> Maybe FireAtWillRequest
settleFireAtWillRequest snapshot request =
  case request of
    Just outstanding
      | combatSnapshotTick snapshot > fireAtWillRequestTick outstanding -> Nothing
    _ -> request

-- | The whole panel read off the snapshot, the outstanding request and the ship
-- under the pointer.
gunPanelState :: CombatSnapshot -> Maybe FireAtWillRequest -> Maybe ShipId -> GunPanelState
gunPanelState snapshot request hoveredShip =
  GunPanelState
    { gunPanelTick = combatSnapshotTick snapshot
    , gunPanelArmed = displayedArmed
    , gunPanelToggleEnabled = displayedArmed || reloadRemaining == 0
    , gunPanelReloadProgress = reloadProgress reloadRemaining reloadTotal
    , gunPanelReloadTicksRemaining = reloadRemaining
    , gunPanelReloadTicksTotal = reloadTotal
    , gunPanelReloadSweepSeconds = reloadSweepSeconds
    , gunPanelLockTarget = lockTarget
    , gunPanelLockReleases = lockTarget /= Nothing && lockTarget == lockedTarget
    }
 where
  player = findSnapshotShip PlayerShip snapshot
  armed = maybe False shipSnapshotFirePermission player
  lockedTarget = player >>= shipSnapshotLockedTarget
  reloadRemaining = maybe 0 shipSnapshotReloadTicksRemaining player
  reloadTotal = maybe 0 shipSnapshotReloadTicksTotal player
  reloadSweepSeconds = max 0 (combatSnapshotTickSeconds snapshot)
  displayedArmed = maybe armed fireAtWillRequestArmed request
  -- The player's own hull is not a lock: the client never offers, and never
  -- sends, a self-lock.
  lockTarget =
    case hoveredShip of
      Just hovered | hovered /= PlayerShip -> Just hovered
      _ ->
        case lockedTarget of
          Just locked | locked /= PlayerShip -> Just locked
          _ -> Nothing

-- | How far the shared reload has come: zero when a volley has just started it,
-- one when the guns are loaded again.
--
-- It reads the reload counter alone, not the fire permission, because the guns
-- reload whether or not they are permitted to fire — so disengaging mid-reload
-- leaves the sweep running to full instead of resetting it.
reloadProgress :: Int -> Int -> Double
reloadProgress remaining total
  | total <= 0 = 1
  | otherwise = fromIntegral (max 0 (min total (total - remaining))) / fromIntegral total
