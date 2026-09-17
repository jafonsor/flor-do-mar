{-# LANGUAGE DerivingStrategies #-}

module FlorDoMar.Client.WebGL.Geometry
  ( Color (..)
  , Rect (..)
  , Vertex2D (..)
  , Geometry2D (..)
  , color
  , rect
  , rectangleGeometry
  , vertex2DFloats
  , geometry2DPositionsAndColors
  )
where

import Data.Word (Word16)
import FlorDoMar.Client.WebGL.Math
  ( Scalar
  , Vec2
  , vec2
  , vec2X
  , vec2Y
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

geometry2DPositionsAndColors :: Geometry2D -> [Scalar]
geometry2DPositionsAndColors =
  foldMap vertex2DFloats . geometryVertices
