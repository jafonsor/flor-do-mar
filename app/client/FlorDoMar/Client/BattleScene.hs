{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Client.BattleScene
  ( BattleScene (..)
  , ShipMarker (..)
  , battleRenderScene
  , battleRenderSceneFromSnapshot
  , battleSceneFromSnapshot
  )
where

import Data.Text (Text)
import FlorDoMar.Client.Render.Scene
import FlorDoMar.Client.WebGL.Camera
import FlorDoMar.Client.WebGL.Geometry
import FlorDoMar.Client.WebGL.Math
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

battleRenderSceneFromSnapshot :: CombatSnapshot -> RenderScene
battleRenderSceneFromSnapshot =
  battleRenderScene . battleSceneFromSnapshot

battleRenderScene :: BattleScene -> RenderScene
battleRenderScene scene =
  RenderScene
    { renderSceneCamera =
        (camera2D (viewport 160 90))
          { cameraCenter = vec2 0 40
          }
    , renderSceneMeshes = concatMap shipMeshes (battleSceneShips scene)
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

shipMeshes :: ShipMarker -> [RenderMesh]
shipMeshes marker =
  [ shipBodyMesh marker
  , headingMarkerMesh marker
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
          shipScale
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

headingRadians :: Heading -> Scalar
headingRadians (Heading degrees) =
  realToFrac (degrees * pi / 180)

damagedShipColor :: ShipMarker -> Color
damagedShipColor marker =
  tintColor darkGray (baseShipColor marker) (hullRatio (markerHull marker))

baseShipColor :: ShipMarker -> Color
baseShipColor marker =
  if markerIsPlayer marker
    then playerColor
    else enemyColor

hullRatio :: Int -> Scalar
hullRatio hull =
  clamp 0 1 (fromIntegral hull / 100)

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

shipScale :: Vec3
shipScale = vec3 10 4 0.25

headingMarkerScale :: Vec3
headingMarkerScale = vec3 2 2 0.25

headingMarkerDistance :: Scalar
headingMarkerDistance = 8

playerColor :: Color
playerColor = color 0.2 0.75 0.95 1

enemyColor :: Color
enemyColor = color 0.95 0.34 0.24 1

headingColor :: Color
headingColor = color 0.96 0.9 0.58 1

darkGray :: Color
darkGray = color 0.18 0.18 0.18 1
