{-# LANGUAGE DerivingStrategies #-}

module FlorDoMar.Client.WebGL.Math
  ( Scalar
  , Vec2
  , Vec3
  , Vec4
  , Quaternion (..)
  , Mat4
  , vec2
  , vec2X
  , vec2Y
  , vec3
  , vec3X
  , vec3Y
  , vec3Z
  , vec4
  , add2
  , scale2
  , identity4
  , mat4FromColumns
  , multiply4
  , orthographic
  , quaternionRotation4
  , rotationZQuaternion
  , rotationZ4
  , scaling4
  , translation4
  , transformPoint3
  , mat4ToColumnMajorList
  )
where

import Linear.Matrix (M44)
import Linear.Quaternion (Quaternion (..), axisAngle)
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

vec3X :: Vec3 -> Scalar
vec3X (Vec3 (V3 x _ _)) = x

vec3Y :: Vec3 -> Scalar
vec3Y (Vec3 (V3 _ y _)) = y

vec3Z :: Vec3 -> Scalar
vec3Z (Vec3 (V3 _ _ z)) = z

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

multiply4 :: Mat4 -> Mat4 -> Mat4
multiply4 (Mat4 left) (Mat4 (V4 right0 right1 right2 right3)) =
  Mat4
    ( V4
        (multiplyColumn left right0)
        (multiplyColumn left right1)
        (multiplyColumn left right2)
        (multiplyColumn left right3)
    )

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

translation4 :: Vec3 -> Mat4
translation4 position =
  mat4FromColumns
    (vec4 1 0 0 0)
    (vec4 0 1 0 0)
    (vec4 0 0 1 0)
    (vec4 (vec3X position) (vec3Y position) (vec3Z position) 1)

rotationZ4 :: Scalar -> Mat4
rotationZ4 radians =
  quaternionRotation4 (rotationZQuaternion radians)

rotationZQuaternion :: Scalar -> Quaternion Scalar
rotationZQuaternion radians =
  axisAngle (V3 0 0 1) radians

quaternionRotation4 :: Quaternion Scalar -> Mat4
quaternionRotation4 (Quaternion w (V3 x y z)) =
  mat4FromColumns
    (vec4 (1 - 2 * (y * y + z * z)) (2 * (x * y + z * w)) (2 * (x * z - y * w)) 0)
    (vec4 (2 * (x * y - z * w)) (1 - 2 * (x * x + z * z)) (2 * (y * z + x * w)) 0)
    (vec4 (2 * (x * z + y * w)) (2 * (y * z - x * w)) (1 - 2 * (x * x + y * y)) 0)
    (vec4 0 0 0 1)

scaling4 :: Vec3 -> Mat4
scaling4 scale =
  mat4FromColumns
    (vec4 (vec3X scale) 0 0 0)
    (vec4 0 (vec3Y scale) 0 0)
    (vec4 0 0 (vec3Z scale) 0)
    (vec4 0 0 0 1)

mat4ToColumnMajorList :: Mat4 -> [Scalar]
mat4ToColumnMajorList (Mat4 (V4 column0 column1 column2 column3)) =
  foldMap v4ToList [column0, column1, column2, column3]

transformPoint3 :: Mat4 -> Vec3 -> Vec3
transformPoint3 (Mat4 (V4 column0 column1 column2 column3)) (Vec3 (V3 x y z)) =
  vec3
    (componentX column0 x column1 y column2 z column3)
    (componentY column0 x column1 y column2 z column3)
    (componentZ column0 x column1 y column2 z column3)

multiplyColumn :: M44 Scalar -> V4 Scalar -> V4 Scalar
multiplyColumn (V4 left0 left1 left2 left3) (V4 x y z w) =
  addV4
    (scaleV4 x left0)
    ( addV4
        (scaleV4 y left1)
        (addV4 (scaleV4 z left2) (scaleV4 w left3))
    )

scaleV4 :: Scalar -> V4 Scalar -> V4 Scalar
scaleV4 scalar (V4 x y z w) =
  V4 (scalar * x) (scalar * y) (scalar * z) (scalar * w)

addV4 :: V4 Scalar -> V4 Scalar -> V4 Scalar
addV4 (V4 leftX leftY leftZ leftW) (V4 rightX rightY rightZ rightW) =
  V4 (leftX + rightX) (leftY + rightY) (leftZ + rightZ) (leftW + rightW)

v4ToList :: V4 Scalar -> [Scalar]
v4ToList (V4 x y z w) = [x, y, z, w]

componentX :: V4 Scalar -> Scalar -> V4 Scalar -> Scalar -> V4 Scalar -> Scalar -> V4 Scalar -> Scalar
componentX (V4 x0 _ _ _) scale0 (V4 x1 _ _ _) scale1 (V4 x2 _ _ _) scaleZ (V4 x3 _ _ _) =
  (x0 * scale0) + (x1 * scale1) + (x2 * scaleZ) + x3

componentY :: V4 Scalar -> Scalar -> V4 Scalar -> Scalar -> V4 Scalar -> Scalar -> V4 Scalar -> Scalar
componentY (V4 _ y0 _ _) scale0 (V4 _ y1 _ _) scale1 (V4 _ y2 _ _) scaleZ (V4 _ y3 _ _) =
  (y0 * scale0) + (y1 * scale1) + (y2 * scaleZ) + y3

componentZ :: V4 Scalar -> Scalar -> V4 Scalar -> Scalar -> V4 Scalar -> Scalar -> V4 Scalar -> Scalar
componentZ (V4 _ _ z0 _) scale0 (V4 _ _ z1 _) scale1 (V4 _ _ z2 _) scaleZ (V4 _ _ z3 _) =
  (z0 * scale0) + (z1 * scale1) + (z2 * scaleZ) + z3
