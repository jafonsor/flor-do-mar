module FlorDoMar.Combat.Api.Local
  ( LocalCombatApi
  , localCombatApi
  , localCombatScenarios
  , newLocalCombatApi
  )
where

import Data.IORef
import FlorDoMar.Combat.Api
import FlorDoMar.Combat.Domain

newtype LocalCombatApi = LocalCombatApi
  { localCombatApi :: CombatApi IO
  }

data LocalCombatState = LocalCombatState
  { localActiveScenario :: Maybe ActiveScenario
  , localPendingCommands :: [CombatCommand]
  }

data ActiveScenario = ActiveScenario
  { activeScenarioSummary :: ScenarioSummary
  , activeCombatState :: CombatState
  }

localCombatScenarios :: [ScenarioSummary]
localCombatScenarios = [caravelaDuelScenario]

newLocalCombatApi :: IO LocalCombatApi
newLocalCombatApi = do
  stateRef <- newIORef emptyLocalCombatState
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
      }

emptyLocalCombatState :: LocalCombatState
emptyLocalCombatState =
  LocalCombatState
    { localActiveScenario = Nothing
    , localPendingCommands = []
    }

startLocalScenario :: IORef LocalCombatState -> ScenarioId -> IO (Either CombatApiError CombatSnapshot)
startLocalScenario stateRef scenarioId =
  case localScenarioById scenarioId of
    Nothing -> pure (Left (CombatScenarioNotFound scenarioId))
    Just activeScenario -> do
      writeIORef
        stateRef
        LocalCombatState
          { localActiveScenario = Just activeScenario
          , localPendingCommands = []
          }
      pure (Right (activeScenarioSnapshot activeScenario))

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
          (updatedState, Right (activeScenarioSnapshot activeScenario))

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
                  tickCombat
                    (localPendingCommands localState)
                    (activeCombatState activeScenario)
              }
          updatedState =
            localState
              { localActiveScenario = Just advancedScenario
              , localPendingCommands = []
              }
         in
          (updatedState, Right (activeScenarioSnapshot advancedScenario))

observeLocalSnapshot :: IORef LocalCombatState -> IO (Either CombatApiError CombatSnapshot)
observeLocalSnapshot stateRef = do
  localState <- readIORef stateRef
  pure $
    case localActiveScenario localState of
      Nothing -> Left CombatScenarioNotStarted
      Just activeScenario -> Right (activeScenarioSnapshot activeScenario)

localScenarioById :: ScenarioId -> Maybe ActiveScenario
localScenarioById scenarioId =
  if scenarioId == caravelaDuelScenarioId
    then
      Just
        ActiveScenario
          { activeScenarioSummary = caravelaDuelScenario
          , activeCombatState = caravelaDuel
          }
    else Nothing

activeScenarioSnapshot :: ActiveScenario -> CombatSnapshot
activeScenarioSnapshot activeScenario =
  combatSnapshotFromState
    (activeScenarioSummary activeScenario)
    (activeCombatState activeScenario)
