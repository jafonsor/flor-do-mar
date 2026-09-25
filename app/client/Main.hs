{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE MonoLocalBinds #-}

module Main (main) where

import Control.Monad.IO.Class (liftIO)
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Time.Clock.POSIX (getPOSIXTime)
import FlorDoMar.Client.BattleView (battleView)
import FlorDoMar.Combat
import Language.Javascript.JSaddle.Warp (jsaddleApp, jsaddleOr)
import Network.HTTP.Types qualified as Http
import Network.Wai qualified as Wai
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
  epoch <- processEpoch
  application <-
    jsaddleOr
      defaultConnectionOptions
      (mainWidget (app combatConfig))
      jsaddleApp
  Warp.runSettings serverSettings (serveEpochPage epoch application)

serverPort :: Int
serverPort = 3911

-- | Identifies this client process to the pages it serves.
--
-- jsaddle keeps a page's sync handlers in process memory, so a page that
-- outlives the process serving it can never make another callback: every
-- synchronous sync POST is answered with @jsaddle missing sync message handler@,
-- and the page's DOM stays on screen while its simulation stops advancing. It
-- looks frozen while its main thread is perfectly healthy.
--
-- That is the normal edit/rebuild/restart loop, so a page has to be able to
-- notice that the process behind it changed and reload itself. This token is how
-- it notices: the page is served with the token of the process that served it,
-- and polls @\/epoch@ for the token of the process that is serving it now.
processEpoch :: IO Text
processEpoch = do
  startedAt <- getPOSIXTime
  pure . Text.pack . show $ (round ((realToFrac startedAt :: Double) * 1000) :: Integer)

-- | Serve the page shell with the restart check in it.
--
-- The document jsaddle serves is an empty shell that loads @\/jsaddle.js@ and
-- lets the app build the body, so the check has to be injected here rather than
-- rendered by the widget: a page that has already lost its session cannot reach
-- the widget at all.
--
-- The check compares the token of the process that served this document with the
-- token of whoever answers @\/epoch@ now. A match means the page still belongs to
-- this process and it boots normally; a mismatch means the peer is gone, so it
-- boots empty and a fresh copy is loaded. Storing the token means a page that
-- somehow keeps seeing a mismatch reloads once instead of looping.
serveEpochPage :: Text -> Wai.Middleware
serveEpochPage epoch application request respond
  -- A websocket upgrade is a GET to the same path as the page itself, so the
  -- upgrade has to be recognised here: answering it with the page would leave
  -- jsaddle unable to connect at all.
  | isWebSocketUpgrade request = application request respond
  | otherwise =
      case (Wai.requestMethod request, Wai.pathInfo request) of
        ("GET", []) -> respond (Wai.responseLBS Http.status200 [("Content-Type", "text/html; charset=utf-8")] (indexPage epoch))
        ("GET", ["epoch"]) -> respond (epochResponse epoch)
        _ -> application request respond

isWebSocketUpgrade :: Wai.Request -> Bool
isWebSocketUpgrade request =
  lookup "Upgrade" (Wai.requestHeaders request) == Just "websocket"

indexPage :: Text -> ByteString
indexPage epoch =
  LBS.fromStrict . encodeUtf8 $
    Text.replace
      "</head>"
      ("<script>" <> watchScript epoch <> "</script></head>")
      (decodeUtf8 (LBS.toStrict jsaddleIndexHtml))

jsaddleIndexHtml :: ByteString
jsaddleIndexHtml =
  "<!DOCTYPE html>\n<html>\n<head>\n<title>JSaddle</title>\n</head>\n<body>\n</body>\n<script src=\"/jsaddle.js\"></script>\n</html>\n"

watchScript :: Text -> Text
watchScript epoch =
  Text.unlines
    [ "(function () {"
    , "  var token = \"" <> epoch <> "\";"
    , "  var reloadForNewClient = function () {"
    , "    try {"
    , "      var stored = window.localStorage.getItem('flor-do-mar-epoch');"
    , "      window.localStorage.setItem('flor-do-mar-epoch', token);"
    , "      if (stored !== null && stored !== token) { window.location.reload(); return true; }"
    , "    } catch (error) { return false; }"
    , "    return false;"
    , "  };"
    , "  if (reloadForNewClient()) return;"
    , "  setInterval(function () {"
    , "    var request = new XMLHttpRequest();"
    , "    request.open('GET', '/epoch', true);"
    , "    request.onreadystatechange = function () {"
    , "      if (request.readyState !== XMLHttpRequest.DONE || request.status !== 200) return;"
    , "      if (request.responseText !== token) window.location.reload();"
    , "    };"
    , "    request.send();"
    , "  }, 2000);"
    , "})();"
    ]

epochResponse :: Text -> Wai.Response
epochResponse epoch =
  Wai.responseLBS
    Http.status200
    [("Content-Type", "text/plain; charset=utf-8"), ("Cache-Control", "no-store")]
    (LBS.fromStrict (encodeUtf8 epoch))

-- | Loopback only, and pinned to one address family on purpose.
--
-- Warp's default host is @*@, and on a dual-stack machine a second instance does
-- not fail to bind: the first instance's address is taken, so it silently falls
-- through to the other family and both processes end up listening on 3911. That
-- is worse than an error. jsaddle keeps its per-connection sync handlers in
-- process memory, so a page whose websocket lands on one instance and whose
-- synchronous sync request lands on the other is told
-- \"jsaddle missing sync message handler\" and its main thread stalls. Pinning
-- the host makes a second instance fail loudly with \"address already in use\".
serverSettings :: Warp.Settings
serverSettings =
  Warp.setBeforeMainLoop logServerReady $
    Warp.setHost "127.0.0.1" $
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

        navigationCommandEvents <- battleView snapshotDynamic (setupOverlayOpen <$> setupStateDynamic) (setupDebugOverlaysEnabled <$> setupStateDynamic)

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
          gunneryPanel snapshotDynamic

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
              navigationCommandEvents
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
          debugOverlays <- debugOverlayCheckbox (setupDebugOverlaysEnabled setupState)
          launchEvent <- button "Launch Engagement"
          pure (leftmost [playerSelection, enemySelection, debugOverlays, LaunchEngagement <$ launchEvent])
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

debugOverlayCheckbox :: Bool -> Widget x (Event DomTimeline SetupAction)
debugOverlayCheckbox enabled =
  elClass "label" "debug-overlay-toggle" $ do
    debugCheckbox <-
      inputElement $
        (def :: InputElementConfig EventResult DomTimeline GhcjsDomSpace)
          { _inputElementConfig_initialChecked = enabled
          , _inputElementConfig_elementConfig =
              (def :: ElementConfig EventResult DomTimeline GhcjsDomSpace)
                { _elementConfig_initialAttributes = Map.fromList [("type", "checkbox")]
                }
          }
    text " Debug overlays"
    pure (SetDebugOverlaysEnabled <$> updated (_inputElement_checked debugCheckbox))

engagementSetupFromSnapshot :: CombatSnapshot -> EngagementSetup
engagementSetupFromSnapshot snapshot =
  EngagementSetup
    { engagementSetupPlayerBoatKind = shipKind PlayerShip
    , engagementSetupEnemyBoatKind = shipKind EnemyShip
    }
 where
  shipKind identity =
    case findSnapshotShip identity snapshot of
      Just ship -> shipSnapshotBoatKind ship
      Nothing -> error "initial engagement is missing a ship"

shipPanel :: Text -> ShipId -> Dynamic DomTimeline CombatSnapshot -> Widget x ()
shipPanel title identity snapshotDynamic =
  elClass "article" "panel" $ do
    el "h2" $ text title
    dynText (shipLine identity <$> snapshotDynamic)

-- | The text readout of each ship's fire-control state.
--
-- It stays beside the gun panel on purpose. The client's DOM text is the
-- cheapest ground truth a browser harness has for lock, permission and reload
-- (docs/agents/testing-and-tooling.md), and it is the only place those numbers
-- are labelled per ship: the panel over the canvas carries no ship labels,
-- because the harnesses split the body text on the words Player and Enemy.
gunneryPanel :: Dynamic DomTimeline CombatSnapshot -> Widget x ()
gunneryPanel snapshotDynamic =
  elClass "article" "panel" $ do
    el "h2" $ text "Gunnery"
    dynText (gunneryLine <$> snapshotDynamic)

shipLine :: ShipId -> CombatSnapshot -> Text
shipLine identity snapshot =
  case findSnapshotShip identity snapshot of
    Nothing -> "No ship"
    Just ship ->
      Text.intercalate
        " | "
        [ "Hull " <> showText (shipSnapshotHull ship)
        , "Heading " <> showHeading (shipSnapshotHeading ship)
        , "Target " <> showHeading (shipSnapshotTargetHeading ship)
        , "Speed " <> showRounded (shipSnapshotCurrentSpeed ship)
        , "Sails " <> showText (shipSnapshotSails ship)
        ]

gunneryLine :: CombatSnapshot -> Text
gunneryLine snapshot =
  Text.intercalate
    " | "
    [ "Player " <> shipGunneryLine PlayerShip snapshot
    , "Enemy " <> shipGunneryLine EnemyShip snapshot
    ]

shipGunneryLine :: ShipId -> CombatSnapshot -> Text
shipGunneryLine identity snapshot =
  case findSnapshotShip identity snapshot of
    Nothing -> "No ship"
    Just ship ->
      Text.intercalate
        ", "
        [ "Locked " <> maybe "none" showText (shipSnapshotLockedTarget ship)
        , "Fire at will " <> showText (shipSnapshotFirePermission ship)
        , "Reload "
            <> showText (shipSnapshotReloadTicksRemaining ship)
            <> " of "
            <> showText (shipSnapshotReloadTicksTotal ship)
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
    , "button { border: 1px solid #2d506a; border-radius: 6px; background: #102536; color: #e6edf3; padding: 8px 10px; font: inherit; cursor: pointer; }"
    , "button:hover { background: #17344a; }"
    , ".battle-view { position: relative; max-width: 760px; }"
    -- The panel is an overlay: the container takes no pointer events, and only
    -- its controls ask for them back. A container that captured them would
    -- swallow the canvas mousedown/mousemove/mouseup stream navigation needs.
    , ".gun-panel { position: absolute; top: 8px; left: 8px; display: flex; align-items: center; gap: 10px; padding: 6px 8px; border: 1px solid #203447; border-radius: 8px; background: rgba(7, 16, 23, 0.72); pointer-events: none; }"
    , ".gun-panel .gun-control { pointer-events: auto; }"
    , ".fire-toggle.disengaged { border-color: #2d506a; color: #9fb6c9; }"
    , ".fire-toggle.armed { border-color: #f0b429; background: #3a2a08; color: #ffd166; }"
    , ".gun-control[disabled] { opacity: 0.45; cursor: not-allowed; }"
    , ".gun-control[disabled]:hover { background: #102536; }"
    , ".lock-control.inactive { display: none; }"
    , ".reload-circle { display: block; }"
    , ".reload-track { fill: none; stroke: #22384a; stroke-width: 3; }"
    , ".reload-fill { fill: none; stroke-width: 3; stroke-linecap: round; }"
    , ".reload-circle.armed .reload-fill { stroke: #ffd166; }"
    , ".reload-circle.disengaged .reload-fill { stroke: #6f8ea3; }"
    , ".setup-overlay { position: fixed; inset: 0; z-index: 10; display: grid; place-items: center; padding: 24px; background: rgba(2, 10, 16, 0.8); }"
    , ".setup-panel { width: min(440px, 100%); border: 1px solid #3d627e; border-radius: 8px; padding: 20px; background: #0b1720; box-shadow: 0 16px 48px rgba(0, 0, 0, 0.45); }"
    , ".boat-kind-choice { margin: 16px 0; }"
    , ".boat-kind-choice h3 { margin: 0 0 8px; font-size: 14px; color: #9fb6c9; }"
    , ".boat-kind { display: inline-block; margin: 0 8px 8px 0; }"
    , ".boat-kind.selected button { border-color: #77c7e8; background: #173f56; }"
    , ".debug-overlay-toggle { display: block; margin: 16px 0; font-size: 14px; }"
    , "@media (max-width: 760px) { main { padding: 14px; } .app-header { display: block; } .status-grid { grid-template-columns: 1fr; } }"
    ]

mainAttributes :: Map Text Text
mainAttributes = Map.fromList [("tabindex", "0"), ("autofocus", "autofocus")]
