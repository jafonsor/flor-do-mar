{-# LANGUAGE DerivingStrategies #-}

module FlorDoMar.Combat.Setup
  ( EngagementSetup (..)
  , SetupAction (..)
  , SetupState (..)
  , applySetupAction
  , initialSetupState
  , setupAllowsTicks
  , setupLaunchSelection
  )
where

import Data.Text (Text)

data EngagementSetup = EngagementSetup
  { engagementSetupPlayerBoatKind :: Text
  , engagementSetupEnemyBoatKind :: Text
  }
  deriving stock (Eq, Show)

data SetupState = SetupState
  { setupOverlayOpen :: Bool
  , setupSelectedEngagement :: EngagementSetup
  , setupActiveEngagement :: EngagementSetup
  -- | Client-session state. It deliberately has no persistence boundary.
  , setupDebugOverlaysEnabled :: Bool
  }
  deriving stock (Eq, Show)

data SetupAction
  = ToggleSetupOverlay
  | SelectPlayerBoatKind Text
  | SelectEnemyBoatKind Text
  | SetDebugOverlaysEnabled Bool
  | LaunchEngagement
  deriving stock (Eq, Show)

initialSetupState :: EngagementSetup -> SetupState
initialSetupState engagement =
  SetupState
    { setupOverlayOpen = False
    , setupSelectedEngagement = engagement
    , setupActiveEngagement = engagement
    , setupDebugOverlaysEnabled = True
    }

applySetupAction :: SetupAction -> SetupState -> SetupState
applySetupAction action state =
  case action of
    ToggleSetupOverlay -> state {setupOverlayOpen = not (setupOverlayOpen state)}
    SelectPlayerBoatKind boatKind
      | setupOverlayOpen state ->
          state
            { setupSelectedEngagement =
                (setupSelectedEngagement state)
                  { engagementSetupPlayerBoatKind = boatKind
                  }
            }
    SelectEnemyBoatKind boatKind
      | setupOverlayOpen state ->
          state
            { setupSelectedEngagement =
                (setupSelectedEngagement state)
                  { engagementSetupEnemyBoatKind = boatKind
                  }
            }
    SetDebugOverlaysEnabled enabled
      | setupOverlayOpen state -> state {setupDebugOverlaysEnabled = enabled}
    LaunchEngagement
      | setupOverlayOpen state ->
          state
            { setupOverlayOpen = False
            , setupActiveEngagement = setupSelectedEngagement state
            }
    _ -> state

setupAllowsTicks :: SetupState -> Bool
setupAllowsTicks = not . setupOverlayOpen

setupLaunchSelection :: SetupState -> Maybe EngagementSetup
setupLaunchSelection state =
  if setupOverlayOpen state
    then Just (setupSelectedEngagement state)
    else Nothing
