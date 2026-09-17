{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Combat
  ( module FlorDoMar.Combat.Api
  , module FlorDoMar.Combat.Api.Local
  , module FlorDoMar.Combat.Domain
  , helloCombat
  , initialScenarioName
  )
where

import Data.Text (Text)
import FlorDoMar.Combat.Api
import FlorDoMar.Combat.Api.Local
import FlorDoMar.Combat.Domain

helloCombat :: Text
helloCombat = "Hello from the local combat core."

initialScenarioName :: Text
initialScenarioName = "Portuguese caravela duel"
