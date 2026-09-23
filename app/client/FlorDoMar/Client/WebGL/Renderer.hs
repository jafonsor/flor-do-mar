{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Client.WebGL.Renderer
  ( Renderer
  , initRenderer
  , renderScene
  )
where

import Control.Monad (void)
import Control.Monad.IO.Class (liftIO)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Word (Word16)
import FlorDoMar.Client.Render.Scene
import FlorDoMar.Client.WebGL.Camera (Camera2D, camera2DMatrix)
import FlorDoMar.Client.WebGL.Geometry
import FlorDoMar.Client.WebGL.Math
  ( Mat4
  , Scalar
  , mat4ToColumnMajorList
  , multiply4
  )
import Language.Javascript.JSaddle
import Language.Javascript.JSaddle.Value qualified as JS

data Renderer = Renderer
  { rendererGl :: JSVal
  , rendererProgram :: JSVal
  , rendererPositionAttribute :: Int
  , rendererMatrixUniform :: JSVal
  , rendererColorUniform :: JSVal
  , rendererGeometryCache :: IORef (Map Text CachedGeometry)
  , rendererCanvasWidth :: Int
  , rendererCanvasHeight :: Int
  }

-- | A primitive's geometry as it currently exists on the GPU, kept so a redraw
-- can skip re-uploading geometry that has not changed.
data CachedGeometry = CachedGeometry
  { cachedGeometrySource :: Geometry3D
  , cachedVertexBuffer :: JSVal
  , cachedIndexBuffer :: JSVal
  }

initRenderer :: JSVal -> JSM (Maybe Renderer)
initRenderer gl = do
  vertexShaderMaybe <- createShader gl vertexShader vertexShaderSource
  fragmentShaderMaybe <- createShader gl fragmentShader fragmentShaderSource
  case (vertexShaderMaybe, fragmentShaderMaybe) of
    (Just vertexShaderValue, Just fragmentShaderValue) -> do
      programMaybe <- createProgram gl vertexShaderValue fragmentShaderValue
      case programMaybe of
        Nothing -> pure Nothing
        Just program -> initializeRendererWithProgram gl program
    _ -> pure Nothing

renderScene :: Renderer -> RenderScene -> JSM ()
renderScene renderer scene = do
  let
    gl = rendererGl renderer
  void $ callMethod "viewport" gl (0 :: Int, 0 :: Int, rendererCanvasWidth renderer, rendererCanvasHeight renderer)
  void $ callMethod "clearColor" gl (0.015 :: Double, 0.035 :: Double, 0.055 :: Double, 1 :: Double)
  void $ callMethod "clearDepth" gl [1 :: Double]
  void $ callMethod "clear" gl [colorBufferBit + depthBufferBit]
  void $ callMethod "useProgram" gl [rendererProgram renderer]
  void $ callMethod "enableVertexAttribArray" gl [rendererPositionAttribute renderer]
  mapM_ (drawPrimitive renderer (renderSceneCamera scene)) (renderScenePrimitives scene)

initializeRendererWithProgram :: JSVal -> JSVal -> JSM (Maybe Renderer)
initializeRendererWithProgram gl program = do
  positionAttributeValue <- callMethod "getAttribLocation" gl (program, "a_position" :: Text)
  positionAttribute <- round <$> JS.valToNumber positionAttributeValue
  matrixUniform <- callMethod "getUniformLocation" gl (program, "u_matrix" :: Text)
  colorUniform <- callMethod "getUniformLocation" gl (program, "u_color" :: Text)
  matrixUniformMaybe <- JS.maybeNullOrUndefined matrixUniform
  colorUniformMaybe <- JS.maybeNullOrUndefined colorUniform
  canvas <- gl ! ("canvas" :: Text)
  canvasWidth <- round <$> (JS.valToNumber =<< canvas ! ("width" :: Text))
  canvasHeight <- round <$> (JS.valToNumber =<< canvas ! ("height" :: Text))
  case (positionAttribute >= 0, matrixUniformMaybe, colorUniformMaybe) of
    (True, Just matrixUniformValue, Just colorUniformValue) -> do
      void $ callMethod "useProgram" gl [program]
      void $ callMethod "enable" gl [depthTest]
      void $ callMethod "depthFunc" gl [lessEqual]
      geometryCache <- liftIO $ newIORef Map.empty
      pure $
        Just
          Renderer
            { rendererGl = gl
            , rendererProgram = program
            , rendererPositionAttribute = positionAttribute
            , rendererMatrixUniform = matrixUniformValue
            , rendererColorUniform = colorUniformValue
            , rendererGeometryCache = geometryCache
            , rendererCanvasWidth = canvasWidth
            , rendererCanvasHeight = canvasHeight
            }
    _ -> do
      logWebGlError "Could not initialize WebGL renderer resources."
      pure Nothing

drawPrimitive :: Renderer -> Camera2D -> RenderPrimitive -> JSM ()
drawPrimitive renderer camera primitive = do
  let
    geometry = renderPrimitiveGeometry primitive
    matrix = camera2DMatrix camera `multiply4` renderPrimitiveWorldMatrix primitive
    fill = materialColor (renderPrimitiveMaterial primitive)
  bindGeometry renderer (renderPrimitiveName primitive) geometry
  uploadMatrix (rendererGl renderer) (rendererMatrixUniform renderer) matrix
  void $
    callMethod
      "uniform4f"
      (rendererGl renderer)
      ( rendererColorUniform renderer
      , realToFrac (colorRed fill) :: Double
      , realToFrac (colorGreen fill) :: Double
      , realToFrac (colorBlue fill) :: Double
      , realToFrac (colorAlpha fill) :: Double
      )
  void $
    callMethod
      "drawElements"
      (rendererGl renderer)
      (triangles, length (geometry3DIndices geometry), unsignedShort, 0 :: Int)

-- | Bind a primitive's buffers, uploading only when its geometry changed.
--
-- Every render used to re-upload every primitive's vertices and indices through
-- jsaddle, which marshals a list one element per command: a single 48-segment
-- ring cost roughly 900 commands, and a pointer move re-rendered the whole
-- scene. The geometry is now compared before upload, so redrawing an unchanged
-- scene costs nothing. Most of the scene really is static between ticks — ship
-- bodies, heading markers and speed rings only change when the simulation does.
--
-- 'vertexAttribPointer' has to be re-issued per primitive because each one now
-- has its own buffers, and it records whichever buffer is bound at the time.
bindGeometry :: Renderer -> Text -> Geometry3D -> JSM ()
bindGeometry renderer name geometry = do
  cached <- cachedGeometry renderer name geometry
  let
    gl = rendererGl renderer
  void $ callMethod "bindBuffer" gl (arrayBuffer, cachedVertexBuffer cached)
  void $ callMethod "bindBuffer" gl (elementArrayBuffer, cachedIndexBuffer cached)
  void $
    callMethod
      "vertexAttribPointer"
      gl
      (rendererPositionAttribute renderer, 3 :: Int, glFloat, False, 0 :: Int, 0 :: Int)

cachedGeometry :: Renderer -> Text -> Geometry3D -> JSM CachedGeometry
cachedGeometry renderer name geometry = do
  cache <- liftIO $ readIORef (rendererGeometryCache renderer)
  case Map.lookup name cache of
    Just cached
      | cachedGeometrySource cached == geometry -> pure cached
      | otherwise -> do
          uploadGeometry renderer (cachedVertexBuffer cached) (cachedIndexBuffer cached) geometry
          store cached { cachedGeometrySource = geometry }
    Nothing -> do
      vertexBuffer <- createBufferOrFail renderer
      indexBuffer <- createBufferOrFail renderer
      uploadGeometry renderer vertexBuffer indexBuffer geometry
      store (CachedGeometry geometry vertexBuffer indexBuffer)
 where
  store cached = do
    liftIO $ modifyIORef' (rendererGeometryCache renderer) (Map.insert name cached)
    pure cached

-- | Reuse the entry's own buffers. Only the contents change, so the buffer
-- objects never need recreating.
uploadGeometry :: Renderer -> JSVal -> JSVal -> Geometry3D -> JSM ()
uploadGeometry renderer vertexBuffer indexBuffer geometry = do
  let gl = rendererGl renderer
  vertices <- float32Array (geometry3DPositions geometry)
  indices <- uint16Array (geometry3DIndices geometry)
  void $ callMethod "bindBuffer" gl (arrayBuffer, vertexBuffer)
  void $ callMethod "bufferData" gl (arrayBuffer, vertices, staticDraw)
  void $ callMethod "bindBuffer" gl (elementArrayBuffer, indexBuffer)
  void $ callMethod "bufferData" gl (elementArrayBuffer, indices, staticDraw)

createBufferOrFail :: Renderer -> JSM JSVal
createBufferOrFail renderer = do
  buffer <- callMethod "createBuffer" (rendererGl renderer) ()
  JS.maybeNullOrUndefined buffer >>= \case
    Nothing -> logWebGlError "Could not create a WebGL buffer."
    Just _ -> pure ()
  pure buffer

uploadMatrix :: JSVal -> JSVal -> Mat4 -> JSM ()
uploadMatrix gl location matrix = do
  matrixArray <- float32Array (mat4ToColumnMajorList matrix)
  void $ callMethod "uniformMatrix4fv" gl (location, False, matrixArray)

createShader :: JSVal -> Int -> Text -> JSM (Maybe JSVal)
createShader gl shaderType source = do
  shaderValue <- callMethod "createShader" gl [shaderType]
  shaderMaybe <- JS.maybeNullOrUndefined shaderValue
  case shaderMaybe of
    Nothing -> pure Nothing
    Just shader -> do
      void $ callMethod "shaderSource" gl (shader, source)
      void $ callMethod "compileShader" gl [shader]
      compiled <- JS.valToBool =<< callMethod "getShaderParameter" gl (shader, compileStatus)
      if compiled
        then pure (Just shader)
        else do
          infoLog <- JS.valToText =<< callMethod "getShaderInfoLog" gl [shader]
          logWebGlError ("Could not compile WebGL shader: " <> infoLog)
          pure Nothing

createProgram :: JSVal -> JSVal -> JSVal -> JSM (Maybe JSVal)
createProgram gl vertexShaderValue fragmentShaderValue = do
  programValue <- callMethod "createProgram" gl ()
  programMaybe <- JS.maybeNullOrUndefined programValue
  case programMaybe of
    Nothing -> pure Nothing
    Just program -> do
      void $ callMethod "attachShader" gl (program, vertexShaderValue)
      void $ callMethod "attachShader" gl (program, fragmentShaderValue)
      void $ callMethod "linkProgram" gl [program]
      linked <- JS.valToBool =<< callMethod "getProgramParameter" gl (program, linkStatus)
      if linked
        then pure (Just program)
        else do
          infoLog <- JS.valToText =<< callMethod "getProgramInfoLog" gl [program]
          logWebGlError ("Could not link WebGL program: " <> infoLog)
          pure Nothing

float32Array :: [Scalar] -> JSM JSVal
float32Array values = do
  constructor <- jsg ("Float32Array" :: Text)
  valuesArray <- JS.val (fmap realToFrac values :: [Double])
  new constructor [valuesArray]

uint16Array :: [Word16] -> JSM JSVal
uint16Array values = do
  constructor <- jsg ("Uint16Array" :: Text)
  valuesArray <- JS.val (fmap fromIntegral values :: [Int])
  new constructor [valuesArray]

callMethod :: (MakeArgs args) => Text -> JSVal -> args -> JSM JSVal
callMethod method target args = do
  functionValue <- target ! method
  call functionValue target args

logWebGlError :: Text -> JSM ()
logWebGlError message = do
  console <- jsg ("console" :: Text)
  void $ callMethod "error" console [message]

vertexShaderSource :: Text
vertexShaderSource =
  "attribute vec3 a_position;\n\
  \uniform mat4 u_matrix;\n\
  \void main() {\n\
  \  gl_Position = u_matrix * vec4(a_position, 1.0);\n\
  \}\n"

fragmentShaderSource :: Text
fragmentShaderSource =
  "precision mediump float;\n\
  \uniform vec4 u_color;\n\
  \void main() {\n\
  \  gl_FragColor = u_color;\n\
  \}\n"

arrayBuffer :: Int
arrayBuffer = 34962

elementArrayBuffer :: Int
elementArrayBuffer = 34963

staticDraw :: Int
staticDraw = 35044

glFloat :: Int
glFloat = 5126

unsignedShort :: Int
unsignedShort = 5123

triangles :: Int
triangles = 4

vertexShader :: Int
vertexShader = 35633

fragmentShader :: Int
fragmentShader = 35632

compileStatus :: Int
compileStatus = 35713

linkStatus :: Int
linkStatus = 35714

colorBufferBit :: Int
colorBufferBit = 16384

depthBufferBit :: Int
depthBufferBit = 256

depthTest :: Int
depthTest = 2929

lessEqual :: Int
lessEqual = 515
