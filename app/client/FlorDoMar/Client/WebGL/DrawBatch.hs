{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The whole of one frame, in the form the browser executes it.
--
-- A frame used to be issued as one jsaddle round trip per WebGL call, which let
-- the compositor present the canvas part-way through a render; because a canvas
-- without @preserveDrawingBuffer@ is cleared once presented, whatever had already
-- been drawn disappeared from the frames that followed. Everything a frame needs
-- is therefore collected here and encoded as one JSON payload, which the browser
-- replays inside a single task.
--
-- Geometry is included only when it differs from what the browser already holds
-- for that primitive name, so a redraw of an unchanged scene carries matrices and
-- colours only.
module FlorDoMar.Client.WebGL.DrawBatch
  ( DrawBatch (..)
  , DrawBatchPrimitive (..)
  , encodeDrawBatch
  ) where

import Data.List (intersperse)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Lazy (toStrict)
import Data.Text.Lazy.Builder (Builder, singleton, toLazyText)
import Data.Text.Lazy.Builder.Int (decimal, hexadecimal)
import Data.Text.Lazy.Builder.RealFloat (realFloat)
import Data.Word (Word16)
import FlorDoMar.Client.WebGL.Geometry (Color (..), Geometry3D (..), geometry3DPositions)
import FlorDoMar.Client.WebGL.Math
  ( Mat4
  , Scalar
  , mat4ToColumnMajorList
  )

-- | Everything one frame draws, plus the state the frame starts from.
data DrawBatch = DrawBatch
  { drawBatchClearColor :: Color
  , drawBatchClearDepth :: Scalar
  , drawBatchPrimitives :: [DrawBatchPrimitive]
  }
  deriving stock (Eq, Show)

-- | One primitive of a frame, in draw order.
--
-- @drawBatchPrimitiveGeometry@ is 'Nothing' when the browser's copy is still
-- current, and 'Just' the geometry to upload before drawing otherwise.
data DrawBatchPrimitive = DrawBatchPrimitive
  { drawBatchPrimitiveName :: Text
  , drawBatchPrimitiveMatrix :: Mat4
  , drawBatchPrimitiveColor :: Color
  , drawBatchPrimitiveGeometry :: Maybe Geometry3D
  }
  deriving stock (Eq, Show)

encodeDrawBatch :: DrawBatch -> Text
encodeDrawBatch batch =
  toStrict . toLazyText $
    "{\"clear\":"
      <> encodeColor (drawBatchClearColor batch)
      <> ",\"depth\":"
      <> encodeScalar (drawBatchClearDepth batch)
      <> ",\"primitives\":["
      <> commaSeparated (fmap encodePrimitive (drawBatchPrimitives batch))
      <> "]}"

encodePrimitive :: DrawBatchPrimitive -> Builder
encodePrimitive primitive =
  "{"
    <> field "name" (encodeText (drawBatchPrimitiveName primitive))
    <> ","
    <> field "matrix" (encodeScalars (mat4ToColumnMajorList (drawBatchPrimitiveMatrix primitive)))
    <> ","
    <> field "color" (encodeColor (drawBatchPrimitiveColor primitive))
    <> maybe mempty encodeGeometry (drawBatchPrimitiveGeometry primitive)
    <> "}"

encodeGeometry :: Geometry3D -> Builder
encodeGeometry geometry =
  ",\"geometry\":{"
    <> field "positions" (encodeScalars (geometry3DPositions geometry))
    <> ","
    <> field "indices" (encodeIndices (geometry3DIndices geometry))
    <> "}"

field :: Builder -> Builder -> Builder
field name value = "\"" <> name <> "\":" <> value

commaSeparated :: [Builder] -> Builder
commaSeparated = mconcat . intersperse ","

encodeColor :: Color -> Builder
encodeColor fill =
  brackets $
    commaSeparated
      [ encodeScalar (colorRed fill)
      , encodeScalar (colorGreen fill)
      , encodeScalar (colorBlue fill)
      , encodeScalar (colorAlpha fill)
      ]

encodeScalars :: [Scalar] -> Builder
encodeScalars = brackets . commaSeparated . fmap encodeScalar

-- | JSON has no spelling for a non-finite number, and one of those would cost the
-- whole frame rather than one coordinate, so they are pinned to zero.
encodeScalar :: Scalar -> Builder
encodeScalar value
  | isNaN value || isInfinite value = "0"
  | otherwise = realFloat value

encodeIndices :: [Word16] -> Builder
encodeIndices = brackets . commaSeparated . fmap encodeIndex

encodeIndex :: Word16 -> Builder
encodeIndex = decimal . fromIntegral

brackets :: Builder -> Builder
brackets inner = "[" <> inner <> "]"

encodeText :: Text -> Builder
encodeText value =
  "\"" <> foldMap encodeCharacter (Text.unpack value) <> "\""

encodeCharacter :: Char -> Builder
encodeCharacter character =
  case character of
    '"' -> "\\\""
    '\\' -> "\\\\"
    '\n' -> "\\n"
    '\r' -> "\\r"
    '\t' -> "\\t"
    _
      | character < ' ' -> unicodeEscape character
      | otherwise -> singleton character

-- | @\\u00XX@, padded so the escape is always four hex digits.
unicodeEscape :: Char -> Builder
unicodeEscape character =
  "\\u" <> hexadecimalPrefix code <> hexadecimal code
 where
  code = fromEnum character

hexadecimalPrefix :: Int -> Builder
hexadecimalPrefix code
  | code < 0x10 = "000"
  | code < 0x100 = "00"
  | code < 0x1000 = "0"
  | otherwise = ""
