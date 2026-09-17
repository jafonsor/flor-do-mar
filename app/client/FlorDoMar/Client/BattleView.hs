{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Client.BattleView
  ( battleView
  , renderBattleScene
  )
where

import Control.Monad (forM_, void)
import Data.Map qualified as Map
import Data.Text (Text)
import FlorDoMar.Client.BattleScene
import FlorDoMar.Combat
import Language.Javascript.JSaddle
import Reflex.Dom.Core

battleView ::
  ( DomBuilder t m
  , MonadJSM (Performable m)
  , PerformEvent t m
  , PostBuild t m
  ) =>
  Dynamic t CombatSnapshot ->
  m ()
battleView snapshotDynamic = do
  elAttr "canvas" canvasAttributes blank
  postBuild <- getPostBuild
  let
    renderEvents =
      leftmost
        [ current snapshotDynamic <@ postBuild
        , updated snapshotDynamic
        ]
  performEvent_ $
    fmap
      (liftJSM . renderBattleScene "battle-view" . battleSceneFromSnapshot)
      renderEvents

renderBattleScene :: Text -> BattleScene -> JSM ()
renderBattleScene canvasId scene = do
  document <- jsg ("document" :: Text)
  canvas <- callMethod "getElementById" document [canvasId]
  gl <- callMethod "getContext" canvas ["webgl" :: Text]
  renderWithWebGl gl scene

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

renderWithWebGl :: JSVal -> BattleScene -> JSM ()
renderWithWebGl gl scene = do
  void $ callMethod "viewport" gl (0 :: Int, 0 :: Int, canvasWidth, canvasHeight)
  void $ callMethod "clearColor" gl (0.015 :: Double, 0.035 :: Double, 0.055 :: Double, 1 :: Double)
  void $ callMethod "clear" gl [colorBufferBit]
  void $ callMethod "enable" gl [scissorTest]
  drawGrid gl
  drawRangeContext gl (battleSceneRange scene)
  forM_ (battleSceneShips scene) (drawShip gl)
  void $ callMethod "disable" gl [scissorTest]

drawGrid :: JSVal -> JSM ()
drawGrid gl = do
  forM_ [80, 160 .. canvasWidth - 80] $ \x ->
    drawRect gl gridColor x 0 1 canvasHeight
  forM_ [60, 120 .. canvasHeight - 60] $ \y ->
    drawRect gl gridColor 0 y canvasWidth 1

drawRangeContext :: JSVal -> Double -> JSM ()
drawRangeContext gl range =
  drawRect gl rangeColor 32 (canvasHeight - 44) (max 4 (round (range * 2))) 4

drawShip :: JSVal -> ShipMarker -> JSM ()
drawShip gl marker = do
  let
    (x, y) = worldToCanvas (markerPosition marker)
    bodyColor =
      if markerIsPlayer marker
        then playerColor
        else enemyColor
    hullWidth = max 4 (round (fromIntegral (markerHull marker) / (100 :: Double) * 14))
  drawRect gl bodyColor (x - 7) (y - 7) 14 14
  drawRect gl headingColor (x - 1) (y - 1) 2 2
  drawHeadingRay gl x y (markerHeading marker)
  drawRect gl hullColor (x - 7) (y - 14) hullWidth 3

drawHeadingRay :: JSVal -> Int -> Int -> Heading -> JSM ()
drawHeadingRay gl originX originY (Heading degrees) =
  forM_ [1 .. 8 :: Int] $ \stepIndex -> do
    let
      distance = fromIntegral (stepIndex * 4)
      radians = degrees * pi / 180
      x = originX + round (distance * cos radians)
      y = originY + round (distance * sin radians)
    drawRect gl headingColor (x - 1) (y - 1) 3 3

drawRect :: JSVal -> (Double, Double, Double, Double) -> Int -> Int -> Int -> Int -> JSM ()
drawRect gl (red, green, blue, alpha) x y width height = do
  void $ callMethod "clearColor" gl (red, green, blue, alpha)
  void $ callMethod "scissor" gl (x, y, width, height)
  void $ callMethod "clear" gl [colorBufferBit]

worldToCanvas :: Point -> (Int, Int)
worldToCanvas point =
  ( round (fromIntegral canvasWidth / 2 + pointX point * worldScale)
  , round (fromIntegral canvasHeight / 2 + pointY point * worldScale)
  )

canvasWidth :: Int
canvasWidth = 760

canvasHeight :: Int
canvasHeight = 428

canvasWidthText :: Text
canvasWidthText = "760"

canvasHeightText :: Text
canvasHeightText = "428"

worldScale :: Double
worldScale = 2

colorBufferBit :: Int
colorBufferBit = 16384

scissorTest :: Int
scissorTest = 3089

playerColor :: (Double, Double, Double, Double)
playerColor = (0.2, 0.75, 0.95, 1)

enemyColor :: (Double, Double, Double, Double)
enemyColor = (0.95, 0.34, 0.24, 1)

headingColor :: (Double, Double, Double, Double)
headingColor = (0.96, 0.9, 0.58, 1)

hullColor :: (Double, Double, Double, Double)
hullColor = (0.37, 0.9, 0.55, 1)

gridColor :: (Double, Double, Double, Double)
gridColor = (0.05, 0.12, 0.18, 1)

rangeColor :: (Double, Double, Double, Double)
rangeColor = (0.2, 0.42, 0.62, 1)
