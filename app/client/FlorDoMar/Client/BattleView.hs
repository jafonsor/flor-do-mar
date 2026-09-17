{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Client.BattleView
  ( battleView
  , initializeBattleRenderer
  , renderBattleScene
  )
where

import Data.Map qualified as Map
import Data.Text (Text)
import FlorDoMar.Client.BattleScene
import FlorDoMar.Client.WebGL.Renderer qualified as WebGL
import FlorDoMar.Combat
import Language.Javascript.JSaddle
import Reflex.Dom.Core

battleView ::
  ( DomBuilder t m
  , MonadJSM (Performable m)
  , MonadHold t m
  , PerformEvent t m
  , PostBuild t m
  ) =>
  Dynamic t CombatSnapshot ->
  m ()
battleView snapshotDynamic = do
  elAttr "canvas" canvasAttributes blank
  postBuild <- getPostBuild
  initializedRenderer <-
    performEvent $
      fmap
        ( \snapshot ->
            liftJSM $ do
              rendererMaybe <- initializeBattleRenderer "battle-view"
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

initializeBattleRenderer :: Text -> JSM (Maybe WebGL.Renderer)
initializeBattleRenderer canvasId = do
  document <- jsg ("document" :: Text)
  canvas <- callMethod "getElementById" document [canvasId]
  gl <- callMethod "getContext" canvas ["webgl" :: Text]
  WebGL.initRenderer gl

renderBattleScene :: WebGL.Renderer -> BattleScene -> JSM ()
renderBattleScene renderer =
  WebGL.renderScene renderer . battleRenderScene

callMethod :: (MakeArgs args) => Text -> JSVal -> args -> JSM JSVal
callMethod method target args = do
  functionValue <- target ! method
  call functionValue target args

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
