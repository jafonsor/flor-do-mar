module FlorDoMar.Combat.Api.Local
  ( LocalCombatApi
  , localCombatApi
  , localCombatApiActiveConfig
  , localCombatApiAttemptReloadConfig
  , localCombatApiReloadConfig
  , localCombatApiStartEngagement
  , localCombatScenarios
  , newConfiguredLocalCombatApi
  , newLocalCombatApi
  )
where

import Data.IORef
import Data.Text (Text)
import FlorDoMar.Combat.Api
import FlorDoMar.Combat.Config
import FlorDoMar.Combat.Domain

data LocalCombatApi = LocalCombatApi
  { localCombatApi :: CombatApi IO
  , localCombatApiActiveConfig :: IO (Maybe CombatConfig)
  , localCombatApiAttemptReloadConfig :: Either [ConfigDiagnostic] CombatConfig -> IO (Either [ConfigDiagnostic] (Maybe CombatConfig))
  , localCombatApiReloadConfig :: CombatConfig -> IO ()
  , localCombatApiStartEngagement :: Text -> Text -> IO (Either CombatApiError CombatSnapshot)
  }

data LocalCombatState = LocalCombatState
  { localActiveScenario :: Maybe ActiveScenario
  , localActiveConfig :: Maybe CombatConfig
  , localPendingCommands :: [CombatCommand]
  }

data ActiveScenario = ActiveScenario
  { activeScenarioSummary :: ScenarioSummary
  , activeCombatState :: CombatState
  , activeScenarioTick :: Maybe CombatConfig -> [CombatCommand] -> CombatState -> CombatState
  }

localCombatScenarios :: [ScenarioSummary]
localCombatScenarios = [caravelaDuelScenario]

newLocalCombatApi :: IO LocalCombatApi
newLocalCombatApi = newLocalCombatApiWith Nothing

newConfiguredLocalCombatApi :: CombatConfig -> IO LocalCombatApi
newConfiguredLocalCombatApi config = newLocalCombatApiWith (Just config)

newLocalCombatApiWith :: Maybe CombatConfig -> IO LocalCombatApi
newLocalCombatApiWith initialConfig = do
  stateRef <- newIORef (emptyLocalCombatState initialConfig)
  pure $
    LocalCombatApi
      { localCombatApi =
          CombatApi
            { combatApiListScenarios = pure localCombatScenarios
            , combatApiStartScenario = startLocalScenario stateRef
            , combatApiSubmitCommand = submitLocalCommand stateRef
            , combatApiAdvanceTick = advanceLocalTick stateRef
            , combatApiObserveSnapshot = observeLocalSnapshot stateRef
            }
      , localCombatApiActiveConfig = localActiveConfig <$> readIORef stateRef
      , localCombatApiAttemptReloadConfig = attemptReloadLocalConfig stateRef
      , localCombatApiReloadConfig = reloadLocalConfig stateRef
      , localCombatApiStartEngagement = startLocalEngagement stateRef
      }

emptyLocalCombatState :: Maybe CombatConfig -> LocalCombatState
emptyLocalCombatState config =
  LocalCombatState
    { localActiveScenario = Nothing
    , localActiveConfig = config
    , localPendingCommands = []
    }

startLocalScenario :: IORef LocalCombatState -> ScenarioId -> IO (Either CombatApiError CombatSnapshot)
startLocalScenario stateRef scenarioId =
  atomicModifyIORef' stateRef $ \localState ->
    case scenarioById (localActiveConfig localState) scenarioId of
      Nothing -> (localState, Left (CombatScenarioNotFound scenarioId))
      Just activeScenario ->
        let updatedState = localState {localActiveScenario = Just activeScenario, localPendingCommands = []}
         in (updatedState, Right (activeScenarioSnapshot (localActiveConfig updatedState) activeScenario))

startLocalEngagement :: IORef LocalCombatState -> Text -> Text -> IO (Either CombatApiError CombatSnapshot)
startLocalEngagement stateRef playerBoatKind enemyBoatKind =
  atomicModifyIORef' stateRef $ \localState ->
    case engagementByBoatKinds (localActiveConfig localState) playerBoatKind enemyBoatKind of
      Left errorValue -> (localState, Left errorValue)
      Right activeScenario ->
        let updatedState = localState {localActiveScenario = Just activeScenario, localPendingCommands = []}
         in (updatedState, Right (activeScenarioSnapshot (localActiveConfig updatedState) activeScenario))

submitLocalCommand :: IORef LocalCombatState -> CombatCommand -> IO (Either CombatApiError CombatSnapshot)
submitLocalCommand stateRef command =
  atomicModifyIORef' stateRef $ \localState ->
    case localActiveScenario localState of
      Nothing -> (localState, Left CombatScenarioNotStarted)
      Just activeScenario ->
        let
          updatedState =
            localState
              { localPendingCommands = localPendingCommands localState <> [command]
              }
         in
          (updatedState, Right (activeScenarioSnapshot (localActiveConfig updatedState) activeScenario))

