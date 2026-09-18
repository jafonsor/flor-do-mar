{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE MonoLocalBinds #-}

module Main (main) where

import Control.Monad.IO.Class (liftIO)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import FlorDoMar.Client.BattleView (battleView)
import FlorDoMar.Combat
import Language.Javascript.JSaddle.Warp (jsaddleApp, jsaddleOr)
import Network.Wai.Handler.Warp qualified as Warp
import Network.WebSockets (defaultConnectionOptions)
import Reflex.Dom.Core
import System.Exit (exitFailure)
import System.IO (hFlush, hPutStrLn, stderr, stdout)

main :: IO ()
main = do
  runtimeConfigDirectory <- runtimeCombatConfigDirectory
  combatConfig <- startupConfigOrDie =<< loadCombatConfig runtimeConfigDirectory
  logConfigDirectory runtimeConfigDirectory
  application <- jsaddleOr defaultConnectionOptions (mainWidget (app combatConfig)) jsaddleApp
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

logConfigDirectory :: FilePath -> IO ()
logConfigDirectory runtimeConfigDirectory = do
  putStrLn $ "[config] loading runtime config from " <> runtimeConfigDirectory
  hFlush stdout

app :: CombatConfig -> Widget x ()
app combatConfig = do
  localApi <- liftIO (newConfiguredLocalCombatApi combatConfig)
  initialSnapshot <-
    liftIO $
      snapshotOrDie
        "Could not start the caravela duel."
        =<< combatApiStartScenario (localCombatApi localApi) caravelaDuelScenarioId

  mdo
    (mainElement, ()) <- elAttr' "main" mainAttributes $ do
      el "style" $ text stylesheet
      mdo
        elClass "header" "app-header" $ do
          el "h1" $ text "Flor do Mar"
          elClass "div" "scenario" $ dynText (scenarioStatusText <$> snapshotDynamic)

        battleView snapshotDynamic

        reloadPoll <- tickLossyFromPostBuildTime 0.5
        reloadResults <- performEvent $ liftIO (reloadRuntimeConfig localApi) <$ reloadPoll
        let configReloads = fmapMaybe successfulReload reloadResults
        configDynamic <- holdDyn combatConfig configReloads

        setupActionsDynamic <-
          dyn $
            setupOverlay <$> (combatConfigBoats <$> configDynamic) <*> setupStateDynamic
        setupActions <- switchHold never setupActionsDynamic

        elClass "section" "status-grid" $ do
          shipPanel "Player" PlayerShip snapshotDynamic
          shipPanel "Enemy" EnemyShip snapshotDynamic
          engagementPanel snapshotDynamic

        commandEvents <- controls snapshotDynamic
        tickEvents <-
          widgetHold
            (tickLossyFromPostBuildTime (realToFrac (combatConfigTickSeconds combatConfig)))
            (tickLossyFromPostBuildTime . realToFrac . combatConfigTickSeconds <$> configReloads)
        let
          tickEvent = switchDyn tickEvents
          api = localCombatApi localApi
          escapeEvent = () <$ ffilter (== 27) (domEvent Keydown mainElement)
          setupEvents = leftmost [ToggleSetupOverlay <$ escapeEvent, setupActions]
          launchSelections =
            attachWithMaybe
              (\setup action ->
                  case action of
                    LaunchEngagement -> setupLaunchSelection setup
                    _ -> Nothing
              )
              (current setupStateDynamic)
              setupActions
          tickRequests =
            attachWith
              (\fallback _ -> liftIO (keepSnapshot fallback <$> combatApiAdvanceTick api))
              (current snapshotDynamic)
              (gate (current (setupAllowsTicks <$> setupStateDynamic)) tickEvent)
          commandRequests =
            attachWith
              (\fallback command -> liftIO (keepSnapshot fallback <$> combatApiSubmitCommand api command))
              (current snapshotDynamic)
              (controlCommand commandEvents)
          reloadRequests =
            attachWith
              (\fallback _ -> liftIO (keepSnapshot fallback <$> combatApiObserveSnapshot api))
              (current snapshotDynamic)
              configReloads
          launchRequests =
            attachWith
              (\fallback setup ->
                  liftIO $
                    keepSnapshot fallback
                      <$> localCombatApiStartEngagement
                        localApi
                        (engagementSetupPlayerBoatKind setup)
                        (engagementSetupEnemyBoatKind setup)
              )
              (current snapshotDynamic)
              launchSelections
        setupStateDynamic <- foldDyn applySetupAction (initialSetupState (engagementSetupFromSnapshot initialSnapshot)) setupEvents
        commandSnapshots <- performEvent commandRequests
        launchSnapshots <- performEvent launchRequests
        reloadSnapshots <- performEvent reloadRequests
        tickSnapshots <- performEvent tickRequests
        snapshotDynamic <-
          holdDyn
            initialSnapshot
            (leftmost [reloadSnapshots, launchSnapshots, commandSnapshots, tickSnapshots])
        pure ()
    pure ()

data ControlEvents t = ControlEvents
  { controlCommand :: Event t CombatCommand
  }

controls :: Dynamic DomTimeline CombatSnapshot -> Widget x (ControlEvents DomTimeline)
controls snapshotDynamic =
  elClass "section" "controls" $ do
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
        { controlCommand = leftmost [turnPortCommand, turnStarboardCommand, fixedCommands]
        }

setupOverlay :: [BoatConfig] -> SetupState -> Widget x (Event DomTimeline SetupAction)
setupOverlay boatConfigs setupState =
  if not (setupOverlayOpen setupState)
    then pure never
    else
      elClass "div" "setup-overlay" $
        elClass "section" "setup-panel" $ do
          el "h2" $ text "Engagement setup"
          playerSelection <- boatKindChoices "Player boat" boatConfigs (engagementSetupPlayerBoatKind selectedEngagement) SelectPlayerBoatKind
          enemySelection <- boatKindChoices "Enemy boat" boatConfigs (engagementSetupEnemyBoatKind selectedEngagement) SelectEnemyBoatKind
          launchEvent <- button "Launch Engagement"
          pure (leftmost [playerSelection, enemySelection, LaunchEngagement <$ launchEvent])
 where
  selectedEngagement = setupSelectedEngagement setupState

boatKindChoices :: Text -> [BoatConfig] -> Text -> (Text -> SetupAction) -> Widget x (Event DomTimeline SetupAction)
boatKindChoices label boatConfigs selectedBoatKind toAction =
  elClass "div" "boat-kind-choice" $ do
    el "h3" $ text label
    events <- mapM boatButton boatConfigs
    pure (leftmost events)
 where
  boatButton boat =
    elClass "div" (if boatConfigId boat == selectedBoatKind then "boat-kind selected" else "boat-kind") $ do
      clickEvent <- button (boatConfigDisplayName boat)
      pure (toAction (boatConfigId boat) <$ clickEvent)

engagementSetupFromSnapshot :: CombatSnapshot -> EngagementSetup
engagementSetupFromSnapshot snapshot =
  EngagementSetup
    { engagementSetupPlayerBoatKind = shipKind PlayerShip
    , engagementSetupEnemyBoatKind = shipKind EnemyShip
    }
 where
  shipKind identity =
    case findShipSnapshot identity snapshot of
      Just ship -> shipSnapshotBoatKind ship
      Nothing -> error "initial engagement is missing a ship"

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
        , "Target " <> showHeading (shipSnapshotTargetHeading ship)
        , "Speed " <> showRounded (shipSnapshotCurrentSpeed ship)
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
    Just ship -> headingDegrees (shipSnapshotTargetHeading ship)

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

startupConfigOrDie :: Either [ConfigDiagnostic] CombatConfig -> IO CombatConfig
startupConfigOrDie result =
  case result of
    Right combatConfig -> pure combatConfig
    Left diagnostics -> do
      mapM_ (hPutStrLn stderr . Text.unpack . renderConfigDiagnostic) diagnostics
      exitFailure

reloadRuntimeConfig :: LocalCombatApi -> IO (Either [ConfigDiagnostic] (Maybe CombatConfig))
reloadRuntimeConfig localApi = do
  result <- loadRuntimeCombatConfig
  reloadResult <- localCombatApiAttemptReloadConfig localApi result
  case reloadResult of
    Left diagnostics -> do
      hPutStrLn stderr "[config] hot reload failed; keeping last valid config."
      mapM_ (hPutStrLn stderr . Text.unpack . renderConfigDiagnostic) diagnostics
      hFlush stderr
      pure reloadResult
    Right Nothing -> pure reloadResult
    Right (Just config) -> do
      logConfigReload config
      pure reloadResult

logConfigReload :: CombatConfig -> IO ()
logConfigReload config = do
  hPutStrLn stdout $
    Text.unpack $
      "[config] hot reload applied: tick_seconds="
        <> showText (combatConfigTickSeconds config)
        <> ", boats="
        <> Text.intercalate ", " (boatReloadSummary <$> combatConfigBoats config)
  hFlush stdout

boatReloadSummary :: BoatConfig -> Text
boatReloadSummary boat =
  boatConfigId boat
    <> "{hull="
    <> showText (boatConfigMaxHull boat)
    <> ", size="
    <> showText (boatConfigRenderedLength boat)
    <> "x"
    <> showText (boatConfigRenderedWidth boat)
    <> ", speed="
    <> showText (boatConfigBattleSpeed boat)
    <> "/"
    <> showText (boatConfigMaxSpeed boat)
    <> ", broadside="
    <> showText (boatConfigBroadsideDamage boat)
    <> "@"
    <> showText (boatConfigBroadsideRange boat)
    <> "}"

successfulReload :: Either [ConfigDiagnostic] (Maybe CombatConfig) -> Maybe CombatConfig
successfulReload result =
  case result of
    Left _ -> Nothing
    Right config -> config

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
    , ".setup-overlay { position: fixed; inset: 0; z-index: 10; display: grid; place-items: center; padding: 24px; background: rgba(2, 10, 16, 0.8); }"
    , ".setup-panel { width: min(440px, 100%); border: 1px solid #3d627e; border-radius: 8px; padding: 20px; background: #0b1720; box-shadow: 0 16px 48px rgba(0, 0, 0, 0.45); }"
    , ".boat-kind-choice { margin: 16px 0; }"
    , ".boat-kind-choice h3 { margin: 0 0 8px; font-size: 14px; color: #9fb6c9; }"
    , ".boat-kind { display: inline-block; margin: 0 8px 8px 0; }"
    , ".boat-kind.selected button { border-color: #77c7e8; background: #173f56; }"
    , "@media (max-width: 760px) { main { padding: 14px; } .app-header { display: block; } .status-grid { grid-template-columns: 1fr; } }"
    ]

mainAttributes :: Map Text Text
mainAttributes = Map.fromList [("tabindex", "0"), ("autofocus", "autofocus")]
