{-# LANGUAGE DerivingStrategies #-}

module FlorDoMar.Client.BattleInput
  ( NavigationHoverIntent (..)
  , NavigationGesture (..)
  , NavigationPointerIntent (..)
  , RawPointerMovement (..)
  , RawPointerEvent (..)
  , ScreenPoint (..)
  , ScreenSize (..)
  , applyNavigationHoverIntent
  , beginNavigationGesture
  , hoverIntentFromRawPointer
  , navigationInputAllowed
  , navigationGestureSelectedSpeed
  , navigationPointerIntentFromRawPointer
  , speedSelectionRadius
  , updateNavigationGesture
  )
where

import FlorDoMar.Client.WebGL.Camera
import FlorDoMar.Client.WebGL.Math
import FlorDoMar.Combat (Point (..), ScenarioStatus (..))

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
  = NavigationPointerMoved Point
  | NavigationPointerPrimaryDown Point
  | NavigationPointerPrimaryUp
  | NavigationPointerLeftBattleView
  deriving stock (Eq, Show)

-- | State held while a primary mouse gesture owns a navigation order. A
-- missing selected speed distinguishes a plain click from a drag-to-speed.
data NavigationGesture
  = NoNavigationGesture
  | NavigationGesture Point Double (Maybe Double)
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
    RawPointerMoved point size -> NavigationPointerMoved (screenToBattlePoint camera point size)
    RawPrimaryPointerDown point size -> NavigationPointerPrimaryDown (screenToBattlePoint camera point size)
    RawPrimaryPointerUp -> NavigationPointerPrimaryUp
    RawPointerLeftBattleView -> NavigationPointerLeftBattleView

beginNavigationGesture :: Point -> Double -> NavigationGesture
beginNavigationGesture waypoint maximumSpeed =
  NavigationGesture waypoint (max 0 maximumSpeed) Nothing

updateNavigationGesture :: Point -> NavigationGesture -> NavigationGesture
updateNavigationGesture pointer gesture =
  case gesture of
    NoNavigationGesture -> NoNavigationGesture
    NavigationGesture waypoint maximumSpeed _ ->
      NavigationGesture
        waypoint
        maximumSpeed
        (Just (maximumSpeed * min 1 (distance waypoint pointer / speedSelectionRadius)))

navigationGestureSelectedSpeed :: NavigationGesture -> Maybe Double
navigationGestureSelectedSpeed gesture =
  case gesture of
    NoNavigationGesture -> Nothing
    NavigationGesture _ _ selectedSpeed -> selectedSpeed

-- | Matches the maximum ring drawn in the battle scene. Direction is
-- deliberately ignored: only distance from the reachable waypoint matters.
speedSelectionRadius :: Double
speedSelectionRadius = 8

distance :: Point -> Point -> Double
distance from to =
  sqrt (((pointX to - pointX from) ** 2) + ((pointY to - pointY from) ** 2))

screenToBattlePoint :: Camera2D -> ScreenPoint -> ScreenSize -> Point
screenToBattlePoint camera point size =
  Point
    { pointX = centerX - halfWidth + (screenPointX point / width) * worldViewportWidth
    , pointY = centerY + halfHeight - (screenPointY point / height) * worldViewportHeight
    }
 where
  center = cameraCenter camera
  view = cameraViewport camera
  zoom = cameraZoom camera
  centerX = realToFrac (vec2X center)
  centerY = realToFrac (vec2Y center)
  worldViewportWidth = realToFrac (viewportWidth view / zoom)
  worldViewportHeight = realToFrac (viewportHeight view / zoom)
  halfWidth = worldViewportWidth / 2
  halfHeight = worldViewportHeight / 2
  width = max 1 (screenSizeWidth size)
  height = max 1 (screenSizeHeight size)
