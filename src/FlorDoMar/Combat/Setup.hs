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
  }
  deriving stock (Eq, Show)

data SetupAction
  = ToggleSetupOverlay
  | SelectPlayerBoatKind Text
  | SelectEnemyBoatKind Text
  | LaunchEngagement
  deriving stock (Eq, Show)

initialSetupState :: EngagementSetup -> SetupState
initialSetupState engagement =
  SetupState
    { setupOverlayOpen = False
    , setupSelectedEngagement = engagement
    , setupActiveEngagement = engagement
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
