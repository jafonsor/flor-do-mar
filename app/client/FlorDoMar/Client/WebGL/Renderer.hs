{-# LANGUAGE OverloadedStrings #-}

-- | The WebGL renderer: a frame is one call, not one call per GL command.
--
-- The browser owns the GL objects — program, uniform locations and per-primitive
-- buffers — behind a small executor installed by 'batchExecutorSource'. Haskell
-- owns the scene, the geometry and the decision about what needs uploading, and
-- hands the browser one encoded 'DrawBatch' per frame. That single call is the
-- whole point: it runs as one browser task, so no compositor frame can land in
-- the middle of a render and present a canvas that is only half drawn.
module FlorDoMar.Client.WebGL.Renderer
  ( Renderer
  , initRenderer
  , renderScene
  ) where

import Control.Monad (void)
import Control.Monad.IO.Class (liftIO)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import FlorDoMar.Client.Render.Scene
import FlorDoMar.Client.WebGL.Camera (camera2DMatrix)
import FlorDoMar.Client.WebGL.DrawBatch
import FlorDoMar.Client.WebGL.Geometry
import FlorDoMar.Client.WebGL.Math (Scalar, multiply4)
import Language.Javascript.JSaddle
import Language.Javascript.JSaddle.Value qualified as JS

data Renderer = Renderer
  { rendererExecutor :: JSVal
  -- ^ The browser-side executor, looked up once so a frame costs one call.
  , rendererRender :: JSVal
  -- ^ Its @render@ method, fetched once rather than per frame: a method lookup is
  -- a round trip, and a frame is rendered up to once per animation frame.
  , rendererHandle :: Int
  -- ^ Which canvas the executor draws to.
  , rendererUploadedGeometry :: IORef (Map Text Geometry3D)
  -- ^ Geometry as the browser currently holds it, per primitive name. A primitive
  -- whose geometry compares equal is not sent again.
  }

-- | Build the program in the browser and return a renderer for it.
initRenderer :: JSVal -> JSM (Maybe Renderer)
initRenderer gl = do
  void $ eval batchExecutorSource
  executor <- jsg ("__fdmRenderer" :: Text)
  created <- callMethod "create" executor (gl, vertexShaderSource, fragmentShaderSource)
  succeeded <- JS.valToBool =<< created ! ("ok" :: Text)
  if not succeeded
    then do
      message <- JS.valToText =<< created ! ("error" :: Text)
      logWebGlError message
      pure Nothing
    else do
      handle <- round <$> (JS.valToNumber =<< created ! ("handle" :: Text))
      renderFunction <- executor ! ("render" :: Text)
      uploadedGeometry <- liftIO $ newIORef Map.empty
      pure $
        Just
          Renderer
            { rendererExecutor = executor
            , rendererRender = renderFunction
            , rendererHandle = handle
            , rendererUploadedGeometry = uploadedGeometry
            }

-- | Draw one frame.
--
-- The upload cache is only advanced once the frame has been handed over, so a
-- frame that fails to execute does not leave the browser holding geometry the
-- renderer believes it has sent.
renderScene :: Renderer -> RenderScene -> JSM ()
renderScene renderer scene = do
  uploaded <- liftIO $ readIORef (rendererUploadedGeometry renderer)
  let (batch, uploadedAfter) = drawBatchForScene uploaded scene
  void $
    call
      (rendererRender renderer)
      (rendererExecutor renderer)
      (rendererHandle renderer, encodeDrawBatch batch)
  liftIO $ writeIORef (rendererUploadedGeometry renderer) uploadedAfter

-- | Collect a scene into the frame the browser will replay, and say what the
-- browser holds afterwards.
drawBatchForScene :: Map Text Geometry3D -> RenderScene -> (DrawBatch, Map Text Geometry3D)
drawBatchForScene uploaded scene =
  ( DrawBatch
      { drawBatchClearColor = sceneClearColor
      , drawBatchClearDepth = sceneClearDepth
      , drawBatchPrimitives = reverse collectedPrimitives
      }
  , collectedGeometry
  )
 where
  camera = renderSceneCamera scene
  (collectedGeometry, collectedPrimitives) =
    foldl collect (uploaded, []) (renderScenePrimitives scene)

  collect (known, primitives) primitive =
    let
      name = renderPrimitiveName primitive
      geometry = renderPrimitiveGeometry primitive
      changed = Map.lookup name known /= Just geometry
     in
      ( if changed then Map.insert name geometry known else known
      , DrawBatchPrimitive
          { drawBatchPrimitiveName = name
          , drawBatchPrimitiveMatrix = camera2DMatrix camera `multiply4` renderPrimitiveWorldMatrix primitive
          , drawBatchPrimitiveColor = materialColor (renderPrimitiveMaterial primitive)
          , drawBatchPrimitiveGeometry = if changed then Just geometry else Nothing
          }
          : primitives
      )

sceneClearColor :: Color
sceneClearColor = color 0.015 0.035 0.055 1

sceneClearDepth :: Scalar
sceneClearDepth = 1

-- | The browser half of the renderer.
--
-- It is deliberately thin: it owns GL objects and replays the commands in the
-- order it is given them, and knows nothing about ships, trajectories or the
-- scene graph. Everything above it is Haskell.
batchExecutorSource :: Text
batchExecutorSource =
  Text.unlines
    [ "(function () {"
    , "  if (window.__fdmRenderer) { return; }"
    , "  var COLOR_BUFFER_BIT = 0x4000;"
    , "  var DEPTH_BUFFER_BIT = 0x0100;"
    , "  var states = [];"
    , ""
    , "  var compileShader = function (gl, type, source) {"
    , "    var shader = gl.createShader(type);"
    , "    if (!shader) { return { error: 'Could not initialize WebGL renderer resources.' }; }"
    , "    gl.shaderSource(shader, source);"
    , "    gl.compileShader(shader);"
    , "    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {"
    , "      return { error: 'Could not compile WebGL shader: ' + gl.getShaderInfoLog(shader) };"
    , "    }"
    , "    return { shader: shader };"
    , "  };"
    , ""
    , "  var buildProgram = function (gl, vertexSource, fragmentSource) {"
    , "    var vertexShader = compileShader(gl, gl.VERTEX_SHADER, vertexSource);"
    , "    if (vertexShader.error) { return vertexShader; }"
    , "    var fragmentShader = compileShader(gl, gl.FRAGMENT_SHADER, fragmentSource);"
    , "    if (fragmentShader.error) { return fragmentShader; }"
    , "    var program = gl.createProgram();"
    , "    if (!program) { return { error: 'Could not initialize WebGL renderer resources.' }; }"
    , "    gl.attachShader(program, vertexShader.shader);"
    , "    gl.attachShader(program, fragmentShader.shader);"
    , "    gl.linkProgram(program);"
    , "    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {"
    , "      return { error: 'Could not link WebGL program: ' + gl.getProgramInfoLog(program) };"
    , "    }"
    , "    return { program: program };"
    , "  };"
    , ""
    , "  var create = function (gl, vertexSource, fragmentSource) {"
    , "    try {"
    , "      var built = buildProgram(gl, vertexSource, fragmentSource);"
    , "      if (built.error) { return { ok: false, error: built.error }; }"
    , "      var positionAttribute = gl.getAttribLocation(built.program, 'a_position');"
    , "      var matrixUniform = gl.getUniformLocation(built.program, 'u_matrix');"
    , "      var colorUniform = gl.getUniformLocation(built.program, 'u_color');"
    , "      if (positionAttribute < 0 || matrixUniform === null || colorUniform === null) {"
    , "        return { ok: false, error: 'Could not initialize WebGL renderer resources.' };"
    , "      }"
    , "      gl.useProgram(built.program);"
    , "      gl.enable(gl.DEPTH_TEST);"
    , "      gl.depthFunc(gl.LEQUAL);"
    , "      states.push({"
    , "        gl: gl,"
    , "        program: built.program,"
    , "        positionAttribute: positionAttribute,"
    , "        matrixUniform: matrixUniform,"
    , "        colorUniform: colorUniform,"
    , "        buffers: {}"
    , "      });"
    , "      return { ok: true, handle: states.length - 1 };"
    , "    } catch (error) {"
    , "      return { ok: false, error: 'Could not initialize WebGL renderer: ' + error };"
    , "    }"
    , "  };"
    , ""
    , "  var primitiveBuffers = function (state, name) {"
    , "    var buffers = state.buffers[name];"
    , "    if (buffers) { return buffers; }"
    , "    var gl = state.gl;"
    , "    buffers = { vertex: gl.createBuffer(), index: gl.createBuffer(), indexCount: 0 };"
    , "    if (!buffers.vertex || !buffers.index) {"
    , "      console.error('Could not create a WebGL buffer.');"
    , "    }"
    , "    state.buffers[name] = buffers;"
    , "    return buffers;"
    , "  };"
    , ""
    , "  var drawPrimitive = function (state, primitive) {"
    , "    var gl = state.gl;"
    , "    var buffers = primitiveBuffers(state, primitive.name);"
    , "    gl.bindBuffer(gl.ARRAY_BUFFER, buffers.vertex);"
    , "    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffers.index);"
    , "    if (primitive.geometry) {"
    , "      var indices = new Uint16Array(primitive.geometry.indices);"
    , "      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(primitive.geometry.positions), gl.STATIC_DRAW);"
    , "      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);"
    , "      buffers.indexCount = indices.length;"
    , "    }"
    , "    gl.vertexAttribPointer(state.positionAttribute, 3, gl.FLOAT, false, 0, 0);"
    , "    gl.uniformMatrix4fv(state.matrixUniform, false, new Float32Array(primitive.matrix));"
    , "    gl.uniform4f("
    , "      state.colorUniform,"
    , "      primitive.color[0],"
    , "      primitive.color[1],"
    , "      primitive.color[2],"
    , "      primitive.color[3]"
    , "    );"
    , "    gl.drawElements(gl.TRIANGLES, buffers.indexCount, gl.UNSIGNED_SHORT, 0);"
    , "  };"
    , ""
    , "  // One call, one task: every command of a frame runs before the browser can"
    , "  // present the canvas again."
    , "  var render = function (handle, payload) {"
    , "    try {"
    , "      draw(handle, payload);"
    , "    } catch (error) {"
    , "      // Housekeeping only: an exception that escaped here would cross back"
    , "      // into the widget and end the page's session, so a bad frame must not"
    , "      // be allowed to take the client down with it."
    , "      console.error('Could not render the draw batch: ' + error);"
    , "    }"
    , "  };"
    , ""
    , "  var draw = function (handle, payload) {"
    , "    var state = states[handle];"
    , "    if (!state) { return; }"
    , "    var batch;"
    , "    try {"
    , "      batch = JSON.parse(payload);"
    , "    } catch (error) {"
    , "      console.error('Could not read the draw batch: ' + error);"
    , "      return;"
    , "    }"
    , "    var gl = state.gl;"
    , "    gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);"
    , "    gl.clearColor(batch.clear[0], batch.clear[1], batch.clear[2], batch.clear[3]);"
    , "    gl.clearDepth(batch.depth);"
    , "    gl.clear(COLOR_BUFFER_BIT | DEPTH_BUFFER_BIT);"
    , "    gl.useProgram(state.program);"
    , "    gl.enableVertexAttribArray(state.positionAttribute);"
    , "    for (var i = 0; i < batch.primitives.length; i++) {"
    , "      drawPrimitive(state, batch.primitives[i]);"
    , "    }"
    , "  };"
    , ""
    , "  window.__fdmRenderer = { create: create, render: render };"
    , "})();"
    ]

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
