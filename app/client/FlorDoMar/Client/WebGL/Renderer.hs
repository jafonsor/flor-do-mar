{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Client.WebGL.Renderer
  ( Renderer
  , initRenderer
  , renderScene
  )
where

import Control.Monad (void)
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
  , rendererVertexBuffer :: JSVal
  , rendererIndexBuffer :: JSVal
  , rendererIndexCount :: Int
  , rendererCanvasWidth :: Int
  , rendererCanvasHeight :: Int
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
  void $ callMethod "bindBuffer" gl (arrayBuffer, rendererVertexBuffer renderer)
  void $ callMethod "bindBuffer" gl (elementArrayBuffer, rendererIndexBuffer renderer)
  void $ callMethod "enableVertexAttribArray" gl [rendererPositionAttribute renderer]
  void $ callMethod "vertexAttribPointer" gl (rendererPositionAttribute renderer, 3 :: Int, glFloat, False, 0 :: Int, 0 :: Int)
  mapM_ (drawMesh renderer (renderSceneCamera scene)) (renderSceneMeshes scene)

initializeRendererWithProgram :: JSVal -> JSVal -> JSM (Maybe Renderer)
initializeRendererWithProgram gl program = do
  positionAttributeValue <- callMethod "getAttribLocation" gl (program, "a_position" :: Text)
  positionAttribute <- round <$> JS.valToNumber positionAttributeValue
  matrixUniform <- callMethod "getUniformLocation" gl (program, "u_matrix" :: Text)
  colorUniform <- callMethod "getUniformLocation" gl (program, "u_color" :: Text)
  matrixUniformMaybe <- JS.maybeNullOrUndefined matrixUniform
  colorUniformMaybe <- JS.maybeNullOrUndefined colorUniform
  vertexBufferMaybe <- createBuffer gl
  indexBufferMaybe <- createBuffer gl
  canvas <- gl ! ("canvas" :: Text)
  canvasWidth <- round <$> (JS.valToNumber =<< canvas ! ("width" :: Text))
  canvasHeight <- round <$> (JS.valToNumber =<< canvas ! ("height" :: Text))
  case (positionAttribute >= 0, matrixUniformMaybe, colorUniformMaybe, vertexBufferMaybe, indexBufferMaybe) of
    (True, Just matrixUniformValue, Just colorUniformValue, Just vertexBuffer, Just indexBuffer) -> do
      uploadCubeGeometry gl vertexBuffer indexBuffer
      void $ callMethod "useProgram" gl [program]
      void $ callMethod "enable" gl [depthTest]
      void $ callMethod "depthFunc" gl [lessEqual]
      pure $
        Just
          Renderer
            { rendererGl = gl
            , rendererProgram = program
            , rendererPositionAttribute = positionAttribute
            , rendererMatrixUniform = matrixUniformValue
            , rendererColorUniform = colorUniformValue
            , rendererVertexBuffer = vertexBuffer
            , rendererIndexBuffer = indexBuffer
            , rendererIndexCount = length (geometry3DIndices unitCubeGeometry)
            , rendererCanvasWidth = canvasWidth
            , rendererCanvasHeight = canvasHeight
            }
    _ -> do
      logWebGlError "Could not initialize WebGL renderer resources."
      pure Nothing

drawMesh :: Renderer -> Camera2D -> RenderMesh -> JSM ()
drawMesh renderer camera mesh =
  case renderMeshGeometry mesh of
    UnitCubeGeometry -> do
      let
        matrix =
          camera2DMatrix camera
            `multiply4` transformMatrix (renderMeshTransform mesh)
        fill = materialColor (renderMeshMaterial mesh)
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
          (triangles, rendererIndexCount renderer, unsignedShort, 0 :: Int)

uploadCubeGeometry :: JSVal -> JSVal -> JSVal -> JSM ()
uploadCubeGeometry gl vertexBuffer indexBuffer = do
  vertices <- float32Array (geometry3DPositions unitCubeGeometry)
  indices <- uint16Array (geometry3DIndices unitCubeGeometry)
  void $ callMethod "bindBuffer" gl (arrayBuffer, vertexBuffer)
  void $ callMethod "bufferData" gl (arrayBuffer, vertices, staticDraw)
  void $ callMethod "bindBuffer" gl (elementArrayBuffer, indexBuffer)
  void $ callMethod "bufferData" gl (elementArrayBuffer, indices, staticDraw)

uploadMatrix :: JSVal -> JSVal -> Mat4 -> JSM ()
uploadMatrix gl location matrix = do
  matrixArray <- float32Array (mat4ToColumnMajorList matrix)
  void $ callMethod "uniformMatrix4fv" gl (location, False, matrixArray)

createBuffer :: JSVal -> JSM (Maybe JSVal)
createBuffer gl = do
  buffer <- callMethod "createBuffer" gl ()
  JS.maybeNullOrUndefined buffer

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
