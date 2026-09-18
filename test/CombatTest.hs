{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (replicateM_)
import Data.Text (Text)
import Data.Text qualified as Text
import FlorDoMar.Client.BattleScene
import FlorDoMar.Client.Render.Scene
import FlorDoMar.Client.WebGL.Camera
import FlorDoMar.Client.WebGL.Geometry
import FlorDoMar.Client.WebGL.Math
import FlorDoMar.Combat
import System.Exit (die)

main :: IO ()
main = do
  assertEqual "combat hello" "Hello from the local combat core." helloCombat
  assertEqual "initial scenario" "Portuguese caravela duel" initialScenarioName
  testTickAdvancement
  testValidBroadsideDamage
  testInvalidBroadsideRange
  testInvalidBroadsideArc
  testReloadCooldown
  testTerminalHullState
  testLoadsRuntimeCombatConfig
  testRejectsMalformedRuntimeCombatConfig
  testRejectsInvalidRuntimeCombatConfig
  testRejectsBoatIdAssetMismatch
  testRejectsMissingRuntimeCombatConfig
  testLocalApiStartsCaravelaDuel
  testConfiguredLocalApiStartsBigVsSmall
  testConfiguredMovementPhysics
  testConfiguredBroadsideTuning
  testConfiguredLocalApiBroadsideTuning
  testConfiguredMovementSnapshot
  testConfiguredLocalApiHotReloadsLiveEngagement
  testInvalidReloadKeepsLastValidConfigAndSnapshot
  testHotReloadPreservesDamageAcrossHullClamp
  testConfiguredLocalApiRestartsSelectedEngagement
  testSetupOverlayState
  testLocalApiQueuesCommandsUntilTick
  testLocalApiReportsTerminalState
  testInitialBattleRenderScene
  testDamagedBattleRenderSceneTint
  putStrLn "combat-test: OK"

assertEqual :: (Eq a, Show a) => String -> a -> a -> IO ()
assertEqual label expected actual =
  if expected == actual
    then pure ()
    else die $ label <> ": expected " <> show expected <> ", got " <> show actual

assertApprox :: String -> Double -> Double -> IO ()
assertApprox label expected actual =
  if abs (expected - actual) < 0.0001
    then pure ()
    else die $ label <> ": expected " <> show expected <> ", got " <> show actual

assertApproxScalar :: String -> Scalar -> Scalar -> IO ()
assertApproxScalar label expected actual =
  if abs (expected - actual) < 0.0001
    then pure ()
    else die $ label <> ": expected " <> show expected <> ", got " <> show actual

assertVec2 :: String -> Vec2 -> Vec2 -> IO ()
assertVec2 label expected actual = do
  assertApproxScalar (label <> " x") (vec2X expected) (vec2X actual)
  assertApproxScalar (label <> " y") (vec2Y expected) (vec2Y actual)

assertVec3 :: String -> Vec3 -> Vec3 -> IO ()
assertVec3 label expected actual = do
  assertApproxScalar (label <> " x") (vec3X expected) (vec3X actual)
  assertApproxScalar (label <> " y") (vec3Y expected) (vec3Y actual)
  assertApproxScalar (label <> " z") (vec3Z expected) (vec3Z actual)

assertColor :: String -> Color -> Color -> IO ()
assertColor label expected actual = do
  assertApproxScalar (label <> " red") (colorRed expected) (colorRed actual)
  assertApproxScalar (label <> " green") (colorGreen expected) (colorGreen actual)
  assertApproxScalar (label <> " blue") (colorBlue expected) (colorBlue actual)
  assertApproxScalar (label <> " alpha") (colorAlpha expected) (colorAlpha actual)

expectRight :: (Show e) => String -> Either e a -> IO a
expectRight label result =
  case result of
    Right value -> pure value
    Left err -> die $ label <> ": expected Right, got Left " <> show err

expectLeft :: String -> Either a b -> IO a
expectLeft label result =
  case result of
    Left err -> pure err
    Right _ -> die $ label <> ": expected Left, got Right"

expectShipSnapshot :: String -> ShipId -> CombatSnapshot -> IO ShipSnapshot
expectShipSnapshot label identity snapshot =
  case matchingShips of
    [ship] -> pure ship
    [] -> die $ label <> ": missing ship " <> show identity
    ships -> die $ label <> ": expected one ship, got " <> show (length ships)
 where
  matchingShips =
    filter
      (\ship -> shipSnapshotId ship == identity)
      (combatSnapshotShips snapshot)

startLocalDuel :: IO (CombatApi IO, CombatSnapshot)
startLocalDuel = do
  localApi <- newLocalCombatApi
  let api = localCombatApi localApi
  snapshot <- expectRight "start local caravela duel" =<< combatApiStartScenario api caravelaDuelScenarioId
  pure (api, snapshot)

queueLocalCommand :: String -> CombatApi IO -> CombatCommand -> IO CombatSnapshot
queueLocalCommand label api command =
  expectRight label =<< combatApiSubmitCommand api command

advanceLocalApiTick :: String -> CombatApi IO -> IO CombatSnapshot
advanceLocalApiTick label api =
  expectRight label =<< combatApiAdvanceTick api

testTickAdvancement :: IO ()
testTickAdvancement = do
  let
    advanced = tickCombat [] caravelaDuel
    playerPosition = shipPosition (combatPlayer advanced)
  assertEqual "tick advances" 1 (combatTick advanced)
  assertApprox "player moves east on battle sails" 4 (pointX playerPosition)
  assertApprox "player y remains stable" 0 (pointY playerPosition)

testValidBroadsideDamage :: IO ()
testValidBroadsideDamage = do
  let fired = tickCombat [FireBroadside PlayerShip EnemyShip Port] caravelaDuel
  assertEqual "broadside check ready" BroadsideReady (canFireBroadside caravelaDuel PlayerShip EnemyShip Port)
  assertEqual "enemy hull damaged" 75 (shipHull (combatEnemy fired))
  assertEqual "player reload set" reloadTicks (shipReload (combatPlayer fired))

testInvalidBroadsideRange :: IO ()
testInvalidBroadsideRange = do
  let
    outOfRange =
      caravelaDuel
        { combatEnemy =
            (combatEnemy caravelaDuel)
              { shipPosition = Point {pointX = 0, pointY = broadsideRange + 50}
              }
        }
    fired = tickCombat [FireBroadside PlayerShip EnemyShip Port] outOfRange
  assertEqual "enemy hull unchanged out of range" 100 (shipHull (combatEnemy fired))
  case canFireBroadside outOfRange PlayerShip EnemyShip Port of
    TargetOutOfRange range ->
      if range > broadsideRange
        then pure ()
        else die "range failure did not report an out-of-range distance"
    other -> die $ "expected TargetOutOfRange, got " <> show other

testInvalidBroadsideArc :: IO ()
testInvalidBroadsideArc = do
  let
    wrongArc =
      caravelaDuel
        { combatEnemy =
            (combatEnemy caravelaDuel)
              { shipPosition = Point {pointX = 80, pointY = 0}
              }
        }
    fired = tickCombat [FireBroadside PlayerShip EnemyShip Port] wrongArc
  assertEqual "enemy hull unchanged outside arc" 100 (shipHull (combatEnemy fired))
  case canFireBroadside wrongArc PlayerShip EnemyShip Port of
    TargetOutsideFiringArc angle ->
      if angle > 45
        then pure ()
        else die "arc failure did not report an outside-arc angle"
    other -> die $ "expected TargetOutsideFiringArc, got " <> show other

testReloadCooldown :: IO ()
testReloadCooldown = do
  let
    fired = tickCombat [FireBroadside PlayerShip EnemyShip Port] caravelaDuel
    blocked = tickCombat [FireBroadside PlayerShip EnemyShip Port] fired
    cooledOnce = tickCombat [] fired
    cooledTwice = tickCombat [] cooledOnce
    readyAgain = tickCombat [] cooledTwice
  assertEqual "second broadside blocked by reload" 75 (shipHull (combatEnemy blocked))
  case canFireBroadside fired PlayerShip EnemyShip Port of
    BroadsideReloading remaining -> assertEqual "reload remaining" reloadTicks remaining
    other -> die $ "expected BroadsideReloading, got " <> show other
  assertEqual "reload counts down once" 2 (shipReload (combatPlayer cooledOnce))
  assertEqual "reload counts down twice" 1 (shipReload (combatPlayer cooledTwice))
  assertEqual "reload reaches ready" 0 (shipReload (combatPlayer readyAgain))

testTerminalHullState :: IO ()
testTerminalHullState = do
  let
    almostDisabled =
      caravelaDuel
        { combatEnemy = (combatEnemy caravelaDuel) {shipHull = broadsideDamage}
        }
    finished = tickCombat [FireBroadside PlayerShip EnemyShip Port] almostDisabled
    afterFinished = tickCombat [] finished
  assertEqual "enemy hull disabled" 0 (shipHull (combatEnemy finished))
  assertEqual "player wins when enemy disabled" (ScenarioFinished (Winner PlayerShip)) (combatStatus finished)
  assertEqual "finished scenario no longer advances" (combatTick finished) (combatTick afterFinished)

testLoadsRuntimeCombatConfig :: IO ()
testLoadsRuntimeCombatConfig = do
  runtimeDirectory <- runtimeCombatConfigDirectory
  assertEqual "runtime config prefers editable source assets" "config/combat" runtimeDirectory
  config <- expectRight "load packaged combat assets" =<< loadRuntimeCombatConfig
  assertApprox "configured tick seconds" 0.8 (physicsTickSeconds (combatConfigPhysics config))
  big <- expectBoatConfig "configured big boat" "big" config
  small <- expectBoatConfig "configured small boat" "small" config
  assertEqual "configured big display name" "Big boat" (boatConfigDisplayName big)
  assertEqual "configured small display name" "Small boat" (boatConfigDisplayName small)
  assertApprox "configured big length" 16 (boatConfigRenderedLength big)
  assertApprox "configured small length" 9 (boatConfigRenderedLength small)

testRejectsMalformedRuntimeCombatConfig :: IO ()
testRejectsMalformedRuntimeCombatConfig = do
  diagnostics <- expectLeft "reject malformed TOML" =<< loadCombatConfig "test/fixtures/config-malformed"
  assertDiagnostic "malformed TOML reports line" "tick_seconds" diagnostics
  assertParserDiagnostic "malformed TOML identifies source location" "test/fixtures/config-malformed/physics.toml" diagnostics

testRejectsInvalidRuntimeCombatConfig :: IO ()
testRejectsInvalidRuntimeCombatConfig = do
  diagnostics <- expectLeft "reject invalid numeric TOML" =<< loadCombatConfig "test/fixtures/config-invalid"
  assertDiagnostic "invalid numeric TOML reports field" "tick_seconds" diagnostics
  assertSemanticDiagnostic "invalid numeric TOML explains the field problem" "tick_seconds" diagnostics

testRejectsBoatIdAssetMismatch :: IO ()
testRejectsBoatIdAssetMismatch = do
  diagnostics <- expectLeft "reject boat id mismatch" =<< loadCombatConfig "test/fixtures/config-id-mismatch"
  assertDiagnostic "boat id mismatch reports id" "id" diagnostics

testRejectsMissingRuntimeCombatConfig :: IO ()
testRejectsMissingRuntimeCombatConfig = do
  diagnostics <- expectLeft "reject missing runtime config" =<< loadCombatConfig "test/fixtures/no-such-config"
  if length diagnostics == 3
    then pure ()
    else die $ "missing config: expected three file diagnostics, got " <> show diagnostics

testLocalApiStartsCaravelaDuel :: IO ()
testLocalApiStartsCaravelaDuel = do
  localApi <- newLocalCombatApi
  let api = localCombatApi localApi
  missingSnapshot <- combatApiObserveSnapshot api
  assertEqual "observe before scenario" (Left CombatScenarioNotStarted) missingSnapshot
  scenarios <- combatApiListScenarios api
  assertEqual "local scenario list" [caravelaDuelScenario] scenarios
  snapshot <- expectRight "start local scenario" =<< combatApiStartScenario api caravelaDuelScenarioId
  player <- expectShipSnapshot "duel player snapshot" PlayerShip snapshot
  enemy <- expectShipSnapshot "duel enemy snapshot" EnemyShip snapshot
  assertEqual "snapshot scenario" caravelaDuelScenario (combatSnapshotScenario snapshot)
  assertEqual "snapshot starts at tick zero" 0 (combatSnapshotTick snapshot)
  assertEqual "snapshot starts running" ScenarioRunning (combatSnapshotStatus snapshot)
  assertEqual "player read-model name" "Player caravela" (shipSnapshotName player)
  assertEqual "enemy read-model name" "Enemy caravela" (shipSnapshotName enemy)
  assertEqual "player hull visible" 100 (shipSnapshotHull player)
  assertEqual "enemy hull visible" 100 (shipSnapshotHull enemy)
  assertApprox "initial duel range visible" 80 (engagementRange (combatSnapshotEngagement snapshot))
  assertEqual "initial port broadside ready" BroadsideReady (engagementPlayerPortBroadside (combatSnapshotEngagement snapshot))

testConfiguredLocalApiStartsBigVsSmall :: IO ()
testConfiguredLocalApiStartsBigVsSmall = do
  config <- expectRight "load packaged config for configured API" =<< loadRuntimeCombatConfig
  localApi <- newConfiguredLocalCombatApi config
  snapshot <- expectRight "start configured local scenario" =<< combatApiStartScenario (localCombatApi localApi) caravelaDuelScenarioId
  player <- expectShipSnapshot "configured player snapshot" PlayerShip snapshot
  enemy <- expectShipSnapshot "configured enemy snapshot" EnemyShip snapshot
  assertEqual "configured player boat kind" "big" (shipSnapshotBoatKind player)
  assertEqual "configured enemy boat kind" "small" (shipSnapshotBoatKind enemy)
  assertEqual "configured player display name" "Big boat" (shipSnapshotDisplayName player)
  assertEqual "configured enemy display name" "Small boat" (shipSnapshotDisplayName enemy)
  assertEqual "configured player max hull" 160 (shipSnapshotMaxHull player)
  assertEqual "configured player current hull" 160 (shipSnapshotHull player)
  assertEqual "configured enemy max hull" 80 (shipSnapshotMaxHull enemy)
  assertEqual "configured enemy current hull" 80 (shipSnapshotHull enemy)
  assertApprox "configured player rendered length" 16 (shipSnapshotRenderedLength player)
  assertApprox "configured player rendered width" 6 (shipSnapshotRenderedWidth player)
  assertApprox "configured enemy rendered length" 9 (shipSnapshotRenderedLength enemy)
  assertApprox "configured enemy rendered width" 3 (shipSnapshotRenderedWidth enemy)
  let renderScene = battleRenderSceneFromSnapshot snapshot
  playerMesh <- expectMesh "ship:player" renderScene
  enemyMesh <- expectMesh "ship:enemy" renderScene
  assertVec3 "configured player ship scale" (vec3 16 6 0.25) (transformScale (renderMeshTransform playerMesh))
  assertVec3 "configured enemy ship scale" (vec3 9 3 0.25) (transformScale (renderMeshTransform enemyMesh))

testConfiguredMovementPhysics :: IO ()
testConfiguredMovementPhysics = do
  config <- expectRight "load packaged config for movement physics" =<< loadRuntimeCombatConfig
  let
    initialState = configuredDefaultEngagement config
    turningState = tickConfiguredCombat config [SetHeading PlayerShip (Heading 180)] initialState
    turningPlayer = combatPlayer turningState
    fullSailsState = tickConfiguredCombat config [SetSails PlayerShip FullSails] turningState
    furledState = tickConfiguredCombat config [SetSails PlayerShip SailsFurled] fullSailsState
    halfSecondConfig = config {combatConfigPhysics = PhysicsConfig 0.5}
    halfSecondState = tickConfiguredCombat halfSecondConfig [] (configuredDefaultEngagement halfSecondConfig)
    halfSecondPlayer = combatPlayer halfSecondState
  assertEqual "heading command updates configured target" (Heading 180) (shipTargetHeading turningPlayer)
  assertApprox "heading turns gradually at low speed" 6 (headingDegrees (shipHeading turningPlayer))
  assertApprox "battle sails accelerate from rest" 1.6 (shipCurrentSpeed turningPlayer)
  assertApprox "movement uses physical heading" 1.273 (pointX (shipPosition turningPlayer))
  assertApprox "movement uses configured tick seconds" (1.6 * 0.8 * sin (6 * pi / 180)) (pointY (shipPosition turningPlayer))
  assertEqual "physical heading keeps port broadside ready" BroadsideReady (canFireBroadside turningState PlayerShip EnemyShip Port)
  assertApprox "full sails continue acceleration toward max speed" 3.2 (shipCurrentSpeed (combatPlayer fullSailsState))
  assertApprox "furled sails decelerate toward zero" 0.8 (shipCurrentSpeed (combatPlayer furledState))
  assertApprox "half-second tick accelerates by configured per-second value" 1 (shipCurrentSpeed halfSecondPlayer)
  assertApprox "half-second tick advances by speed times tick seconds" 0.5 (pointX (shipPosition halfSecondPlayer))

testConfiguredBroadsideTuning :: IO ()
testConfiguredBroadsideTuning = do
  config <- expectRight "load packaged config for broadside tuning" =<< loadRuntimeCombatConfig
  let
    tunedConfig =
      config
        { combatConfigBoats =
            [ tuneBoat boat
            | boat <- combatConfigBoats config
            ]
        }
    bigAtLongRange = configuredDefaultEngagement tunedConfig
    bigAtShortRange =
      bigAtLongRange
        { combatEnemy = (combatEnemy bigAtLongRange) {shipPosition = Point 0 60}
        }
    bigFired = tickConfiguredCombat tunedConfig [SetHeading PlayerShip (Heading 180), FireBroadside PlayerShip EnemyShip Port] bigAtShortRange
    smallAtLongRange =
      case configuredEngagement tunedConfig "small" "big" of
        Just state -> state
        Nothing -> error "validated combat config is missing a configured boat kind"
    smallArcState =
      smallAtLongRange
        { combatEnemy = (combatEnemy smallAtLongRange) {shipPosition = Point (-30) 52}
        }
    smallFired = tickConfiguredCombat tunedConfig [FireBroadside PlayerShip EnemyShip Port] smallAtLongRange
    bigArcState =
      bigAtShortRange
        { combatEnemy = (combatEnemy bigAtShortRange) {shipPosition = Point (-30) 52}
        }
  case canFireBroadsideWith (broadsideTuningForShip tunedConfig) bigAtLongRange PlayerShip EnemyShip Port of
    TargetOutOfRange _ -> pure ()
    other -> die $ "configured big range: expected TargetOutOfRange, got " <> show other
  assertEqual "configured big damage" 49 (shipHull (combatEnemy bigFired))
  assertEqual "configured big reload" 4 (shipReload (combatPlayer bigFired))
  assertApprox "configured heading intent does not replace physical heading for broadside" 6 (headingDegrees (shipHeading (combatPlayer bigFired)))
  assertEqual "configured small range differs from big" BroadsideReady (canFireBroadsideWith (broadsideTuningForShip tunedConfig) smallAtLongRange PlayerShip EnemyShip Port)
  assertEqual "configured small damage" 147 (shipHull (combatEnemy smallFired))
  assertEqual "configured small reload" 1 (shipReload (combatPlayer smallFired))
  assertEqual "configured small firing arc differs from big" BroadsideReady (canFireBroadsideWith (broadsideTuningForShip tunedConfig) smallArcState PlayerShip EnemyShip Port)
  case canFireBroadsideWith (broadsideTuningForShip tunedConfig) bigArcState PlayerShip EnemyShip Port of
    TargetOutsideFiringArc _ -> pure ()
    other -> die $ "configured big firing arc: expected TargetOutsideFiringArc, got " <> show other
 where
  tuneBoat boat =
    case boatConfigId boat of
      "big" -> boat {boatConfigBroadsideRange = 70, boatConfigBroadsideDamage = 31, boatConfigReloadTicks = 4, boatConfigFiringArcDegrees = 15}
      "small" -> boat {boatConfigBroadsideRange = 100, boatConfigBroadsideDamage = 13, boatConfigReloadTicks = 1, boatConfigFiringArcDegrees = 45}
      _ -> boat

testConfiguredLocalApiBroadsideTuning :: IO ()
testConfiguredLocalApiBroadsideTuning = do
  config <- expectRight "load packaged config for API broadside tuning" =<< loadRuntimeCombatConfig
  let
    tunedConfig =
      config
        { combatConfigBoats =
            [ boat {boatConfigBroadsideDamage = 31, boatConfigReloadTicks = 4}
            | boat <- combatConfigBoats config
            ]
        }
  localApi <- newConfiguredLocalCombatApi tunedConfig
  let api = localCombatApi localApi
  _ <- expectRight "start configured scenario for API broadside tuning" =<< combatApiStartScenario api caravelaDuelScenarioId
  _ <- queueLocalCommand "queue configured API broadside" api (FireBroadside PlayerShip EnemyShip Port)
  snapshot <- advanceLocalApiTick "advance configured API broadside" api
  player <- expectShipSnapshot "configured API broadside player" PlayerShip snapshot
  enemy <- expectShipSnapshot "configured API broadside enemy" EnemyShip snapshot
  assertEqual "configured API damage" 49 (shipSnapshotHull enemy)
  assertEqual "configured API reload snapshot" 4 (shipSnapshotReload player)

testConfiguredMovementSnapshot :: IO ()
testConfiguredMovementSnapshot = do
  config <- expectRight "load packaged config for movement snapshot" =<< loadRuntimeCombatConfig
  localApi <- newConfiguredLocalCombatApi config
  let api = localCombatApi localApi
  _ <- expectRight "start configured scenario for movement snapshot" =<< combatApiStartScenario api caravelaDuelScenarioId
  _ <- queueLocalCommand "queue configured heading" api (SetHeading PlayerShip (Heading 90))
  snapshot <- advanceLocalApiTick "advance configured movement snapshot" api
  player <- expectShipSnapshot "configured movement snapshot player" PlayerShip snapshot
  assertApprox "snapshot exposes physical heading" 6 (headingDegrees (shipSnapshotHeading player))
  assertEqual "snapshot exposes target heading" (Heading 90) (shipSnapshotTargetHeading player)
  assertApprox "snapshot exposes current speed" 1.6 (shipSnapshotCurrentSpeed player)

testConfiguredLocalApiHotReloadsLiveEngagement :: IO ()
testConfiguredLocalApiHotReloadsLiveEngagement = do
  config <- expectRight "load packaged config for hot reload" =<< loadRuntimeCombatConfig
  localApi <- newConfiguredLocalCombatApi config
  let api = localCombatApi localApi
  _ <- expectRight "start configured scenario before hot reload" =<< combatApiStartScenario api caravelaDuelScenarioId
  _ <- queueLocalCommand "queue player heading before hot reload" api (SetHeading PlayerShip (Heading 90))
  _ <- queueLocalCommand "queue player broadside before hot reload" api (FireBroadside PlayerShip EnemyShip Port)
  _ <- queueLocalCommand "queue enemy broadside before hot reload" api (FireBroadside EnemyShip PlayerShip Port)
  beforeReload <- advanceLocalApiTick "advance configured scenario before hot reload" api
  playerBefore <- expectShipSnapshot "player before hot reload" PlayerShip beforeReload
  enemyBefore <- expectShipSnapshot "enemy before hot reload" EnemyShip beforeReload
  let reloadedConfig = tuneForHotReload config
  localCombatApiReloadConfig localApi reloadedConfig
  activeConfig <- localCombatApiActiveConfig localApi
  assertEqual "hot reload atomically updates active config" (Just reloadedConfig) activeConfig
  assertApprox "hot reload updates tick cadence seam" 0.5 (combatConfigTickSeconds reloadedConfig)
  afterReload <- expectRight "observe configured scenario after hot reload" =<< combatApiObserveSnapshot api
  playerAfter <- expectShipSnapshot "player after hot reload" PlayerShip afterReload
  enemyAfter <- expectShipSnapshot "enemy after hot reload" EnemyShip afterReload
  assertEqual "hot reload keeps player boat kind" "big" (shipSnapshotBoatKind playerAfter)
  assertEqual "hot reload keeps player position" (shipSnapshotPosition playerBefore) (shipSnapshotPosition playerAfter)
  assertEqual "hot reload keeps player physical heading" (shipSnapshotHeading playerBefore) (shipSnapshotHeading playerAfter)
  assertEqual "hot reload keeps player target heading" (shipSnapshotTargetHeading playerBefore) (shipSnapshotTargetHeading playerAfter)
  assertApprox "hot reload keeps player speed" (shipSnapshotCurrentSpeed playerBefore) (shipSnapshotCurrentSpeed playerAfter)
  assertEqual "hot reload keeps player reload" (shipSnapshotReload playerBefore) (shipSnapshotReload playerAfter)
  assertEqual "hot reload recalculates big hull from damage" 175 (shipSnapshotHull playerAfter)
  assertEqual "hot reload updates big max hull" 200 (shipSnapshotMaxHull playerAfter)
  assertApprox "hot reload updates big length" 22 (shipSnapshotRenderedLength playerAfter)
  assertApprox "hot reload updates big width" 9 (shipSnapshotRenderedWidth playerAfter)
  assertEqual "hot reload recalculates small hull from damage" 45 (shipSnapshotHull enemyAfter)
  assertEqual "hot reload updates small max hull" 70 (shipSnapshotMaxHull enemyAfter)
  assertEqual "hot reload keeps enemy reload" (shipSnapshotReload enemyBefore) (shipSnapshotReload enemyAfter)
  advanced <- advanceLocalApiTick "advance using reloaded movement values" api
  advancedPlayer <- expectShipSnapshot "player after reloaded movement" PlayerShip advanced
  assertApprox "hot reload uses new tick seconds and acceleration" 4 (shipSnapshotCurrentSpeed advancedPlayer)
  replicateM_ 2 $ do
    _ <- advanceLocalApiTick "cool down after hot reload" api
    pure ()
  _ <- queueLocalCommand "queue player broadside after hot reload" api (FireBroadside PlayerShip EnemyShip Port)
  fired <- advanceLocalApiTick "fire using reloaded broadside tuning" api
  firedPlayer <- expectShipSnapshot "player after reloaded broadside" PlayerShip fired
  firedEnemy <- expectShipSnapshot "enemy after reloaded broadside" EnemyShip fired
  assertEqual "hot reload uses new broadside damage" 5 (shipSnapshotHull firedEnemy)
  assertEqual "hot reload uses new broadside reload" 6 (shipSnapshotReload firedPlayer)
 where
  tuneForHotReload currentConfig =
    currentConfig
      { combatConfigPhysics = PhysicsConfig 0.5
      , combatConfigBoats = fmap tuneBoat (combatConfigBoats currentConfig)
      }
  tuneBoat boat =
    case boatConfigId boat of
      "big" ->
        boat
          { boatConfigMaxHull = 200
          , boatConfigRenderedLength = 22
          , boatConfigRenderedWidth = 9
          , boatConfigBattleSpeed = 4
          , boatConfigAcceleration = 5
          , boatConfigBroadsideRange = 110
          , boatConfigBroadsideDamage = 40
          , boatConfigReloadTicks = 6
          }
      "small" -> boat {boatConfigMaxHull = 70}
      _ -> boat

testInvalidReloadKeepsLastValidConfigAndSnapshot :: IO ()
testInvalidReloadKeepsLastValidConfigAndSnapshot = do
  config <- expectRight "load packaged config for invalid reload" =<< loadRuntimeCombatConfig
  localApi <- newConfiguredLocalCombatApi config
  let api = localCombatApi localApi
  _ <- expectRight "start configured scenario before invalid reload" =<< combatApiStartScenario api caravelaDuelScenarioId
  beforeReload <- advanceLocalApiTick "advance configured scenario before invalid reload" api
  malformed <- expectLeft "load malformed config for invalid reload" =<< loadCombatConfig "test/fixtures/config-malformed"
  semantic <- expectLeft "load semantic config for invalid reload" =<< loadCombatConfig "test/fixtures/config-invalid"
  missing <- expectLeft "load missing config for invalid reload" =<< loadCombatConfig "test/fixtures/no-such-config"
  assertInvalidReloadPreservesLiveEngagement "malformed reload" localApi config beforeReload malformed
  assertInvalidReloadPreservesLiveEngagement "semantic reload" localApi config beforeReload semantic
  assertInvalidReloadPreservesLiveEngagement "missing reload" localApi config beforeReload missing

testHotReloadPreservesDamageAcrossHullClamp :: IO ()
testHotReloadPreservesDamageAcrossHullClamp = do
  config <- expectRight "load packaged config for repeated hull reload" =<< loadRuntimeCombatConfig
  localApi <- newConfiguredLocalCombatApi config
  let api = localCombatApi localApi
  _ <- expectRight "start configured scenario before hull reload" =<< combatApiStartScenario api caravelaDuelScenarioId
  _ <- queueLocalCommand "queue enemy damage before hull reload" api (FireBroadside EnemyShip PlayerShip Port)
  damaged <- advanceLocalApiTick "apply enemy damage before hull reload" api
  damagedPlayer <- expectShipSnapshot "player damaged before hull reload" PlayerShip damaged
  assertEqual "broadside records player damage" 135 (shipSnapshotHull damagedPlayer)
  localCombatApiReloadConfig localApi (withBigHull 20 config)
  clamped <- expectRight "observe player after clamping hull reload" =<< combatApiObserveSnapshot api
  clampedPlayer <- expectShipSnapshot "player after clamping hull reload" PlayerShip clamped
  assertEqual "lower max hull clamps current hull" 0 (shipSnapshotHull clampedPlayer)
  assertEqual "lower max hull is visible" 20 (shipSnapshotMaxHull clampedPlayer)
  localCombatApiReloadConfig localApi (withBigHull 200 config)
  restored <- expectRight "observe player after raised hull reload" =<< combatApiObserveSnapshot api
  restoredPlayer <- expectShipSnapshot "player after raised hull reload" PlayerShip restored
  assertEqual "raised max hull preserves original broadside damage" 175 (shipSnapshotHull restoredPlayer)
  assertEqual "raised max hull is visible" 200 (shipSnapshotMaxHull restoredPlayer)
 where
  withBigHull hull currentConfig =
    currentConfig
      { combatConfigBoats =
          [ if boatConfigId boat == "big" then boat {boatConfigMaxHull = hull} else boat
          | boat <- combatConfigBoats currentConfig
          ]
      }

testConfiguredLocalApiRestartsSelectedEngagement :: IO ()
testConfiguredLocalApiRestartsSelectedEngagement = do
  config <- expectRight "load packaged config for selected engagement" =<< loadRuntimeCombatConfig
  localApi <- newConfiguredLocalCombatApi config
  let api = localCombatApi localApi
  _ <- expectRight "start configured scenario before selected engagement" =<< combatApiStartScenario api caravelaDuelScenarioId
  _ <- advanceLocalApiTick "advance configured scenario before selected engagement" api
  selectedSnapshot <- expectRight "start selected configured engagement" =<< localCombatApiStartEngagement localApi "small" "big"
  player <- expectShipSnapshot "selected player snapshot" PlayerShip selectedSnapshot
  enemy <- expectShipSnapshot "selected enemy snapshot" EnemyShip selectedSnapshot
  assertEqual "selected engagement has exactly two ships" 2 (length (combatSnapshotShips selectedSnapshot))
  assertEqual "selected player kind" "small" (shipSnapshotBoatKind player)
  assertEqual "selected enemy kind" "big" (shipSnapshotBoatKind enemy)
  assertEqual "selected engagement resets tick" 0 (combatSnapshotTick selectedSnapshot)
  assertEqual "selected player starts undamaged" 80 (shipSnapshotHull player)
  assertEqual "selected enemy starts undamaged" 160 (shipSnapshotHull enemy)
  invalidResult <- localCombatApiStartEngagement localApi "missing" "big"
  assertEqual "selected engagement rejects unknown player kind" (Left (CombatBoatKindNotFound "missing")) invalidResult

testSetupOverlayState :: IO ()
testSetupOverlayState = do
  let
    defaultEngagement = EngagementSetup "big" "small"
    initialState = initialSetupState defaultEngagement
    openState = applySetupAction ToggleSetupOverlay initialState
    selectedState = applySetupAction (SelectEnemyBoatKind "big") (applySetupAction (SelectPlayerBoatKind "small") openState)
    launchedState = applySetupAction LaunchEngagement selectedState
    lockedState = applySetupAction (SelectPlayerBoatKind "big") launchedState
    selectedEngagement = EngagementSetup "small" "big"
  assertEqual "setup starts closed" False (setupOverlayOpen initialState)
  assertEqual "setup permits ticks while closed" True (setupAllowsTicks initialState)
  assertEqual "escape opens setup" True (setupOverlayOpen openState)
  assertEqual "setup pauses ticks while open" False (setupAllowsTicks openState)
  assertEqual "setup selection does not change active engagement" defaultEngagement (setupActiveEngagement selectedState)
  assertEqual "setup launch selection uses selected boat kinds" (Just selectedEngagement) (setupLaunchSelection selectedState)
  assertEqual "launch closes setup" False (setupOverlayOpen launchedState)
  assertEqual "launch locks selected boat kinds into active engagement" selectedEngagement (setupActiveEngagement launchedState)
  assertEqual "selection cannot change while engagement is active" launchedState lockedState

testLocalApiQueuesCommandsUntilTick :: IO ()
testLocalApiQueuesCommandsUntilTick = do
  (api, _) <- startLocalDuel
  queuedSnapshot <- queueLocalCommand "queue local broadside" api (FireBroadside PlayerShip EnemyShip Port)
  queuedEnemy <- expectShipSnapshot "queued enemy snapshot" EnemyShip queuedSnapshot
  observedSnapshot <- expectRight "observe queued scenario" =<< combatApiObserveSnapshot api
  observedEnemy <- expectShipSnapshot "observed enemy snapshot" EnemyShip observedSnapshot
  advancedSnapshot <- advanceLocalApiTick "advance queued command" api
  advancedPlayer <- expectShipSnapshot "advanced player snapshot" PlayerShip advancedSnapshot
  advancedEnemy <- expectShipSnapshot "advanced enemy snapshot" EnemyShip advancedSnapshot
  assertEqual "queued command does not advance tick" 0 (combatSnapshotTick queuedSnapshot)
  assertEqual "queued command does not damage immediately" 100 (shipSnapshotHull queuedEnemy)
  assertEqual "observe hides pending command mutation" 100 (shipSnapshotHull observedEnemy)
  assertEqual "advance increments tick" 1 (combatSnapshotTick advancedSnapshot)
  assertEqual "advance applies broadside damage" 75 (shipSnapshotHull advancedEnemy)
  assertEqual "advance exposes reload" reloadTicks (shipSnapshotReload advancedPlayer)

testLocalApiReportsTerminalState :: IO ()
testLocalApiReportsTerminalState = do
  (api, _) <- startLocalDuel
  _ <- queueLocalCommand "queue player furl sails" api (SetSails PlayerShip SailsFurled)
  _ <- queueLocalCommand "queue enemy furl sails" api (SetSails EnemyShip SailsFurled)
  firstShot <- firePlayerPortBroadside api
  assertEnemyHull "first API broadside" 75 firstShot
  coolDownPlayerReload api
  secondShot <- firePlayerPortBroadside api
  assertEnemyHull "second API broadside" 50 secondShot
  coolDownPlayerReload api
  thirdShot <- firePlayerPortBroadside api
  assertEnemyHull "third API broadside" 25 thirdShot
  coolDownPlayerReload api
  finalShot <- firePlayerPortBroadside api
  afterFinished <- advanceLocalApiTick "advance finished local scenario" api
  assertEnemyHull "final API broadside" 0 finalShot
  assertEqual "API reports player victory" (ScenarioFinished (Winner PlayerShip)) (combatSnapshotStatus finalShot)
  assertEqual "finished API scenario no longer advances" (combatSnapshotTick finalShot) (combatSnapshotTick afterFinished)
  assertEqual "finished API snapshot remains terminal" (combatSnapshotStatus finalShot) (combatSnapshotStatus afterFinished)

firePlayerPortBroadside :: CombatApi IO -> IO CombatSnapshot
firePlayerPortBroadside api = do
  _ <- queueLocalCommand "queue player port broadside" api (FireBroadside PlayerShip EnemyShip Port)
  advanceLocalApiTick "advance player port broadside" api

coolDownPlayerReload :: CombatApi IO -> IO ()
coolDownPlayerReload api =
  replicateM_ reloadTicks $ do
    _ <- advanceLocalApiTick "cool down player reload" api
    pure ()

testInitialBattleRenderScene :: IO ()
testInitialBattleRenderScene = do
  let
    renderScene =
      battleRenderSceneFromSnapshot $
        combatSnapshotFromState caravelaDuelScenario caravelaDuel
    camera = renderSceneCamera renderScene
    meshes = renderSceneMeshes renderScene
  assertVec2 "render camera center" (vec2 0 40) (cameraCenter camera)
  assertApproxScalar "render camera viewport width" 160 (viewportWidth (cameraViewport camera))
  assertApproxScalar "render camera viewport height" 90 (viewportHeight (cameraViewport camera))
  assertApproxScalar "render camera zoom" 1 (cameraZoom camera)
  assertEqual "render mesh count" 6 (length meshes)
  assertMesh
    "initial player ship"
    "ship:player"
    (vec3 0 0 0)
    0
    (vec3 10 4 0.25)
    (color 0.2 0.75 0.95 1)
    =<< expectMesh "ship:player" renderScene
  assertMesh
    "initial player heading"
    "heading:player"
    (vec3 8 0 0)
    0
    (vec3 2 2 0.25)
    (color 0.96 0.9 0.58 1)
    =<< expectMesh "heading:player" renderScene
  assertMesh
    "initial player target heading"
    "target-heading:player"
    (vec3 11 0 0)
    0
    (vec3 1 1 0.25)
    (color 0.56 0.93 0.7 1)
    =<< expectMesh "target-heading:player" renderScene
  assertMesh
    "initial enemy ship"
    "ship:enemy"
    (vec3 0 80 0)
    pi
    (vec3 10 4 0.25)
    (color 0.95 0.34 0.24 1)
    =<< expectMesh "ship:enemy" renderScene
  assertMesh
    "initial enemy heading"
    "heading:enemy"
    (vec3 (-8) 80 0)
    pi
    (vec3 2 2 0.25)
    (color 0.96 0.9 0.58 1)
    =<< expectMesh "heading:enemy" renderScene
  assertMesh
    "initial enemy target heading"
    "target-heading:enemy"
    (vec3 (-11) 80 0)
    pi
    (vec3 1 1 0.25)
    (color 0.56 0.93 0.7 1)
    =<< expectMesh "target-heading:enemy" renderScene

testDamagedBattleRenderSceneTint :: IO ()
testDamagedBattleRenderSceneTint = do
  let
    damagedDuel =
      caravelaDuel
        { combatEnemy = (combatEnemy caravelaDuel) {shipHull = 50}
        }
    renderScene =
      battleRenderSceneFromSnapshot $
        combatSnapshotFromState caravelaDuelScenario damagedDuel
  enemyShip <- expectMesh "ship:enemy" renderScene
  assertColor
    "damaged enemy ship tint"
    (color 0.565 0.26 0.21 1)
    (materialColor (renderMeshMaterial enemyShip))

expectMesh :: Text -> RenderScene -> IO RenderMesh
expectMesh name renderScene =
  case filter ((== name) . renderMeshName) (renderSceneMeshes renderScene) of
    [mesh] -> pure mesh
    [] -> die $ "missing render mesh " <> show name
    meshes -> die $ "expected one render mesh " <> show name <> ", got " <> show (length meshes)

assertMesh ::
  String ->
  Text ->
  Vec3 ->
  Scalar ->
  Vec3 ->
  Color ->
  RenderMesh ->
  IO ()
assertMesh label expectedName expectedPosition expectedRotation expectedScale expectedColor mesh = do
  assertEqual (label <> " name") expectedName (renderMeshName mesh)
  assertEqual (label <> " geometry") UnitCubeGeometry (renderMeshGeometry mesh)
  assertVec3 (label <> " position") expectedPosition (transformPosition meshTransform)
  assertApproxScalar (label <> " rotation") expectedRotation (transformRotationZ meshTransform)
  assertVec3 (label <> " scale") expectedScale (transformScale meshTransform)
  assertColor (label <> " color") expectedColor (materialColor (renderMeshMaterial mesh))
 where
  meshTransform = renderMeshTransform mesh

assertEnemyHull :: String -> Int -> CombatSnapshot -> IO ()
assertEnemyHull label expected snapshot = do
  enemy <- expectShipSnapshot label EnemyShip snapshot
  assertEqual label expected (shipSnapshotHull enemy)

expectBoatConfig :: String -> Text -> CombatConfig -> IO BoatConfig
expectBoatConfig label boatId config =
  case findBoatConfig boatId config of
    Just boat -> pure boat
    Nothing -> die $ label <> ": missing boat kind " <> Text.unpack boatId

assertDiagnostic :: String -> Text -> [ConfigDiagnostic] -> IO ()
assertDiagnostic label expectedField diagnostics =
  if any ((== Just expectedField) . configDiagnosticField) diagnostics
    then pure ()
    else die $ label <> ": expected field " <> Text.unpack expectedField <> ", got " <> show diagnostics

assertParserDiagnostic :: String -> FilePath -> [ConfigDiagnostic] -> IO ()
assertParserDiagnostic label expectedFile diagnostics =
  if any hasParserLocation diagnostics
    then pure ()
    else die $ label <> ": expected filename, line, and column, got " <> show diagnostics
 where
  hasParserLocation diagnosticValue =
    configDiagnosticFile diagnosticValue == expectedFile
      && configDiagnosticLine diagnosticValue /= Nothing
      && configDiagnosticColumn diagnosticValue /= Nothing

assertSemanticDiagnostic :: String -> Text -> [ConfigDiagnostic] -> IO ()
assertSemanticDiagnostic label expectedField diagnostics =
  if any isActionable diagnostics
    then pure ()
    else die $ label <> ": expected field, explanation, and hint, got " <> show diagnostics
 where
  isActionable diagnosticValue =
    configDiagnosticField diagnosticValue == Just expectedField
      && not (Text.null (configDiagnosticMessage diagnosticValue))
      && not (Text.null (configDiagnosticHint diagnosticValue))

assertInvalidReloadPreservesLiveEngagement :: String -> LocalCombatApi -> CombatConfig -> CombatSnapshot -> [ConfigDiagnostic] -> IO ()
assertInvalidReloadPreservesLiveEngagement label localApi expectedConfig expectedSnapshot diagnostics = do
  result <- localCombatApiAttemptReloadConfig localApi (Left diagnostics)
  assertEqual (label <> " reports diagnostics") (Left diagnostics) result
  activeConfig <- localCombatApiActiveConfig localApi
  assertEqual (label <> " keeps last valid config") (Just expectedConfig) activeConfig
  snapshot <- expectRight (label <> " observes running engagement") =<< combatApiObserveSnapshot (localCombatApi localApi)
  assertEqual (label <> " keeps active snapshot") expectedSnapshot snapshot
