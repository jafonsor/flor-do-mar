{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module FlorDoMar.Combat.Config
  ( BoatConfig (..)
  , CombatConfig (..)
  , ConfigDiagnostic (..)
  , PhysicsConfig (..)
  , configuredEngagement
  , configuredDefaultEngagement
  , applyConfigToCombatState
  , broadsideTuningForShip
  , combatConfigTickSeconds
  , findBoatConfig
  , loadCombatConfig
  , loadRuntimeCombatConfig
  , movementPhysicsForShip
  , renderConfigDiagnostic
  , runtimeCombatConfigDirectory
  , tickConfiguredCombat
  )
where

import Control.Exception (IOException, try)
import Data.List (find)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import FlorDoMar.Combat.Domain
import Paths_flor_do_mar (getDataFileName)
import System.Directory (doesDirectoryExist)
import System.FilePath ((</>), takeBaseName)
import Text.Read (readMaybe)

data PhysicsConfig = PhysicsConfig
  { physicsTickSeconds :: Double
  }
  deriving stock (Eq, Show)

data BoatConfig = BoatConfig
  { boatConfigId :: Text
  , boatConfigDisplayName :: Text
  , boatConfigMaxHull :: Int
  , boatConfigRenderedLength :: Double
  , boatConfigRenderedWidth :: Double
  , boatConfigBattleSpeed :: Double
  , boatConfigMaxSpeed :: Double
  , boatConfigAcceleration :: Double
  , boatConfigDeceleration :: Double
  , boatConfigTurnRate :: Double
  , boatConfigIdealTurnSpeed :: Double
  , boatConfigYawAcceleration :: Double
  , boatConfigBroadsideRange :: Double
  , boatConfigBroadsideDamage :: Int
  , boatConfigReloadTicks :: Int
  , boatConfigFiringArcDegrees :: Double
  }
  deriving stock (Eq, Show)

data CombatConfig = CombatConfig
  { combatConfigPhysics :: PhysicsConfig
  , combatConfigBoats :: [BoatConfig]
  }
  deriving stock (Eq, Show)

data ConfigDiagnostic = ConfigDiagnostic
  { configDiagnosticFile :: FilePath
  , configDiagnosticLine :: Maybe Int
  , configDiagnosticColumn :: Maybe Int
  , configDiagnosticField :: Maybe Text
  , configDiagnosticMessage :: Text
  , configDiagnosticHint :: Text
  }
  deriving stock (Eq, Show)

data TomlValue
  = TomlText Text
  | TomlNumber Double

data FieldValue = FieldValue
  { fieldValueLine :: Int
  , fieldValueColumn :: Int
  , fieldValue :: TomlValue
  }

type Fields = Map Text FieldValue

loadRuntimeCombatConfig :: IO (Either [ConfigDiagnostic] CombatConfig)
loadRuntimeCombatConfig = do
  runtimeDirectory <- runtimeCombatConfigDirectory
  loadCombatConfig runtimeDirectory

runtimeCombatConfigDirectory :: IO FilePath
runtimeCombatConfigDirectory = do
  editableDirectoryExists <- doesDirectoryExist editableRuntimeConfigDirectory
  if editableDirectoryExists
    then pure editableRuntimeConfigDirectory
    else getDataFileName editableRuntimeConfigDirectory

editableRuntimeConfigDirectory :: FilePath
editableRuntimeConfigDirectory = "config/combat"

loadCombatConfig :: FilePath -> IO (Either [ConfigDiagnostic] CombatConfig)
loadCombatConfig configDirectory = do
  physicsResult <- loadTomlFile (configDirectory </> "physics.toml")
  bigResult <- loadTomlFile (configDirectory </> "boats" </> "big.toml")
  smallResult <- loadTomlFile (configDirectory </> "boats" </> "small.toml")
  let
    physicsPath = configDirectory </> "physics.toml"
    bigPath = configDirectory </> "boats" </> "big.toml"
    smallPath = configDirectory </> "boats" </> "small.toml"
    physicsValidation = physicsResult >>= validatePhysics physicsPath
    bigValidation = bigResult >>= validateBoat bigPath
    smallValidation = smallResult >>= validateBoat smallPath
    diagnostics = concat [voidResult physicsValidation, voidResult bigValidation, voidResult smallValidation]
  pure $
    if null diagnostics
      then
        case (physicsValidation, bigValidation, smallValidation) of
          (Right physics, Right big, Right small) -> Right (CombatConfig physics [big, small])
          _ -> Left diagnostics
      else Left diagnostics

configuredDefaultEngagement :: CombatConfig -> CombatState
configuredDefaultEngagement config =
  case configuredEngagement config "big" "small" of
    Just engagement -> engagement
    Nothing -> error "validated combat config is missing the default boat kinds"

configuredEngagement :: CombatConfig -> Text -> Text -> Maybe CombatState
configuredEngagement config playerBoatKind enemyBoatKind = do
  playerBoat <- findBoatConfig playerBoatKind config
  enemyBoat <- findBoatConfig enemyBoatKind config
  pure $
    CombatState
    { combatTick = 0
    , combatWind = Wind {windDirection = Heading 0, windSpeed = 0}
    , combatPlayer = shipFromConfig PlayerShip (Point 0 0) (Heading 0) playerBoat
    , combatEnemy = shipFromConfig EnemyShip (Point 0 80) (Heading 180) enemyBoat
    , combatEnemyOrbitAutopilot = EnemyOrbitAutopilot (Point 0 80) 0
    , combatStatus = ScenarioRunning
    }

-- | Retain per-instance state while refreshing values owned by a boat kind.
applyConfigToCombatState :: CombatConfig -> CombatState -> CombatState
applyConfigToCombatState config state =
  state
    { combatPlayer = applyConfigToShip config (combatPlayer state)
    , combatEnemy = applyConfigToShip config (combatEnemy state)
    }

-- | Refresh the values a boat kind owns while retaining per-instance state.
--
-- A ship's locked target and its permission to fire are live state, like the
-- reload counter and the damage taken, so they are deliberately not refreshed
-- here: a config hot reload must not release a lock or disarm the guns.
applyConfigToShip :: CombatConfig -> Ship -> Ship
applyConfigToShip config ship =
  case findBoatConfig (shipBoatKind ship) config of
    Nothing -> ship
    Just boat ->
      let refreshedHull = max 0 (boatConfigMaxHull boat - shipDamageTaken ship)
       in ship
            { shipDisplayName = boatConfigDisplayName boat
            , shipMaxHull = boatConfigMaxHull boat
            , shipHull = refreshedHull
            , shipRenderedLength = boatConfigRenderedLength boat
            , shipRenderedWidth = boatConfigRenderedWidth boat
            , shipTargetSpeed = max 0 (min (boatConfigMaxSpeed boat) (shipTargetSpeed ship))
            , shipNavigationOrder = if refreshedHull <= 0 then Nothing else shipNavigationOrder ship
            }
combatConfigTickSeconds :: CombatConfig -> Double
combatConfigTickSeconds = physicsTickSeconds . combatConfigPhysics

tickConfiguredCombat :: CombatConfig -> [CombatCommand] -> CombatState -> CombatState
tickConfiguredCombat config =
  tickCombatWithTuning
    (combatConfigTickSeconds config)
    (movementPhysicsForShip config)
    (broadsideTuningForShip config)

movementPhysicsForShip :: CombatConfig -> Ship -> MovementPhysics
movementPhysicsForShip config ship =
  case findBoatConfig (shipBoatKind ship) config of
    Just boat ->
      MovementPhysics
        { movementBattleSpeed = boatConfigBattleSpeed boat
        , movementMaxSpeed = boatConfigMaxSpeed boat
        , movementAcceleration = boatConfigAcceleration boat
        , movementDeceleration = boatConfigDeceleration boat
        , movementTurnRate = boatConfigTurnRate boat
        , movementIdealTurnSpeed = boatConfigIdealTurnSpeed boat
        , movementYawAcceleration = boatConfigYawAcceleration boat
        }
    Nothing -> error "combat state references a boat kind absent from its config"

broadsideTuningForShip :: CombatConfig -> Ship -> BroadsideTuning
broadsideTuningForShip config ship =
  case findBoatConfig (shipBoatKind ship) config of
    Just boat ->
      BroadsideTuning
        { broadsideTuningRange = boatConfigBroadsideRange boat
        , broadsideTuningDamage = boatConfigBroadsideDamage boat
        , broadsideTuningReloadTicks = boatConfigReloadTicks boat
        , broadsideTuningFiringArcDegrees = boatConfigFiringArcDegrees boat
        }
    Nothing -> error "combat state references a boat kind absent from its config"

findBoatConfig :: Text -> CombatConfig -> Maybe BoatConfig
findBoatConfig boatId = find ((== boatId) . boatConfigId) . combatConfigBoats

shipFromConfig :: ShipId -> Point -> Heading -> BoatConfig -> Ship
shipFromConfig identity position heading boat =
  Ship
    { shipId = identity
    , shipBoatKind = boatConfigId boat
    , shipDisplayName = boatConfigDisplayName boat
    , shipPosition = position
    , shipHeading = heading
    , shipTargetHeading = heading
    , shipSails = BattleSails
    , shipCurrentSpeed = 0
    , shipTargetSpeed = boatConfigBattleSpeed boat
    , shipCurrentYawRate = 0
    , shipNavigationOrder = Nothing
    , shipMaxHull = boatConfigMaxHull boat
    , shipDamageTaken = 0
    , shipHull = boatConfigMaxHull boat
    , shipRenderedLength = boatConfigRenderedLength boat
    , shipRenderedWidth = boatConfigRenderedWidth boat
    , shipReload = 0
    , shipLockedTarget = Nothing
    , shipFirePermission = False
    }

loadTomlFile :: FilePath -> IO (Either [ConfigDiagnostic] Fields)
loadTomlFile path = do
  contentsResult <- try (Text.IO.readFile path) :: IO (Either IOException Text)
  pure $
    case contentsResult of
      Left exception -> Left [diagnostic path Nothing Nothing Nothing ("Could not read config: " <> Text.pack (show exception)) "Check that the required runtime config asset exists and is readable."]
      Right contents -> parseToml path contents

parseToml :: FilePath -> Text -> Either [ConfigDiagnostic] Fields
parseToml path contents =
  let (fields, diagnostics) = foldl parseLine (Map.empty, []) (zip [1 ..] (Text.lines contents))
   in if null diagnostics then Right fields else Left diagnostics
 where
  parseLine (fields, diagnostics) (lineNumber, rawLine) =
    let line = Text.strip (Text.takeWhile (/= '#') rawLine)
     in if Text.null line
          then (fields, diagnostics)
          else
            case Text.breakOn "=" line of
              (_, remainder) | Text.null remainder ->
                (fields, diagnostics <> [diagnostic path (Just lineNumber) Nothing Nothing "Expected a TOML key/value assignment." "Use `field_name = value`." ])
              (rawKey, rawValue) ->
                let key = Text.strip rawKey
                    valueText = Text.strip (Text.drop 1 rawValue)
                    column = Text.length rawKey + 2
                 in if Text.null key || Text.null valueText
                      then (fields, diagnostics <> [diagnostic path (Just lineNumber) (Just column) Nothing "Expected both a key and a value." "Use `field_name = value`." ])
                      else
                        case parseValue valueText of
                          Nothing -> (fields, diagnostics <> [diagnostic path (Just lineNumber) (Just column) (Just key) "Expected a quoted string or numeric TOML value." "Quote text values and use a decimal number for numeric values."])
                          Just value ->
                            if Map.member key fields
                              then (fields, diagnostics <> [diagnostic path (Just lineNumber) (Just column) (Just key) "Duplicate field." "Keep exactly one value for this field."])
                              else (Map.insert key (FieldValue lineNumber column value) fields, diagnostics)

parseValue :: Text -> Maybe TomlValue
parseValue valueText
  | Text.length valueText >= 2 && Text.head valueText == '"' && Text.last valueText == '"' = Just (TomlText (Text.init (Text.tail valueText)))
  | otherwise = TomlNumber <$> readMaybe (Text.unpack valueText)

validatePhysics :: FilePath -> Fields -> Either [ConfigDiagnostic] PhysicsConfig
validatePhysics path fields =
  case requiredPositiveNumber path "tick_seconds" fields of
    (Just tickSeconds, []) -> Right (PhysicsConfig tickSeconds)
    (_, diagnostics) -> Left diagnostics

validateBoat :: FilePath -> Fields -> Either [ConfigDiagnostic] BoatConfig
validateBoat path fields =
  case values of
    ( Just boatIdValue, Just displayNameValue, Just maxHullValue, Just renderedLengthValue, Just renderedWidthValue, Just battleSpeedValue, Just maxSpeedValue, Just accelerationValue, Just decelerationValue, Just turnRateValue, Just idealTurnSpeedValue, Just yawAccelerationValue, Just broadsideRangeConfigValue, Just broadsideDamageConfigValue, Just reloadTicksConfigValue, Just firingArcDegreesValue )
      | null allDiagnostics && boatIdValue == Text.pack (takeBaseName path) ->
          Right BoatConfig {boatConfigId = boatIdValue, boatConfigDisplayName = displayNameValue, boatConfigMaxHull = maxHullValue, boatConfigRenderedLength = renderedLengthValue, boatConfigRenderedWidth = renderedWidthValue, boatConfigBattleSpeed = battleSpeedValue, boatConfigMaxSpeed = maxSpeedValue, boatConfigAcceleration = accelerationValue, boatConfigDeceleration = decelerationValue, boatConfigTurnRate = turnRateValue, boatConfigIdealTurnSpeed = idealTurnSpeedValue, boatConfigYawAcceleration = yawAccelerationValue, boatConfigBroadsideRange = broadsideRangeConfigValue, boatConfigBroadsideDamage = broadsideDamageConfigValue, boatConfigReloadTicks = reloadTicksConfigValue, boatConfigFiringArcDegrees = firingArcDegreesValue}
    _ -> Left allDiagnostics
 where
  (boatId, idDiagnostics) = requiredText path "id" fields
  (displayName, displayNameDiagnostics) = requiredText path "display_name" fields
  (maxHull, maxHullDiagnostics) = requiredPositiveInt path "max_hull" fields
  (renderedLength, renderedLengthDiagnostics) = requiredPositiveNumber path "rendered_length" fields
  (renderedWidth, renderedWidthDiagnostics) = requiredPositiveNumber path "rendered_width" fields
  (battleSpeed, battleSpeedDiagnostics) = requiredNonNegativeNumber path "battle_speed" fields
  (maxSpeed, maxSpeedDiagnostics) = requiredPositiveNumber path "max_speed" fields
  (acceleration, accelerationDiagnostics) = requiredPositiveNumber path "acceleration" fields
  (deceleration, decelerationDiagnostics) = requiredPositiveNumber path "deceleration" fields
  (turnRate, turnRateDiagnostics) = requiredPositiveNumber path "turn_rate" fields
  (idealTurnSpeed, idealTurnSpeedDiagnostics) = requiredPositiveNumber path "ideal_turn_speed" fields
  (yawAcceleration, yawAccelerationDiagnostics) = requiredPositiveNumber path "yaw_acceleration" fields
  (broadsideRangeValue, broadsideRangeDiagnostics) = requiredPositiveNumber path "broadside_range" fields
  (broadsideDamageValue, broadsideDamageDiagnostics) = requiredPositiveInt path "broadside_damage" fields
  (reloadTicksValue, reloadTicksDiagnostics) = requiredNonNegativeInt path "reload_ticks" fields
  (firingArcDegrees, firingArcDiagnostics) = requiredNumberWhere path "firing_arc_degrees" fields (\value -> value > 0 && value <= 180) "Must be greater than zero and no more than 180 degrees." "Use a firing arc in the range (0, 180]."
  values = (boatId, displayName, maxHull, renderedLength, renderedWidth, battleSpeed, maxSpeed, acceleration, deceleration, turnRate, idealTurnSpeed, yawAcceleration, broadsideRangeValue, broadsideDamageValue, reloadTicksValue, firingArcDegrees)
  diagnostics = concat [idDiagnostics, displayNameDiagnostics, maxHullDiagnostics, renderedLengthDiagnostics, renderedWidthDiagnostics, battleSpeedDiagnostics, maxSpeedDiagnostics, accelerationDiagnostics, decelerationDiagnostics, turnRateDiagnostics, idealTurnSpeedDiagnostics, yawAccelerationDiagnostics, broadsideRangeDiagnostics, broadsideDamageDiagnostics, reloadTicksDiagnostics, firingArcDiagnostics]
  boatIdMismatch =
    case boatId of
      Just value | value /= Text.pack (takeBaseName path) -> [diagnostic path Nothing Nothing (Just "id") "Boat id does not match its asset name." "Rename the id or the TOML file so both use the same boat kind."]
      _ -> []
  speedDiagnostics =
    case (battleSpeed, maxSpeed) of
      (Just battleSpeedValue, Just maxSpeedValue)
        | battleSpeedValue > maxSpeedValue -> [diagnostic path Nothing Nothing (Just "battle_speed") "Must not exceed max_speed." "Lower battle_speed or raise max_speed."]
      _ -> []
  idealTurnSpeedLimitDiagnostics =
    case (idealTurnSpeed, maxSpeed) of
      (Just idealTurnSpeedValue, Just maxSpeedValue)
        | idealTurnSpeedValue > maxSpeedValue -> [diagnostic path Nothing Nothing (Just "ideal_turn_speed") "Must not exceed max_speed." "Lower ideal_turn_speed or raise max_speed."]
      _ -> []
  allDiagnostics = diagnostics <> boatIdMismatch <> speedDiagnostics <> idealTurnSpeedLimitDiagnostics

requiredText :: FilePath -> Text -> Fields -> (Maybe Text, [ConfigDiagnostic])
requiredText path key fields =
  case Map.lookup key fields of
    Nothing -> (Nothing, [missingField path key])
    Just field -> case fieldValue field of
      TomlText value | not (Text.null value) -> (Just value, [])
      TomlText _ -> (Nothing, [fieldError path field key "Must not be empty." "Provide a non-empty quoted string."])
      TomlNumber _ -> (Nothing, [fieldError path field key "Expected a quoted string." "Quote this text value."])

requiredPositiveInt :: FilePath -> Text -> Fields -> (Maybe Int, [ConfigDiagnostic])
requiredPositiveInt path key fields = requiredIntWhere path key fields (> 0) "Must be a positive whole number." "Use an integer greater than zero."

requiredNonNegativeInt :: FilePath -> Text -> Fields -> (Maybe Int, [ConfigDiagnostic])
requiredNonNegativeInt path key fields = requiredIntWhere path key fields (>= 0) "Must be a non-negative whole number." "Use zero or a positive integer."

requiredIntWhere :: FilePath -> Text -> Fields -> (Int -> Bool) -> Text -> Text -> (Maybe Int, [ConfigDiagnostic])
requiredIntWhere path key fields predicate message hint =
  case Map.lookup key fields of
    Nothing -> (Nothing, [missingField path key])
    Just field -> case fieldValue field of
      TomlText _ -> (Nothing, [fieldError path field key "Expected a numeric value." "Remove the quotes and use a whole number."])
      TomlNumber value
        | isFinite value && value == fromIntegral (round value :: Int) && predicate (round value) -> (Just (round value), [])
        | otherwise -> (Nothing, [fieldError path field key message hint])

requiredPositiveNumber :: FilePath -> Text -> Fields -> (Maybe Double, [ConfigDiagnostic])
requiredPositiveNumber path key fields = requiredNumberWhere path key fields (> 0) "Must be a positive finite number." "Use a number greater than zero."

requiredNonNegativeNumber :: FilePath -> Text -> Fields -> (Maybe Double, [ConfigDiagnostic])
requiredNonNegativeNumber path key fields = requiredNumberWhere path key fields (>= 0) "Must be a non-negative finite number." "Use zero or a positive number."

requiredNumberWhere :: FilePath -> Text -> Fields -> (Double -> Bool) -> Text -> Text -> (Maybe Double, [ConfigDiagnostic])
requiredNumberWhere path key fields predicate message hint =
  case Map.lookup key fields of
    Nothing -> (Nothing, [missingField path key])
    Just field -> case fieldValue field of
      TomlText _ -> (Nothing, [fieldError path field key "Expected a numeric value." "Remove the quotes and use a decimal number."])
      TomlNumber value
        | isFinite value && predicate value -> (Just value, [])
        | otherwise -> (Nothing, [fieldError path field key message hint])

isFinite :: Double -> Bool
isFinite value = not (isNaN value || isInfinite value)

missingField :: FilePath -> Text -> ConfigDiagnostic
missingField path key = diagnostic path Nothing Nothing (Just key) "Missing required field." "Add this field to the TOML asset."

fieldError :: FilePath -> FieldValue -> Text -> Text -> Text -> ConfigDiagnostic
fieldError path field key message hint = diagnostic path (Just (fieldValueLine field)) (Just (fieldValueColumn field)) (Just key) message hint

diagnostic :: FilePath -> Maybe Int -> Maybe Int -> Maybe Text -> Text -> Text -> ConfigDiagnostic
diagnostic = ConfigDiagnostic

voidResult :: Either [ConfigDiagnostic] a -> [ConfigDiagnostic]
voidResult result = case result of Left diagnostics -> diagnostics; Right _ -> []

renderConfigDiagnostic :: ConfigDiagnostic -> Text
renderConfigDiagnostic diagnosticValue =
  Text.pack (configDiagnosticFile diagnosticValue)
    <> maybe "" (\line -> ":" <> Text.pack (show line)) (configDiagnosticLine diagnosticValue)
    <> maybe "" (\column -> ":" <> Text.pack (show column)) (configDiagnosticColumn diagnosticValue)
    <> maybe "" (" [" <>) (configDiagnosticField diagnosticValue)
    <> maybe "" (\_ -> "]") (configDiagnosticField diagnosticValue)
    <> ": " <> configDiagnosticMessage diagnosticValue <> " Hint: " <> configDiagnosticHint diagnosticValue
