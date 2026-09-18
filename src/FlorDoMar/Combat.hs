{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Combat
  ( module FlorDoMar.Combat.Api
  , module FlorDoMar.Combat.Api.Local
  , module FlorDoMar.Combat.Config
  , module FlorDoMar.Combat.Domain
  , module FlorDoMar.Combat.Setup
  , helloCombat
  , initialScenarioName
  )
where

import Data.Text (Text)
import FlorDoMar.Combat.Api
import FlorDoMar.Combat.Api.Local
import FlorDoMar.Combat.Config
import FlorDoMar.Combat.Domain
import FlorDoMar.Combat.Setup

helloCombat :: Text
helloCombat = "Hello from the local combat core."

initialScenarioName :: Text
initialScenarioName = "Portuguese caravela duel"
