{-# LANGUAGE DerivingStrategies #-}

module FlorDoMar.Client.WebGL.Math
  ( Scalar
  , Vec2
  , Vec3
  , Vec4
  , Mat4
  , vec2
  , vec2X
  , vec2Y
  , vec3
  , vec4
  , add2
  , scale2
  , identity4
  , mat4FromColumns
  , orthographic
  , mat4ToColumnMajorList
  )
where

import Linear.Matrix (M44)
import Linear.V2 (V2 (..))
import Linear.V3 (V3 (..))
import Linear.V4 (V4 (..))

type Scalar = Float

newtype Vec2 = Vec2 (V2 Scalar)
  deriving stock (Eq, Show)

newtype Vec3 = Vec3 (V3 Scalar)
  deriving stock (Eq, Show)

newtype Vec4 = Vec4 (V4 Scalar)
  deriving stock (Eq, Show)

newtype Mat4 = Mat4 (M44 Scalar)
  deriving stock (Eq, Show)

vec2 :: Scalar -> Scalar -> Vec2
vec2 x y = Vec2 (V2 x y)

vec2X :: Vec2 -> Scalar
vec2X (Vec2 (V2 x _)) = x

vec2Y :: Vec2 -> Scalar
vec2Y (Vec2 (V2 _ y)) = y

vec3 :: Scalar -> Scalar -> Scalar -> Vec3
vec3 x y z = Vec3 (V3 x y z)

vec4 :: Scalar -> Scalar -> Scalar -> Scalar -> Vec4
vec4 x y z w = Vec4 (V4 x y z w)

add2 :: Vec2 -> Vec2 -> Vec2
add2 (Vec2 left) (Vec2 right) = Vec2 (left + right)

scale2 :: Scalar -> Vec2 -> Vec2
scale2 scalar (Vec2 value) = Vec2 (fmap (* scalar) value)

identity4 :: Mat4
identity4 =
  mat4FromColumns
    (vec4 1 0 0 0)
    (vec4 0 1 0 0)
    (vec4 0 0 1 0)
    (vec4 0 0 0 1)

mat4FromColumns :: Vec4 -> Vec4 -> Vec4 -> Vec4 -> Mat4
mat4FromColumns (Vec4 column0) (Vec4 column1) (Vec4 column2) (Vec4 column3) =
  Mat4 (V4 column0 column1 column2 column3)

orthographic :: Scalar -> Scalar -> Scalar -> Scalar -> Scalar -> Scalar -> Mat4
orthographic left right bottom top near far =
  mat4FromColumns
    (vec4 (2 / width) 0 0 0)
    (vec4 0 (2 / height) 0 0)
    (vec4 0 0 (-2 / depth) 0)
    (vec4 (-(right + left) / width) (-(top + bottom) / height) (-(far + near) / depth) 1)
 where
  width = right - left
  height = top - bottom
  depth = far - near

mat4ToColumnMajorList :: Mat4 -> [Scalar]
mat4ToColumnMajorList (Mat4 (V4 column0 column1 column2 column3)) =
  foldMap v4ToList [column0, column1, column2, column3]

v4ToList :: V4 Scalar -> [Scalar]
v4ToList (V4 x y z w) = [x, y, z, w]
