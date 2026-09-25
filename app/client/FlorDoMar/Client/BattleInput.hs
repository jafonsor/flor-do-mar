{-# LANGUAGE DerivingStrategies #-}

module FlorDoMar.Client.BattleInput
  ( NavigationGesture (..)
  , NavigationHoverIntent (..)
  , NavigationPointerIntent (..)
  , NavigationPress (..)
  , NavigationReleaseIntent (..)
  , PointerSample (..)
  , RawPointerMovement (..)
  , RawPointerEvent (..)
  , ScreenPoint (..)
  , ScreenSize (..)
  , applyNavigationHoverIntent
  , beginNavigationGestureAt
  , hoverIntentFromRawPointer
  , hoveredShipAt
  , hullAtReticle
  , lockTargetAtSample
  , navigationGestureSelectedSpeed
  , navigationInputAllowed
  , navigationPointerIntentFromRawPointer
  , navigationReleaseIntent
  , pointerSample
  , reticleRadiusPixels
  , reticleShip
  , screenBattleViewport
  , screenReticleRadius
  , screenToBattlePoint
  , speedSelectionRadius
  , updateNavigationGesture
  )
where

import Data.List (sortOn)
import FlorDoMar.Client.WebGL.Camera
import FlorDoMar.Client.WebGL.Math
import FlorDoMar.Combat (CombatSnapshot (..), Point (..), ScenarioStatus (..), ShipId, ShipSnapshot (..))

data ScreenPoint = ScreenPoint
  { screenPointX :: Double
  , screenPointY :: Double
  }
  deriving stock (Eq, Show)

data ScreenSize = ScreenSize
  { screenSizeWidth :: Double
  , screenSizeHeight :: Double
  }
  deriving stock (Eq, Show)

-- | A pointer position in battle units together with the reticle that position
-- carries: 'reticleRadiusPixels' converted at the same camera and canvas size the
-- position was converted at.
--
-- The two travel together on purpose. The hover ring and the locked ring are
-- drawn at this radius and the click hit test runs at this radius, so the marker
-- cannot lie about the gesture — the ring is where the click lands, however the
-- canvas is displayed.
data PointerSample = PointerSample
  { pointerSamplePoint :: Point
  , pointerSampleReticleRadius :: Double
  }
  deriving stock (Eq, Show)

data RawPointerMovement
  = PointerMoved ScreenPoint ScreenSize
  | PointerLeftBattleView
  | PointerMovedOverControl
  deriving stock (Eq, Show)

-- | Raw DOM pointer facts. This adapter is the only client layer that knows
-- about screen coordinates; the battle view turns its results into commands.
data RawPointerEvent
  = RawPointerMoved ScreenPoint ScreenSize
  | RawPrimaryPointerDown ScreenPoint ScreenSize
  | RawPrimaryPointerUp
  | RawPointerLeftBattleView
  deriving stock (Eq, Show)

data NavigationHoverIntent
  = PreviewNavigation Point
  | ClearNavigationHover
  deriving stock (Eq, Show)

-- | UI-level pointer intent, independent of DOM events and combat commands.
data NavigationPointerIntent
  = NavigationPointerMoved PointerSample
  | NavigationPointerPrimaryDown PointerSample
  | NavigationPointerPrimaryUp
  | NavigationPointerLeftBattleView
  deriving stock (Eq, Show)

-- | The facts a primary press holds for as long as the gesture lasts.
--
-- The ship under the reticle is decided here, at the press position, because the
-- release rule is \"a press on a hull that releases without movement toggles the
-- lock\": which hull that is was fixed when the press landed, and dragging must
-- not re-aim it.
data NavigationPress = NavigationPress
  { navigationPressRequestedWaypoint :: Point
  , navigationPressReachableWaypoint :: Point
  , navigationPressMaximumSpeed :: Double
  , navigationPressShip :: Maybe ShipId
  }
  deriving stock (Eq, Show)

-- | State held while a primary mouse gesture owns a navigation order. A
-- missing selected speed distinguishes a plain click from a drag-to-speed.
data NavigationGesture
  = NoNavigationGesture
  | NavigationGesture NavigationPress (Maybe Double)
  deriving stock (Eq, Show)

-- | What a released primary gesture asks the battle view to do.
--
-- A click on empty water is still a navigation order: the lock gesture must not
-- cost the navigation gesture it grew out of.
data NavigationReleaseIntent
  = NavigateOnRelease Point (Maybe Double)
  | LockOnRelease ShipId
  deriving stock (Eq, Show)

-- | Navigation gestures only belong to a live battle. The battle view and
-- scene both use this predicate so a blocked interaction cannot leave an
-- overlay behind.
navigationInputAllowed :: Bool -> ScenarioStatus -> Bool
navigationInputAllowed setupIsOpen scenarioStatus =
  not setupIsOpen && scenarioStatus == ScenarioRunning

hoverIntentFromRawPointer :: Camera2D -> RawPointerMovement -> NavigationHoverIntent
hoverIntentFromRawPointer camera movement =
  case movement of
    PointerMoved point size -> PreviewNavigation (screenToBattlePoint camera point size)
    PointerLeftBattleView -> ClearNavigationHover
    PointerMovedOverControl -> ClearNavigationHover

applyNavigationHoverIntent :: Maybe Point -> NavigationHoverIntent -> Maybe Point
applyNavigationHoverIntent _ intent =
  case intent of
    PreviewNavigation point -> Just point
    ClearNavigationHover -> Nothing

navigationPointerIntentFromRawPointer :: Camera2D -> RawPointerEvent -> NavigationPointerIntent
navigationPointerIntentFromRawPointer camera rawEvent =
  case rawEvent of
    RawPointerMoved point size -> NavigationPointerMoved (pointerSample camera point size)
    RawPrimaryPointerDown point size -> NavigationPointerPrimaryDown (pointerSample camera point size)
    RawPrimaryPointerUp -> NavigationPointerPrimaryUp
    RawPointerLeftBattleView -> NavigationPointerLeftBattleView

-- | One pointer position with the reticle it carries, converted in one place.
pointerSample :: Camera2D -> ScreenPoint -> ScreenSize -> PointerSample
pointerSample camera point size =
  PointerSample
    { pointerSamplePoint = screenToBattlePoint camera point size
    , pointerSampleReticleRadius = screenReticleRadius camera size
    }

-- | The gesture a press begins, from the requested waypoint, the planner's
-- reachable waypoint, the ship's maximum speed and the ship the press hit.
beginNavigationGestureAt :: Point -> Point -> Double -> Maybe ShipId -> NavigationGesture
beginNavigationGestureAt requestedWaypoint reachableWaypoint maximumSpeed pressedShip =
  NavigationGesture
    NavigationPress
      { navigationPressRequestedWaypoint = requestedWaypoint
      , navigationPressReachableWaypoint = reachableWaypoint
      , navigationPressMaximumSpeed = max 0 maximumSpeed
      , navigationPressShip = pressedShip
      }
    Nothing

updateNavigationGesture :: Point -> NavigationGesture -> NavigationGesture
updateNavigationGesture pointer gesture =
  case gesture of
    NoNavigationGesture -> NoNavigationGesture
    NavigationGesture press _ ->
      NavigationGesture
        press
        (Just (navigationPressMaximumSpeed press * min 1 (distance (navigationPressReachableWaypoint press) pointer / speedSelectionRadius)))

navigationGestureSelectedSpeed :: NavigationGesture -> Maybe Double
navigationGestureSelectedSpeed gesture =
  case gesture of
    NoNavigationGesture -> Nothing
    NavigationGesture _ selectedSpeed -> selectedSpeed

-- | What a released primary gesture asks for, decided at release from what the
-- press was.
--
-- The split is the gesture model's own signal: a plain click never selects a
-- post-waypoint speed, and anything that moved has one. A click on a hull the
-- shooter may lock toggles that lock and issues no navigation order; a click on
-- the shooter's own hull asks for nothing at all; every other release is a
-- navigation order, with the selected speed when there is one.
navigationReleaseIntent :: ShipId -> ScenarioStatus -> Bool -> NavigationGesture -> Maybe NavigationReleaseIntent
navigationReleaseIntent shooter scenarioStatus setupIsOpen gesture
  | not (navigationInputAllowed setupIsOpen scenarioStatus) = Nothing
  | otherwise =
      case gesture of
        NoNavigationGesture -> Nothing
        NavigationGesture press selectedSpeed ->
          case selectedSpeed of
            Just speed -> Just (NavigateOnRelease (navigationPressRequestedWaypoint press) (Just speed))
            Nothing ->
              case navigationPressShip press of
                Just target
                  | target /= shooter -> Just (LockOnRelease target)
                  | otherwise -> Nothing
                Nothing -> Just (NavigateOnRelease (navigationPressRequestedWaypoint press) Nothing)

-- | The radius every reticle is drawn at and every click is hit-tested with, in
-- canvas pixels.
--
-- One number on purpose: the hover ring, the locked ring and the hit test are
-- the same radius, so the marker tells the truth about the gesture. If it ever
-- changes, all three change together.
reticleRadiusPixels :: Double
reticleRadiusPixels = 24

-- | The battle units one canvas pixel spans at this camera and canvas size.
--
-- The canvas is drawn in world units while the pointer arrives in canvas pixels,
-- so this is the scale 'screenToBattlePoint' already crosses. It is taken from
-- the canvas width because that is the axis the pointer's x is converted with,
-- and at the shipped camera the vertical scale differs by a tenth of a percent
-- (the canvas is 760 by 428 rather than exactly 16:9).
battleUnitsPerScreenPixel :: Camera2D -> ScreenSize -> Double
battleUnitsPerScreenPixel camera size =
  screenBattleViewportWidth / max 1 (screenSizeWidth size)
 where
  (screenBattleViewportWidth, _) = screenBattleViewport camera

-- | 'reticleRadiusPixels' in battle units: the radius a reticle ring is drawn at
-- and the radius a click is hit-tested with.
screenReticleRadius :: Camera2D -> ScreenSize -> Double
screenReticleRadius camera size =
  reticleRadiusPixels * battleUnitsPerScreenPixel camera size

-- | The world extent the camera shows, in battle units. 'screenToBattlePoint'
-- and 'screenReticleRadius' both divide by the zoom through this one function.
screenBattleViewport :: Camera2D -> (Double, Double)
screenBattleViewport camera =
  ( realToFrac (viewportWidth view / zoom)
  , realToFrac (viewportHeight view / zoom)
  )
 where
  view = cameraViewport camera
  zoom = cameraZoom camera

-- | The nearest hull whose centre lies inside the reticle, whoever owns it.
--
-- This is the one hit test. The lock-candidate question — what a hover marks and
-- what a click takes — is this same test with @shooter@'s own hull taken out of
-- the list, so the marker and the gesture cannot disagree about what is under the
-- reticle.
hullAtReticle :: PointerSample -> [ShipSnapshot] -> Maybe ShipId
hullAtReticle pointer ships =
  case sortOn (distance (pointerSamplePoint pointer) . shipSnapshotPosition) candidates of
    hit : _ -> Just (shipSnapshotId hit)
    [] -> Nothing
 where
  candidates =
    [ ship
    | ship <- ships
    , distance (pointerSamplePoint pointer) (shipSnapshotPosition ship) <= pointerSampleReticleRadius pointer
    ]

-- | The ship a click this sample would lock: the nearest hull under the reticle
-- that is not @shooter@'s own, however close @shooter@'s own hull is.
--
-- The player's own hull is never a candidate, so the client never offers and
-- never sends a self-lock, however the simulation would answer one.
reticleShip :: ShipId -> PointerSample -> [ShipSnapshot] -> Maybe ShipId
reticleShip shooter pointer =
  hullAtReticle pointer . filter ((/= shooter) . shipSnapshotId)

-- | The lock candidate a pointer sample is over: the hover state one pointer
-- position produces, and the target a click at that same position would take.
lockTargetAtSample :: ShipId -> CombatSnapshot -> PointerSample -> Maybe ShipId
lockTargetAtSample shooter snapshot pointer =
  reticleShip shooter pointer (combatSnapshotShips snapshot)

-- | The ship a stationary pointer is over, against the snapshot in hand.
--
-- The hover is re-derived from the pointer's last position on every snapshot,
-- not only when the pointer moves, because a ship moves under a pointer that is
-- holding still. A hover carried over from the last pointer event would keep a
-- ring on a hull the pointer has already left — and the click that followed
-- hit-tests the press fresh, so the marker would lie about the gesture in exactly
-- the way the shared reticle radius exists to prevent.
--
-- It is the same test a click runs, so the hover and the click cannot disagree
-- by construction. 'Nothing' means no pointer is over the canvas (it left, or the
-- setup overlay opened), the hull under the reticle has moved out of it, or the
-- only hull under it is @shooter@'s own.
hoveredShipAt :: ShipId -> Maybe PointerSample -> CombatSnapshot -> Maybe ShipId
hoveredShipAt shooter pointer snapshot =
  lockTargetAtSample shooter snapshot =<< pointer

-- | A point in battle units, from a pointer position in canvas pixels.
screenToBattlePoint :: Camera2D -> ScreenPoint -> ScreenSize -> Point
screenToBattlePoint camera point size =
  Point
    { pointX = centerX - halfWidth + (screenPointX point / width) * viewportWorldWidth
    , pointY = centerY + halfHeight - (screenPointY point / height) * viewportWorldHeight
    }
 where
  center = cameraCenter camera
  (viewportWorldWidth, viewportWorldHeight) = screenBattleViewport camera
  centerX = realToFrac (vec2X center)
  centerY = realToFrac (vec2Y center)
  halfWidth = viewportWorldWidth / 2
  halfHeight = viewportWorldHeight / 2
  width = max 1 (screenSizeWidth size)
  height = max 1 (screenSizeHeight size)

-- | Matches the maximum ring drawn in the battle scene. Direction is
-- deliberately ignored: only distance from the reachable waypoint matters.
speedSelectionRadius :: Double
speedSelectionRadius = 8

distance :: Point -> Point -> Double
distance from to =
  sqrt (((pointX to - pointX from) ** 2) + ((pointY to - pointY from) ** 2))
