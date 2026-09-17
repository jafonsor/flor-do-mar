{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}

module FlorDoMar.Client.BattleView
  ( battleView
  , initializeBattleRenderer
  , renderBattleScene
  )
where

import Control.Monad (void)
import Data.Map qualified as Map
import Data.Text (Text)
import FlorDoMar.Client.BattleScene
import FlorDoMar.Client.WebGL.Renderer qualified as WebGL
import FlorDoMar.Combat
import Language.Javascript.JSaddle
import Language.Javascript.JSaddle.Value qualified as JS
import Reflex.Dom.Core

battleView ::
  ( DomBuilder t m
  , ToJSVal (RawElement (DomBuilderSpace m))
  , MonadJSM (Performable m)
  , MonadHold t m
  , PerformEvent t m
  , PostBuild t m
  ) =>
  Dynamic t CombatSnapshot ->
  m ()
battleView snapshotDynamic = do
  (canvasElement, ()) <- elAttr' "canvas" canvasAttributes blank
  postBuild <- getPostBuild
  initializedRenderer <-
    performEvent $
      fmap
        ( \snapshot ->
            liftJSM $ do
              canvas <- toJSVal (_element_raw canvasElement)
              rendererMaybe <- initializeBattleRenderer canvas
              case rendererMaybe of
                Nothing -> pure ()
                Just renderer -> renderBattleScene renderer (battleSceneFromSnapshot snapshot)
              pure rendererMaybe
        )
        (current snapshotDynamic <@ postBuild)
  rendererDynamic <- holdDyn Nothing initializedRenderer
  performEvent_ $
    attachWithMaybe
      ( \rendererMaybe snapshot ->
          fmap
            ( \renderer ->
                liftJSM $
                  renderBattleScene renderer (battleSceneFromSnapshot snapshot)
            )
            rendererMaybe
      )
      (current rendererDynamic)
      (updated snapshotDynamic)

initializeBattleRenderer :: JSVal -> JSM (Maybe WebGL.Renderer)
initializeBattleRenderer canvas = do
  canvasMaybe <- JS.maybeNullOrUndefined canvas
  case canvasMaybe of
    Nothing -> do
      logBrowserError "Could not initialize battle renderer: canvas element is missing."
      pure Nothing
    Just canvasValue -> do
      gl <- callMethod "getContext" canvasValue ["webgl" :: Text]
      glMaybe <- JS.maybeNullOrUndefined gl
      case glMaybe of
        Nothing -> do
          logBrowserError "Could not initialize battle renderer: WebGL context is unavailable."
          pure Nothing
        Just glValue -> WebGL.initRenderer glValue

renderBattleScene :: WebGL.Renderer -> BattleScene -> JSM ()
renderBattleScene renderer =
  WebGL.renderScene renderer . battleRenderScene

callMethod :: (MakeArgs args) => Text -> JSVal -> args -> JSM JSVal
callMethod method target args = do
  functionValue <- target ! method
  call functionValue target args

logBrowserError :: Text -> JSM ()
logBrowserError message = do
  console <- jsg ("console" :: Text)
  void $ callMethod "error" console [message]

canvasAttributes :: Map.Map Text Text
canvasAttributes =
  Map.fromList
    [ ("id", "battle-view")
    , ("width", canvasWidthText)
    , ("height", canvasHeightText)
    , ( "style"
      , "width: 100%; max-width: 760px; aspect-ratio: 16 / 9; border: 1px solid #203447; background: #061019; display: block;"
      )
    ]

canvasWidthText :: Text
canvasWidthText = "760"

canvasHeightText :: Text
canvasHeightText = "428"
