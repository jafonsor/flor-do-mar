{-# LANGUAGE DerivingStrategies #-}

module FlorDoMar.Client.WebGL.Camera
  ( Viewport (..)
  , Camera2D (..)
  , viewport
  , camera2D
  , camera2DMatrix
  )
where

import FlorDoMar.Client.WebGL.Math
  ( Mat4
  , Scalar
  , Vec2
  , orthographic
  , vec2
  , vec2X
  , vec2Y
  )

data Viewport = Viewport
  { viewportWidth :: Scalar
  , viewportHeight :: Scalar
  }
  deriving stock (Eq, Show)

data Camera2D = Camera2D
  { cameraCenter :: Vec2
  , cameraViewport :: Viewport
  , cameraZoom :: Scalar
  }
  deriving stock (Eq, Show)

viewport :: Scalar -> Scalar -> Viewport
viewport width height =
  Viewport
    { viewportWidth = width
    , viewportHeight = height
    }

camera2D :: Viewport -> Camera2D
camera2D view =
  Camera2D
    { cameraCenter = vec2 0 0
    , cameraViewport = view
    , cameraZoom = 1
    }

camera2DMatrix :: Camera2D -> Mat4
camera2DMatrix camera =
  orthographic
    (centerX - halfWidth)
    (centerX + halfWidth)
    (centerY - halfHeight)
    (centerY + halfHeight)
    (-1)
    1
 where
  center = cameraCenter camera
  view = cameraViewport camera
  zoom = cameraZoom camera
  halfWidth = viewportWidth view / (2 * zoom)
  halfHeight = viewportHeight view / (2 * zoom)
  centerX = vec2X center
  centerY = vec2Y center
