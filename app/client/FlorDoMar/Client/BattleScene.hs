{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Client.BattleScene
  ( BattleScene (..)
  , ShipMarker (..)
  , battleCamera
  , battleRenderScene
  , battleRenderSceneFromSnapshot
  , battleSceneFromSnapshot
  , battleSceneFromSnapshotWithHover
  , battleSceneFromSnapshotWithNavigationGesture
  , battleSceneFromSnapshotWithNavigationGestureAndDebug
  )
where

import Data.Text (Text)
import FlorDoMar.Client.BattleInput
import FlorDoMar.Client.Render.Scene
import FlorDoMar.Client.WebGL.Camera
import FlorDoMar.Client.WebGL.Geometry
import FlorDoMar.Client.WebGL.Math
import FlorDoMar.Combat

data BattleScene = BattleScene
  { battleSceneShips :: [ShipMarker]
  , battleSceneRange :: Double
  , battleSceneStatus :: ScenarioStatus
  , battleScenePlanningEnabled :: Bool
  , battleSceneDebugOverlaysEnabled :: Bool
  , battleSceneHoverNavigationPlan :: Maybe NavigationPlan
  , battleSceneNavigationGesture :: NavigationGesture
  }
  deriving stock (Eq, Show)

data ShipMarker = ShipMarker
  { markerName :: Text
  , markerPosition :: Point
  , markerHeading :: Heading
  , markerTargetHeading :: Heading
  , markerMaxHull :: Int
  , markerHull :: Int
  , markerRenderedLength :: Double
  , markerRenderedWidth :: Double
  , markerIsPlayer :: Bool
  , markerNavigationOrder :: Maybe NavigationOrder
  , markerActiveNavigationPlan :: Maybe NavigationPlan
  , markerMaxSpeed :: Double
  }
  deriving stock (Eq, Show)

battleSceneFromSnapshot :: CombatSnapshot -> BattleScene
battleSceneFromSnapshot = battleSceneFromSnapshotWithNavigationGestureAndDebug False True Nothing NoNavigationGesture

battleSceneFromSnapshotWithHover :: Bool -> Maybe Point -> CombatSnapshot -> BattleScene
battleSceneFromSnapshotWithHover setupIsOpen hoverWaypoint =
  battleSceneFromSnapshotWithNavigationGestureAndDebug setupIsOpen True hoverWaypoint NoNavigationGesture

battleSceneFromSnapshotWithNavigationGesture :: Bool -> Maybe Point -> NavigationGesture -> CombatSnapshot -> BattleScene
battleSceneFromSnapshotWithNavigationGesture setupIsOpen hoverWaypoint navigationGesture snapshot =
  battleSceneFromSnapshotWithNavigationGestureAndDebug setupIsOpen True hoverWaypoint navigationGesture snapshot

battleSceneFromSnapshotWithNavigationGestureAndDebug :: Bool -> Bool -> Maybe Point -> NavigationGesture -> CombatSnapshot -> BattleScene
battleSceneFromSnapshotWithNavigationGestureAndDebug setupIsOpen debugOverlaysEnabled hoverWaypoint navigationGesture snapshot =
  BattleScene
    { battleSceneShips = fmap shipMarker (combatSnapshotShips snapshot)
    , battleSceneRange = engagementRange (combatSnapshotEngagement snapshot)
    , battleSceneStatus = combatSnapshotStatus snapshot
    , battleScenePlanningEnabled = navigationInputAllowed setupIsOpen (combatSnapshotStatus snapshot)
    , battleSceneDebugOverlaysEnabled = debugOverlaysEnabled
    , battleSceneHoverNavigationPlan =
        if navigationInputAllowed setupIsOpen (combatSnapshotStatus snapshot)
          then hoverWaypoint >>= planNavigationForSnapshot snapshot PlayerShip
          else Nothing
    , battleSceneNavigationGesture = navigationGesture
    }

battleRenderSceneFromSnapshot :: CombatSnapshot -> RenderScene
battleRenderSceneFromSnapshot =
  battleRenderScene . battleSceneFromSnapshot

battleRenderScene :: BattleScene -> RenderScene
battleRenderScene scene =
  RenderScene
    { renderSceneCamera = battleCamera
    , renderSceneNodes =
        fmap RenderMeshNode (concatMap shipMeshes (battleSceneShips scene))
          <> activeNavigationNodes scene
          <> hoverNavigationNodes scene
          <> navigationGestureNodes scene
    }

battleCamera :: Camera2D
battleCamera =
  (camera2D (viewport 160 90))
    { cameraCenter = vec2 0 40
    }

shipMarker :: ShipSnapshot -> ShipMarker
shipMarker ship =
  ShipMarker
    { markerName = shipSnapshotDisplayName ship
    , markerPosition = shipSnapshotPosition ship
    , markerHeading = shipSnapshotHeading ship
    , markerTargetHeading = shipSnapshotTargetHeading ship
    , markerMaxHull = shipSnapshotMaxHull ship
    , markerHull = shipSnapshotHull ship
    , markerRenderedLength = shipSnapshotRenderedLength ship
    , markerRenderedWidth = shipSnapshotRenderedWidth ship
    , markerIsPlayer = shipSnapshotId ship == PlayerShip
    , markerNavigationOrder = shipSnapshotNavigationOrder ship
    , markerActiveNavigationPlan = shipSnapshotActiveNavigationPlan ship
    , markerMaxSpeed = shipSnapshotMaxSpeed ship
    }

activeNavigationNodes :: BattleScene -> [RenderNode]
activeNavigationNodes scene =
  concatMap activeNavigationNodesForMarker (filter (shouldRenderActiveNavigation scene) (battleSceneShips scene))

shouldRenderActiveNavigation :: BattleScene -> ShipMarker -> Bool
shouldRenderActiveNavigation scene marker =
  battleScenePlanningEnabled scene
    && (markerIsPlayer marker || battleSceneDebugOverlaysEnabled scene)

activeNavigationNodesForMarker :: ShipMarker -> [RenderNode]
activeNavigationNodesForMarker marker =
  case (markerNavigationOrder marker, markerActiveNavigationPlan marker) of
    (Just order, Just plan) ->
      [ StrokePath
          (navigationNodeName "trajectory" marker)
          overlayTransform
          (fmap (pointPosition . trajectorySamplePosition) (navigationPlanSamples plan))
          activeTrajectoryStyle
      , RingStroke
          (navigationNodeName "speed-ring:max" marker)
          (waypointTransform (navigationReachableWaypoint order))
          ringCenter
          speedRingMaximumRadius
          speedRingSegments
          speedRingMaximumStyle
      , RingStroke
          (navigationNodeName "speed-ring:pending" marker)
          (waypointTransform (navigationReachableWaypoint order))
          ringCenter
          (speedRingRadius (markerMaxSpeed marker) (navigationPostWaypointSpeed order))
          speedRingSegments
          speedRingPendingStyle
      ]
    _ -> []

hoverNavigationNodes :: BattleScene -> [RenderNode]
hoverNavigationNodes scene =
  if not (battleScenePlanningEnabled scene)
    then []
    else
      case battleSceneHoverNavigationPlan scene of
        Just plan ->
          [ StrokePath
              "hover-trajectory:player"
              (transform (vec3 0 0 0.15) 0 (vec3 1 1 1))
              (fmap (pointPosition . trajectorySamplePosition) (navigationPlanSamples plan))
              hoverTrajectoryStyle
          , RingStroke
              "hover-speed-ring:max:player"
              (waypointTransformAtHeight (navigationPlanReachableWaypoint plan) hoverOverlayHeight)
              ringCenter
              speedRingMaximumRadius
              speedRingSegments
              hoverMaximumSpeedRingStyle
          , RingStroke
              "hover-speed-ring:arrival:player"
              (waypointTransformAtHeight (navigationPlanReachableWaypoint plan) hoverOverlayHeight)
              ringCenter
              (speedRingRadius (playerMaxSpeed scene) (navigationPlanArrivalSpeed plan))
              speedRingSegments
              hoverArrivalSpeedRingStyle
          ]
        Nothing -> []

navigationGestureNodes :: BattleScene -> [RenderNode]
navigationGestureNodes scene =
  if not (battleScenePlanningEnabled scene)
    then []
    else
      case battleSceneNavigationGesture scene of
        NavigationGesture waypoint maximumSpeed (Just selectedSpeed) ->
          [ RingStroke
              "drag-speed-ring:player"
              (waypointTransformAtHeight waypoint dragOverlayHeight)
              ringCenter
              (speedRingRadius maximumSpeed selectedSpeed)
              speedRingSegments
              dragSpeedRingStyle
          ]
        _ -> []

playerMaxSpeed :: BattleScene -> Double
playerMaxSpeed scene =
  case filter markerIsPlayer (battleSceneShips scene) of
    marker : _ -> markerMaxSpeed marker
    [] -> 0

navigationNodeName :: Text -> ShipMarker -> Text
navigationNodeName prefix marker =
  prefix <> ":" <> if markerIsPlayer marker then "player" else "enemy"

overlayTransform :: Transform
overlayTransform =
  transform (vec3 0 0 overlayHeight) 0 (vec3 1 1 1)

waypointTransform :: Point -> Transform
waypointTransform = (`waypointTransformAtHeight` overlayHeight)

waypointTransformAtHeight :: Point -> Scalar -> Transform
waypointTransformAtHeight waypoint height =
  transform
    (vec3 (realToFrac (pointX waypoint)) (realToFrac (pointY waypoint)) height)
    0
    (vec3 1 1 1)

speedRingRadius :: Double -> Double -> Scalar
speedRingRadius maximumSpeed pendingSpeed
  | maximumSpeed <= 0 = 0
  | otherwise = speedRingMaximumRadius * realToFrac speedRatio
 where
  speedRatio = max 0 (min 1 (pendingSpeed / maximumSpeed))

ringCenter :: Vec3
ringCenter = vec3 0 0 0

overlayHeight :: Scalar
overlayHeight = 0.1

hoverOverlayHeight :: Scalar
hoverOverlayHeight = 0.15

dragOverlayHeight :: Scalar
dragOverlayHeight = 0.2

speedRingMaximumRadius :: Scalar
speedRingMaximumRadius = 8

speedRingSegments :: Int
speedRingSegments = 48

activeTrajectoryStyle :: StrokeStyle
activeTrajectoryStyle = strokeStyle 0.7 (color 0.3 0.9 1 1)

speedRingMaximumStyle :: StrokeStyle
speedRingMaximumStyle = strokeStyle 0.45 (color 0.95 0.86 0.4 0.85)

speedRingPendingStyle :: StrokeStyle
speedRingPendingStyle = strokeStyle 0.8 (color 0.3 0.9 1 1)

hoverTrajectoryStyle :: StrokeStyle
hoverTrajectoryStyle = strokeStyle 0.7 (color 0.95 0.58 0.24 0.95)

hoverMaximumSpeedRingStyle :: StrokeStyle
hoverMaximumSpeedRingStyle = strokeStyle 0.45 (color 0.95 0.72 0.3 0.8)

hoverArrivalSpeedRingStyle :: StrokeStyle
hoverArrivalSpeedRingStyle = strokeStyle 0.8 (color 0.95 0.58 0.24 0.95)

dragSpeedRingStyle :: StrokeStyle
dragSpeedRingStyle = strokeStyle 0.9 (color 0.35 1 0.56 1)

shipMeshes :: ShipMarker -> [RenderMesh]
shipMeshes marker =
  [ shipBodyMesh marker
  , headingMarkerMesh marker
  , targetHeadingMarkerMesh marker
  ]

shipBodyMesh :: ShipMarker -> RenderMesh
shipBodyMesh marker =
  RenderMesh
    { renderMeshName = meshName "ship" marker
    , renderMeshGeometry = UnitCubeGeometry
    , renderMeshMaterial = basicMaterial (damagedShipColor marker)
    , renderMeshTransform =
        transform
          (pointPosition (markerPosition marker))
          (headingRadians (markerHeading marker))
          (shipScale marker)
    }

headingMarkerMesh :: ShipMarker -> RenderMesh
headingMarkerMesh marker =
  RenderMesh
    { renderMeshName = meshName "heading" marker
    , renderMeshGeometry = UnitCubeGeometry
    , renderMeshMaterial = basicMaterial headingColor
    , renderMeshTransform =
        transform
          (headingMarkerPosition marker)
          (headingRadians (markerHeading marker))
          headingMarkerScale
    }

targetHeadingMarkerMesh :: ShipMarker -> RenderMesh
targetHeadingMarkerMesh marker =
  RenderMesh
    { renderMeshName = meshName "target-heading" marker
    , renderMeshGeometry = UnitCubeGeometry
    , renderMeshMaterial = basicMaterial targetHeadingColor
    , renderMeshTransform =
        transform
          (targetHeadingMarkerPosition marker)
          (headingRadians (markerTargetHeading marker))
          targetHeadingMarkerScale
    }

meshName :: Text -> ShipMarker -> Text
meshName prefix marker =
  prefix <> ":" <> if markerIsPlayer marker then "player" else "enemy"

pointPosition :: Point -> Vec3
pointPosition point =
  vec3
    (realToFrac (pointX point))
    (realToFrac (pointY point))
    0

headingMarkerPosition :: ShipMarker -> Vec3
headingMarkerPosition marker =
  let
    position = markerPosition marker
    radians = headingRadians (markerHeading marker)
   in
    vec3
      (realToFrac (pointX position) + headingMarkerDistance * cos radians)
      (realToFrac (pointY position) + headingMarkerDistance * sin radians)
      0

targetHeadingMarkerPosition :: ShipMarker -> Vec3
targetHeadingMarkerPosition marker =
  let
    position = markerPosition marker
    radians = headingRadians (markerTargetHeading marker)
   in
    vec3
      (realToFrac (pointX position) + targetHeadingMarkerDistance * cos radians)
      (realToFrac (pointY position) + targetHeadingMarkerDistance * sin radians)
      0

headingRadians :: Heading -> Scalar
headingRadians (Heading degrees) =
  realToFrac (degrees * pi / 180)

damagedShipColor :: ShipMarker -> Color
damagedShipColor marker =
  tintColor darkGray (baseShipColor marker) (hullRatio (markerMaxHull marker) (markerHull marker))

baseShipColor :: ShipMarker -> Color
baseShipColor marker =
  if markerIsPlayer marker
    then playerColor
    else enemyColor

hullRatio :: Int -> Int -> Scalar
hullRatio maxHull hull =
  clamp 0 1 (fromIntegral hull / fromIntegral maxHull)

tintColor :: Color -> Color -> Scalar -> Color
tintColor from to amount =
  color
    (lerp (colorRed from) (colorRed to) amount)
    (lerp (colorGreen from) (colorGreen to) amount)
    (lerp (colorBlue from) (colorBlue to) amount)
    (lerp (colorAlpha from) (colorAlpha to) amount)

lerp :: Scalar -> Scalar -> Scalar -> Scalar
lerp from to amount =
  from + ((to - from) * amount)

clamp :: Scalar -> Scalar -> Scalar -> Scalar
clamp lower upper value =
  max lower (min upper value)

shipScale :: ShipMarker -> Vec3
shipScale marker =
  vec3
    (realToFrac (markerRenderedLength marker))
    (realToFrac (markerRenderedWidth marker))
    0.25

headingMarkerScale :: Vec3
headingMarkerScale = vec3 2 2 0.25

targetHeadingMarkerScale :: Vec3
targetHeadingMarkerScale = vec3 1 1 0.25

headingMarkerDistance :: Scalar
headingMarkerDistance = 8

targetHeadingMarkerDistance :: Scalar
targetHeadingMarkerDistance = 11

playerColor :: Color
playerColor = color 0.2 0.75 0.95 1

enemyColor :: Color
enemyColor = color 0.95 0.34 0.24 1

headingColor :: Color
headingColor = color 0.96 0.9 0.58 1

targetHeadingColor :: Color
targetHeadingColor = color 0.56 0.93 0.7 1

darkGray :: Color
darkGray = color 0.18 0.18 0.18 1
