{-# LANGUAGE DerivingStrategies #-}

module FlorDoMar.Client.Render.Scene
  ( GeometryRef (..)
  , Material (..)
  , RenderMesh (..)
  , RenderScene (..)
  , Transform (..)
  , basicMaterial
  , transform
  , transformMatrix
  )
where

import Data.Text (Text)
import FlorDoMar.Client.WebGL.Camera (Camera2D)
import FlorDoMar.Client.WebGL.Geometry (Color)
import FlorDoMar.Client.WebGL.Math
  ( Mat4
  , Scalar
  , Vec3
  , multiply4
  , rotationZ4
  , scaling4
  , translation4
  )

data RenderScene = RenderScene
  { renderSceneCamera :: Camera2D
  , renderSceneMeshes :: [RenderMesh]
  }
  deriving stock (Eq, Show)

data RenderMesh = RenderMesh
  { renderMeshName :: Text
  , renderMeshGeometry :: GeometryRef
  , renderMeshMaterial :: Material
  , renderMeshTransform :: Transform
  }
  deriving stock (Eq, Show)

data GeometryRef = UnitCubeGeometry
  deriving stock (Eq, Show)

data Material = BasicMaterial
  { materialColor :: Color
  }
  deriving stock (Eq, Show)

data Transform = Transform
  { transformPosition :: Vec3
  , transformRotationZ :: Scalar
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
  Transform
    { transformPosition = position
    , transformRotationZ = rotationZ
    , transformScale = scale
    }

transformMatrix :: Transform -> Mat4
transformMatrix value =
  translation4 (transformPosition value)
    `multiply4` rotationZ4 (transformRotationZ value)
    `multiply4` scaling4 (transformScale value)
