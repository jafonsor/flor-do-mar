{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Client.BattleScene
  ( BattleScene (..)
  , ReticleState (..)
  , ShipMarker (..)
  , battleCamera
  , battleCanvasSize
  , battleRenderScene
  , battleRenderSceneFromSnapshot
  , battleSceneFromSnapshot
  , battleSceneFromSnapshotWithHover
  , battleSceneFromSnapshotWithNavigationGesture
  , battleSceneFromSnapshotWithNavigationGestureAndDebug
  , battleSceneFromSnapshotWithReticle
  , restingReticleState
  )
where

import Control.Monad (guard)
import Data.List (find)
import Data.Text (Text)
import FlorDoMar.Client.BattleInput
import FlorDoMar.Client.Render.Scene
import FlorDoMar.Client.WebGL.Camera
import FlorDoMar.Client.WebGL.Geometry
import FlorDoMar.Client.WebGL.Math
import FlorDoMar.Combat

data BattleScene = BattleScene
  { battleSceneShips :: [ShipMarker]
  , battleSceneStatus :: ScenarioStatus
  , battleScenePlanningEnabled :: Bool
  , battleSceneDebugOverlaysEnabled :: Bool
  , battleSceneHoverNavigationPlan :: Maybe NavigationPlan
  , battleSceneNavigationGesture :: NavigationGesture
  , battleSceneReticle :: ReticleState
  }
  deriving stock (Eq, Show)

-- | What the pointer is doing: the radius every reticle is drawn at, and the
-- ship the pointer is over, if any.
--
-- The radius is carried rather than recomputed here because it is a screen-space
-- constant converted at the canvas size the pointer actually arrived in, and the
-- hit test that found the hovered ship ran at this same number.
data ReticleState = ReticleState
  { reticleStateRadius :: Double
  , reticleStateHoveredShip :: Maybe ShipId
  }
  deriving stock (Eq, Show)

-- | The reticle at rest: the radius the shipped canvas gives it, hovering
-- nothing. The scene builders that take no pointer state start here.
restingReticleState :: ReticleState
restingReticleState = ReticleState (screenReticleRadius battleCamera battleCanvasSize) Nothing

-- | What the battle view draws about one ship.
--
-- The gunnery fields are carried straight off that ship's snapshot — its tuning
-- record, its lock, its permission, its reload progress and its per-side
-- target-inside verdict — because the firing envelope and the reload readout are
-- drawn from the same values the simulation validates volleys against. The
-- verdict in particular is not recomputed here: a client that derived the
-- highlight from the geometry itself could disagree with the guns.
data ShipMarker = ShipMarker
  { markerIdentity :: ShipId
  , markerName :: Text
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
  , markerBroadsideTuning :: BroadsideTuning
  , markerLockedTarget :: Maybe ShipId
  , markerFirePermission :: Bool
  , markerReloadTicksRemaining :: Int
  , markerReloadTicksTotal :: Int
  , markerPortHoldsTarget :: Bool
  , markerStarboardHoldsTarget :: Bool
  }
  deriving stock (Eq, Show)

battleSceneFromSnapshot :: CombatSnapshot -> BattleScene
battleSceneFromSnapshot =
  battleSceneFromSnapshotWithReticle restingReticleState False True Nothing NoNavigationGesture

battleSceneFromSnapshotWithHover :: Bool -> Maybe Point -> CombatSnapshot -> BattleScene
battleSceneFromSnapshotWithHover setupIsOpen hoverWaypoint =
  battleSceneFromSnapshotWithReticle restingReticleState setupIsOpen True hoverWaypoint NoNavigationGesture

battleSceneFromSnapshotWithNavigationGesture :: Bool -> Maybe Point -> NavigationGesture -> CombatSnapshot -> BattleScene
battleSceneFromSnapshotWithNavigationGesture setupIsOpen hoverWaypoint navigationGesture =
  battleSceneFromSnapshotWithReticle restingReticleState setupIsOpen True hoverWaypoint navigationGesture

battleSceneFromSnapshotWithNavigationGestureAndDebug :: Bool -> Bool -> Maybe Point -> NavigationGesture -> CombatSnapshot -> BattleScene
battleSceneFromSnapshotWithNavigationGestureAndDebug setupIsOpen debugOverlaysEnabled hoverWaypoint navigationGesture =
  battleSceneFromSnapshotWithReticle restingReticleState setupIsOpen debugOverlaysEnabled hoverWaypoint navigationGesture

-- | The whole scene: the snapshot, the navigation overlay state, the overlay
-- switches, and what the pointer is doing.
battleSceneFromSnapshotWithReticle :: ReticleState -> Bool -> Bool -> Maybe Point -> NavigationGesture -> CombatSnapshot -> BattleScene
battleSceneFromSnapshotWithReticle reticle setupIsOpen debugOverlaysEnabled hoverWaypoint navigationGesture snapshot =
  BattleScene
    { battleSceneShips = fmap shipMarker (combatSnapshotShips snapshot)
    , battleSceneStatus = combatSnapshotStatus snapshot
    , battleScenePlanningEnabled = navigationInputAllowed setupIsOpen (combatSnapshotStatus snapshot)
    , battleSceneDebugOverlaysEnabled = debugOverlaysEnabled
    , battleSceneHoverNavigationPlan =
        if navigationInputAllowed setupIsOpen (combatSnapshotStatus snapshot)
          then hoverWaypoint >>= planNavigationForSnapshot snapshot PlayerShip
          else Nothing
    , battleSceneNavigationGesture = navigationGesture
    , battleSceneReticle = reticle
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
          <> reticleNodes scene
    }

-- | The battle view's fixed camera.
--
-- At 0.6 the visible world is 266.7 by 150 units centred on the arena centre, so
-- the opening engagement — both hulls, both engagement-facing firing envelopes
-- and the contested space between them — fits at once, and the big boat still
-- renders about 46 by 17 pixels on the 760 by 428 canvas. 'screenToBattlePoint'
-- and the renderer both divide by the zoom, so pointer conversion and
-- hit-testing follow it rather than assuming 1.
battleCamera :: Camera2D
battleCamera =
  (camera2D (viewport 160 90))
    { cameraCenter = vec2 0 40
    , cameraZoom = 0.6
    }

-- | The size the battle canvas is served at, and the seed for the pointer's
-- screen space before the first pointer event arrives.
--
-- The canvas element's width and height attributes are built from it, so the
-- drawing buffer and the pointer's pixel space start out the same size.
battleCanvasSize :: ScreenSize
battleCanvasSize = ScreenSize 760 428

shipMarker :: ShipSnapshot -> ShipMarker
shipMarker ship =
  ShipMarker
    { markerIdentity = shipSnapshotId ship
    , markerName = shipSnapshotDisplayName ship
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
    , markerBroadsideTuning = shipSnapshotBroadsideTuning ship
    , markerLockedTarget = shipSnapshotLockedTarget ship
    , markerFirePermission = shipSnapshotFirePermission ship
    , markerReloadTicksRemaining = shipSnapshotReloadTicksRemaining ship
    , markerReloadTicksTotal = shipSnapshotReloadTicksTotal ship
    , markerPortHoldsTarget = shipSnapshotPortHoldsTarget ship
    , markerStarboardHoldsTarget = shipSnapshotStarboardHoldsTarget ship
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
        NavigationGesture press (Just selectedSpeed) ->
          [ RingStroke
              "drag-speed-ring:player"
              (waypointTransformAtHeight (navigationPressReachableWaypoint press) dragOverlayHeight)
              ringCenter
              (speedRingRadius (navigationPressMaximumSpeed press) selectedSpeed)
              speedRingSegments
              dragSpeedRingStyle
          ]
        _ -> []

playerMaxSpeed :: BattleScene -> Double
playerMaxSpeed scene =
  case filter markerIsPlayer (battleSceneShips scene) of
    marker : _ -> markerMaxSpeed marker
    [] -> 0

-- | The two reticles: a hover ring on the ship a click would lock, and a ring on
-- the ship already locked. Both are drawn at the one reticle radius and differ
-- only in colour, so committing to a lock is a colour change rather than a shape
-- change.
--
-- The rings use the pointer's own radius — the number the hit test that set the
-- hover ran with — so a hover ring is a promise about where the click lands. The
-- hover ring is not drawn on the ship that is already locked: a click there
-- releases the lock, so that ship's marker is the locked ring.
reticleNodes :: BattleScene -> [RenderNode]
reticleNodes scene =
  hoverReticleNodes scene <> lockedReticleNodes scene

hoverReticleNodes :: BattleScene -> [RenderNode]
hoverReticleNodes scene
  | not (battleScenePlanningEnabled scene) = []
  | otherwise =
      case hoveredMarker scene of
        Just marker -> [reticleNode "hover-reticle" hoverReticleStyle scene marker]
        Nothing -> []

lockedReticleNodes :: BattleScene -> [RenderNode]
lockedReticleNodes scene =
  case lockedTargetMarker scene of
    Just marker -> [reticleNode "locked-reticle" lockedReticleStyle scene marker]
    Nothing -> []

reticleNode :: Text -> StrokeStyle -> BattleScene -> ShipMarker -> RenderNode
reticleNode prefix style scene marker =
  RingStroke
    (meshName prefix marker)
    (waypointTransformAtHeight (markerPosition marker) reticleHeight)
    ringCenter
    (realToFrac (reticleStateRadius (battleSceneReticle scene)))
    speedRingSegments
    style

-- | The ship the pointer is over, when it is one a click would lock. The
-- player's own hull is never drawn as a lock candidate, and the ship already
-- locked wears the locked ring instead.
hoveredMarker :: BattleScene -> Maybe ShipMarker
hoveredMarker scene = do
  hovered <- reticleStateHoveredShip (battleSceneReticle scene)
  marker <- markerForShip scene hovered
  guard (not (markerIsPlayer marker))
  guard (Just hovered /= lockedTargetId scene)
  pure marker

-- | The ship the player has locked, when the scene carries it.
lockedTargetMarker :: BattleScene -> Maybe ShipMarker
lockedTargetMarker scene = do
  target <- lockedTargetId scene
  marker <- markerForShip scene target
  guard (not (markerIsPlayer marker))
  pure marker

lockedTargetId :: BattleScene -> Maybe ShipId
lockedTargetId scene = do
  player <- find markerIsPlayer (battleSceneShips scene)
  markerLockedTarget player

markerForShip :: BattleScene -> ShipId -> Maybe ShipMarker
markerForShip scene identity =
  find ((== identity) . markerIdentity) (battleSceneShips scene)

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

-- | The reticles sit above the hull rather than inside it. A ship's own z extent
-- reaches 0.125 — a unit cube scaled to 0.25 in z — so an overlay at the
-- existing 0.1 to 0.2 heights would be buried in the hull it marks.
reticleHeight :: Scalar
reticleHeight = 0.3

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

-- | The hover reticle: pale and cool, the marker for a click that would take a
-- lock.
hoverReticleStyle :: StrokeStyle
hoverReticleStyle = strokeStyle reticleStrokeWidth (color 0.82 0.9 1 0.85)

-- | The locked reticle: the same ring in a hot colour, so the lock reads as a
-- change of state rather than a change of shape.
lockedReticleStyle :: StrokeStyle
lockedReticleStyle = strokeStyle reticleStrokeWidth (color 1 0.72 0.2 1)

reticleStrokeWidth :: Scalar
reticleStrokeWidth = 0.5

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
