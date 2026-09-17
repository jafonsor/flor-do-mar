{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (replicateM_)
import Data.Text (Text)
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
  testLocalApiStartsCaravelaDuel
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
  assertEqual "render mesh count" 4 (length meshes)
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
