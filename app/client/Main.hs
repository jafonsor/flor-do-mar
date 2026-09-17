{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE MonoLocalBinds #-}

module Main (main) where

import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)
import Data.Text qualified as Text
import FlorDoMar.Client.BattleView (battleView)
import FlorDoMar.Combat
import Language.Javascript.JSaddle.Warp (jsaddleApp, jsaddleOr)
import Network.Wai.Handler.Warp qualified as Warp
import Network.WebSockets (defaultConnectionOptions)
import Reflex.Dom.Core
import System.IO (hFlush, stdout)

main :: IO ()
main = do
  application <- jsaddleOr defaultConnectionOptions (mainWidget app) jsaddleApp
  Warp.runSettings serverSettings application

serverPort :: Int
serverPort = 3911

serverSettings :: Warp.Settings
serverSettings =
  Warp.setBeforeMainLoop logServerReady $
    Warp.setPort serverPort Warp.defaultSettings

logServerReady :: IO ()
logServerReady = do
  putStrLn $ "Flor do Mar client ready at http://localhost:" <> show serverPort <> "/"
  hFlush stdout

app :: Widget x ()
app = do
  localApi <- liftIO newLocalCombatApi
  initialSnapshot <-
    liftIO $
      snapshotOrDie
        "Could not start the caravela duel."
        =<< combatApiStartScenario (localCombatApi localApi) caravelaDuelScenarioId

  el "main" $ do
    el "style" $ text stylesheet
    mdo
      elClass "header" "app-header" $ do
        el "h1" $ text "Flor do Mar"
        elClass "div" "scenario" $ dynText (scenarioStatusText <$> snapshotDynamic)

      battleView snapshotDynamic

      elClass "section" "status-grid" $ do
        shipPanel "Player" PlayerShip snapshotDynamic
        shipPanel "Enemy" EnemyShip snapshotDynamic
        engagementPanel snapshotDynamic

      commandEvents <- controls snapshotDynamic
      tickEvent <- tickLossyFromPostBuildTime 0.8
      let
        api = localCombatApi localApi
        resetRequests =
          attachWith
            (\fallback () -> liftIO (keepSnapshot fallback <$> combatApiStartScenario api caravelaDuelScenarioId))
            (current snapshotDynamic)
            (controlReset commandEvents)
        commandRequests =
          attachWith
            (\fallback command -> liftIO (keepSnapshot fallback <$> combatApiSubmitCommand api command))
            (current snapshotDynamic)
            (controlCommand commandEvents)
        tickRequests =
          attachWith
            (\fallback _ -> liftIO (keepSnapshot fallback <$> combatApiAdvanceTick api))
            (current snapshotDynamic)
            tickEvent
      resetSnapshots <- performEvent resetRequests
      commandSnapshots <- performEvent commandRequests
      tickSnapshots <- performEvent tickRequests
      snapshotDynamic <-
        holdDyn
          initialSnapshot
          (leftmost [resetSnapshots, commandSnapshots, tickSnapshots])
      pure ()

data ControlEvents t = ControlEvents
  { controlReset :: Event t ()
  , controlCommand :: Event t CombatCommand
  }

controls :: Dynamic DomTimeline CombatSnapshot -> Widget x (ControlEvents DomTimeline)
controls snapshotDynamic =
  elClass "section" "controls" $ do
    resetEvent <- button "Reset duel"
    turnPortEvent <- button "Turn port"
    turnStarboardEvent <- button "Turn starboard"
    furlEvent <- button "Furl sails"
    battleSailsEvent <- button "Battle sails"
    fullSailsEvent <- button "Full sails"
    firePortEvent <- button "Fire port"
    fireStarboardEvent <- button "Fire starboard"
    let
      turnPortCommand =
        attachWith
          (\snapshot () -> SetHeading PlayerShip (Heading (playerHeading snapshot + 15)))
          (current snapshotDynamic)
          turnPortEvent
      turnStarboardCommand =
        attachWith
          (\snapshot () -> SetHeading PlayerShip (Heading (playerHeading snapshot - 15)))
          (current snapshotDynamic)
          turnStarboardEvent
      fixedCommands =
        leftmost
          [ SetSails PlayerShip SailsFurled <$ furlEvent
          , SetSails PlayerShip BattleSails <$ battleSailsEvent
          , SetSails PlayerShip FullSails <$ fullSailsEvent
          , FireBroadside PlayerShip EnemyShip Port <$ firePortEvent
          , FireBroadside PlayerShip EnemyShip Starboard <$ fireStarboardEvent
          ]
    pure
      ControlEvents
        { controlReset = resetEvent
        , controlCommand = leftmost [turnPortCommand, turnStarboardCommand, fixedCommands]
        }

