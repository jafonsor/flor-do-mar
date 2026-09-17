{-# LANGUAGE DerivingStrategies #-}

module FlorDoMar.Client.WebGL.Geometry
  ( Color (..)
  , Geometry3D (..)
  , Rect (..)
  , Vertex2D (..)
  , Geometry2D (..)
  , color
  , rect
  , rectangleGeometry
  , unitCubeGeometry
  , vertex2DFloats
  , vec3Floats
  , geometry2DPositionsAndColors
  , geometry3DPositions
  )
where

import Data.Word (Word16)
import FlorDoMar.Client.WebGL.Math
  ( Scalar
  , Vec2
  , Vec3
  , vec2
  , vec2X
  , vec2Y
  , vec3
  , vec3X
  , vec3Y
  , vec3Z
  )

data Color = Color
  { colorRed :: Scalar
  , colorGreen :: Scalar
  , colorBlue :: Scalar
  , colorAlpha :: Scalar
  }
  deriving stock (Eq, Show)

data Rect = Rect
  { rectOrigin :: Vec2
  , rectSize :: Vec2
  }
  deriving stock (Eq, Show)

data Vertex2D = Vertex2D
  { vertexPosition :: Vec2
  , vertexColor :: Color
  }
  deriving stock (Eq, Show)

data Geometry2D = Geometry2D
  { geometryVertices :: [Vertex2D]
  , geometryIndices :: [Word16]
  }
  deriving stock (Eq, Show)

data Geometry3D = Geometry3D
  { geometry3DVertices :: [Vec3]
  , geometry3DIndices :: [Word16]
  }
  deriving stock (Eq, Show)

color :: Scalar -> Scalar -> Scalar -> Scalar -> Color
color red green blue alpha =
  Color
    { colorRed = red
    , colorGreen = green
    , colorBlue = blue
    , colorAlpha = alpha
    }

rect :: Vec2 -> Vec2 -> Rect
rect origin size =
  Rect
    { rectOrigin = origin
    , rectSize = size
    }

rectangleGeometry :: Rect -> Color -> Geometry2D
rectangleGeometry rectangle fill =
  Geometry2D
    { geometryVertices =
        [ vertex x0 y0
        , vertex x1 y0
        , vertex x1 y1
        , vertex x0 y1
        ]
    , geometryIndices = [0, 1, 2, 0, 2, 3]
    }
 where
  origin = rectOrigin rectangle
  size = rectSize rectangle
  x0 = vec2X origin
  y0 = vec2Y origin
  x1 = x0 + vec2X size
  y1 = y0 + vec2Y size
  vertex x y =
    Vertex2D
      { vertexPosition = vec2 x y
      , vertexColor = fill
      }

unitCubeGeometry :: Geometry3D
unitCubeGeometry =
  Geometry3D
    { geometry3DVertices =
        [ vec3 (-0.5) (-0.5) (-0.5)
        , vec3 0.5 (-0.5) (-0.5)
        , vec3 0.5 0.5 (-0.5)
        , vec3 (-0.5) 0.5 (-0.5)
        , vec3 (-0.5) (-0.5) 0.5
        , vec3 0.5 (-0.5) 0.5
        , vec3 0.5 0.5 0.5
        , vec3 (-0.5) 0.5 0.5
        ]
    , geometry3DIndices =
        [ 0, 1, 2, 0, 2, 3
        , 4, 6, 5, 4, 7, 6
        , 0, 4, 5, 0, 5, 1
        , 1, 5, 6, 1, 6, 2
        , 2, 6, 7, 2, 7, 3
        , 3, 7, 4, 3, 4, 0
        ]
    }

vertex2DFloats :: Vertex2D -> [Scalar]
vertex2DFloats vertex =
  [ vec2X (vertexPosition vertex)
  , vec2Y (vertexPosition vertex)
  , colorRed vertexColorValue
  , colorGreen vertexColorValue
  , colorBlue vertexColorValue
  , colorAlpha vertexColorValue
  ]
 where
  vertexColorValue = vertexColor vertex

vec3Floats :: Vec3 -> [Scalar]
vec3Floats value =
  [ vec3X value
  , vec3Y value
  , vec3Z value
  ]

geometry2DPositionsAndColors :: Geometry2D -> [Scalar]
geometry2DPositionsAndColors =
  foldMap vertex2DFloats . geometryVertices

geometry3DPositions :: Geometry3D -> [Scalar]
geometry3DPositions =
  foldMap vec3Floats . geometry3DVertices
