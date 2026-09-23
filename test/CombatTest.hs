{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (replicateM_)
import Data.Text (Text)
import Data.Text qualified as Text
import FlorDoMar.Client.BattleInput
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
  testNavigationPlannerClampsAndCommitsOrders
  testNavigationProjectionMatchesExecution
  testNavigationSteeringDoesNotWeave
  testNavigationArrivalPreservesSpeedIntent
  testMouseNavigationCommandLifecycle
  testStoppedNavigationOrderBuildsWay
  testBroadsideKeepsActiveNavigationOrder
  testDisabledShipsClearAndIgnoreNavigation
  testNavigationSafetyCapIsSurfaced
  testLocalApiExposesNavigationOrder
  testEnemyOrbitAutopilotIssuesNavigationOrders
  testConfiguredBroadsideTuning
  testConfiguredLocalApiBroadsideTuning
  testConfiguredMovementSnapshot
  testConfiguredLocalApiHotReloadsLiveEngagement
  testHotReloadPreservesCommittedNavigationWaypoint
  testInvalidReloadKeepsLastValidConfigAndSnapshot
  testHotReloadPreservesDamageAcrossHullClamp
  testConfiguredLocalApiRestartsSelectedEngagement
  testSetupOverlayState
  testSetupDebugOverlayState
  testLocalApiQueuesCommandsUntilTick
  testLocalApiReportsTerminalState
  testInitialBattleRenderScene
  testDamagedBattleRenderSceneTint
  testActiveNavigationRenderScene
  testEnemyDebugNavigationRenderScene
  testBattleInputHoverIntent
  testBattleInputMouseNavigationGesture
  testHoverNavigationRenderScene
  testHoverNavigationIsHiddenOutsideActiveBattleView
  testSetupOverlayBlocksNavigation
  testFinishedScenarioBlocksNavigation
  testFinishedBattleRenderSceneHidesPlanning
  testSceneGraphTraversal
  testStrokePathRenderPrimitive
  testRingStrokeRenderPrimitive
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

assertPoint :: String -> Point -> Point -> IO ()
assertPoint label expected actual = do
  assertApprox (label <> " x") (pointX expected) (pointX actual)
  assertApprox (label <> " y") (pointY expected) (pointY actual)

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

expectJust :: String -> Maybe a -> IO a
expectJust label value =
  case value of
    Just result -> pure result
    Nothing -> die $ label <> ": expected Just, got Nothing"

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
    inertialConfig = config {combatConfigBoats = fmap (\boat -> boat {boatConfigYawAcceleration = 2.5}) (combatConfigBoats config)}
    initialState = configuredDefaultEngagement inertialConfig
    acceleratingState = tickConfiguredCombat inertialConfig [SetHeading PlayerShip (Heading 90), SetTargetSpeed PlayerShip 2.5] initialState
    acceleratingPlayer = combatPlayer acceleratingState
    turningState = tickConfiguredCombat inertialConfig [] acceleratingState
    turningPlayer = combatPlayer turningState
    starboardAcceleratingState = tickConfiguredCombat inertialConfig [SetHeading PlayerShip (Heading (-90)), SetTargetSpeed PlayerShip 2.5] initialState
    starboardTurningPlayer = combatPlayer (tickConfiguredCombat inertialConfig [] starboardAcceleratingState)
    deceleratingState = tickConfiguredCombat inertialConfig [SetTargetSpeed PlayerShip 0] turningState
    deceleratingPlayer = combatPlayer deceleratingState
    negativeTargetState = tickConfiguredCombat inertialConfig [SetTargetSpeed PlayerShip (-1)] turningState
    negativeTargetPlayer = combatPlayer negativeTargetState
    maximumTargetState = tickConfiguredCombat inertialConfig [SetTargetSpeed PlayerShip 100] initialState
    maximumTargetPlayer = combatPlayer maximumTargetState
    easingState =
      (configuredDefaultEngagement inertialConfig)
        { combatPlayer =
            (combatPlayer (configuredDefaultEngagement inertialConfig))
              { shipCurrentSpeed = 4
              , shipTargetSpeed = 4
              , shipCurrentYawRate = 5
              }
        }
    easingPlayer = combatPlayer (tickConfiguredCombat inertialConfig [] easingState)
  big <- expectBoatConfig "configured big boat has yaw tuning" "big" inertialConfig
  assertApprox "ideal turn speed is configured" 4 (boatConfigIdealTurnSpeed big)
  assertApprox "yaw acceleration is configured" 2.5 (boatConfigYawAcceleration big)
  assertEqual "heading command updates configured target" (Heading 90) (shipTargetHeading acceleratingPlayer)
  assertApprox "continuous target speed is retained" 2.5 (shipTargetSpeed acceleratingPlayer)
  assertApprox "stopped ship cannot turn" 0 (headingDegrees (shipHeading acceleratingPlayer))
  assertApprox "stopped ship has zero yaw rate" 0 (shipCurrentYawRate acceleratingPlayer)
  assertApprox "ship accelerates straight ahead before turning" 1.6 (shipCurrentSpeed acceleratingPlayer)
  assertApprox "straight-ahead acceleration advances position" 1.28 (pointX (shipPosition acceleratingPlayer))
  assertApprox "yaw rate accelerates toward rudder-limited target" 2 (shipCurrentYawRate turningPlayer)
  assertApprox "yaw rate retains starboard sign" (-2) (shipCurrentYawRate starboardTurningPlayer)
  assertApprox "heading advances from signed yaw rate" 1.6 (headingDegrees (shipHeading turningPlayer))
  assertEqual "physical heading keeps port broadside ready" BroadsideReady (canFireBroadside turningState PlayerShip EnemyShip Port)
  assertApprox "continuous speed decelerates toward requested speed" 0.1 (shipCurrentSpeed deceleratingPlayer)
  assertApprox "negative target speed clamps to zero" 0 (shipTargetSpeed negativeTargetPlayer)
  assertApprox "target speed clamps to ship maximum" 4 (shipTargetSpeed maximumTargetPlayer)
  assertApprox "yaw rate eases out without turn intent" 3 (shipCurrentYawRate easingPlayer)
  assertApprox "yaw inertia advances heading while easing out" 2.4 (headingDegrees (shipHeading easingPlayer))

testNavigationPlannerClampsAndCommitsOrders :: IO ()
testNavigationPlannerClampsAndCommitsOrders = do
  let
    tickSeconds = 0.25
    initialState =
      caravelaDuel
        { combatPlayer =
            (combatPlayer caravelaDuel)
              { shipCurrentSpeed = 4
              , shipTargetSpeed = 4
              }
        }
    player = combatPlayer initialState
    tightRequest = Point 0.5 0
    plan = planNavigation tickSeconds navigationMovement player tightRequest
    commanded = tickCombatWith tickSeconds (const navigationMovement) [IssueNavigationOrder PlayerShip tightRequest] initialState
    replacementRequest = Point 30 12
    replaced = tickCombatWith tickSeconds (const navigationMovement) [IssueNavigationOrder PlayerShip replacementRequest] commanded
    changedMovement = navigationMovement {movementTurnRate = 30}
    afterPhysicsChange = tickCombatWith tickSeconds (const changedMovement) [] commanded
    enemyCommanded = tickCombatWith tickSeconds (const navigationMovement) [IssueNavigationOrder EnemyShip (Point 20 65)] initialState
  committed <- expectNavigationOrder "player navigation order is committed" (combatPlayer commanded)
  replacement <- expectNavigationOrder "new navigation order replaces the active order" (combatPlayer replaced)
  preserved <- expectNavigationOrder "committed waypoint survives physics changes" (combatPlayer afterPhysicsChange)
  enemyOrder <- expectNavigationOrder "enemy accepts navigation orders" (combatEnemy enemyCommanded)
  assertEqual "tight request is marked clamped" True (navigationPlanWasClamped plan)
  assertPoint "planner retains requested waypoint" tightRequest (navigationPlanRequestedWaypoint plan)
  assertPoint "order retains requested waypoint" tightRequest (navigationRequestedWaypoint committed)
  assertPoint "command commits planner reachable waypoint" (navigationPlanReachableWaypoint plan) (navigationReachableWaypoint committed)
  assertEqual "clamped waypoint is farther than tight request" True (pointX (navigationReachableWaypoint committed) > pointX tightRequest)
  assertPoint "replacement stores its own requested waypoint" replacementRequest (navigationRequestedWaypoint replacement)
  assertEqual "replacement removes the prior waypoint" False (navigationReachableWaypoint replacement == navigationReachableWaypoint committed)
  assertPoint "committed waypoint remains fixed after command time" (navigationReachableWaypoint committed) (navigationReachableWaypoint preserved)
  assertPoint "enemy order stores requested waypoint" (Point 20 65) (navigationRequestedWaypoint enemyOrder)
  assertPlannerSamplesStartAtZero plan
  assertEqual "planner samples have sequential tick offsets" [0 .. length (navigationPlanSamples plan) - 1] (fmap trajectorySampleTickOffset (navigationPlanSamples plan))

testNavigationProjectionMatchesExecution :: IO ()
testNavigationProjectionMatchesExecution = do
  let
    tickSeconds = 0.25
    requestedWaypoint = Point 26 11
    initialState =
      caravelaDuel
        { combatPlayer =
            (combatPlayer caravelaDuel)
              { shipCurrentSpeed = 3
              , shipTargetSpeed = 3
              }
        }
    initialPlayer = combatPlayer initialState
    plan = planNavigation tickSeconds navigationMovement initialPlayer requestedWaypoint
    expectedSamples = drop 1 (navigationPlanSamples plan)
    executionCommands = [IssueNavigationOrder PlayerShip requestedWaypoint] : replicate (length expectedSamples - 1) []
    executedStates = drop 1 (scanl (flip (tickCombatWith tickSeconds (const navigationMovement))) initialState executionCommands)
  assertEqual "planner exposes selected samples only through its sample list" (length expectedSamples + 1) (length (navigationPlanSamples plan))
  mapM_ (uncurry assertSampleMatchesShip) (zip expectedSamples (fmap combatPlayer executedStates))

testNavigationArrivalPreservesSpeedIntent :: IO ()
testNavigationArrivalPreservesSpeedIntent = do
  let
    tickSeconds = 0.25
    requestedWaypoint = Point 16 0
    initialState =
      caravelaDuel
        { combatPlayer =
            (combatPlayer caravelaDuel)
              { shipCurrentSpeed = 4
              , shipTargetSpeed = 3
              }
        }
    ordered = tickCombatWith tickSeconds (const navigationMovement) [IssueNavigationOrder PlayerShip requestedWaypoint] initialState
    arrived = advanceUntilNavigationClears 100 (tickCombatWith tickSeconds (const navigationMovement) []) ordered
    orderedPlayer = combatPlayer ordered
    arrivedPlayer = combatPlayer arrived
  order <- expectNavigationOrder "navigation order remains active before arrival" orderedPlayer
  assertEqual "arrival clears active waypoint" Nothing (shipNavigationOrder arrivedPlayer)
  assertApprox "arrival leaves post-waypoint speed intent" (navigationPostWaypointSpeed order) (shipTargetSpeed arrivedPlayer)

testNavigationSteeringDoesNotWeave :: IO ()
testNavigationSteeringDoesNotWeave = do
  let
    tickSeconds = 0.25
    -- A long order that is mostly forward but well off the bow. Anything that
    -- hunts around its bearing shows up here as repeated turn reversals.
    requestedWaypoint = Point 60 25
    initialState =
      caravelaDuel
        { combatPlayer =
            (combatPlayer caravelaDuel)
              { shipCurrentSpeed = 0
              , shipTargetSpeed = 4
              }
        }
    initialPlayer = combatPlayer initialState
    ordered = tickCombatWith tickSeconds (const navigationMovement) [IssueNavigationOrder PlayerShip requestedWaypoint] initialState
    execution = take 200 (iterate (tickCombatWith tickSeconds (const navigationMovement) []) ordered)
    executed = takeWhile (maybe False (const True) . shipNavigationOrder . combatPlayer) execution
    reachedWaypoint = length executed < length execution
    yawRates = fmap (shipCurrentYawRate . combatPlayer) executed
    turnRuns = fmap signum (filter ((> 1e-9) . abs) yawRates)
    reversals = length (filter id (zipWith (/=) turnRuns (drop 1 turnRuns)))

  -- Relay steering reverses turn direction every time yaw inertia carries the
  -- ship past its bearing, so one order produced several reversals and a path
  -- 1.45x the direct distance. A proportional command settles instead.
  assertEqual "navigation steering holds one turn direction along the approach" 0 reversals
  assertEqual "navigation steering settles on the waypoint instead of orbiting it" True reachedWaypoint

  -- The command must still be proportional rather than a relay: a large error
  -- saturates at the whole turn rate, while a smaller one asks for strictly
  -- less. A sign-only law cannot tell the two apart.
  assertApprox "error beyond the proportional band saturates at full rudder authority"
    (movementTurnRate navigationMovement)
    (abs (targetYawRate navigationMovement (steeringProbe 180)))
  assertApprox "error inside the proportional band asks for yaw below full rudder authority"
    (60 / navigationHeadingCorrectionSeconds)
    (abs (targetYawRate navigationMovement (steeringProbe 60)))

  -- No turn intent still settles to zero, so a ship without a waypoint eases
  -- out of its turn according to yaw inertia rather than holding a command.
  assertApprox "no turn intent commands zero yaw rate"
    0
    (targetYawRate navigationMovement initialPlayer)

steeringProbe :: Double -> Ship
steeringProbe headingError =
  (combatPlayer caravelaDuel)
    { shipCurrentSpeed = movementIdealTurnSpeed navigationMovement
    , shipHeading = Heading 0
    , shipTargetHeading = Heading headingError
    }

testMouseNavigationCommandLifecycle :: IO ()
testMouseNavigationCommandLifecycle = do
  let
    tickSeconds = 0.25
    requestedWaypoint = Point 0.5 0
    initialState =
      caravelaDuel
        { combatPlayer =
            (combatPlayer caravelaDuel)
              { shipCurrentSpeed = 3
              , shipTargetSpeed = 3
              }
        }
    clickPlan = planNavigation tickSeconds navigationMovement (combatPlayer initialState) requestedWaypoint
    clicked =
      tickCombatWith
        tickSeconds
        (const navigationMovement)
        [IssueNavigationOrder PlayerShip requestedWaypoint]
        initialState
    dragged =
      tickCombatWith
        tickSeconds
        (const navigationMovement)
        [SetNavigationPostWaypointSpeed PlayerShip 4.5]
        clicked
    stoppedState =
      initialState
        { combatPlayer =
            (combatPlayer initialState)
              { shipCurrentSpeed = 0
              , shipTargetSpeed = 0
              }
        }
    arrivedBeforeRelease =
      tickCombatWith
        tickSeconds
        (const navigationMovement)
        [IssueNavigationOrder PlayerShip (Point 1 0)]
        stoppedState
    releasedAfterArrival =
      tickCombatWith
        tickSeconds
        (const navigationMovement)
        [SetNavigationPostWaypointSpeed PlayerShip 4.5]
        arrivedBeforeRelease
    replacementWaypoint = Point (-24) 18
    replaced =
      tickCombatWith
        tickSeconds
        (const navigationMovement)
        [IssueNavigationOrder PlayerShip replacementWaypoint]
        dragged
  clickOrder <- expectNavigationOrder "mouse down commits a navigation order" (combatPlayer clicked)
  draggedOrder <- expectNavigationOrder "drag release keeps the navigation order active" (combatPlayer dragged)
  replacementOrder <- expectNavigationOrder "new mouse navigation order replaces active order" (combatPlayer replaced)
  assertApprox
    "plain click inherits arrival speed as post-waypoint speed"
    (navigationPlanArrivalSpeed clickPlan)
    (navigationPostWaypointSpeed clickOrder)
  assertEqual "tight mouse-down request is clamped" True (navigationPlanWasClamped clickPlan)
  assertPoint "mouse down retains the raw requested waypoint" requestedWaypoint (navigationRequestedWaypoint clickOrder)
  assertPoint "mouse down commits the planner reachable waypoint" (navigationPlanReachableWaypoint clickPlan) (navigationReachableWaypoint clickOrder)
  assertApprox "drag release updates active order post-waypoint speed" 4.5 (navigationPostWaypointSpeed draggedOrder)
  assertApprox "drag release leaves current target speed alone before arrival" 3 (shipTargetSpeed (combatPlayer dragged))
  assertEqual "near waypoint clears before release" Nothing (shipNavigationOrder (combatPlayer arrivedBeforeRelease))
  assertApprox "release after arrival sets current target speed" 4.5 (shipTargetSpeed (combatPlayer releasedAfterArrival))
  assertPoint "replacement order takes effect immediately on its tick" replacementWaypoint (navigationRequestedWaypoint replacementOrder)

testStoppedNavigationOrderBuildsWay :: IO ()
testStoppedNavigationOrderBuildsWay = do
  let
    tickSeconds = 0.25
    stoppedState =
      caravelaDuel
        { combatPlayer =
            (combatPlayer caravelaDuel)
              { shipCurrentSpeed = 0
              , shipTargetSpeed = 0
              }
        }
    ordered =
      tickCombatWith
        tickSeconds
        (const navigationMovement)
        [IssueNavigationOrder PlayerShip (Point 40 20)]
        stoppedState
    player = combatPlayer ordered
  assertApprox "stopped navigation sets cruise target speed" (movementBattleSpeed navigationMovement) (shipTargetSpeed player)
  assertApprox "stopped navigation builds way before turning" 1 (shipCurrentSpeed player)
  assertApprox "stopped navigation accelerates straight ahead" 0.25 (pointX (shipPosition player))
  assertApprox "stopped navigation has not turned before building way" 0 (headingDegrees (shipHeading player))

testBroadsideKeepsActiveNavigationOrder :: IO ()
testBroadsideKeepsActiveNavigationOrder = do
  let
    ordered = tickCombat [IssueNavigationOrder PlayerShip (Point 40 20)] caravelaDuel
    fired = tickCombat [FireBroadside PlayerShip EnemyShip Port] ordered
  orderBeforeFiring <- expectNavigationOrder "navigation order before broadside" (combatPlayer ordered)
  orderAfterFiring <- expectNavigationOrder "navigation order after broadside" (combatPlayer fired)
  assertEqual "broadside damages independently of navigation" 75 (shipHull (combatEnemy fired))
  assertEqual "broadside does not mutate the active navigation order" orderBeforeFiring orderAfterFiring

testDisabledShipsClearAndIgnoreNavigation :: IO ()
testDisabledShipsClearAndIgnoreNavigation = do
  let
    ordered = tickCombat [IssueNavigationOrder PlayerShip (Point 40 20)] caravelaDuel
    disabled =
      ordered
        { combatPlayer =
            (combatPlayer ordered)
              { shipHull = 0
              }
        }
    attemptedNavigation =
      tickCombat
        [ IssueNavigationOrder PlayerShip (Point (-40) 20)
        , SetNavigationPostWaypointSpeed PlayerShip 0
        ]
        disabled
    disabledSnapshot = combatSnapshotFromState caravelaDuelScenario attemptedNavigation
  disabledPlayer <- expectShipSnapshot "disabled player navigation snapshot" PlayerShip disabledSnapshot
  assertEqual "disabled ship clears an active navigation order" Nothing (shipNavigationOrder (combatPlayer attemptedNavigation))
  assertEqual "disabled ship ignores new navigation intent" (shipTargetSpeed (combatPlayer ordered)) (shipTargetSpeed (combatPlayer attemptedNavigation))
  assertEqual "disabled ship has no active navigation projection" Nothing (shipSnapshotActiveNavigationPlan disabledPlayer)

testNavigationSafetyCapIsSurfaced :: IO ()
testNavigationSafetyCapIsSurfaced = do
  let
    tickSeconds = 0.25
    initialState =
      caravelaDuel
        { combatPlayer =
            (combatPlayer caravelaDuel)
              { shipCurrentSpeed = 4
              , shipTargetSpeed = 4
              }
        }
    ordered = tickCombatWith tickSeconds (const navigationMovement) [IssueNavigationOrder PlayerShip (Point 0 60)] initialState
    noTurnMovement = navigationMovement {movementTurnRate = 0}
  order <- expectNavigationOrder "navigation order before safety fallback" (combatPlayer ordered)
  cappedPlan <- expectJust "active navigation plan after physics change" (planActiveNavigation tickSeconds noTurnMovement (combatPlayer ordered))
  assertPoint "safety fallback keeps the committed waypoint" (navigationReachableWaypoint order) (navigationPlanReachableWaypoint cappedPlan)
  assertEqual "safety fallback is surfaced instead of reclamping" True (navigationPlanReachedSafetyCap cappedPlan)

testLocalApiExposesNavigationOrder :: IO ()
testLocalApiExposesNavigationOrder = do
  (api, _) <- startLocalDuel
  let requestedWaypoint = Point 24 8
  _ <- queueLocalCommand "queue local navigation order" api (IssueNavigationOrder PlayerShip requestedWaypoint)
  snapshot <- advanceLocalApiTick "advance local navigation order" api
  player <- expectShipSnapshot "navigation order snapshot" PlayerShip snapshot
  order <- expectSnapshotNavigationOrder "snapshot exposes active navigation order" player
  assertPoint "snapshot keeps requested waypoint" requestedWaypoint (navigationRequestedWaypoint order)
  assertEqual "snapshot navigation order post-waypoint speed is non-negative" True (navigationPostWaypointSpeed order >= 0)

testEnemyOrbitAutopilotIssuesNavigationOrders :: IO ()
testEnemyOrbitAutopilotIssuesNavigationOrders = do
  let
    initialState = caravelaDuel
    initialCenter = shipPosition (combatEnemy initialState)
    firstOrdered = tickCombat [] initialState
    firstEnemy = combatEnemy firstOrdered
    firstAutopilot = combatEnemyOrbitAutopilot firstOrdered
  firstOrder <- expectNavigationOrder "enemy autopilot issues a navigation order" firstEnemy
  let
    reachedFirstWaypoint =
      firstOrdered
        { combatEnemy =
            firstEnemy
              { shipPosition = navigationReachableWaypoint firstOrder
              , shipHeading = Heading 0
              , shipTargetHeading = Heading 0
              , shipCurrentSpeed = 0
              }
        }
    afterArrival = tickCombat [] reachedFirstWaypoint
    nextAutopilot = combatEnemyOrbitAutopilot afterArrival
  nextOrder <- expectNavigationOrder "enemy autopilot issues the next order after arrival" (combatEnemy afterArrival)
  assertPoint "first orbit center is the enemy starting position" initialCenter (enemyOrbitCenter firstAutopilot)
  assertApprox "first orbit waypoint uses the fixed radius" enemyOrbitRadius (pointDistance initialCenter (navigationRequestedWaypoint firstOrder))
  assertEqual "first orbit order is an ordinary navigation order" (navigationRequestedWaypoint firstOrder) (navigationReachableWaypoint firstOrder)
  assertEqual "orbit advances after issuing a successive waypoint" 2 (enemyOrbitNextWaypointIndex nextAutopilot)
  assertApprox "next orbit waypoint keeps the fixed radius" enemyOrbitRadius (pointDistance initialCenter (navigationRequestedWaypoint nextOrder))

navigationMovement :: MovementPhysics
navigationMovement =
  MovementPhysics
    { movementBattleSpeed = 4
    , movementMaxSpeed = 6
    , movementAcceleration = 4
    , movementDeceleration = 4
    , movementTurnRate = 90
    , movementIdealTurnSpeed = 4
    , movementYawAcceleration = 180
    }

expectNavigationOrder :: String -> Ship -> IO NavigationOrder
expectNavigationOrder label ship =
  case shipNavigationOrder ship of
    Just order -> pure order
    Nothing -> die $ label <> ": expected an active navigation order"

expectSnapshotNavigationOrder :: String -> ShipSnapshot -> IO NavigationOrder
expectSnapshotNavigationOrder label ship =
  case shipSnapshotNavigationOrder ship of
    Just order -> pure order
    Nothing -> die $ label <> ": expected an active navigation order in the snapshot"

assertPlannerSamplesStartAtZero :: NavigationPlan -> IO ()
assertPlannerSamplesStartAtZero plan =
  case navigationPlanSamples plan of
    firstSample : _ -> assertEqual "planner samples start at tick zero" 0 (trajectorySampleTickOffset firstSample)
    [] -> die "planner returned no trajectory samples"

assertSampleMatchesShip :: TrajectorySample -> Ship -> IO ()
assertSampleMatchesShip sample ship = do
  assertPoint "projection position matches simulation" (trajectorySamplePosition sample) (shipPosition ship)
  assertApprox "projection heading matches simulation" (headingDegrees (trajectorySampleHeading sample)) (headingDegrees (shipHeading ship))
  assertApprox "projection speed matches simulation" (trajectorySampleSpeed sample) (shipCurrentSpeed ship)
  assertApprox "projection yaw rate matches simulation" (trajectorySampleYawRate sample) (shipCurrentYawRate ship)

advanceUntilNavigationClears :: Int -> (CombatState -> CombatState) -> CombatState -> CombatState
advanceUntilNavigationClears remaining advance state
  | shipNavigationOrder (combatPlayer state) == Nothing = state
  | remaining <= 0 = error "navigation order did not arrive before the test safety limit"
  | otherwise = advanceUntilNavigationClears (remaining - 1) advance (advance state)

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
  assertApprox "configured heading intent does not replace physical heading for broadside" 0 (headingDegrees (shipHeading (combatPlayer bigFired)))
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
  _ <- queueLocalCommand "queue configured heading" api (SetHeading PlayerShip (Heading (-90)))
  _ <- queueLocalCommand "queue configured target speed" api (SetTargetSpeed PlayerShip 2.5)
  snapshot <- advanceLocalApiTick "advance configured movement snapshot" api
  player <- expectShipSnapshot "configured movement snapshot player" PlayerShip snapshot
  secondSnapshot <- advanceLocalApiTick "advance configured movement snapshot again" api
  secondPlayer <- expectShipSnapshot "configured movement snapshot player after yaw acceleration" PlayerShip secondSnapshot
  assertApprox "snapshot exposes physical heading" 0 (headingDegrees (shipSnapshotHeading player))
  assertEqual "snapshot exposes target heading" (Heading 270) (shipSnapshotTargetHeading player)
  assertApprox "snapshot exposes current speed" 1.6 (shipSnapshotCurrentSpeed player)
  assertApprox "snapshot exposes continuous target speed" 2.5 (shipSnapshotTargetSpeed player)
  assertApprox "snapshot exposes signed current yaw rate" 0 (shipSnapshotCurrentYawRate player)
  assertApprox "snapshot exposes signed yaw rate after acceleration" (-8) (shipSnapshotCurrentYawRate secondPlayer)

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

testHotReloadPreservesCommittedNavigationWaypoint :: IO ()
testHotReloadPreservesCommittedNavigationWaypoint = do
  config <- expectRight "load packaged config for navigation hot reload" =<< loadRuntimeCombatConfig
  localApi <- newConfiguredLocalCombatApi config
  let
    api = localCombatApi localApi
    reloadedConfig =
      config
        { combatConfigPhysics = PhysicsConfig 0.5
        , combatConfigBoats = fmap tuneNavigationPhysics (combatConfigBoats config)
        }
  _ <- expectRight "start configured scenario before navigation hot reload" =<< combatApiStartScenario api caravelaDuelScenarioId
  _ <- queueLocalCommand "queue navigation before hot reload" api (IssueNavigationOrder PlayerShip (Point 45 30))
  beforeReload <- advanceLocalApiTick "advance navigation before hot reload" api
  playerBefore <- expectShipSnapshot "player before navigation hot reload" PlayerShip beforeReload
  orderBefore <- expectSnapshotNavigationOrder "order before navigation hot reload" playerBefore
  planBefore <- expectSnapshotNavigationPlan "plan before navigation hot reload" playerBefore
  localCombatApiReloadConfig localApi reloadedConfig
  afterReload <- expectRight "observe navigation after hot reload" =<< combatApiObserveSnapshot api
  playerAfter <- expectShipSnapshot "player after navigation hot reload" PlayerShip afterReload
  orderAfter <- expectSnapshotNavigationOrder "order after navigation hot reload" playerAfter
  planAfter <- expectSnapshotNavigationPlan "plan after navigation hot reload" playerAfter
  assertPoint "hot reload does not move the committed waypoint" (navigationReachableWaypoint orderBefore) (navigationReachableWaypoint orderAfter)
  assertPoint "hot reload reprojects to the original committed waypoint" (navigationReachableWaypoint orderBefore) (navigationPlanReachableWaypoint planAfter)
  assertEqual "hot reload retains the requested waypoint metadata" (navigationRequestedWaypoint orderBefore) (navigationRequestedWaypoint orderAfter)
  assertEqual "hot reload keeps the latest actual position" (shipSnapshotPosition playerBefore) (shipSnapshotPosition playerAfter)
  assertApprox "hot reload exposes the updated tick duration to planning" 0.5 (combatSnapshotTickSeconds afterReload)
  assertApprox "hot reload exposes updated turn physics to planning" 120 (movementTurnRate (shipSnapshotMovementPhysics playerAfter))
  assertEqual "hot reload recomputes the projection with new physics" False (navigationPlanSamples planBefore == navigationPlanSamples planAfter)
 where
  tuneNavigationPhysics boat
    | boatConfigId boat == "big" =
        boat
          { boatConfigMaxSpeed = 6
          , boatConfigAcceleration = 5
          , boatConfigTurnRate = 120
          , boatConfigYawAcceleration = 80
          }
    | otherwise = boat

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

testSetupDebugOverlayState :: IO ()
testSetupDebugOverlayState = do
  let
    engagement = EngagementSetup "big" "small"
    initialState = initialSetupState engagement
    openedState = applySetupAction ToggleSetupOverlay initialState
    disabledState = applySetupAction (SetDebugOverlaysEnabled False) openedState
    launchedState = applySetupAction LaunchEngagement disabledState
    reopenedState = applySetupAction ToggleSetupOverlay launchedState
    enabledState = applySetupAction (SetDebugOverlaysEnabled True) reopenedState
    nextClientSession = initialSetupState engagement
  assertEqual "debug overlays default on" True (setupDebugOverlaysEnabled initialState)
  assertEqual "debug toggle applies while the engagement is active" False (setupDebugOverlaysEnabled disabledState)
  assertEqual "debug toggle does not alter the selected engagement" engagement (setupSelectedEngagement disabledState)
  assertEqual "debug toggle persists through launch in this client session" False (setupDebugOverlaysEnabled launchedState)
  assertEqual "debug toggle can be changed immediately after reopening setup" True (setupDebugOverlaysEnabled enabledState)
  assertEqual "new client setup state starts with the default debug flag" True (setupDebugOverlaysEnabled nextClientSession)

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
    primitives = renderScenePrimitives renderScene
  assertVec2 "render camera center" (vec2 0 40) (cameraCenter camera)
  assertApproxScalar "render camera viewport width" 160 (viewportWidth (cameraViewport camera))
  assertApproxScalar "render camera viewport height" 90 (viewportHeight (cameraViewport camera))
  assertApproxScalar "render camera zoom" 1 (cameraZoom camera)
  assertEqual "render mesh count" 6 (length meshes)
  assertEqual "ship nodes flatten to render primitives" 6 (length primitives)
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

testActiveNavigationRenderScene :: IO ()
testActiveNavigationRenderScene = do
  let
    requestedWaypoint = Point 40 20
    ordered = tickCombat [IssueNavigationOrder PlayerShip requestedWaypoint] caravelaDuel
    advanced = tickCombat [] ordered
    orderedSnapshot = combatSnapshotFromState caravelaDuelScenario ordered
    advancedSnapshot = combatSnapshotFromState caravelaDuelScenario advanced
    orderedScene = battleRenderSceneFromSnapshot orderedSnapshot
    advancedScene = battleRenderSceneFromSnapshot advancedSnapshot
  orderedPlayer <- expectShipSnapshot "active navigation render snapshot" PlayerShip orderedSnapshot
  order <- expectSnapshotNavigationOrder "active navigation render order" orderedPlayer
  plan <- expectSnapshotNavigationPlan "active navigation render plan" orderedPlayer
  trajectory <- expectStrokePath "trajectory:player" orderedScene
  maximumRing <- expectRingStroke "speed-ring:max:player" orderedScene
  pendingRing <- expectRingStroke "speed-ring:pending:player" orderedScene
  let
    (trajectoryTransform, trajectoryPoints) = trajectory
    (maximumRingTransform, maximumRingRadius) = maximumRing
    (pendingRingTransform, pendingRingRadius) = pendingRing
  assertEqual "active trajectory uses selected planner samples" (fmap (pointPosition . trajectorySamplePosition) (navigationPlanSamples plan)) trajectoryPoints
  assertVec3 "active trajectory sits above water" (vec3 0 0 0.1) (transformPosition trajectoryTransform)
  assertVec3 "maximum speed ring stays at committed waypoint" (waypointPosition order) (transformPosition maximumRingTransform)
  assertVec3 "pending speed ring stays at committed waypoint" (waypointPosition order) (transformPosition pendingRingTransform)
  assertApproxScalar "maximum speed ring has fixed radius" 8 maximumRingRadius
  assertApproxScalar
    "pending speed ring scales to maximum speed"
    (8 * realToFrac (navigationPostWaypointSpeed order / shipSnapshotMaxSpeed orderedPlayer))
    pendingRingRadius
  advancedPlayer <- expectShipSnapshot "advanced active navigation render snapshot" PlayerShip advancedSnapshot
  advancedOrder <- expectSnapshotNavigationOrder "advanced active navigation render order" advancedPlayer
  advancedPlan <- expectSnapshotNavigationPlan "advanced active navigation render plan" advancedPlayer
  advancedTrajectory <- expectStrokePath "trajectory:player" advancedScene
  (advancedRingTransform, _) <- expectRingStroke "speed-ring:max:player" advancedScene
  firstAdvancedSample <- expectFirstTrajectorySample "advanced active navigation render plan" advancedPlan
  assertPoint "remaining trajectory starts at latest actual position" (shipSnapshotPosition advancedPlayer) (trajectorySamplePosition firstAdvancedSample)
  assertEqual "remaining trajectory does not keep prior path history" False (snd trajectory == snd advancedTrajectory)
  assertVec3 "speed ring remains visible at its committed waypoint" (waypointPosition advancedOrder) (transformPosition advancedRingTransform)

testEnemyDebugNavigationRenderScene :: IO ()
testEnemyDebugNavigationRenderScene = do
  let
    snapshot = combatSnapshotFromState caravelaDuelScenario (tickCombat [] caravelaDuel)
    debugScene =
      battleRenderScene $
        battleSceneFromSnapshotWithNavigationGestureAndDebug False True Nothing NoNavigationGesture snapshot
    normalScene =
      battleRenderScene $
        battleSceneFromSnapshotWithNavigationGestureAndDebug False False Nothing NoNavigationGesture snapshot
  enemy <- expectShipSnapshot "enemy debug render snapshot" EnemyShip snapshot
  order <- expectSnapshotNavigationOrder "enemy debug navigation order" enemy
  plan <- expectSnapshotNavigationPlan "enemy debug navigation plan" enemy
  (trajectoryTransform, trajectoryPoints) <- expectStrokePath "trajectory:enemy" debugScene
  (maximumRingTransform, _) <- expectRingStroke "speed-ring:max:enemy" debugScene
  (pendingRingTransform, _) <- expectRingStroke "speed-ring:pending:enemy" debugScene
  assertEqual "enemy debug trajectory uses the active navigation plan" (fmap (pointPosition . trajectorySamplePosition) (navigationPlanSamples plan)) trajectoryPoints
  assertVec3 "enemy debug trajectory sits above water" (vec3 0 0 0.1) (transformPosition trajectoryTransform)
  assertVec3 "enemy debug maximum speed ring stays at the waypoint" (waypointPosition order) (transformPosition maximumRingTransform)
  assertVec3 "enemy debug pending speed ring stays at the waypoint" (waypointPosition order) (transformPosition pendingRingTransform)
  assertEqual "enemy debug overlays are omitted when disabled" [] (enemyNavigationNodes normalScene)

testBattleInputHoverIntent :: IO ()
testBattleInputHoverIntent = do
  let
    centerPointer =
      PointerMoved
        (ScreenPoint 380 214)
        (ScreenSize 760 428)
    hoverIntent = hoverIntentFromRawPointer battleCamera centerPointer
  assertEqual "canvas center becomes navigation hover intent" (PreviewNavigation (Point 0 40)) hoverIntent
  assertEqual
    "pointer movement updates hover state"
    (Just (Point 0 40))
    (applyNavigationHoverIntent Nothing hoverIntent)
  assertEqual
    "leaving battle view clears hover state"
    Nothing
    (applyNavigationHoverIntent (Just (Point 0 40)) (hoverIntentFromRawPointer battleCamera PointerLeftBattleView))
  assertEqual
    "other controls clear hover state"
    Nothing
    (applyNavigationHoverIntent (Just (Point 0 40)) (hoverIntentFromRawPointer battleCamera PointerMovedOverControl))

testBattleInputMouseNavigationGesture :: IO ()
testBattleInputMouseNavigationGesture = do
  tightPlan <-
    expectJust
      "tight mouse-down has a navigation plan"
      ( planNavigationForSnapshot
          (combatSnapshotFromState caravelaDuelScenario caravelaDuel)
          PlayerShip
          (Point 0.5 0)
      )
  let
    centerPointer =
      ScreenPoint 380 214
    canvasSize = ScreenSize 760 428
    mouseDownIntent =
      navigationPointerIntentFromRawPointer
        battleCamera
        (RawPrimaryPointerDown centerPointer canvasSize)
    reachableWaypoint = navigationPlanReachableWaypoint tightPlan
    gesture = beginNavigationGesture reachableWaypoint 6
    eastDrag = updateNavigationGesture (offsetPoint reachableWaypoint 4 0) gesture
    northDrag = updateNavigationGesture (offsetPoint reachableWaypoint 0 4) gesture
    stoppedDrag = updateNavigationGesture reachableWaypoint gesture
    maximumDrag = updateNavigationGesture (offsetPoint reachableWaypoint 20 0) gesture
    dragScene =
      battleRenderScene $
        battleSceneFromSnapshotWithNavigationGesture
          False
          Nothing
          eastDrag
          (combatSnapshotFromState caravelaDuelScenario caravelaDuel)
  assertEqual
    "primary mouse down becomes a semantic navigation intent"
    (NavigationPointerPrimaryDown (Point 0 40))
    mouseDownIntent
  assertEqual "tight gesture plan is clamped" True (navigationPlanWasClamped tightPlan)
  assertEqual "drag gesture centers on the reachable waypoint" False (reachableWaypoint == Point 0.5 0)
  assertEqual "plain click leaves post-waypoint speed inherited" Nothing (navigationGestureSelectedSpeed gesture)
  assertApprox "drag distance selects a proportional speed" 3 =<< expectJust "east drag selects speed" (navigationGestureSelectedSpeed eastDrag)
  assertApprox "drag direction has no gameplay meaning" 3 =<< expectJust "north drag selects speed" (navigationGestureSelectedSpeed northDrag)
  assertApprox "dragging from waypoint center selects stopped speed" 0 =<< expectJust "center drag selects speed" (navigationGestureSelectedSpeed stoppedDrag)
  assertApprox "dragging past the speed ring selects maximum speed" 6 =<< expectJust "outer drag selects speed" (navigationGestureSelectedSpeed maximumDrag)
  (dragRingTransform, dragRingRadius) <- expectRingStroke "drag-speed-ring:player" dragScene
  assertVec3
    "drag speed ring stays at the reachable waypoint"
    (vec3 (realToFrac (pointX reachableWaypoint)) (realToFrac (pointY reachableWaypoint)) 0.2)
    (transformPosition dragRingTransform)
  assertApproxScalar "drag speed ring previews the selected speed" 4 dragRingRadius

testHoverNavigationRenderScene :: IO ()
testHoverNavigationRenderScene = do
  let
    ordered = tickCombat [IssueNavigationOrder PlayerShip (Point 40 20)] caravelaDuel
    requestedWaypoint = shipPosition (combatPlayer ordered)
    snapshot = combatSnapshotFromState caravelaDuelScenario ordered
    scene = battleSceneFromSnapshotWithHover False (Just requestedWaypoint) snapshot
    renderScene = battleRenderScene scene
  expectedPlan <- expectHoverNavigationPlan "hover navigation plan" scene
  snapshotPlan <- expectJust "snapshot hover navigation plan" (planNavigationForSnapshot snapshot PlayerShip requestedWaypoint)
  player <- expectShipSnapshot "hover navigation player" PlayerShip snapshot
  activeTrajectory <- expectStrokePath "trajectory:player" renderScene
  hoverTrajectory <- expectStrokePath "hover-trajectory:player" renderScene
  (maximumRingTransform, maximumRingRadius) <- expectRingStroke "hover-speed-ring:max:player" renderScene
  (arrivalRingTransform, arrivalRingRadius) <- expectRingStroke "hover-speed-ring:arrival:player" renderScene
  assertEqual "hover uses the snapshot planner result" snapshotPlan expectedPlan
  assertEqual "hover clamps a tight cursor waypoint" True (navigationPlanWasClamped expectedPlan)
  assertEqual "active trajectory remains beside hover preview" False (snd activeTrajectory == snd hoverTrajectory)
  assertEqual "hover trajectory uses selected planner samples" (fmap (pointPosition . trajectorySamplePosition) (navigationPlanSamples expectedPlan)) (snd hoverTrajectory)
  assertVec3 "hover maximum speed ring sits at reachable waypoint" (hoverWaypointPosition expectedPlan) (transformPosition maximumRingTransform)
  assertVec3 "hover arrival speed ring sits at reachable waypoint" (hoverWaypointPosition expectedPlan) (transformPosition arrivalRingTransform)
  assertApproxScalar "hover maximum speed ring has fixed radius" 8 maximumRingRadius
  assertApproxScalar
    "hover arrival ring shows expected arrival speed"
    (8 * realToFrac (navigationPlanArrivalSpeed expectedPlan / shipSnapshotMaxSpeed player))
    arrivalRingRadius

testHoverNavigationIsHiddenOutsideActiveBattleView :: IO ()
testHoverNavigationIsHiddenOutsideActiveBattleView = do
  let
    requestedWaypoint = Point 30 20
    runningSnapshot = combatSnapshotFromState caravelaDuelScenario caravelaDuel
    finishedSnapshot =
      combatSnapshotFromState
        caravelaDuelScenario
        (caravelaDuel {combatStatus = ScenarioFinished (Winner PlayerShip)})
    setupScene = battleRenderScene (battleSceneFromSnapshotWithHover True (Just requestedWaypoint) runningSnapshot)
    finishedScene = battleRenderScene (battleSceneFromSnapshotWithHover False (Just requestedWaypoint) finishedSnapshot)
  assertEqual "setup overlay hides hover preview" [] (hoverPlanningNodes setupScene)
  assertEqual "finished scenario hides hover preview" [] (hoverPlanningNodes finishedScene)

testSetupOverlayBlocksNavigation :: IO ()
testSetupOverlayBlocksNavigation = do
  let
    snapshot =
      combatSnapshotFromState
        caravelaDuelScenario
        (tickCombat [IssueNavigationOrder PlayerShip (Point 40 20)] caravelaDuel)
    gesture = NavigationGesture (Point 40 20) 4 (Just 2)
    setupScene = battleRenderScene (battleSceneFromSnapshotWithNavigationGesture True (Just (Point 30 20)) gesture snapshot)
  assertEqual "setup overlay rejects navigation input" False (navigationInputAllowed True ScenarioRunning)
  assertEqual "setup overlay hides active, hover, and drag planning overlays" [] (filter isPlanningNode (renderSceneNodes setupScene))

testFinishedScenarioBlocksNavigation :: IO ()
testFinishedScenarioBlocksNavigation = do
  let
    finishedState =
      (tickCombat [IssueNavigationOrder PlayerShip (Point 40 20)] caravelaDuel)
        { combatStatus = ScenarioFinished (Winner PlayerShip)
        }
    finishedSnapshot = combatSnapshotFromState caravelaDuelScenario finishedState
    gesture = NavigationGesture (Point 40 20) 4 (Just 2)
    finishedScene = battleRenderScene (battleSceneFromSnapshotWithNavigationGesture False (Just (Point 30 20)) gesture finishedSnapshot)
  assertEqual "finished scenario rejects navigation input" False (navigationInputAllowed False (combatSnapshotStatus finishedSnapshot))
  assertEqual "finished scenario rejects navigation planning" Nothing (planNavigationForSnapshot finishedSnapshot PlayerShip (Point 30 20))
  assertEqual "finished scenario hides active, hover, and drag planning overlays" [] (filter isPlanningNode (renderSceneNodes finishedScene))

testFinishedBattleRenderSceneHidesPlanning :: IO ()
testFinishedBattleRenderSceneHidesPlanning = do
  let
    ordered = tickCombat [IssueNavigationOrder PlayerShip (Point 40 20)] caravelaDuel
    finished = ordered {combatStatus = ScenarioFinished (Winner PlayerShip)}
    renderScene = battleRenderSceneFromSnapshot (combatSnapshotFromState caravelaDuelScenario finished)
    planningNodes = filter isPlanningNode (renderSceneNodes renderScene)
  assertEqual "finished scenarios hide active planning overlays" [] planningNodes

testSceneGraphTraversal :: IO ()
testSceneGraphTraversal = do
  let
    scene =
      RenderScene
        { renderSceneCamera = camera2D (viewport 160 90)
        , renderSceneNodes =
            [ RenderGroup
                "fleet"
                (transform (vec3 10 20 0.5) (pi / 2) (vec3 1 1 1))
                [ RenderMeshNode
                    RenderMesh
                      { renderMeshName = "ship"
                      , renderMeshGeometry = UnitCubeGeometry
                      , renderMeshMaterial = basicMaterial (color 1 1 1 1)
                      , renderMeshTransform = transform (vec3 2 0 0) 0 (vec3 1 1 1)
                      }
                ]
            ]
        }
  primitive <- expectRenderPrimitive "ship" scene
  assertEqual "scene graph keeps mesh nodes" 1 (length (renderSceneMeshes scene))
  assertVec3
    "scene graph composes parent transform"
    (vec3 10 22 0.5)
    (transformPoint3 (renderPrimitiveWorldMatrix primitive) (vec3 0 0 0))
  assertApproxScalar
    "quaternion-backed helper rotation remains readable"
    (pi / 2)
    (transformRotationZ (transform (vec3 0 0 0) (pi / 2) (vec3 1 1 1)))
  assertEqual
    "mesh primitive uses cube geometry"
    (length (geometry3DIndices unitCubeGeometry))
    (length (geometry3DIndices (renderPrimitiveGeometry primitive)))

testStrokePathRenderPrimitive :: IO ()
testStrokePathRenderPrimitive = do
  let
    scene =
      RenderScene
        { renderSceneCamera = camera2D (viewport 160 90)
        , renderSceneNodes =
            [ StrokePath
                "trajectory"
                (transform (vec3 0 0 0.1) 0 (vec3 1 1 1))
                [vec3 0 0 0, vec3 10 0 0]
                (strokeStyle 2 (color 0.3 0.8 1 1))
            ]
        }
  primitive <- expectRenderPrimitive "trajectory" scene
  let geometry = renderPrimitiveGeometry primitive
  firstVertex <- expectFirstVertex "stroke path" geometry
  assertEqual "stroke path expands to four vertices" 4 (length (geometry3DVertices geometry))
  assertEqual "stroke path expands to two triangles" 6 (length (geometry3DIndices geometry))
  assertVec3
    "stroke transform lifts flat geometry above water"
    (vec3 0 1 0.1)
    (transformPoint3 (renderPrimitiveWorldMatrix primitive) firstVertex)

testRingStrokeRenderPrimitive :: IO ()
testRingStrokeRenderPrimitive = do
  let
    scene =
      RenderScene
        { renderSceneCamera = camera2D (viewport 160 90)
        , renderSceneNodes =
            [ RingStroke
                "speed-ring"
                (transform (vec3 5 7 0.2) 0 (vec3 1 1 1))
                (vec3 0 0 0)
                12
                8
                (strokeStyle 1 (color 0.9 0.8 0.3 1))
            ]
        }
  primitive <- expectRenderPrimitive "speed-ring" scene
  let geometry = renderPrimitiveGeometry primitive
  firstVertex <- expectFirstVertex "ring stroke" geometry
  assertEqual "ring stroke expands each segment to a quad" 32 (length (geometry3DVertices geometry))
  assertEqual "ring stroke expands each segment to two triangles" 48 (length (geometry3DIndices geometry))
  assertApproxScalar
    "ring geometry stays flat before its transform"
    0
    (vec3Z firstVertex)
  assertApproxScalar
    "ring transform lifts geometry above water"
    0.2
    (vec3Z (transformPoint3 (renderPrimitiveWorldMatrix primitive) firstVertex))

expectRenderPrimitive :: Text -> RenderScene -> IO RenderPrimitive
expectRenderPrimitive name scene =
  case filter ((== name) . renderPrimitiveName) (renderScenePrimitives scene) of
    [primitive] -> pure primitive
    [] -> die $ "missing render primitive " <> show name
    primitives -> die $ "expected one render primitive " <> show name <> ", got " <> show (length primitives)

expectStrokePath :: Text -> RenderScene -> IO (Transform, [Vec3])
expectStrokePath name scene =
  case matchingNodes of
    [(localTransform, points)] -> pure (localTransform, points)
    [] -> die $ "missing stroke path " <> show name
    nodes -> die $ "expected one stroke path " <> show name <> ", got " <> show (length nodes)
 where
  matchingNodes =
    [ (localTransform, points)
    | StrokePath nodeName localTransform points _ <- renderSceneNodes scene
    , nodeName == name
    ]

expectRingStroke :: Text -> RenderScene -> IO (Transform, Scalar)
expectRingStroke name scene =
  case matchingNodes of
    [(localTransform, radius)] -> pure (localTransform, radius)
    [] -> die $ "missing ring stroke " <> show name
    nodes -> die $ "expected one ring stroke " <> show name <> ", got " <> show (length nodes)
 where
  matchingNodes =
    [ (localTransform, radius)
    | RingStroke nodeName localTransform _ radius _ _ <- renderSceneNodes scene
    , nodeName == name
    ]

expectSnapshotNavigationPlan :: String -> ShipSnapshot -> IO NavigationPlan
expectSnapshotNavigationPlan label ship =
  case shipSnapshotActiveNavigationPlan ship of
    Just plan -> pure plan
    Nothing -> die $ label <> ": expected an active navigation plan in the snapshot"

expectHoverNavigationPlan :: String -> BattleScene -> IO NavigationPlan
expectHoverNavigationPlan label scene =
  case battleSceneHoverNavigationPlan scene of
    Just plan -> pure plan
    Nothing -> die $ label <> ": expected a hover navigation plan"

expectFirstTrajectorySample :: String -> NavigationPlan -> IO TrajectorySample
expectFirstTrajectorySample label plan =
  case navigationPlanSamples plan of
    sample : _ -> pure sample
    [] -> die $ label <> ": expected at least one trajectory sample"

pointPosition :: Point -> Vec3
pointPosition point =
  vec3 (realToFrac (pointX point)) (realToFrac (pointY point)) 0

offsetPoint :: Point -> Double -> Double -> Point
offsetPoint point offsetX offsetY =
  Point
    { pointX = pointX point + offsetX
    , pointY = pointY point + offsetY
    }

pointDistance :: Point -> Point -> Double
pointDistance from to =
  sqrt (((pointX to - pointX from) ** 2) + ((pointY to - pointY from) ** 2))

waypointPosition :: NavigationOrder -> Vec3
waypointPosition order =
  let waypoint = navigationReachableWaypoint order
   in vec3 (realToFrac (pointX waypoint)) (realToFrac (pointY waypoint)) 0.1

hoverWaypointPosition :: NavigationPlan -> Vec3
hoverWaypointPosition plan =
  let waypoint = navigationPlanReachableWaypoint plan
   in vec3 (realToFrac (pointX waypoint)) (realToFrac (pointY waypoint)) 0.15

isPlanningNode :: RenderNode -> Bool
isPlanningNode node =
  case node of
    StrokePath _ _ _ _ -> True
    RingStroke _ _ _ _ _ _ -> True
    _ -> False

enemyNavigationNodes :: RenderScene -> [RenderNode]
enemyNavigationNodes scene =
  filter isEnemyNavigationNode (renderSceneNodes scene)

isEnemyNavigationNode :: RenderNode -> Bool
isEnemyNavigationNode node =
  case node of
    StrokePath name _ _ _ -> ":enemy" `Text.isSuffixOf` name
    RingStroke name _ _ _ _ _ -> ":enemy" `Text.isSuffixOf` name
    _ -> False

hoverPlanningNodes :: RenderScene -> [RenderNode]
hoverPlanningNodes scene =
  filter isHoverPlanningNode (renderSceneNodes scene)

isHoverPlanningNode :: RenderNode -> Bool
isHoverPlanningNode node =
  case node of
    StrokePath name _ _ _ -> "hover-trajectory" `Text.isPrefixOf` name
    RingStroke name _ _ _ _ _ -> "hover-speed-ring" `Text.isPrefixOf` name
    _ -> False

expectFirstVertex :: String -> Geometry3D -> IO Vec3
expectFirstVertex label geometry =
  case geometry3DVertices geometry of
    vertex : _ -> pure vertex
    [] -> die $ label <> ": expected generated geometry to contain a vertex"

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