shipPanel :: Text -> ShipId -> Dynamic DomTimeline CombatSnapshot -> Widget x ()
shipPanel title identity snapshotDynamic =
  elClass "article" "panel" $ do
    el "h2" $ text title
    dynText (shipLine identity <$> snapshotDynamic)

engagementPanel :: Dynamic DomTimeline CombatSnapshot -> Widget x ()
engagementPanel snapshotDynamic =
  elClass "article" "panel" $ do
    el "h2" $ text "Engagement"
    dynText (engagementLine <$> snapshotDynamic)

shipLine :: ShipId -> CombatSnapshot -> Text
shipLine identity snapshot =
  case findShipSnapshot identity snapshot of
    Nothing -> "No ship"
    Just ship ->
      Text.intercalate
        " | "
        [ "Hull " <> showText (shipSnapshotHull ship)
        , "Reload " <> showText (shipSnapshotReload ship)
        , "Heading " <> showHeading (shipSnapshotHeading ship)
        , "Sails " <> showText (shipSnapshotSails ship)
        ]

engagementLine :: CombatSnapshot -> Text
engagementLine snapshot =
  let
    engagement = combatSnapshotEngagement snapshot
   in
    Text.intercalate
      " | "
      [ "Range " <> showRounded (engagementRange engagement)
      , "Port " <> showText (engagementPlayerPortBroadside engagement)
      , "Starboard " <> showText (engagementPlayerStarboardBroadside engagement)
      ]

scenarioStatusText :: CombatSnapshot -> Text
scenarioStatusText snapshot =
  case combatSnapshotStatus snapshot of
    ScenarioRunning ->
      "Tick " <> showText (combatSnapshotTick snapshot) <> " | " <> scenarioSummaryName (combatSnapshotScenario snapshot)
    ScenarioFinished outcome ->
      "Tick " <> showText (combatSnapshotTick snapshot) <> " | " <> outcomeText outcome

outcomeText :: ScenarioOutcome -> Text
outcomeText outcome =
  case outcome of
    Winner PlayerShip -> "Victory"
    Winner EnemyShip -> "Defeat"
    MutualDestruction -> "Mutual destruction"

playerHeading :: CombatSnapshot -> Double
playerHeading snapshot =
  case findShipSnapshot PlayerShip snapshot of
    Nothing -> 0
    Just ship -> headingDegrees (shipSnapshotHeading ship)

findShipSnapshot :: ShipId -> CombatSnapshot -> Maybe ShipSnapshot
findShipSnapshot identity snapshot =
  case filter ((== identity) . shipSnapshotId) (combatSnapshotShips snapshot) of
    ship : _ -> Just ship
    [] -> Nothing

keepSnapshot :: CombatSnapshot -> Either CombatApiError CombatSnapshot -> CombatSnapshot
keepSnapshot fallback result =
  case result of
    Left _ -> fallback
    Right snapshot -> snapshot

snapshotOrDie :: String -> Either CombatApiError CombatSnapshot -> IO CombatSnapshot
snapshotOrDie message result =
  case result of
    Left _ -> fail message
    Right snapshot -> pure snapshot

showHeading :: Heading -> Text
showHeading (Heading degrees) = showRounded degrees

showRounded :: Double -> Text
showRounded = showText . (round :: Double -> Int)

showText :: (Show value) => value -> Text
showText = Text.pack . show

stylesheet :: Text
stylesheet =
  Text.unlines
    [ "html, body { margin: 0; min-height: 100%; background: #071017; color: #e6edf3; font-family: system-ui, sans-serif; }"
    , "main { max-width: 980px; margin: 0 auto; padding: 24px; }"
    , ".app-header { display: flex; align-items: baseline; justify-content: space-between; gap: 16px; margin-bottom: 16px; }"
    , "h1 { font-size: 28px; line-height: 1.1; margin: 0; }"
    , "h2 { font-size: 14px; line-height: 1.2; margin: 0 0 8px; color: #9fb6c9; }"
    , ".scenario { color: #a9c7da; font-size: 14px; }"
    , ".status-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; margin: 16px 0; }"
    , ".panel { border: 1px solid #203447; border-radius: 8px; padding: 12px; min-height: 74px; background: #0b1720; font-size: 13px; line-height: 1.45; }"
    , ".controls { display: flex; flex-wrap: wrap; gap: 8px; }"
    , "button { border: 1px solid #2d506a; border-radius: 6px; background: #102536; color: #e6edf3; padding: 8px 10px; font: inherit; cursor: pointer; }"
    , "button:hover { background: #17344a; }"
    , "@media (max-width: 760px) { main { padding: 14px; } .app-header { display: block; } .status-grid { grid-template-columns: 1fr; } }"
    ]