advanceLocalTick :: IORef LocalCombatState -> IO (Either CombatApiError CombatSnapshot)
advanceLocalTick stateRef =
  atomicModifyIORef' stateRef $ \localState ->
    case localActiveScenario localState of
      Nothing -> (localState, Left CombatScenarioNotStarted)
      Just activeScenario ->
        let
          advancedScenario =
            activeScenario
              { activeCombatState =
                  activeScenarioTick activeScenario
                    (localActiveConfig localState)
                    (localPendingCommands localState)
                    (activeCombatState activeScenario)
              }
          updatedState =
            localState
              { localActiveScenario = Just advancedScenario
              , localPendingCommands = []
              }
         in
          (updatedState, Right (activeScenarioSnapshot (localActiveConfig updatedState) advancedScenario))

observeLocalSnapshot :: IORef LocalCombatState -> IO (Either CombatApiError CombatSnapshot)
observeLocalSnapshot stateRef = do
  localState <- readIORef stateRef
  pure $
    case localActiveScenario localState of
      Nothing -> Left CombatScenarioNotStarted
      Just activeScenario -> Right (activeScenarioSnapshot (localActiveConfig localState) activeScenario)

reloadLocalConfig :: IORef LocalCombatState -> CombatConfig -> IO ()
reloadLocalConfig stateRef config =
  atomicModifyIORef' stateRef $ \localState ->
    let refreshedScenario = fmap (refreshScenario config) (localActiveScenario localState)
     in (localState {localActiveConfig = Just config, localActiveScenario = refreshedScenario}, ())

-- | A failed load deliberately leaves the live state and its last valid config alone.
attemptReloadLocalConfig :: IORef LocalCombatState -> Either [ConfigDiagnostic] CombatConfig -> IO (Either [ConfigDiagnostic] (Maybe CombatConfig))
attemptReloadLocalConfig _ (Left diagnostics) = pure (Left diagnostics)
attemptReloadLocalConfig stateRef (Right config) =
  atomicModifyIORef' stateRef $ \localState ->
    if localActiveConfig localState == Just config
      then (localState, Right Nothing)
      else
        let refreshedScenario = fmap (refreshScenario config) (localActiveScenario localState)
            updatedState = localState {localActiveConfig = Just config, localActiveScenario = refreshedScenario}
         in (updatedState, Right (Just config))

scenarioById :: Maybe CombatConfig -> ScenarioId -> Maybe ActiveScenario
scenarioById maybeConfig scenarioId =
  if scenarioId == caravelaDuelScenarioId
    then
      Just $ case maybeConfig of
        Nothing -> legacyScenario
        Just config -> configuredScenario config
    else Nothing

legacyScenario :: ActiveScenario
legacyScenario =
  ActiveScenario
    { activeScenarioSummary = caravelaDuelScenario
    , activeCombatState = caravelaDuel
    , activeScenarioTick = const tickCombat
    }

configuredScenario :: CombatConfig -> ActiveScenario
configuredScenario config =
  ActiveScenario
    { activeScenarioSummary = caravelaDuelScenario
    , activeCombatState = configuredDefaultEngagement config
    , activeScenarioTick = configuredTick
    }

engagementByBoatKinds :: Maybe CombatConfig -> Text -> Text -> Either CombatApiError ActiveScenario
engagementByBoatKinds Nothing playerBoatKind _ = Left (CombatBoatKindNotFound playerBoatKind)
engagementByBoatKinds (Just config) playerBoatKind enemyBoatKind =
  case configuredEngagement config playerBoatKind enemyBoatKind of
    Nothing ->
      case findBoatConfig playerBoatKind config of
        Nothing -> Left (CombatBoatKindNotFound playerBoatKind)
        Just _ -> Left (CombatBoatKindNotFound enemyBoatKind)
    Just combatState ->
      Right
        ActiveScenario
          { activeScenarioSummary = caravelaDuelScenario
          , activeCombatState = combatState
          , activeScenarioTick = configuredTick
          }

refreshScenario :: CombatConfig -> ActiveScenario -> ActiveScenario
refreshScenario config activeScenario =
  activeScenario {activeCombatState = applyConfigToCombatState config (activeCombatState activeScenario)}

activeScenarioSnapshot :: Maybe CombatConfig -> ActiveScenario -> CombatSnapshot
activeScenarioSnapshot maybeConfig activeScenario =
  case maybeConfig of
    Nothing -> combatSnapshotFromState (activeScenarioSummary activeScenario) (activeCombatState activeScenario)
    Just config ->
      combatSnapshotFromStateWith
        (broadsideTuningForShip config)
        (activeScenarioSummary activeScenario)
        (activeCombatState activeScenario)

configuredTick :: Maybe CombatConfig -> [CombatCommand] -> CombatState -> CombatState
configuredTick maybeConfig =
  case maybeConfig of
    Just config -> tickConfiguredCombat config
    Nothing -> error "configured scenario is missing its combat config"
