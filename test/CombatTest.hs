{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
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
  testDuelStartsWithNoFiringState
  testLockCommandTogglesTheLockedTarget
  testSelfLockIsRefusedAndLeavesTheLockAlone
  testLockOnAShipOutsideTheScenarioIsRefused
  testFireAtWillIsIndependentOfTheLock
  testInvalidBroadsideRange
  testInvalidBroadsideArc
  testReloadCooldownIsUnaffectedByFiringStateCommands
  testVolleyFiresOnTheTickTheQueuedArmOrderApplies
  testVolleyLeavesOnTheTickTheReloadReachesZero
  testNoVolleyWithoutALockedTarget
  testNoVolleyWithoutFirePermission
  testNoVolleyWhileTheGunsAreReloading
  testNoVolleyWhenTheTargetIsOutsideBothFiringEnvelopes
  testNoVolleyWhenTheTargetIsBeyondTheEnvelopeReach
  testTheSideHoldingTheTargetIsTheOneThatFires
  testFiringEitherSideStartsTheOneSharedReload
  testWithdrawingDuringAReloadPreventsTheCompletingVolley
  testWithdrawingDuringAReloadLeavesTheReloadCountingDown
  testArmingIsRefusedAndReportedWhileTheReloadIsAboveZero
  testArmingOnTheTickTheReloadCompletesCatchesThatTicksVolley
  testVolleysInOneTickResolveSimultaneously
  testVolleysJudgeTheGeometryTheClientLastDrew
  testADisabledShipFiresNothing
  testTerminalHullState
  testLoadsRuntimeCombatConfig
  testRejectsMalformedRuntimeCombatConfig
  testRejectsInvalidRuntimeCombatConfig
  testRejectsBoatIdAssetMismatch
  testRejectsFiringArcWiderThanNinetyDegrees
  testAcceptsAFiringArcAtTheNinetyDegreeLimit
  testRejectsMissingRuntimeCombatConfig
  testLocalApiStartsCaravelaDuel
  testConfiguredLocalApiStartsBigVsSmall
  testConfiguredEngagementStartsWithNoFiringState
  testShippedDuelOpensOutsideBothShipsReach
  testHotReloadKeepsLockAndFirePermission
  testConfiguredMovementPhysics
  testNavigationPlannerClampsAndCommitsOrders
  testNavigationProjectionMatchesExecution
  testNavigationSteeringDoesNotWeave
  testNavigationArrivalPreservesSpeedIntent
  testMouseNavigationCommandLifecycle
  testStoppedNavigationOrderBuildsWay
  testFiringStateCommandsKeepActiveNavigationOrder
  testDisabledShipsClearAndIgnoreNavigation
  testNavigationSafetyCapIsSurfaced
  testLocalApiExposesNavigationOrder
  testEnemyOrbitAutopilotIssuesNavigationOrders
  testConfiguredBroadsideTuning
  testConfiguredVolleysUseTheBoatTuning
  testConfiguredMovementSnapshot
  testConfiguredLocalApiBroadsideTuning
  testConfiguredLocalApiHotReloadsLiveEngagement
  testHotReloadPreservesCommittedNavigationWaypoint
  testInvalidReloadKeepsLastValidConfigAndSnapshot
  testHotReloadPreservesDamageAcrossHullClamp
  testConfiguredLocalApiRestartsSelectedEngagement
  testSetupOverlayState
  testSetupDebugOverlayState
  testSnapshotCarriesLockedTargetAndFirePermission
  testLocalApiQueuesCommandsUntilTick
  testLocalApiExposesLockedTargetAndFirePermission
  testLocalApiFiresAndWithdrawsThroughTheQueuedOrders
  testLocalApiReportsTerminalState
  testInitialBattleRenderScene
  testShippedEngagementFitsTheVisibleExtent
  testShippedEnemyOrbitRingStaysInsideTheVisibleExtent
  testShippedZoomRendersHullsLegibly
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

testDuelStartsWithNoFiringState :: IO ()
testDuelStartsWithNoFiringState = do
  assertEqual "duel player starts with no locked target" Nothing (shipLockedTarget (combatPlayer caravelaDuel))
  assertEqual "duel player starts with its guns not permitted to fire" False (shipFirePermission (combatPlayer caravelaDuel))
  assertEqual "duel enemy starts with no locked target" Nothing (shipLockedTarget (combatEnemy caravelaDuel))
  assertEqual "duel enemy starts with its guns not permitted to fire" False (shipFirePermission (combatEnemy caravelaDuel))

testLockCommandTogglesTheLockedTarget :: IO ()
testLockCommandTogglesTheLockedTarget = do
  let
    locked = tickCombat [Lock PlayerShip EnemyShip] caravelaDuel
    unlocked = tickCombat [Lock PlayerShip EnemyShip] locked
    enemyLocked = tickCombat [Lock EnemyShip PlayerShip] caravelaDuel
  assertEqual "a lock names a single target" (Just EnemyShip) (shipLockedTarget (combatPlayer locked))
  assertEqual "the same command against the locked target releases it" Nothing (shipLockedTarget (combatPlayer unlocked))
  assertEqual "one ship's lock is not the other's" Nothing (shipLockedTarget (combatEnemy locked))
  assertEqual "the enemy locks through the same command" (Just PlayerShip) (shipLockedTarget (combatEnemy enemyLocked))
  assertEqual "locking grants no permission to fire" False (shipFirePermission (combatPlayer locked))

testSelfLockIsRefusedAndLeavesTheLockAlone :: IO ()
testSelfLockIsRefusedAndLeavesTheLockAlone = do
  let
    lockedOnEnemy = tickCombat [Lock PlayerShip EnemyShip] caravelaDuel
    attemptedFromUnlocked = tickCombat [Lock PlayerShip PlayerShip] caravelaDuel
    attemptedFromLocked = tickCombat [Lock PlayerShip PlayerShip] lockedOnEnemy
  assertEqual "a ship may not lock itself" (TargetIsSelf PlayerShip) (canLockTarget caravelaDuel PlayerShip PlayerShip)
  assertEqual "a refused self-lock acquires no lock" Nothing (shipLockedTarget (combatPlayer attemptedFromUnlocked))
  assertEqual "a refused self-lock does not release the target already held" (Just EnemyShip) (shipLockedTarget (combatPlayer attemptedFromLocked))

testLockOnAShipOutsideTheScenarioIsRefused :: IO ()
testLockOnAShipOutsideTheScenarioIsRefused = do
  let
    -- Membership is read from the ships the scenario carries, so a state whose
    -- hulls both answer to the player's id has no enemy to point a lock at.
    withoutEnemy =
      caravelaDuel
        { combatEnemy = (combatEnemy caravelaDuel) { shipId = PlayerShip }
        }
    attempted = tickCombat [Lock PlayerShip EnemyShip] withoutEnemy
  assertEqual
    "a lock on a ship the scenario does not carry is refused"
    (TargetNotInScenario EnemyShip)
    (canLockTarget withoutEnemy PlayerShip EnemyShip)
  assertEqual "a refused lock is not stored" Nothing (shipLockedTarget (combatPlayer attempted))

testFireAtWillIsIndependentOfTheLock :: IO ()
testFireAtWillIsIndependentOfTheLock = do
  let
    permitted = tickCombat [SetFireAtWill PlayerShip True] caravelaDuel
    withdrawn = tickCombat [SetFireAtWill PlayerShip False] permitted
    lockedOnly = tickCombat [Lock PlayerShip EnemyShip] caravelaDuel
    lockedAndWithdrawn = tickCombat [SetFireAtWill PlayerShip False] lockedOnly
  assertEqual "fire at will is granted without a locked target" True (shipFirePermission (combatPlayer permitted))
  assertEqual "granting fire at will locks nothing" Nothing (shipLockedTarget (combatPlayer permitted))
  assertEqual "fire at will is withdrawn again" False (shipFirePermission (combatPlayer withdrawn))
  assertEqual "withdrawing fire at will keeps the locked target" (Just EnemyShip) (shipLockedTarget (combatPlayer lockedAndWithdrawn))
  assertEqual "the other ship's permission is untouched" False (shipFirePermission (combatEnemy permitted))

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
  case canFireBroadside wrongArc PlayerShip EnemyShip Port of
    TargetOutsideFiringArc angle ->
      if angle > 45
        then pure ()
        else die "arc failure did not report an outside-arc angle"
    other -> die $ "expected TargetOutsideFiringArc, got " <> show other

-- | The reload is the whole of the delay the firing model rests on, so it has to
-- keep running on its own clock while the fire-control state is set.
--
-- Issue 01 asserted here that permission could be granted during a reload. Issue
-- 02 supersedes exactly that rule: re-engaging during a reload is refused, so the
-- arm order in this sequence is deliberately not applied. The test's subject is
-- untouched — the counter is neither reset nor slowed by the commands, and it
-- still reaches zero.
testReloadCooldownIsUnaffectedByFiringStateCommands :: IO ()
testReloadCooldownIsUnaffectedByFiringStateCommands = do
  let
    -- A volley is what starts this reload; the fixture sets it so the test stays
    -- about the cooldown rather than about firing.
    reloading =
      caravelaDuel
        { combatPlayer = (combatPlayer caravelaDuel) {shipReload = reloadTicks}
        }
    commanded =
      tickCombat
        [ Lock PlayerShip EnemyShip
        , SetFireAtWill PlayerShip True
        ]
        reloading
    uncommanded = tickCombat [] reloading
    cooledOnce = tickCombat [] commanded
    readyAgain = tickCombat [] cooledOnce
  assertEqual "firing state commands leave the reload counter alone" (shipReload (combatPlayer uncommanded)) (shipReload (combatPlayer commanded))
  assertEqual "a lock does not need loaded guns" (Just EnemyShip) (shipLockedTarget (combatPlayer commanded))
  assertEqual "the arm order is refused during a reload and leaves the guns disengaged" False (shipFirePermission (combatPlayer commanded))
  assertEqual "the refused arm order fires nothing" 100 (shipHull (combatEnemy commanded))
  case canFireBroadside commanded PlayerShip EnemyShip Port of
    BroadsideReloading remaining ->
      assertEqual "a reloading ship reports its own remaining reload" (shipReload (combatPlayer commanded)) remaining
    other -> die $ "expected BroadsideReloading, got " <> show other
  assertEqual "reload counts down once" 1 (shipReload (combatPlayer cooledOnce))
  assertEqual "reload reaches ready" 0 (shipReload (combatPlayer readyAgain))

-- | A ship that is locked, loaded and permitted fires on the tick its queued
-- order applies. Commands and the volley phase share one tick, so from the
-- player's side the volley leaves on the tick after they arm.
testVolleyFiresOnTheTickTheQueuedArmOrderApplies :: IO ()
testVolleyFiresOnTheTickTheQueuedArmOrderApplies = do
  let
    armed =
      tickCombat
        [ Lock PlayerShip EnemyShip
        , SetFireAtWill PlayerShip True
        ]
        caravelaDuel
  assertEqual "the arm order is stored on the tick it applies" True (shipFirePermission (combatPlayer armed))
  assertEqual "the volley damages the locked target on that tick" 75 (shipHull (combatEnemy armed))
  assertEqual "the volley starts the boat's configured reload" reloadTicks (shipReload (combatPlayer armed))
  assertEqual "the firing ship takes nothing from its own volley" 100 (shipHull (combatPlayer armed))

-- | The reload counts down at the top of the tick, before the tick's commands,
-- so the tick that empties it is itself a tick that can fire.
testVolleyLeavesOnTheTickTheReloadReachesZero :: IO ()
testVolleyLeavesOnTheTickTheReloadReachesZero = do
  let
    firstVolley = tickCombat [] playerReadyToFire
    cooling = tickCombat [] firstVolley
    oneTickLeft = tickCombat [] cooling
    completing = tickCombat [] oneTickLeft
  assertEqual "the first volley leaves the enemy damaged" 75 (shipHull (combatEnemy firstVolley))
  assertEqual "no volley leaves while the shared reload runs" 75 (shipHull (combatEnemy oneTickLeft))
  assertEqual "the reload is down to its last tick" 1 (shipReload (combatPlayer oneTickLeft))
  assertEqual "the volley leaves on the tick the reload reaches zero" 50 (shipHull (combatEnemy completing))
  assertEqual "the completing volley starts the reload again" reloadTicks (shipReload (combatPlayer completing))

-- | A volley needs a lock, whatever the guns are doing.
testNoVolleyWithoutALockedTarget :: IO ()
testNoVolleyWithoutALockedTarget = do
  let
    armedOnly = tickCombat [SetFireAtWill PlayerShip True] caravelaDuel
    -- A lock the scenario cannot honour — its enemy slot answers to the player's
    -- id — is no target for the guns either.
    absentTarget =
      playerReadyToFire
        { combatEnemy = (combatEnemy caravelaDuel) {shipId = PlayerShip}
        }
    firedAtNothing = tickCombat [] absentTarget
  assertEqual "a ship permitted to fire with no lock fires nothing" 100 (shipHull (combatEnemy armedOnly))
  assertEqual "a ship permitted to fire with no lock stays loaded" 0 (shipReload (combatPlayer armedOnly))
  assertEqual "a lock on a ship the scenario does not carry fires nothing" 100 (shipHull (combatEnemy firedAtNothing))
  assertEqual "a lock on a ship the scenario does not carry starts no reload" 0 (shipReload (combatPlayer firedAtNothing))

testNoVolleyWithoutFirePermission :: IO ()
testNoVolleyWithoutFirePermission = do
  let ticked = tickCombat [] playerHoldingFire
  assertEqual "a locked, loaded ship whose guns are not permitted fires nothing" 100 (shipHull (combatEnemy ticked))
  assertEqual "a ship whose guns are not permitted stays loaded" 0 (shipReload (combatPlayer ticked))

testNoVolleyWhileTheGunsAreReloading :: IO ()
testNoVolleyWhileTheGunsAreReloading = do
  let
    reloading =
      playerReadyToFire
        { combatPlayer = (combatPlayer playerReadyToFire) {shipReload = 2}
        }
    ticked = tickCombat [] reloading
  assertEqual "a reloading ship fires nothing" 100 (shipHull (combatEnemy ticked))
  assertEqual "the reload keeps counting down while the guns are loaded and held" 1 (shipReload (combatPlayer ticked))
  assertEqual "the lock survives the reload" (Just EnemyShip) (shipLockedTarget (combatPlayer ticked))

-- | Turning the ship across the target's bearing puts it ninety degrees off both
-- beams, so neither envelope reaches it.
testNoVolleyWhenTheTargetIsOutsideBothFiringEnvelopes :: IO ()
testNoVolleyWhenTheTargetIsOutsideBothFiringEnvelopes = do
  let
    abeam =
      playerReadyToFire
        { combatPlayer = (combatPlayer playerReadyToFire) {shipHeading = Heading 90, shipTargetHeading = Heading 90}
        }
    ticked = tickCombat [] abeam
  case canFireBroadside abeam PlayerShip EnemyShip Port of
    TargetOutsideFiringArc _ -> pure ()
    other -> die $ "expected the port side to hold nothing, got " <> show other
  case canFireBroadside abeam PlayerShip EnemyShip Starboard of
    TargetOutsideFiringArc _ -> pure ()
    other -> die $ "expected the starboard side to hold nothing, got " <> show other
  assertEqual "no volley fires when the target is outside both envelopes" 100 (shipHull (combatEnemy ticked))
  assertEqual "the guns stay loaded when the target is outside both envelopes" 0 (shipReload (combatPlayer ticked))

testNoVolleyWhenTheTargetIsBeyondTheEnvelopeReach :: IO ()
testNoVolleyWhenTheTargetIsBeyondTheEnvelopeReach = do
  let
    beyondReach =
      playerReadyToFire
        { combatEnemy = (combatEnemy caravelaDuel) {shipPosition = Point 0 (broadsideRange + 50)}
        }
    ticked = tickCombat [] beyondReach
  case canFireBroadside beyondReach PlayerShip EnemyShip Port of
    TargetOutOfRange _ -> pure ()
    other -> die $ "expected TargetOutOfRange, got " <> show other
  assertEqual "no volley fires past the guns' reach" 100 (shipHull (combatEnemy ticked))
  assertEqual "the guns stay loaded past the guns' reach" 0 (shipReload (combatPlayer ticked))

-- | The side that fires is the side whose envelope holds the target, and only
-- that side: one tick with both sides checked fires one broadside.
testTheSideHoldingTheTargetIsTheOneThatFires :: IO ()
testTheSideHoldingTheTargetIsTheOneThatFires = do
  let
    targetOnPort = playerReadyToFire
    targetOnStarboard =
      playerReadyToFire
        { combatEnemy = (combatEnemy caravelaDuel) {shipPosition = Point 0 (-80)}
        }
    portVolley = tickCombat [] targetOnPort
    starboardVolley = tickCombat [] targetOnStarboard
  assertEqual "the duel's enemy sits in the port envelope" BroadsideReady (canFireBroadside targetOnPort PlayerShip EnemyShip Port)
  case canFireBroadside targetOnPort PlayerShip EnemyShip Starboard of
    TargetOutsideFiringArc _ -> pure ()
    other -> die $ "expected the starboard side to hold nothing, got " <> show other
  assertEqual "the port volley lands" 75 (shipHull (combatEnemy portVolley))
  assertEqual "with the enemy to the south the starboard envelope holds instead" BroadsideReady (canFireBroadside targetOnStarboard PlayerShip EnemyShip Starboard)
  case canFireBroadside targetOnStarboard PlayerShip EnemyShip Port of
    TargetOutsideFiringArc _ -> pure ()
    other -> die $ "expected the port side to hold nothing, got " <> show other
  assertEqual "the side that holds the target fires once, not twice" 75 (shipHull (combatEnemy starboardVolley))

-- | One reload covers both broadsides: after a starboard volley the port side is
-- as blocked as the side that fired.
testFiringEitherSideStartsTheOneSharedReload :: IO ()
testFiringEitherSideStartsTheOneSharedReload = do
  let
    targetOnStarboard =
      playerReadyToFire
        { combatEnemy = (combatEnemy caravelaDuel) {shipPosition = Point 0 (-80)}
        }
    fired = tickCombat [] targetOnStarboard
    nextTick = tickCombat [] fired
  assertEqual "the volley starts the boat's configured reload" reloadTicks (shipReload (combatPlayer fired))
  case canFireBroadside fired PlayerShip EnemyShip Starboard of
    BroadsideReloading remaining ->
      assertEqual "the side that fired reports the shared reload" reloadTicks remaining
    other -> die $ "expected BroadsideReloading on the side that fired, got " <> show other
  case canFireBroadside fired PlayerShip EnemyShip Port of
    BroadsideReloading remaining ->
      assertEqual "the other side reports the same shared reload" reloadTicks remaining
    other -> die $ "expected BroadsideReloading on the other side, got " <> show other
  assertEqual "the other side fires nothing while the shared reload runs" (shipHull (combatEnemy fired)) (shipHull (combatEnemy nextTick))

testWithdrawingDuringAReloadPreventsTheCompletingVolley :: IO ()
testWithdrawingDuringAReloadPreventsTheCompletingVolley = do
  let
    firstVolley = tickCombat [] playerReadyToFire
    withdrawn = tickCombat [SetFireAtWill PlayerShip False] firstVolley
    completing = tickCombat [] (tickCombat [] withdrawn)
  assertEqual "withdrawing permission during a reload is accepted" False (shipFirePermission (combatPlayer withdrawn))
  assertEqual "the enemy took exactly the first volley" 75 (shipHull (combatEnemy completing))
  assertEqual "no volley leaves on the tick the reload completes once permission is withdrawn" (shipHull (combatEnemy withdrawn)) (shipHull (combatEnemy completing))

testWithdrawingDuringAReloadLeavesTheReloadCountingDown :: IO ()
testWithdrawingDuringAReloadLeavesTheReloadCountingDown = do
  let
    firstVolley = tickCombat [] playerReadyToFire
    withdrawn = tickCombat [SetFireAtWill PlayerShip False] firstVolley
    cooledOnce = tickCombat [] withdrawn
    loaded = tickCombat [] cooledOnce
    rearmed = tickCombat [SetFireAtWill PlayerShip True] loaded
  assertEqual "the reload counts down while the guns are disengaged" 1 (shipReload (combatPlayer cooledOnce))
  assertEqual "the reload reaches zero while the guns are disengaged" 0 (shipReload (combatPlayer loaded))
  assertEqual "the disengaged ship fires nothing on the tick its reload completes" 75 (shipHull (combatEnemy loaded))
  assertEqual "re-engaging after the reload reaches zero is accepted" True (shipFirePermission (combatPlayer rearmed))
  assertEqual "the re-engaged ship fires on the tick its order applies" 50 (shipHull (combatEnemy rearmed))

-- | Re-engaging during a reload is refused by a named guard rather than being
-- silently ignored. The reload has already counted down for this tick when the
-- order is applied, and the guard reports the counter's post-decrement value.
testArmingIsRefusedAndReportedWhileTheReloadIsAboveZero :: IO ()
testArmingIsRefusedAndReportedWhileTheReloadIsAboveZero = do
  let
    reloading =
      playerHoldingFire
        { combatPlayer = (combatPlayer playerHoldingFire) {shipReload = reloadTicks}
        }
    refused = tickCombat [SetFireAtWill PlayerShip True] reloading
  assertEqual "the guard names the reload as the refusal" (BroadsideReloading reloadTicks) (canSetFireAtWill reloading PlayerShip True)
  assertEqual "the tick's decrement still applies to the refused order" 2 (shipReload (combatPlayer refused))
  assertEqual "the refused order does not permit the guns" False (shipFirePermission (combatPlayer refused))
  assertEqual "the refused order fires nothing" 100 (shipHull (combatEnemy refused))

-- | The reload counts down before the tick's commands are applied, so an arm
-- order that lands on the tick the reload reaches zero is accepted and catches
-- that tick's volley.
testArmingOnTheTickTheReloadCompletesCatchesThatTicksVolley :: IO ()
testArmingOnTheTickTheReloadCompletesCatchesThatTicksVolley = do
  let
    oneTickLeft =
      playerHoldingFire
        { combatPlayer = (combatPlayer playerHoldingFire) {shipReload = 1}
        }
    caught = tickCombat [SetFireAtWill PlayerShip True] oneTickLeft
  assertEqual "the guard would refuse the order against the counter's pre-tick value" (BroadsideReloading 1) (canSetFireAtWill oneTickLeft PlayerShip True)
  assertEqual "the tick's decrement leaves the guns loaded for the order" True (shipFirePermission (combatPlayer caught))
  assertEqual "the arm order catches that tick's volley" 75 (shipHull (combatEnemy caught))
  assertEqual "the caught volley starts the reload" reloadTicks (shipReload (combatPlayer caught))

-- | Every volley in a tick is decided before any of them is applied, so two
-- ships that can each disable the other both land their shot. A phase that
-- resolved one ship at a time would leave the first shooter afloat.
testVolleysInOneTickResolveSimultaneously :: IO ()
testVolleysInOneTickResolveSimultaneously = do
  let
    bothEngaged =
      caravelaDuel
        { combatPlayer = combatPlayer playerReadyToFire
        , combatEnemy =
            (combatEnemy caravelaDuel)
              { shipLockedTarget = Just PlayerShip
              , shipFirePermission = True
              }
        }
    lethal = legacyBroadsideTuning {broadsideTuningDamage = shipMaxHull (combatPlayer caravelaDuel)}
    resolved = tickCombatWithTuning 1 (const legacyMovementPhysics) (const lethal) [] bothEngaged
  assertEqual "the player's volley disables the enemy on that tick" 0 (shipHull (combatEnemy resolved))
  assertEqual "the enemy's volley lands although it was disabled in the same tick" 0 (shipHull (combatPlayer resolved))
  assertEqual "the duel ends on the tick both volleys land" (ScenarioFinished MutualDestruction) (combatStatus resolved)

testADisabledShipFiresNothing :: IO ()
testADisabledShipFiresNothing = do
  let
    disabled =
      playerReadyToFire
        { combatPlayer = (combatPlayer playerReadyToFire) {shipHull = 0}
        }
    ticked = tickCombat [] disabled
  assertEqual "a disabled ship fires nothing" 100 (shipHull (combatEnemy ticked))
  assertEqual "a disabled ship starts no reload" 0 (shipReload (combatPlayer ticked))

-- | The volley phase runs before the tick's movement, so the guns are judged on
-- the geometry the client last drew — the end of the previous tick — rather than
-- on positions the player has not seen yet. Here the enemy is in reach when the
-- tick starts and its own move carries it far out of reach within that same tick;
-- the volley still leaves.
testVolleysJudgeTheGeometryTheClientLastDrew :: IO ()
testVolleysJudgeTheGeometryTheClientLastDrew = do
  let
    fleeing =
      playerReadyToFire
        { combatEnemy =
            (combatEnemy playerReadyToFire)
              { shipCurrentSpeed = 200
              , shipTargetSpeed = 200
              }
        }
    fired = tickCombat [] fleeing
    -- The player's own reload would mask the geometry check, so the end-of-tick
    -- geometry is read from a copy with the guns loaded.
    firedAtRest = fired {combatPlayer = (combatPlayer fired) {shipReload = 0}}
  assertEqual "the enemy is in reach when the tick starts" BroadsideReady (canFireBroadside fleeing PlayerShip EnemyShip Port)
  assertEqual "the volley leaves before the enemy's move carries it away" 75 (shipHull (combatEnemy fired))
  case canFireBroadside firedAtRest PlayerShip EnemyShip Port of
    TargetOutOfRange _ -> pure ()
    other -> die $ "expected the enemy to end the tick out of reach, got " <> show other

-- | The state every firing test varies one field of: a loaded ship, locked on the
-- enemy, permitted to fire, with the duel's opening geometry holding the enemy in
-- its port envelope.
playerReadyToFire :: CombatState
playerReadyToFire =
  caravelaDuel
    { combatPlayer =
        (combatPlayer caravelaDuel)
          { shipLockedTarget = Just EnemyShip
          , shipFirePermission = True
          }
    }

-- | The same ship with its guns still disengaged: what an arm order is applied
-- to.
playerHoldingFire :: CombatState
playerHoldingFire =
  playerReadyToFire
    { combatPlayer = (combatPlayer playerReadyToFire) {shipFirePermission = False}
    }

testTerminalHullState :: IO ()
testTerminalHullState = do
  let
    -- The disabling damage is part of the fixture; the rule under test is what a
    -- disabled hull does to the tick. Firing is what ends the duel through the
    -- local API, which its own test covers.
    disabledEnemy = applyBroadsideDamage (shipMaxHull (combatEnemy caravelaDuel)) (combatEnemy caravelaDuel)
    almostDisabled = caravelaDuel {combatEnemy = disabledEnemy}
    finished = tickCombat [] almostDisabled
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
  -- The shipped gunnery numbers are what the game plays with: three big-boat
  -- lengths of practical range, and a half-angle narrow enough that the two
  -- broadsides stay disjoint.
  assertApprox "configured big broadside range" 48 (boatConfigBroadsideRange big)
  assertApprox "configured small broadside range" 48 (boatConfigBroadsideRange small)
  assertApprox "configured big firing arc" 45 (boatConfigFiringArcDegrees big)
  assertApprox "configured small firing arc" 45 (boatConfigFiringArcDegrees small)

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

-- | The half-angle bound is what keeps a ship's two broadsides disjoint, so a
-- config that widens it into an all-round battery is refused by name.
testRejectsFiringArcWiderThanNinetyDegrees :: IO ()
testRejectsFiringArcWiderThanNinetyDegrees = do
  diagnostics <- expectLeft "reject a firing arc wider than 90 degrees" =<< loadCombatConfig "test/fixtures/config-arc-too-wide"
  assertDiagnostic "a too-wide firing arc reports the field" "firing_arc_degrees" diagnostics
  assertSemanticDiagnostic "a too-wide firing arc explains the field problem" "firing_arc_degrees" diagnostics

-- | The bound is inclusive: a 90-degree half-angle is the widest disjoint pair,
-- so it validates. The shipped 45 is asserted against the shipped assets by
-- 'testLoadsRuntimeCombatConfig'.
testAcceptsAFiringArcAtTheNinetyDegreeLimit :: IO ()
testAcceptsAFiringArcAtTheNinetyDegreeLimit = do
  config <- expectRight "accept a firing arc of exactly 90 degrees" =<< loadCombatConfig "test/fixtures/config-arc-at-limit"
  big <- expectBoatConfig "arc-limit big boat" "big" config
  small <- expectBoatConfig "arc-limit small boat" "small" config
  assertApprox "a firing arc at the validation limit is accepted" 90 (boatConfigFiringArcDegrees big)
  assertApprox "the narrow arc beside it is untouched" 45 (boatConfigFiringArcDegrees small)

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

testFiringStateCommandsKeepActiveNavigationOrder :: IO ()
testFiringStateCommandsKeepActiveNavigationOrder = do
  let
    ordered = tickCombat [IssueNavigationOrder PlayerShip (Point 40 20)] caravelaDuel
    commanded =
      tickCombat
        [ Lock PlayerShip EnemyShip
        , SetFireAtWill PlayerShip True
        ]
        ordered
  orderBefore <- expectNavigationOrder "navigation order before firing state commands" (combatPlayer ordered)
  orderAfter <- expectNavigationOrder "navigation order after firing state commands" (combatPlayer commanded)
  assertEqual "firing state commands do not mutate the active navigation order" orderBefore orderAfter
  assertEqual "lock and fire at will still apply beside a navigation order" (Just EnemyShip) (shipLockedTarget (combatPlayer commanded))
  assertEqual "fire at will still applies beside a navigation order" True (shipFirePermission (combatPlayer commanded))

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
    -- The enemy still starts at (0, 80); its orbit centre is the arena centre,
    -- which is the point the camera is centred on, so the ring sits in view.
    arenaCenter = Point 0 40
    startingPosition = shipPosition (combatEnemy initialState)
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
  assertPoint "the enemy starts north of the arena" (Point 0 80) startingPosition
  assertPoint "first orbit center is the arena centre" arenaCenter (enemyOrbitCenter firstAutopilot)
  assertApprox "first orbit waypoint uses the fixed radius" enemyOrbitRadius (pointDistance arenaCenter (navigationRequestedWaypoint firstOrder))
  assertEqual "first orbit order is an ordinary navigation order" (navigationRequestedWaypoint firstOrder) (navigationReachableWaypoint firstOrder)
  assertEqual "orbit advances after issuing a successive waypoint" 2 (enemyOrbitNextWaypointIndex nextAutopilot)
  assertApprox "next orbit waypoint keeps the fixed radius" enemyOrbitRadius (pointDistance arenaCenter (navigationRequestedWaypoint nextOrder))

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
    tunedConfig = tunedBoatConfig config
    bigAtLongRange = configuredDefaultEngagement tunedConfig
    bigTuning = broadsideTuningForShip tunedConfig (combatPlayer bigAtLongRange)
    bigAtShortRange =
      bigAtLongRange
        { combatEnemy = (combatEnemy bigAtLongRange) {shipPosition = Point 0 60}
        }
    bigCommanded = tickConfiguredCombat tunedConfig [SetHeading PlayerShip (Heading 180)] bigAtShortRange
    smallAtLongRange =
      case configuredEngagement tunedConfig "small" "big" of
        Just state -> state
        Nothing -> error "validated combat config is missing a configured boat kind"
    smallTuning = broadsideTuningForShip tunedConfig (combatPlayer smallAtLongRange)
    smallArcState =
      smallAtLongRange
        { combatEnemy = (combatEnemy smallAtLongRange) {shipPosition = Point (-30) 52}
        }
    bigArcState =
      bigAtShortRange
        { combatEnemy = (combatEnemy bigAtShortRange) {shipPosition = Point (-30) 52}
        }
  case canFireBroadsideWith (broadsideTuningForShip tunedConfig) bigAtLongRange PlayerShip EnemyShip Port of
    TargetOutOfRange _ -> pure ()
    other -> die $ "configured big range: expected TargetOutOfRange, got " <> show other
  assertApprox "configured big range" 70 (broadsideTuningRange bigTuning)
  assertEqual "configured big damage" 31 (broadsideTuningDamage bigTuning)
  assertEqual "configured big reload" 4 (broadsideTuningReloadTicks bigTuning)
  assertApprox "configured heading intent does not replace physical heading for broadside" 0 (headingDegrees (shipHeading (combatPlayer bigCommanded)))
  assertEqual "configured small range differs from big" BroadsideReady (canFireBroadsideWith (broadsideTuningForShip tunedConfig) smallAtLongRange PlayerShip EnemyShip Port)
  assertEqual "configured small damage" 13 (broadsideTuningDamage smallTuning)
  assertEqual "configured small reload" 1 (broadsideTuningReloadTicks smallTuning)
  assertEqual "configured small firing arc differs from big" BroadsideReady (canFireBroadsideWith (broadsideTuningForShip tunedConfig) smallArcState PlayerShip EnemyShip Port)
  case canFireBroadsideWith (broadsideTuningForShip tunedConfig) bigArcState PlayerShip EnemyShip Port of
    TargetOutsideFiringArc _ -> pure ()
    other -> die $ "configured big firing arc: expected TargetOutsideFiringArc, got " <> show other

-- | Per-boat tuning reaches the volley itself: the configured range and arc
-- decide whether one leaves, and the configured damage and reload decide what it
-- does. The tuning is 'tunedBoatConfig', so the big and small boats pull in
-- opposite directions.
testConfiguredVolleysUseTheBoatTuning :: IO ()
testConfiguredVolleysUseTheBoatTuning = do
  config <- expectRight "load packaged config for configured volleys" =<< loadRuntimeCombatConfig
  let
    tunedConfig = tunedBoatConfig config
    engagement = configuredDefaultEngagement tunedConfig
    engagedAt position =
      engagement
        { combatPlayer = (combatPlayer engagement) {shipLockedTarget = Just EnemyShip, shipFirePermission = True}
        , combatEnemy = (combatEnemy engagement) {shipPosition = position}
        }
    beyondConfiguredRange = tickConfiguredCombat tunedConfig [] (engagedAt (Point 0 80))
    outsideConfiguredArc = tickConfiguredCombat tunedConfig [] (engagedAt (Point 30 60))
    inside = tickConfiguredCombat tunedConfig [] (engagedAt (Point 0 60))
    smallFlyingEngagement =
      case configuredEngagement tunedConfig "small" "big" of
        Just state ->
          state
            { combatPlayer = (combatPlayer state) {shipLockedTarget = Just EnemyShip, shipFirePermission = True}
            }
        Nothing -> error "validated combat config is missing a configured boat kind"
    smallVolley = tickConfiguredCombat tunedConfig [] smallFlyingEngagement
  assertEqual "a target past the configured range takes no volley" 80 (shipHull (combatEnemy beyondConfiguredRange))
  assertEqual "a target outside the configured arc takes no volley" 80 (shipHull (combatEnemy outsideConfiguredArc))
  assertEqual "the configured damage is what the volley applies" 49 (shipHull (combatEnemy inside))
  assertEqual "the configured reload is what the volley starts" 4 (shipReload (combatPlayer inside))
  assertEqual "the small boat's configured damage is what its volley applies" 147 (shipHull (combatEnemy smallVolley))
  assertEqual "the small boat's configured reload is what its volley starts" 1 (shipReload (combatPlayer smallVolley))

-- | Boat tuning distinct from the shipped values: the big boat reaches less far
-- with a narrower arc and hits harder and slower, the small boat keeps the
-- shipped reach with a lighter, quicker broadside. Every configured-gunnery test
-- uses it, so they cannot drift apart.
tunedBoatConfig :: CombatConfig -> CombatConfig
tunedBoatConfig config =
  config
    { combatConfigBoats =
        [ tuneBoat boat
        | boat <- combatConfigBoats config
        ]
    }
 where
  tuneBoat boat =
    case boatConfigId boat of
      "big" -> boat {boatConfigBroadsideRange = 70, boatConfigBroadsideDamage = 31, boatConfigReloadTicks = 4, boatConfigFiringArcDegrees = 15}
      "small" -> boat {boatConfigBroadsideRange = 100, boatConfigBroadsideDamage = 13, boatConfigReloadTicks = 1, boatConfigFiringArcDegrees = 45}
      _ -> boat

-- | Give every boat the reach a volley across the duel's opening needs.
--
-- The shipped practical range is 48, short of the 80-unit opening separation, so
-- the shipped duel opens with a closing phase. Tests whose subject is a tuning
-- path rather than the shipped geometry use this to reach across the opening;
-- the shipped numbers themselves are pinned by 'testLoadsRuntimeCombatConfig'
-- and 'testShippedDuelOpensOutsideBothShipsReach'.
configReachingAcrossTheOpening :: CombatConfig -> CombatConfig
configReachingAcrossTheOpening config =
  config
    { combatConfigBoats =
        [ boat {boatConfigBroadsideRange = 90}
        | boat <- combatConfigBoats config
        ]
    }

-- | A ship built from a boat config is armed the way every other ship starts:
-- no locked target and no permission to fire.
testConfiguredEngagementStartsWithNoFiringState :: IO ()
testConfiguredEngagementStartsWithNoFiringState = do
  config <- expectRight "load packaged config for initial firing state" =<< loadRuntimeCombatConfig
  let engagement = configuredDefaultEngagement config
  assertEqual "configured player starts with no locked target" Nothing (shipLockedTarget (combatPlayer engagement))
  assertEqual "configured player starts with its guns not permitted to fire" False (shipFirePermission (combatPlayer engagement))
  assertEqual "configured enemy starts with no locked target" Nothing (shipLockedTarget (combatEnemy engagement))
  assertEqual "configured enemy starts with its guns not permitted to fire" False (shipFirePermission (combatEnemy engagement))

-- | The reduced practical range is a pacing decision: at the shipped 48 the
-- duel's 80-unit opening separation is outside both ships' reach, so the fight
-- opens with a closing phase. That is intended and is pinned here rather than
-- assumed, for both boats and every side.
testShippedDuelOpensOutsideBothShipsReach :: IO ()
testShippedDuelOpensOutsideBothShipsReach = do
  config <- expectRight "load packaged config for the opening separation" =<< loadRuntimeCombatConfig
  let
    engagement = configuredDefaultEngagement config
    separation = pointDistance (shipPosition (combatPlayer engagement)) (shipPosition (combatEnemy engagement))
  assertApprox "the shipped duel opens at its designed separation" 80 separation
  forM_ [(PlayerShip, EnemyShip), (EnemyShip, PlayerShip)] $ \(attackerId, targetId) ->
    forM_ [Port, Starboard] $ \side ->
      case canFireBroadsideWith (broadsideTuningForShip config) engagement attackerId targetId side of
        TargetOutOfRange reportedRange ->
          assertApprox "the opened distance is what each side reports as out of reach" separation reportedRange
        other -> die $ "expected the shipped opening separation to hold no broadside, got " <> show other

-- | A hot reload refreshes what the boat kind owns. The lock and the permission
-- belong to the live ship, so neither may be reset by it.
testHotReloadKeepsLockAndFirePermission :: IO ()
testHotReloadKeepsLockAndFirePermission = do
  config <- expectRight "load packaged config for firing state hot reload" =<< loadRuntimeCombatConfig
  let
    engagement = configuredDefaultEngagement config
    live =
      engagement
        { combatPlayer =
            (combatPlayer engagement)
              { shipLockedTarget = Just EnemyShip
              , shipFirePermission = True
              , shipReload = reloadTicks
              }
        }
    reloaded = applyConfigToCombatState (withBigHull 200 config) live
    player = combatPlayer reloaded
    enemy = combatEnemy reloaded
  assertEqual "hot reload keeps the locked target" (Just EnemyShip) (shipLockedTarget player)
  assertEqual "hot reload keeps fire permission" True (shipFirePermission player)
  assertEqual "hot reload does not touch the reload counter" reloadTicks (shipReload player)
  assertEqual "hot reload still refreshes values the boat kind owns" 200 (shipMaxHull player)
  assertEqual "an unlocked ship stays unlocked across a hot reload" Nothing (shipLockedTarget enemy)
  assertEqual "a disengaged ship stays disengaged across a hot reload" False (shipFirePermission enemy)
 where
  withBigHull hull currentConfig =
    currentConfig
      { combatConfigBoats =
          [ if boatConfigId boat == "big" then boat {boatConfigMaxHull = hull} else boat
          | boat <- combatConfigBoats currentConfig
          ]
      }

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

-- | Configured gunnery tuning is what a volley through the API actually uses:
-- the tuned damage lands on the enemy and the tuned reload appears in the
-- player's snapshot.
--
-- The fixture supplies the reach as well as the damage and reload: the shipped
-- 48 no longer covers the duel's opening separation, and that the shipped
-- opening is out of range is pinned by 'testShippedDuelOpensOutsideBothShipsReach'.
testConfiguredLocalApiBroadsideTuning :: IO ()
testConfiguredLocalApiBroadsideTuning = do
  config <- expectRight "load packaged config for API broadside tuning" =<< loadRuntimeCombatConfig
  let
    tunedConfig =
      configReachingAcrossTheOpening $
        config
          { combatConfigBoats =
              [ boat {boatConfigBroadsideDamage = 31, boatConfigReloadTicks = 4}
              | boat <- combatConfigBoats config
              ]
          }
  localApi <- newConfiguredLocalCombatApi tunedConfig
  let api = localCombatApi localApi
  _ <- expectRight "start configured scenario for API broadside tuning" =<< combatApiStartScenario api caravelaDuelScenarioId
  _ <- queueLocalCommand "queue configured API lock" api (Lock PlayerShip EnemyShip)
  _ <- queueLocalCommand "queue configured API fire at will" api (SetFireAtWill PlayerShip True)
  snapshot <- advanceLocalApiTick "advance configured API volley" api
  player <- expectShipSnapshot "configured API broadside player" PlayerShip snapshot
  enemy <- expectShipSnapshot "configured API broadside enemy" EnemyShip snapshot
  assertEqual "configured API volley damage reaches the snapshot" 49 (shipSnapshotHull enemy)
  assertEqual "configured API volley reload reaches the snapshot" 4 (shipSnapshotReload player)

-- | A hot reload refreshes what the boat kind owns while live state survives it.
-- The opening volley is deliberate: it makes the reload across the reload
-- non-zero, and the tuning the reloaded config supplies is then proven by the
-- volley that follows rather than by the config object alone.
--
-- The opening volley needs reach across the duel's opening separation, which the
-- shipped 48 no longer supplies, so the pre-reload engagement is given it here;
-- this test is about the tuning path across a hot reload rather than about the
-- closing phase, which 'testShippedDuelOpensOutsideBothShipsReach' pins.
testConfiguredLocalApiHotReloadsLiveEngagement :: IO ()
testConfiguredLocalApiHotReloadsLiveEngagement = do
  config <- expectRight "load packaged config for hot reload" =<< loadRuntimeCombatConfig
  localApi <- newConfiguredLocalCombatApi (configReachingAcrossTheOpening config)
  let api = localCombatApi localApi
  _ <- expectRight "start configured scenario before hot reload" =<< combatApiStartScenario api caravelaDuelScenarioId
  _ <- queueLocalCommand "queue player heading before hot reload" api (SetHeading PlayerShip (Heading 90))
  _ <- queueLocalCommand "queue player lock before hot reload" api (Lock PlayerShip EnemyShip)
  _ <- queueLocalCommand "queue player fire at will before hot reload" api (SetFireAtWill PlayerShip True)
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
  -- The volley on the tick before the reload sets this, so comparing it is not
  -- zero against zero: a hot reload that reset the cooldown would show here.
  assertEqual "the opening volley starts a reload before the hot reload" reloadTicks (shipSnapshotReload playerBefore)
  assertEqual "hot reload keeps player reload" (shipSnapshotReload playerBefore) (shipSnapshotReload playerAfter)
  assertEqual "hot reload keeps the player's locked target" (shipSnapshotLockedTarget playerBefore) (shipSnapshotLockedTarget playerAfter)
  assertEqual "hot reload keeps the player's fire permission" (shipSnapshotFirePermission playerBefore) (shipSnapshotFirePermission playerAfter)
  assertEqual "hot reload keeps the enemy's locked target" (shipSnapshotLockedTarget enemyBefore) (shipSnapshotLockedTarget enemyAfter)
  assertEqual "hot reload keeps the enemy's fire permission" (shipSnapshotFirePermission enemyBefore) (shipSnapshotFirePermission enemyAfter)
  assertEqual "hot reload updates big max hull" 200 (shipSnapshotMaxHull playerAfter)
  assertApprox "hot reload updates big length" 22 (shipSnapshotRenderedLength playerAfter)
  assertApprox "hot reload updates big width" 9 (shipSnapshotRenderedWidth playerAfter)
  assertEqual "hot reload updates a fresh hull to the new maximum" 200 (shipSnapshotHull playerAfter)
  assertEqual "hot reload updates small max hull" 70 (shipSnapshotMaxHull enemyAfter)
  assertEqual "hot reload recalculates the small hull from the damage it has taken" 45 (shipSnapshotHull enemyAfter)
  assertEqual "hot reload keeps enemy reload" (shipSnapshotReload enemyBefore) (shipSnapshotReload enemyAfter)
  advanced <- advanceLocalApiTick "advance using reloaded movement values" api
  advancedPlayer <- expectShipSnapshot "player after reloaded movement" PlayerShip advanced
  assertApprox "hot reload uses new tick seconds and acceleration" 4 (shipSnapshotCurrentSpeed advancedPlayer)
  -- The shipped reload the opening volley started still has two ticks to run, so
  -- the first volley the reloaded config can be judged by is the one after them.
  _ <- advanceLocalApiTick "cool the reloaded engagement once" api
  beforeVolley <- expectRight "observe the reloaded engagement before its volley" =<< combatApiObserveSnapshot api
  beforeVolleyPlayer <- expectShipSnapshot "player before the reloaded volley" PlayerShip beforeVolley
  assertEqual "the reload is on its last tick before the reloaded volley" 1 (shipSnapshotReload beforeVolleyPlayer)
  fired <- advanceLocalApiTick "fire using the reloaded broadside tuning" api
  firedPlayer <- expectShipSnapshot "player after the reloaded volley" PlayerShip fired
  firedEnemy <- expectShipSnapshot "enemy after the reloaded volley" EnemyShip fired
  assertEqual "hot reload uses the reloaded broadside damage" 5 (shipSnapshotHull firedEnemy)
  assertEqual "hot reload uses the reloaded reload ticks" 6 (shipSnapshotReload firedPlayer)
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

-- | The damage taken is what a hull reload recomputes the current hull from, so
-- it has to survive a clamp down and back up. The fixture applies that damage
-- with the domain's own accounting, so the test stays about the clamp rather than
-- about firing.
testHotReloadPreservesDamageAcrossHullClamp :: IO ()
testHotReloadPreservesDamageAcrossHullClamp = do
  config <- expectRight "load packaged config for repeated hull reload" =<< loadRuntimeCombatConfig
  let
    engagement = configuredDefaultEngagement config
    damaged =
      engagement
        { combatPlayer = applyBroadsideDamage 25 (combatPlayer engagement)
        }
    clamped = applyConfigToCombatState (withBigHull 20 config) damaged
    restored = applyConfigToCombatState (withBigHull 200 config) damaged
    clampedPlayer = combatPlayer clamped
    restoredPlayer = combatPlayer restored
  assertEqual "a volley records player damage against the hull" 135 (shipHull (combatPlayer damaged))
  assertEqual "lower max hull clamps current hull" 0 (shipHull clampedPlayer)
  assertEqual "lower max hull is visible" 20 (shipMaxHull clampedPlayer)
  assertEqual "raised max hull preserves original broadside damage" 175 (shipHull restoredPlayer)
  assertEqual "raised max hull is visible" 200 (shipMaxHull restoredPlayer)
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
  queuedSnapshot <- queueLocalCommand "queue local lock" api (Lock PlayerShip EnemyShip)
  queuedPlayer <- expectShipSnapshot "queued player snapshot" PlayerShip queuedSnapshot
  observedSnapshot <- expectRight "observe queued scenario" =<< combatApiObserveSnapshot api
  observedPlayer <- expectShipSnapshot "observed player snapshot" PlayerShip observedSnapshot
  advancedSnapshot <- advanceLocalApiTick "advance queued command" api
  advancedPlayer <- expectShipSnapshot "advanced player snapshot" PlayerShip advancedSnapshot
  assertEqual "queued command does not advance tick" 0 (combatSnapshotTick queuedSnapshot)
  assertEqual "queued lock is not applied immediately" Nothing (shipSnapshotLockedTarget queuedPlayer)
  assertEqual "observe hides the pending command" Nothing (shipSnapshotLockedTarget observedPlayer)
  assertEqual "advance increments tick" 1 (combatSnapshotTick advancedSnapshot)
  assertEqual "advance applies the queued lock" (Just EnemyShip) (shipSnapshotLockedTarget advancedPlayer)

-- | Both commands are read-model state, and the local API is where the client
-- meets them.
testLocalApiExposesLockedTargetAndFirePermission :: IO ()
testLocalApiExposesLockedTargetAndFirePermission = do
  (api, snapshot) <- startLocalDuel
  playerAtStart <- expectShipSnapshot "duel player at start" PlayerShip snapshot
  assertEqual "a fresh duel ship reports no locked target" Nothing (shipSnapshotLockedTarget playerAtStart)
  assertEqual "a fresh duel ship reports no permission to fire" False (shipSnapshotFirePermission playerAtStart)
  _ <- queueLocalCommand "queue player lock" api (Lock PlayerShip EnemyShip)
  _ <- queueLocalCommand "queue player fire at will" api (SetFireAtWill PlayerShip True)
  locked <- advanceLocalApiTick "advance queued lock and fire at will" api
  lockedPlayer <- expectShipSnapshot "locked player snapshot" PlayerShip locked
  lockedEnemy <- expectShipSnapshot "locked enemy snapshot" EnemyShip locked
  assertEqual "the lock command reaches the snapshot" (Just EnemyShip) (shipSnapshotLockedTarget lockedPlayer)
  assertEqual "the fire at will command reaches the snapshot" True (shipSnapshotFirePermission lockedPlayer)
  assertEqual "an unlocked ship still reports no locked target" Nothing (shipSnapshotLockedTarget lockedEnemy)
  assertEqual "an unarmed ship still reports no permission to fire" False (shipSnapshotFirePermission lockedEnemy)
  _ <- queueLocalCommand "queue player unlock" api (Lock PlayerShip EnemyShip)
  _ <- queueLocalCommand "queue player hold fire" api (SetFireAtWill PlayerShip False)
  released <- advanceLocalApiTick "advance queued unlock and hold fire" api
  releasedPlayer <- expectShipSnapshot "released player snapshot" PlayerShip released
  assertEqual "the same command through the API releases the lock" Nothing (shipSnapshotLockedTarget releasedPlayer)
  assertEqual "withdrawing fire at will reaches the snapshot" False (shipSnapshotFirePermission releasedPlayer)

-- | The whole rule through the local API: a volley leaves on the tick the queued
-- order applies, withdrawing during the reload stops the volley that was coming
-- without stopping the cooldown, and an arm order after it fires again.
testLocalApiFiresAndWithdrawsThroughTheQueuedOrders :: IO ()
testLocalApiFiresAndWithdrawsThroughTheQueuedOrders = do
  (api, _) <- startLocalDuel
  _ <- queueLocalCommand "queue player furl sails" api (SetSails PlayerShip SailsFurled)
  _ <- queueLocalCommand "queue player lock" api (Lock PlayerShip EnemyShip)
  _ <- queueLocalCommand "queue player fire at will" api (SetFireAtWill PlayerShip True)
  firstVolley <- advanceLocalApiTick "advance the first API volley" api
  playerAfterFirst <- expectShipSnapshot "player after the first API volley" PlayerShip firstVolley
  enemyAfterFirst <- expectShipSnapshot "enemy after the first API volley" EnemyShip firstVolley
  -- The enemy's autopilot restores cruise speed on the tick it issues its first
  -- order, so the order that actually holds it still is the one applied next.
  _ <- queueLocalCommand "queue enemy furl sails" api (SetSails EnemyShip SailsFurled)
  _ <- advanceLocalApiTick "advance the pinned enemy" api
  _ <- queueLocalCommand "queue player hold fire" api (SetFireAtWill PlayerShip False)
  withdrawn <- advanceLocalApiTick "advance the withdrawal" api
  playerWithdrawn <- expectShipSnapshot "player after the withdrawal" PlayerShip withdrawn
  loaded <- advanceLocalApiTick "advance past the completing tick" api
  loadedPlayer <- expectShipSnapshot "player on the tick the reload completes" PlayerShip loaded
  loadedEnemy <- expectShipSnapshot "enemy on the tick the reload completes" EnemyShip loaded
  _ <- queueLocalCommand "queue player fire at will again" api (SetFireAtWill PlayerShip True)
  rearmed <- advanceLocalApiTick "advance the re-armed volley" api
  rearmedPlayer <- expectShipSnapshot "player after re-arming" PlayerShip rearmed
  rearmedEnemy <- expectShipSnapshot "enemy after re-arming" EnemyShip rearmed
  assertEqual "the queued order fires a volley through the API" 75 (shipSnapshotHull enemyAfterFirst)
  assertEqual "the API snapshot shows the volley's reload" reloadTicks (shipSnapshotReload playerAfterFirst)
  assertEqual "the withdrawal is accepted during a reload" False (shipSnapshotFirePermission playerWithdrawn)
  assertEqual "the reload reaches zero while the guns are disengaged" 0 (shipSnapshotReload loadedPlayer)
  assertEqual "no volley leaves on the reload's completing tick once permission is withdrawn" 75 (shipSnapshotHull loadedEnemy)
  assertEqual "re-arming after the reload reaches zero is accepted" True (shipSnapshotFirePermission rearmedPlayer)
  assertEqual "the re-armed volley leaves through the API" 50 (shipSnapshotHull rearmedEnemy)

-- | Volleys through the API until the duel ends: the winner is reported and a
-- finished scenario stops advancing. Nothing but a volley takes a hull to zero,
-- so this is also the API's proof that automatic fire ends a fight.
testLocalApiReportsTerminalState :: IO ()
testLocalApiReportsTerminalState = do
  (api, _) <- startLocalDuel
  _ <- queueLocalCommand "queue player furl sails" api (SetSails PlayerShip SailsFurled)
  _ <- queueLocalCommand "queue player lock" api (Lock PlayerShip EnemyShip)
  _ <- queueLocalCommand "queue player fire at will" api (SetFireAtWill PlayerShip True)
  firstVolley <- advanceLocalApiTick "advance the first player volley" api
  firstEnemy <- expectShipSnapshot "enemy after the first player volley" EnemyShip firstVolley
  -- The enemy's autopilot restores cruise speed on the tick it issues its first
  -- order, so the order that actually holds it still is the one applied next.
  _ <- queueLocalCommand "queue enemy furl sails" api (SetSails EnemyShip SailsFurled)
  finished <- advanceUntilTerminal 20 "advance the local duel to its end" api
  player <- expectShipSnapshot "player at the end of the local duel" PlayerShip finished
  enemy <- expectShipSnapshot "enemy at the end of the local duel" EnemyShip finished
  afterFinished <- advanceLocalApiTick "advance a finished local scenario" api
  assertEqual "the first volley leaves the enemy damaged" 75 (shipSnapshotHull firstEnemy)
  assertEqual "the volleys disable the enemy" 0 (shipSnapshotHull enemy)
  assertEqual "the API reports the player's victory" (ScenarioFinished (Winner PlayerShip)) (combatSnapshotStatus finished)
  assertEqual "the enemy never fires: it holds no lock" 100 (shipSnapshotHull player)
  assertEqual "a finished API scenario stops advancing" (combatSnapshotTick finished) (combatSnapshotTick afterFinished)
  assertEqual "a finished API snapshot stays terminal" (combatSnapshotStatus finished) (combatSnapshotStatus afterFinished)

-- | Advance the local API until the scenario reaches a terminal status.
advanceUntilTerminal :: Int -> String -> CombatApi IO -> IO CombatSnapshot
advanceUntilTerminal remaining label api = do
  snapshot <- advanceLocalApiTick label api
  case combatSnapshotStatus snapshot of
    ScenarioFinished _ -> pure snapshot
    ScenarioRunning
      | remaining <= 0 -> die $ label <> ": the scenario did not finish before the test safety limit"
      | otherwise -> advanceUntilTerminal (remaining - 1) label api

-- | @shipFromSnapshot@ is the return leg of the read model, so a field that only
-- travels one way is a field the round trip silently drops.
testSnapshotCarriesLockedTargetAndFirePermission :: IO ()
testSnapshotCarriesLockedTargetAndFirePermission = do
  let
    locked =
      caravelaDuel
        { combatPlayer =
            (combatPlayer caravelaDuel)
              { shipLockedTarget = Just EnemyShip
              , shipFirePermission = True
              }
        }
    snapshot = combatSnapshotFromState caravelaDuelScenario locked
  player <- expectShipSnapshot "locked player snapshot" PlayerShip snapshot
  enemy <- expectShipSnapshot "unlocked enemy snapshot" EnemyShip snapshot
  assertEqual "snapshot exposes the locked target" (Just EnemyShip) (shipSnapshotLockedTarget player)
  assertEqual "snapshot exposes fire permission" True (shipSnapshotFirePermission player)
  assertEqual "snapshot exposes an unlocked ship" Nothing (shipSnapshotLockedTarget enemy)
  assertEqual "snapshot exposes a disengaged ship" False (shipSnapshotFirePermission enemy)
  assertEqual "snapshot round trip reconstructs the locked ship" (combatPlayer locked) (shipFromSnapshot player)
  assertEqual "snapshot round trip reconstructs the unlocked ship" (combatEnemy locked) (shipFromSnapshot enemy)
  assertEqual "snapshot round trip keeps the locked target" (Just EnemyShip) (shipLockedTarget (shipFromSnapshot player))
  assertEqual "snapshot round trip keeps fire permission" True (shipFirePermission (shipFromSnapshot player))

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
  assertApproxScalar "render camera zoom" 0.6 (cameraZoom camera)
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

-- | The range decision and the zoom decision are one decision: at 0.6 the
-- visible world is 266.7 by 150 units centred on the arena centre, and the
-- engagement-facing half of the duel's opening geometry fits inside it — both
-- hulls, each ship's engagement-facing envelope, and the contested space between
-- them.
--
-- Known clarification, recorded in issue 03: the criterion asks for the whole of
-- both ships' reach, and the outward-facing wedges do not fit. At this zoom the
-- visible world runs from -35 to 115 vertically, while the player's outward
-- envelope reaches y = -48 and the enemy's outward envelope y = 128 — each 13
-- units past the canvas edge. The last two assertions pin that, so a future
-- camera or range change cannot move it unnoticed.
testShippedEngagementFitsTheVisibleExtent :: IO ()
testShippedEngagementFitsTheVisibleExtent = do
  config <- expectRight "load packaged config for the visible extent" =<< loadRuntimeCombatConfig
  let
    engagement = configuredDefaultEngagement config
    player = combatPlayer engagement
    enemy = combatEnemy engagement
    playerTuning = broadsideTuningForShip config player
    enemyTuning = broadsideTuningForShip config enemy
    extent = visibleBounds battleCamera
    playerFacing = broadsideBounds player playerTuning (sideFacing player enemy)
    enemyFacing = broadsideBounds enemy enemyTuning (sideFacing enemy player)
    contested = intersectBounds playerFacing enemyFacing
    playerOutward = broadsideBounds player playerTuning (oppositeSide (sideFacing player enemy))
    enemyOutward = broadsideBounds enemy enemyTuning (oppositeSide (sideFacing enemy player))
  assertApprox "the visible world reaches the west edge" (-133.33333) (boundsMinX extent)
  assertApprox "the visible world reaches the east edge" 133.33333 (boundsMaxX extent)
  assertApprox "the visible world reaches the south edge" (-35) (boundsMinY extent)
  assertApprox "the visible world reaches the north edge" 115 (boundsMaxY extent)
  assertInsideExtent "the player's hull" (hullBounds player) extent
  assertInsideExtent "the enemy's hull" (hullBounds enemy) extent
  assertInsideExtent "the player's engagement-facing envelope" playerFacing extent
  assertInsideExtent "the enemy's engagement-facing envelope" enemyFacing extent
  assertInsideExtent "the contested space" contested extent
  assertEqual "the player's engagement-facing side is its port" Port (sideFacing player enemy)
  assertEqual "the enemy's engagement-facing side is its port" Port (sideFacing enemy player)
  assertEqual "the contested space is the overlap of both reaches" True (boundsWidth contested > 0 && boundsHeight contested > 0)
  -- The player's envelope runs 48 units north from its hull and the enemy's 48
  -- south from its own, so they meet between y = 32 and y = 48, and neither is
  -- wider than the half-angle allows: 48 cos 45 = 33.94 off the centre line.
  assertApprox "the contested space opens where the enemy's reach ends" 32 (boundsMinY contested)
  assertApprox "the contested space closes at the player's reach" 48 (boundsMaxY contested)
  assertApprox "the widest the reaches get is 48 cos 45 off the centre line" 33.9411 (boundsMaxX contested)
  assertApprox "the contested space mirrors about the centre line" (-33.9411) (boundsMinX contested)
  -- Known clarification: the outward-facing wedges are the part that does not fit.
  assertApprox "the player's outward envelope reaches 13 units past the south edge" (boundsMinY extent - 13) (boundsMinY playerOutward)
  assertApprox "the enemy's outward envelope reaches 13 units past the north edge" (boundsMaxY extent + 13) (boundsMaxY enemyOutward)

-- | The enemy's orbit is a circle of the fixed radius about the arena centre, so
-- the furthest any part of the enemy reaches from that centre is the radius plus
-- half its drawn length. That reach has to sit inside the visible world for a
-- whole circuit: the check is sufficient and exact because the ring is a circle
-- and the hull is drawn centred on it.
testShippedEnemyOrbitRingStaysInsideTheVisibleExtent :: IO ()
testShippedEnemyOrbitRingStaysInsideTheVisibleExtent = do
  config <- expectRight "load packaged config for the orbit ring" =<< loadRuntimeCombatConfig
  let
    engagement = configuredDefaultEngagement config
    enemy = combatEnemy engagement
    center = enemyOrbitCenter (combatEnemyOrbitAutopilot engagement)
    ringReach = enemyOrbitRadius + shipRenderedLength enemy / 2
    ring =
      Bounds
        { boundsMinX = pointX center - ringReach
        , boundsMaxX = pointX center + ringReach
        , boundsMinY = pointY center - ringReach
        , boundsMaxY = pointY center + ringReach
        }
  assertPoint "the shipped orbit centre is the arena centre" (Point 0 40) center
  assertApprox "the camera is centred on the orbit centre's x" (pointX center) (realToFrac (vec2X (cameraCenter battleCamera)))
  assertApprox "the camera is centred on the orbit centre's y" (pointY center) (realToFrac (vec2Y (cameraCenter battleCamera)))
  assertApprox "the ring plus half the enemy's hull reaches 28.5 units" 28.5 ringReach
  assertInsideExtent "the enemy's whole orbit circuit" ring (visibleBounds battleCamera)

-- | Legibility is checked numerically rather than in a browser: the battle
-- canvas's drawing buffer is 760 by 428 and the camera's world viewport is 160
-- by 90, so at zoom 0.6 one world unit is 2.85 pixels and the shipped hulls
-- render 45.6 by 17.1 pixels (big boat) and 25.65 by 8.55 (small boat). The
-- smallest dimension rounds to nine pixels, which is what makes the hulls
-- readable while the whole engagement fits.
--
-- The check by eye is deliberately deferred to issue 07: it is the first issue
-- with a firing envelope to look at, and driving a browser for it needs an
-- escalation this session does not have.
testShippedZoomRendersHullsLegibly :: IO ()
testShippedZoomRendersHullsLegibly = do
  config <- expectRight "load packaged config for the zoom legibility" =<< loadRuntimeCombatConfig
  let
    engagement = configuredDefaultEngagement config
    view = cameraViewport battleCamera
    zoom = realToFrac (cameraZoom battleCamera) :: Double
    worldWidth = realToFrac (viewportWidth view) / zoom
    worldHeight = realToFrac (viewportHeight view) / zoom
    pixelsPerUnitX = battleCanvasWidthPixels / worldWidth
    pixelsPerUnitY = battleCanvasHeightPixels / worldHeight
    pixels ship = (shipRenderedLength ship * pixelsPerUnitX, shipRenderedWidth ship * pixelsPerUnitX)
    (bigLengthPixels, bigWidthPixels) = pixels (combatPlayer engagement)
    (smallLengthPixels, smallWidthPixels) = pixels (combatEnemy engagement)
  assertApprox "the zoomed world viewport is 266.7 units wide" 266.66666 worldWidth
  assertApprox "the zoomed world viewport is 150 units tall" 150 worldHeight
  assertApprox "one world unit is 2.85 pixels across at the shipped zoom" 2.85 pixelsPerUnitX
  -- The canvas is 760 by 428 rather than exactly 16:9, so the vertical scale is
  -- a tenth of a percent larger; the pixel sizes below use the horizontal one.
  assertApprox "the canvas is not exactly 16:9, so the vertical scale is 2.8533" 2.85333 pixelsPerUnitY
  assertApprox "the big boat renders 45.6 pixels long" 45.6 bigLengthPixels
  assertApprox "the big boat renders 17.1 pixels abeam" 17.1 bigWidthPixels
  assertApprox "the small boat renders 25.65 pixels long" 25.65 smallLengthPixels
  assertApprox "the small boat renders 8.55 pixels abeam" 8.55 smallWidthPixels
  assertEqual "the smallest hull still clears 25 pixels by 8" True (smallLengthPixels >= 25 && smallWidthPixels >= 8)

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

-- | The drawing buffer the client serves the battle canvas at.
battleCanvasWidthPixels :: Double
battleCanvasWidthPixels = 760

battleCanvasHeightPixels :: Double
battleCanvasHeightPixels = 428

-- | An axis-aligned box in world units: the visible world, a hull, or a firing
-- envelope's bounds.
data Bounds = Bounds
  { boundsMinX :: Double
  , boundsMaxX :: Double
  , boundsMinY :: Double
  , boundsMaxY :: Double
  }
  deriving stock (Eq, Show)

-- | The world rectangle a camera shows: half the world viewport on each side of
-- its centre. This is the same division 'camera2DMatrix' and
-- 'screenToBattlePoint' do, so the extent asserted here is the one drawn.
visibleBounds :: Camera2D -> Bounds
visibleBounds camera =
  Bounds
    { boundsMinX = centerX - halfWidth
    , boundsMaxX = centerX + halfWidth
    , boundsMinY = centerY - halfHeight
    , boundsMaxY = centerY + halfHeight
    }
 where
  centerX = realToFrac (vec2X (cameraCenter camera))
  centerY = realToFrac (vec2Y (cameraCenter camera))
  zoom = realToFrac (cameraZoom camera) :: Double
  halfWidth = realToFrac (viewportWidth (cameraViewport camera)) / (2 * zoom)
  halfHeight = realToFrac (viewportHeight (cameraViewport camera)) / (2 * zoom)

-- | The box a hull occupies at its heading.
hullBounds :: Ship -> Bounds
hullBounds ship =
  Bounds
    { boundsMinX = positionX - extentX
    , boundsMaxX = positionX + extentX
    , boundsMinY = positionY - extentY
    , boundsMaxY = positionY + extentY
    }
 where
  positionX = pointX (shipPosition ship)
  positionY = pointY (shipPosition ship)
  halfLength = shipRenderedLength ship / 2
  halfWidth = shipRenderedWidth ship / 2
  radians = toRadians (headingDegrees (shipHeading ship))
  extentX = abs (halfLength * cos radians) + abs (halfWidth * sin radians)
  extentY = abs (halfLength * sin radians) + abs (halfWidth * cos radians)

-- | The box one broadside's firing envelope occupies: a circular sector from the
-- ship along that side's beam, out to the boat's practical range. A sector's
-- extremes are its apex or its arc at one of the two half-angle edges or at an
-- axis direction inside it, so those candidates are exact rather than sampled.
broadsideBounds :: Ship -> BroadsideTuning -> BroadsideSide -> Bounds
broadsideBounds ship tuning side =
  Bounds
    { boundsMinX = minimum (fmap fst corners)
    , boundsMaxX = maximum (fmap fst corners)
    , boundsMinY = minimum (fmap snd corners)
    , boundsMaxY = maximum (fmap snd corners)
    }
 where
  corners = (pointX center, pointY center) : fmap (sectorPoint center range) directions
  center = shipPosition ship
  range = broadsideTuningRange tuning
  halfAngle = broadsideTuningFiringArcDegrees tuning
  beam = headingDegrees (shipHeading ship) + beamOffset side
  directions = [beam - halfAngle, beam + halfAngle] <> filter insideArc [0, 90, 180, 270]
  insideArc degrees = abs (signedAngleDelta beam degrees) <= halfAngle + 1e-9

-- | A point on a sector's arc at a given bearing and radius.
sectorPoint :: Point -> Double -> Double -> (Double, Double)
sectorPoint center radius degrees =
  ( pointX center + radius * cos radians
  , pointY center + radius * sin radians
  )
 where
  radians = toRadians degrees

-- | The beam a broadside fires along, measured from the hull's heading: the port
-- beam is 90 degrees clockwise of it, the starboard beam 90 degrees the other
-- way, exactly as the domain's broadside check measures it.
beamOffset :: BroadsideSide -> Double
beamOffset side =
  case side of
    Port -> 90
    Starboard -> -90

-- | The broadside whose beam points at the target: the side a ship could bring
-- to bear if the target were in reach. At the duel's opening geometry both
-- ships' facing side is their port.
sideFacing :: Ship -> Ship -> BroadsideSide
sideFacing ship target =
  if facingDelta Port <= facingDelta Starboard then Port else Starboard
 where
  facingDelta side = abs (signedAngleDelta (headingDegrees (shipHeading ship) + beamOffset side) bearing)
  bearing = bearingDegrees (shipPosition ship) (shipPosition target)

oppositeSide :: BroadsideSide -> BroadsideSide
oppositeSide side =
  case side of
    Port -> Starboard
    Starboard -> Port

-- | The shortest signed angle from one direction to another, in (-180, 180].
signedAngleDelta :: Double -> Double -> Double
signedAngleDelta from to =
  let
    raw = to - from
    wrapped = raw - 360 * fromIntegral (floor (raw / 360) :: Int)
   in
    if wrapped > 180 then wrapped - 360 else wrapped

bearingDegrees :: Point -> Point -> Double
bearingDegrees from to =
  toDegrees (atan2 (pointY to - pointY from) (pointX to - pointX from))

toRadians :: Double -> Double
toRadians degrees = degrees * pi / 180

toDegrees :: Double -> Double
toDegrees radians = radians * 180 / pi

intersectBounds :: Bounds -> Bounds -> Bounds
intersectBounds left right =
  Bounds
    { boundsMinX = max (boundsMinX left) (boundsMinX right)
    , boundsMaxX = min (boundsMaxX left) (boundsMaxX right)
    , boundsMinY = max (boundsMinY left) (boundsMinY right)
    , boundsMaxY = min (boundsMaxY left) (boundsMaxY right)
    }

boundsWidth :: Bounds -> Double
boundsWidth bounds = boundsMaxX bounds - boundsMinX bounds

boundsHeight :: Bounds -> Double
boundsHeight bounds = boundsMaxY bounds - boundsMinY bounds

boundsWithin :: Bounds -> Bounds -> Bool
boundsWithin inner outer =
  boundsMinX inner >= boundsMinX outer
    && boundsMaxX inner <= boundsMaxX outer
    && boundsMinY inner >= boundsMinY outer
    && boundsMaxY inner <= boundsMaxY outer

assertInsideExtent :: String -> Bounds -> Bounds -> IO ()
assertInsideExtent label inner outer =
  if boundsWithin inner outer
    then pure ()
    else die $ label <> ": expected " <> show inner <> " inside the visible extent " <> show outer

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
