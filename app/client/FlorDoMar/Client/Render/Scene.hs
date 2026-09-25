{-# LANGUAGE DerivingStrategies #-}

module FlorDoMar.Client.Render.Scene
  ( GeometryRef (..)
  , Material (..)
  , RenderNode (..)
  , RenderMesh (..)
  , RenderPrimitive (..)
  , RenderScene (..)
  , StrokeStyle (..)
  , Transform (..)
  , basicMaterial
  , identityTransform
  , renderSceneMeshes
  , renderScenePrimitives
  , strokeStyle
  , transform
  , transform3D
  , transformMatrix
  , transformRotationZ
  )
where

import Data.Text (Text)
import FlorDoMar.Client.WebGL.Camera (Camera2D)
import FlorDoMar.Client.WebGL.Geometry (Color)
import FlorDoMar.Client.WebGL.Geometry qualified as Geometry
import FlorDoMar.Client.WebGL.Math
  ( Mat4
  , Scalar
  , Vec3
  , identity4
  , multiply4
  , quaternionRotation4
  , rotationZQuaternion
  , scaling4
  , translation4
  , vec3
  )
import Linear.Quaternion (Quaternion (..))
import Linear.V3 (V3 (..))

data RenderScene = RenderScene
  { renderSceneCamera :: Camera2D
  , renderSceneNodes :: [RenderNode]
  }
  deriving stock (Eq, Show)

data RenderNode
  = RenderGroup Text Transform [RenderNode]
  | RenderMeshNode RenderMesh
  | StrokePath Text Transform [Vec3] StrokeStyle
  | RingStroke Text Transform Vec3 Scalar Int StrokeStyle
  deriving stock (Eq, Show)

data RenderMesh = RenderMesh
  { renderMeshName :: Text
  , renderMeshGeometry :: GeometryRef
  , renderMeshMaterial :: Material
  , renderMeshTransform :: Transform
  }
  deriving stock (Eq, Show)

data GeometryRef
  = UnitCubeGeometry
  | -- | One broadside's firing envelope: a sector sampled in the hull's own
    -- frame, carrying the reload's fill and the whole envelope's outline in one
    -- shape. The browser replays it as triangles like every other primitive, so
    -- nothing about the wire format changes for it.
    FiringEnvelopeGeometry Geometry.SectorWedge
  deriving stock (Eq, Show)

data Material = BasicMaterial
  { materialColor :: Color
  }
  deriving stock (Eq, Show)

data StrokeStyle = StrokeStyle
  { strokeStyleWidth :: Scalar
  , strokeStyleMaterial :: Material
  }
  deriving stock (Eq, Show)

data RenderPrimitive = RenderPrimitive
  { renderPrimitiveName :: Text
  , renderPrimitiveGeometry :: Geometry.Geometry3D
  , renderPrimitiveMaterial :: Material
  , renderPrimitiveWorldMatrix :: Mat4
  }
  deriving stock (Eq, Show)

data Transform = Transform
  { transformPosition :: Vec3
  , transformRotation :: Quaternion Scalar
  , transformScale :: Vec3
  }
  deriving stock (Eq, Show)

basicMaterial :: Color -> Material
basicMaterial fill =
  BasicMaterial
    { materialColor = fill
    }

transform :: Vec3 -> Scalar -> Vec3 -> Transform
transform position rotationZ scale =
  transform3D position (rotationZQuaternion rotationZ) scale

transform3D :: Vec3 -> Quaternion Scalar -> Vec3 -> Transform
transform3D position rotation scale =
  Transform
    { transformPosition = position
    , transformRotation = rotation
    , transformScale = scale
    }

identityTransform :: Transform
identityTransform =
  transform (vec3 0 0 0) 0 (vec3 1 1 1)

transformRotationZ :: Transform -> Scalar
transformRotationZ value =
  if angle < 0 then angle + (2 * pi) else angle
 where
  angle =
    atan2
      (2 * ((rotationW * rotationZ) + (rotationX * rotationY)))
      (1 - (2 * ((rotationY * rotationY) + (rotationZ * rotationZ))))
  Quaternion rotationW (V3 rotationX rotationY rotationZ) = transformRotation value

transformMatrix :: Transform -> Mat4
transformMatrix value =
  translation4 (transformPosition value)
    `multiply4` quaternionRotation4 (transformRotation value)
    `multiply4` scaling4 (transformScale value)

strokeStyle :: Scalar -> Color -> StrokeStyle
strokeStyle width fill =
  StrokeStyle
    { strokeStyleWidth = width
    , strokeStyleMaterial = basicMaterial fill
    }

renderSceneMeshes :: RenderScene -> [RenderMesh]
renderSceneMeshes = concatMap collect . renderSceneNodes
 where
  collect node =
    case node of
      RenderGroup _ _ children -> concatMap collect children
      RenderMeshNode mesh -> [mesh]
      StrokePath {} -> []
      RingStroke {} -> []

renderScenePrimitives :: RenderScene -> [RenderPrimitive]
renderScenePrimitives scene =
  concatMap (flattenNode identity4) (renderSceneNodes scene)

flattenNode :: Mat4 -> RenderNode -> [RenderPrimitive]
flattenNode parentMatrix node =
  case node of
    RenderGroup _ localTransform children ->
      concatMap (flattenNode worldMatrix) children
     where
      worldMatrix = parentMatrix `multiply4` transformMatrix localTransform
    RenderMeshNode mesh ->
      [ RenderPrimitive
          { renderPrimitiveName = renderMeshName mesh
          , renderPrimitiveGeometry = geometryFor (renderMeshGeometry mesh)
          , renderPrimitiveMaterial = renderMeshMaterial mesh
          , renderPrimitiveWorldMatrix = parentMatrix `multiply4` transformMatrix (renderMeshTransform mesh)
          }
      ]
    StrokePath name localTransform points style ->
      [ RenderPrimitive
          { renderPrimitiveName = name
          , renderPrimitiveGeometry = Geometry.strokePathGeometry points (strokeStyleWidth style)
          , renderPrimitiveMaterial = strokeStyleMaterial style
          , renderPrimitiveWorldMatrix = parentMatrix `multiply4` transformMatrix localTransform
          }
      ]
    RingStroke name localTransform center radius segments style ->
      [ RenderPrimitive
          { renderPrimitiveName = name
          , renderPrimitiveGeometry = Geometry.ringStrokeGeometry center radius segments (strokeStyleWidth style)
          , renderPrimitiveMaterial = strokeStyleMaterial style
          , renderPrimitiveWorldMatrix = parentMatrix `multiply4` transformMatrix localTransform
          }
      ]

geometryFor :: GeometryRef -> Geometry.Geometry3D
geometryFor UnitCubeGeometry = Geometry.unitCubeGeometry
geometryFor (FiringEnvelopeGeometry wedge) = Geometry.sectorWedgeGeometry wedge
