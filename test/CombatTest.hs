{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
import Data.Text (Text)
import Data.Text qualified as Text
import FlorDoMar.Client.BattleInput
import FlorDoMar.Client.BattleScene
import FlorDoMar.Client.GunPanel
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
  testEnemyLockAndArmGoThroughTheSameCommands
  testEnemyLockDelayIsANamedNonZeroConstant
  testEnemyArmOrderIsRefusedAndReportedDuringAReload
  testEnemyFiresThroughTheSameVolleyPhase
  testEnemyVolleysObeyTheSameRefusals
  testDisabledEnemyAcquiresNothing
  testEnemyNeverWithdrawsPermission
  testEnemyOrbitKeepsAdvancingWhileEngaged
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
  testSnapshotRoundTripKeepsTheReloadCounter
  testSnapshotExposesPerShipGunneryState
  testPerSideVerdictFollowsEachShipsOwnLock
  testReloadingShipStillReportsItsTargetInside
  testSnapshotPublishesNoSideHeldForALockItCannotAnswer
  testSnapshotTuningMatchesTheBoatConfig
  testHotReloadedGunneryTuningReachesTheSnapshot
  testBroadsideGeometryIsTheEnvelopeCheck
  testBroadsideRefusalOrderIsUnchanged
  testBattleSceneCarriesGunneryState
  testLocalApiQueuesCommandsUntilTick
  testLocalApiExposesLockedTargetAndFirePermission
  testLocalApiFiresAndWithdrawsThroughTheQueuedOrders
  testLocalApiReportsTerminalState
  testLocalApiEnemyClosesLocksArmsAndDamagesThePlayer
  testInitialBattleRenderScene
  testShippedEngagementFitsTheVisibleExtent
  testShippedEnemyOrbitRingStaysInsideTheVisibleExtent
  testShippedZoomRendersHullsLegibly
  testDamagedBattleRenderSceneTint
  testActiveNavigationRenderScene
  testEnemyDebugNavigationRenderScene
  testBattleInputHoverIntent
  testBattleInputMouseNavigationGesture
  testReticleRadiusIsOneScreenSpaceNumber
  testReticleHitTest
  testReticleHoverFollowsTheSnapshot
  testNavigationReleaseSplitsClickFromDrag
  testReticleRenderScene
  testGunPanelReloadProgress
  testGunPanelToggleIsClickableOnlyWhenItCanAct
  testGunPanelShowsTheRequestedStateUntilATickDecidesIt
  testGunPanelLockControlNeedsALockableTarget
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

-- | The enemy fights through the commands a player uses: it locks the player
-- with 'Lock' and arms itself with 'SetFireAtWill', both submitted through the
-- tick's ordinary command path, and never by writing 'shipLockedTarget' or
-- 'shipFirePermission' directly.
--
-- Locking needs no permission and grants none, exactly as it does for the player:
-- the enemy is committed to a target on the tick it locks and still silent until
-- its next order is applied.
testEnemyLockAndArmGoThroughTheSameCommands :: IO ()
testEnemyLockAndArmGoThroughTheSameCommands = do
  let
    afterDelay = advanceTicks (enemyLockDelayTicks - 1) caravelaDuel
    locked = advanceTicks enemyLockDelayTicks caravelaDuel
    armed = advanceTicks (enemyLockDelayTicks + 1) caravelaDuel
  assertEqual "the enemy locks the player through the ordinary lock command" (Just PlayerShip) (shipLockedTarget (combatEnemy locked))
  assertEqual "the lock is one the domain would accept from a player" BroadsideReady (canLockTarget afterDelay EnemyShip PlayerShip)
  assertEqual "the enemy's lock grants it no permission" False (shipFirePermission (combatEnemy locked))
  assertEqual "the enemy's lock is not the player's" Nothing (shipLockedTarget (combatPlayer locked))
  assertEqual "the enemy arms itself through the ordinary permission command" True (shipFirePermission (combatEnemy armed))
  assertEqual "the enemy's arm order does not touch the player's guns" False (shipFirePermission (combatPlayer armed))
  assertEqual "the enemy keeps the lock it armed against" (Just PlayerShip) (shipLockedTarget (combatEnemy armed))

-- | The delay before the enemy's first lock is a named constant in one place, and
-- it is not zero. The boundary is exact: the enemy is still unlocked on every
-- tick before the delay and locked on the tick that reaches it.
testEnemyLockDelayIsANamedNonZeroConstant :: IO ()
testEnemyLockDelayIsANamedNonZeroConstant = do
  assertEqual "the lock delay is a named constant" 3 enemyLockDelayTicks
  assertEqual "the lock delay is not zero" True (enemyLockDelayTicks > 0)
  assertEqual
    "the enemy holds no lock on the tick before the delay"
    Nothing
    (shipLockedTarget (combatEnemy (advanceTicks (enemyLockDelayTicks - 1) caravelaDuel)))
  assertEqual
    "the enemy acquires its lock on the delay tick"
    (Just PlayerShip)
    (shipLockedTarget (combatEnemy (advanceTicks enemyLockDelayTicks caravelaDuel)))
  assertEqual
    "the delay is counted in ticks from scenario start"
    enemyLockDelayTicks
    (combatTick (advanceTicks enemyLockDelayTicks caravelaDuel))

-- | The enemy is subject to the same arm guard the player is: while its shared
-- reload is above zero the autopilot's arm order is refused, the refusal is the
-- named 'BroadsideReloading' the player would get, and the guns stay disengaged.
--
-- A refused order leaves the state alone rather than being dropped, so the same
-- order is re-issued on the following tick and accepted once the reload finishes.
-- The player is far outside the enemy's reach here, so the silence being asserted
-- is the guard's doing rather than the geometry's.
testEnemyArmOrderIsRefusedAndReportedDuringAReload :: IO ()
testEnemyArmOrderIsRefusedAndReportedDuringAReload = do
  let
    -- A volley is what starts this reload; the fixture sets it and clears the
    -- permission it would have left behind, which is the one state in which the
    -- autopilot has an arm order to place during a reload.
    reloading =
      caravelaDuel
        { combatEnemy =
            (combatEnemy caravelaDuel)
              { shipLockedTarget = Just PlayerShip
              , shipFirePermission = False
              , shipReload = reloadTicks
              }
        }
    refused = tickCombat [] reloading
    cooledOnce = tickCombat [] refused
    loaded = tickCombat [] cooledOnce
  assertEqual "the order the autopilot places is refused by the reload guard" (BroadsideReloading reloadTicks) (canSetFireAtWill reloading EnemyShip True)
  assertEqual "the guard reads the counter's pre-tick value, as it does for the player" (BroadsideReloading 1) (canSetFireAtWill cooledOnce EnemyShip True)
  assertEqual "the tick's decrement still applies to the refused arm order" 2 (shipReload (combatEnemy refused))
  assertEqual "the refused arm order does not permit the enemy's guns" False (shipFirePermission (combatEnemy refused))
  assertEqual "the reloading enemy fires nothing" 100 (shipHull (combatPlayer refused))
  assertEqual "the enemy re-issues the refused order rather than dropping it" True (shipFirePermission (combatEnemy loaded))
  assertEqual "the re-issued order is accepted once the reload reaches zero" 0 (shipReload (combatEnemy loaded))

-- | The enemy's volleys leave through the tick's own volley phase and the one
-- envelope check, so the same rules bound them as bound the player's: with the
-- guns loaded and the player inside a broadside's envelope a volley lands, and
-- the shared reload blocks the next one.
--
-- Setting the two flags by hand is deliberate: this is the phase the enemy's
-- shots leave through, exercised without the autopilot's timing around it.
testEnemyFiresThroughTheSameVolleyPhase :: IO ()
testEnemyFiresThroughTheSameVolleyPhase = do
  let
    inEnemyEnvelope =
      caravelaDuel
        { combatEnemy =
            (combatEnemy caravelaDuel)
              { shipPosition = Point 0 40
              , shipLockedTarget = Just PlayerShip
              , shipFirePermission = True
              }
        }
    fired = tickCombat [] inEnemyEnvelope
    cooling = tickCombat [] fired
  assertEqual "the enemy's port envelope holds the player" BroadsideReady (canFireBroadside inEnemyEnvelope EnemyShip PlayerShip Port)
  assertEqual "the other beam holds nothing" (TargetOutsideFiringArc 180) (canFireBroadside inEnemyEnvelope EnemyShip PlayerShip Starboard)
  assertEqual "the enemy's volley damages the player" 75 (shipHull (combatPlayer fired))
  assertEqual "the volley starts the enemy's configured reload" reloadTicks (shipReload (combatEnemy fired))
  assertEqual "the enemy takes nothing from its own volley" 100 (shipHull (combatEnemy fired))
  assertEqual "the enemy fires nothing while its shared reload runs" 75 (shipHull (combatPlayer cooling))
  assertEqual "the enemy's shared reload keeps counting down" 2 (shipReload (combatEnemy cooling))
  assertEqual "the enemy holds the lock through the reload" (Just PlayerShip) (shipLockedTarget (combatEnemy cooling))

-- | The enemy's volleys obey the same refusals: no lock, no permission, no target
-- inside the envelope and no loaded guns each keep its guns silent.
--
-- The engine rules are read on the tick the duel starts, before the autopilot has
-- locked anything, so the only ship that could fire is the one the fixture armed.
-- The reach is a fixture value rather than the shipped 48: these fixtures move the
-- duel's own geometry around, and a target that is out of reach only because the
-- duel opens wide would not be showing the rule.
testEnemyVolleysObeyTheSameRefusals :: IO ()
testEnemyVolleysObeyTheSameRefusals = do
  let
    enemyTuning = legacyBroadsideTuning {broadsideTuningRange = 50}
    ticked scenario = tickCombatWithTuning 1 (const legacyMovementPhysics) (const enemyTuning) [] scenario
    -- The enemy's port beam points south from its opening heading, so a player
    -- eighty units south of it is on the beam and past the guns' reach: only the
    -- range can refuse that shot.
    onTheBeamBeyondReach =
      caravelaDuel
        { combatEnemy =
            (combatEnemy caravelaDuel)
              { shipLockedTarget = Just PlayerShip
              , shipFirePermission = True
              }
        }
    facingTheLockedPlayer =
      caravelaDuel
        { combatEnemy =
            (combatEnemy caravelaDuel)
              { shipPosition = Point 0 40
              , shipLockedTarget = Just PlayerShip
              , shipFirePermission = True
              }
        }
    outsideTheEnvelope =
      facingTheLockedPlayer
        { combatEnemy = (combatEnemy facingTheLockedPlayer) {shipHeading = Heading 90}
        }
    lockedButNotPermitted =
      facingTheLockedPlayer
        { combatEnemy = (combatEnemy facingTheLockedPlayer) {shipFirePermission = False}
        }
    reloading =
      facingTheLockedPlayer
        { combatEnemy = (combatEnemy facingTheLockedPlayer) {shipReload = 2}
        }
  assertEqual "the enemy's port beam holds the player it faces" BroadsideReady (canFireBroadsideWith (const enemyTuning) facingTheLockedPlayer EnemyShip PlayerShip Port)
  assertEqual "the other beam holds nothing" (TargetOutsideFiringArc 180) (canFireBroadsideWith (const enemyTuning) facingTheLockedPlayer EnemyShip PlayerShip Starboard)
  assertEqual "the player's geometry is on the port beam and only past the reach" (TargetOutOfRange 80) (canFireBroadsideWith (const enemyTuning) onTheBeamBeyondReach EnemyShip PlayerShip Port)
  assertEqual "the enemy's early ticks put no volley on the player" 100 (shipHull (combatPlayer (advanceTicks (enemyLockDelayTicks - 1) caravelaDuel)))
  assertEqual "the enemy's guns are still silent on the tick it locks" 100 (shipHull (combatPlayer (advanceTicks enemyLockDelayTicks caravelaDuel)))
  assertEqual "a locked enemy with no permission fires nothing on its tick" 100 (shipHull (combatPlayer (ticked lockedButNotPermitted)))
  assertEqual "a locked enemy with no permission stays loaded" 0 (shipReload (combatEnemy (ticked lockedButNotPermitted)))
  assertEqual "the lock survives the tick it did not fire on" (Just PlayerShip) (shipLockedTarget (combatEnemy (ticked lockedButNotPermitted)))
  assertEqual "a target outside both envelopes takes no volley" 100 (shipHull (combatPlayer (ticked outsideTheEnvelope)))
  assertEqual "a target across the beams starts no reload" 0 (shipReload (combatEnemy (ticked outsideTheEnvelope)))
  assertEqual "a target past the guns' reach takes no volley" 100 (shipHull (combatPlayer (ticked onTheBeamBeyondReach)))
  assertEqual "a target past the guns' reach starts no reload" 0 (shipReload (combatEnemy (ticked onTheBeamBeyondReach)))
  assertEqual "a reloading enemy fires nothing" 100 (shipHull (combatPlayer (ticked reloading)))
  assertEqual "a reloading enemy's counter still counts down" 1 (shipReload (combatEnemy (ticked reloading)))

-- | A disabled enemy acquires nothing: the autopilot places no lock and no arm
-- order, so a wreck neither picks a target nor asks for its guns back. The two
-- commands it would place are also refused outright by the scenario's status,
-- which is the engine's half of the same rule.
testDisabledEnemyAcquiresNothing :: IO ()
testDisabledEnemyAcquiresNothing = do
  let
    disabled = caravelaDuel {combatEnemy = (combatEnemy caravelaDuel) {shipHull = 0}}
    ticked = tickCombat [] disabled
    armedWreck =
      disabled {combatEnemy = (combatEnemy disabled) {shipFirePermission = True, shipLockedTarget = Just PlayerShip}}
    finishedWreck = tickCombat [] armedWreck
  assertEqual "a disabled enemy acquires no lock" Nothing (shipLockedTarget (combatEnemy ticked))
  assertEqual "a disabled enemy is never permitted to fire" False (shipFirePermission (combatEnemy ticked))
  assertEqual "a disabled enemy fires nothing" 100 (shipHull (combatPlayer ticked))
  assertEqual "the scenario ends when the enemy is disabled" (ScenarioFinished (Winner PlayerShip)) (combatStatus finishedWreck)
  -- The autopilot is asked directly, at the tick it would otherwise have locked
  -- on: a wreck places nothing, and neither does anyone in a finished scenario.
  assertEqual "a disabled enemy places no orders" [] (enemyGunneryOrders (armedWreck {combatTick = enemyLockDelayTicks}))
  assertEqual "the same state with a live hull places the lock" [Lock EnemyShip PlayerShip] (enemyGunneryOrders (caravelaDuel {combatTick = enemyLockDelayTicks}))
  assertEqual "a finished scenario's enemy places no orders" [] (enemyGunneryOrders (armedWreck {combatTick = enemyLockDelayTicks, combatStatus = ScenarioFinished (Winner PlayerShip)}))


-- | The enemy never withdraws the permission it granted itself. Once armed, no
-- later tick may disarm it — not the reload it waits on, and not the volley that
-- starts one — and the lock that produced the arming is never released either.
--
-- Read off the live duel rather than a fixture: the arming is the autopilot's own,
-- so the sequence is the one the game produces. It does fire during it, which the
-- player's hull shows.
testEnemyNeverWithdrawsPermission :: IO ()
testEnemyNeverWithdrawsPermission = do
  let afterArming = advanceTicks (enemyLockDelayTicks + 1) engagedDuel
  assertEqual "the enemy is permitted by the tick after it locks" True (shipFirePermission (combatEnemy afterArming))
  assertEqual "the enemy's volley starts its reload" reloadTicks (shipReload (combatEnemy afterArming))
  assertEqual "the enemy holds the lock it acquired" (Just PlayerShip) (shipLockedTarget (combatEnemy afterArming))
  assertEqual "the enemy damaged the player on the tick it armed" 75 (shipHull (combatPlayer afterArming))
  disarmed <- firstDisarmAfterArming 12 engagedDuel
  assertEqual "no later tick withdraws the permission the enemy granted itself" Nothing disarmed

-- | The first tick on which the enemy held a lock, had been permitted to fire, and
-- was then found without that permission — the autopilot disarming itself.
-- 'Nothing' when it never does.
firstDisarmAfterArming :: Int -> CombatState -> IO (Maybe Int)
firstDisarmAfterArming remaining state = go remaining state False
 where
  go left current wasArmed
    | left <= 0 = pure Nothing
    | wasArmed && shipLockedTarget enemy == Nothing = pure (Just (combatTick current))
    | wasArmed && not (shipFirePermission enemy) = pure (Just (combatTick current))
    | otherwise = go (left - 1) (tickCombat [] current) (wasArmed || shipFirePermission enemy)
   where
    enemy = combatEnemy current

-- | The gunnery work does not disturb the orbit: while the enemy is locked and
-- armed, the autopilot keeps issuing waypoints on the fixed ring around the arena
-- centre, and the ship keeps clearing them and advancing to the next.
testEnemyOrbitKeepsAdvancingWhileEngaged :: IO ()
testEnemyOrbitKeepsAdvancingWhileEngaged = do
  let
    locked = advanceTicks enemyLockDelayTicks caravelaDuel
    afterFirstWaypoint = advanceTicks 16 caravelaDuel
    centre = enemyOrbitCenter (combatEnemyOrbitAutopilot locked)
  assertEqual "the enemy is engaged by the tick it locks" (Just PlayerShip) (shipLockedTarget (combatEnemy locked))
  assertEqual "the enemy still holds an orbit order while engaged" True (shipNavigationOrder (combatEnemy locked) /= Nothing)
  assertEqual
    "the autopilot consumed the first orbit waypoint"
    True
    (enemyOrbitNextWaypointIndex (combatEnemyOrbitAutopilot afterFirstWaypoint) > enemyOrbitNextWaypointIndex (combatEnemyOrbitAutopilot locked))
  assertEqual "the enemy holds a further orbit order after clearing one" True (shipNavigationOrder (combatEnemy afterFirstWaypoint) /= Nothing)
  assertEqual "the gunnery work leaves the arena centre alone" (Point 0 40) centre
  assertEqual "the enemy is still engaged after clearing a waypoint" True (shipFirePermission (combatEnemy afterFirstWaypoint))
  forM_ [4, 8, 12, 16] $ \ticks ->
    assertEqual
      ("the orbit order at tick " <> show ticks <> " sits on the fixed ring")
      True
      (orbitOrderOnTheRing centre (advanceTicks ticks caravelaDuel))

-- | Whether the enemy's current orbit order aims at a waypoint on the ring the
-- autopilot draws around its centre.
orbitOrderOnTheRing :: Point -> CombatState -> Bool
orbitOrderOnTheRing centre state =
  case shipNavigationOrder (combatEnemy state) of
    Nothing -> False
    Just order -> abs (pointDistance centre (navigationRequestedWaypoint order) - enemyOrbitRadius) < 0.0001

-- | The whole fight through the local API, with the enemy driving itself: it
-- closes, locks the player, arms its guns and damages the player, all of it
-- through the same tick and the same commands a player's orders go through.
--
-- Nothing here writes the enemy's fire-control state: its lock, its permission
-- and the damage it deals are read from the snapshot the client reads.
--
-- The player is stopped and holds its fire, which is the geometry that lets the
-- fight happen at all: the duel opens outside both ships' 48-unit reach, so an
-- enemy circling a 24-unit ring only closes once the player stops running, and a
-- player who shoots back disables an 80-hull boat before it gets a second volley
-- away. Both of those are balance, not mechanism — this test is about the enemy
-- getting its shots off through the shared path.
testLocalApiEnemyClosesLocksArmsAndDamagesThePlayer :: IO ()
testLocalApiEnemyClosesLocksArmsAndDamagesThePlayer = do
  config <- expectRight "load packaged config for the enemy's fight" =<< loadRuntimeCombatConfig
  localApi <- newConfiguredLocalCombatApi config
  let api = localCombatApi localApi
  start <- expectRight "start the shipped duel for the enemy's fight" =<< combatApiStartScenario api caravelaDuelScenarioId
  _ <- queueLocalCommand "queue player furl sails" api (SetSails PlayerShip SailsFurled)
  _ <- queueLocalCommand "queue the player's lock" api (Lock PlayerShip EnemyShip)
  undamagedPlayer <- expectShipSnapshot "player before the enemy's first volley" PlayerShip start
  (firstHitTick, firstHit) <- advanceUntilTheEnemyDrawsBlood 40 "advance the shipped duel until the enemy draws blood" (shipSnapshotHull undamagedPlayer) api
  firstHitPlayer <- expectShipSnapshot "player after the enemy's first volley" PlayerShip firstHit
  firstHitEnemy <- expectShipSnapshot "enemy after its first volley" EnemyShip firstHit
  (secondHitTick, secondHit) <- advanceUntilTheEnemyDrawsBlood 20 "advance the shipped duel until the enemy fires again" (shipSnapshotHull firstHitPlayer) api
  secondHitPlayer <- expectShipSnapshot "player after the enemy's second volley" PlayerShip secondHit
  secondHitEnemy <- expectShipSnapshot "enemy after its second volley" EnemyShip secondHit
  assertEqual "the enemy's close and volley damage the player through the shared phase" 135 (shipSnapshotHull firstHitPlayer)
  assertEqual "the enemy acquired its lock through the ordinary lock command" (Just PlayerShip) (shipSnapshotLockedTarget firstHitEnemy)
  assertEqual "the enemy granted itself permission through the ordinary command" True (shipSnapshotFirePermission firstHitEnemy)
  assertEqual "the enemy's first volley starts its reload" reloadTicks (shipSnapshotReloadTicksRemaining firstHitEnemy)
  assertEqual "the enemy's next volley waits out the same shared reload" reloadTicks (secondHitTick - firstHitTick)
  assertEqual "the enemy's second volley damages the player again" 110 (shipSnapshotHull secondHitPlayer)
  assertEqual "the enemy never withdraws the permission it granted itself" True (shipSnapshotFirePermission secondHitEnemy)
  assertEqual "the enemy still holds the player it locked" (Just PlayerShip) (shipSnapshotLockedTarget secondHitEnemy)

-- | Advance the local API until the enemy has taken hull off the player, and
-- report the tick the damage appeared on. The damage is read only from the
-- snapshot, so it cannot be the test's own doing.
advanceUntilTheEnemyDrawsBlood :: Int -> String -> Int -> CombatApi IO -> IO (Int, CombatSnapshot)
advanceUntilTheEnemyDrawsBlood remaining label hullBefore api
  | remaining <= 0 = die $ label <> ": the enemy never damaged the player before the test safety limit"
  | otherwise = do
      snapshot <- advanceLocalApiTick label api
      player <- expectShipSnapshot label PlayerShip snapshot
      if shipSnapshotHull player < hullBefore
        then pure (combatSnapshotTick snapshot, snapshot)
        else advanceUntilTheEnemyDrawsBlood (remaining - 1) label hullBefore api

-- | The duel with the player parked on the enemy's port beam, forty units away,
-- so the enemy's volleys land as soon as it arms its guns. Only the geometry is
-- set here: the enemy's lock and permission are still acquired through the
-- autopilot's own commands.
engagedDuel :: CombatState
engagedDuel =
  caravelaDuel
    { combatEnemy = (combatEnemy caravelaDuel) {shipPosition = Point 0 40}
    , combatPlayer = (combatPlayer caravelaDuel) {shipPosition = Point 0 0}
    }

-- | Step the pure tick transition a fixed number of times.
advanceTicks :: Int -> CombatState -> CombatState
advanceTicks ticks state
  | ticks <= 0 = state
  | otherwise = advanceTicks (ticks - 1) (tickCombat [] state)

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
  assertEqual "the opening duel locks nothing" Nothing (shipSnapshotLockedTarget player)
  assertEqual "the opening duel permits no fire" False (shipSnapshotFirePermission player)
  -- Target inside is geometry plus a lock: with nothing locked, neither side of
  -- either ship holds a target, however the opening geometry lies.
  assertEqual "an unlocked ship's port side holds nothing" False (shipSnapshotPortHoldsTarget player)
  assertEqual "an unlocked ship's starboard side holds nothing" False (shipSnapshotStarboardHoldsTarget player)
  assertEqual "the enemy is unlocked too" Nothing (shipSnapshotLockedTarget enemy)
  assertEqual "the enemy's port side holds nothing" False (shipSnapshotPortHoldsTarget enemy)
  assertEqual "the enemy's starboard side holds nothing" False (shipSnapshotStarboardHoldsTarget enemy)

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
  assertEqual "configured API volley reload reaches the snapshot" 4 (shipSnapshotReloadTicksRemaining player)

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
  assertEqual "the opening volley starts a reload before the hot reload" reloadTicks (shipSnapshotReloadTicksRemaining playerBefore)
  assertEqual "hot reload keeps player reload" (shipSnapshotReloadTicksRemaining playerBefore) (shipSnapshotReloadTicksRemaining playerAfter)
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
  assertEqual "hot reload keeps enemy reload" (shipSnapshotReloadTicksRemaining enemyBefore) (shipSnapshotReloadTicksRemaining enemyAfter)
  advanced <- advanceLocalApiTick "advance using reloaded movement values" api
  advancedPlayer <- expectShipSnapshot "player after reloaded movement" PlayerShip advanced
  assertApprox "hot reload uses new tick seconds and acceleration" 4 (shipSnapshotCurrentSpeed advancedPlayer)
  -- The shipped reload the opening volley started still has two ticks to run, so
  -- the first volley the reloaded config can be judged by is the one after them.
  _ <- advanceLocalApiTick "cool the reloaded engagement once" api
  beforeVolley <- expectRight "observe the reloaded engagement before its volley" =<< combatApiObserveSnapshot api
  beforeVolleyPlayer <- expectShipSnapshot "player before the reloaded volley" PlayerShip beforeVolley
  assertEqual "the reload is on its last tick before the reloaded volley" 1 (shipSnapshotReloadTicksRemaining beforeVolleyPlayer)
  fired <- advanceLocalApiTick "fire using the reloaded broadside tuning" api
  firedPlayer <- expectShipSnapshot "player after the reloaded volley" PlayerShip fired
  firedEnemy <- expectShipSnapshot "enemy after the reloaded volley" EnemyShip fired
  assertEqual "hot reload uses the reloaded broadside damage" 5 (shipSnapshotHull firedEnemy)
  assertEqual "hot reload uses the reloaded reload ticks" 6 (shipSnapshotReloadTicksRemaining firedPlayer)
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
  assertEqual "the API snapshot shows the volley's reload" reloadTicks (shipSnapshotReloadTicksRemaining playerAfterFirst)
  assertEqual "the withdrawal is accepted during a reload" False (shipSnapshotFirePermission playerWithdrawn)
  assertEqual "the reload reaches zero while the guns are disengaged" 0 (shipSnapshotReloadTicksRemaining loadedPlayer)
  assertEqual "no volley leaves on the reload's completing tick once permission is withdrawn" 75 (shipSnapshotHull loadedEnemy)
  assertEqual "re-arming after the reload reaches zero is accepted" True (shipSnapshotFirePermission rearmedPlayer)
  assertEqual "the re-armed volley leaves through the API" 50 (shipSnapshotHull rearmedEnemy)

-- | Volleys through the API until the duel ends: the winner is reported and a
-- finished scenario stops advancing. Nothing but a volley takes a hull to zero,
-- so this is also the API's proof that automatic fire ends a fight.
--
-- Issue 02 asserted here that the enemy never fires, because it held no lock. That
-- reason is gone: the enemy holds a lock and its guns are armed, and this test now
-- asserts exactly that. What keeps the player untouched is the fixture's geometry,
-- and the refusal is the arc rather than the range: the enemy's sails are furled
-- to hold it still, which leaves it bow-on to the bearing — the player sits about
-- 76.5 units away at roughly 90 degrees off both beams, so neither broadside
-- bears — and this legacy fixture's reach is 100, not the shipped 48, so 76.5
-- units is comfortably inside it. Measured, not assumed. That the enemy does shoot
-- when a broadside bears is 'testLocalApiEnemyClosesLocksArmsAndDamagesThePlayer'.
-- This test's subject is untouched: the API reports the winner, and a finished
-- scenario stops advancing.
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
  assertEqual "the enemy held the lock and the arm order it placed through the commands" (Just PlayerShip, True) (shipSnapshotLockedTarget enemy, shipSnapshotFirePermission enemy)
  assertEqual "the player takes nothing: the pinned enemy is bow-on to the bearing" 100 (shipSnapshotHull player)
  assertEqual "so neither of the enemy's broadsides bears on the player" (False, False) (shipSnapshotPortHoldsTarget enemy, shipSnapshotStarboardHoldsTarget enemy)
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

-- | @shipFromSnapshot@ is the return leg of the read model for ship-owned state.
-- The reload counter is the third such field, and it travels back as the same
-- counter it came from; the tuning and the per-side verdicts are boat- and
-- geometry-derived, so they belong to the boat kind rather than to the ship.
testSnapshotRoundTripKeepsTheReloadCounter :: IO ()
testSnapshotRoundTripKeepsTheReloadCounter = do
  let
    reloading =
      caravelaDuel
        { combatPlayer = (combatPlayer caravelaDuel) {shipReload = reloadTicks}
        }
    snapshot = combatSnapshotFromState caravelaDuelScenario reloading
  player <- expectShipSnapshot "reloading round-trip player snapshot" PlayerShip snapshot
  assertEqual "the snapshot exposes the remaining ticks" reloadTicks (shipSnapshotReloadTicksRemaining player)
  assertEqual "the snapshot exposes the total the counter started from" reloadTicks (shipSnapshotReloadTicksTotal player)
  assertEqual "the round trip keeps the remaining ticks" reloadTicks (shipReload (shipFromSnapshot player))
  assertEqual "the round trip reconstructs the reloading ship" (combatPlayer reloading) (shipFromSnapshot player)

-- | Every gunnery field travels in the snapshot, for a locked ship and for an
-- unlocked one. The per-side verdicts are geometry against that ship's own
-- locked target: the opening geometry puts the enemy on the player's port beam,
-- and the port side holds it while the starboard side does not.
testSnapshotExposesPerShipGunneryState :: IO ()
testSnapshotExposesPerShipGunneryState = do
  let
    playerLockedOnEnemy =
      caravelaDuel
        { combatPlayer =
            (combatPlayer caravelaDuel)
              { shipLockedTarget = Just EnemyShip
              , shipFirePermission = True
              , shipReload = reloadTicks
              }
        }
    snapshot = combatSnapshotFromState caravelaDuelScenario playerLockedOnEnemy
  player <- expectShipSnapshot "gunnery player snapshot" PlayerShip snapshot
  enemy <- expectShipSnapshot "gunnery enemy snapshot" EnemyShip snapshot
  assertEqual "snapshot exposes the locked target" (Just EnemyShip) (shipSnapshotLockedTarget player)
  assertEqual "snapshot exposes fire permission" True (shipSnapshotFirePermission player)
  assertEqual "snapshot exposes the reload ticks remaining" reloadTicks (shipSnapshotReloadTicksRemaining player)
  assertEqual "snapshot exposes the total reload ticks" reloadTicks (shipSnapshotReloadTicksTotal player)
  assertEqual "snapshot exposes the boat's practical range" broadsideRange (broadsideTuningRange (shipSnapshotBroadsideTuning player))
  assertEqual "snapshot exposes the boat's firing arc" (broadsideTuningFiringArcDegrees legacyBroadsideTuning) (broadsideTuningFiringArcDegrees (shipSnapshotBroadsideTuning player))
  assertEqual "snapshot exposes the boat's reload ticks" reloadTicks (broadsideTuningReloadTicks (shipSnapshotBroadsideTuning player))
  assertEqual "the locked ship's port side holds the enemy" True (shipSnapshotPortHoldsTarget player)
  assertEqual "the locked ship's starboard side does not" False (shipSnapshotStarboardHoldsTarget player)
  assertEqual "the unlocked ship exposes no locked target" Nothing (shipSnapshotLockedTarget enemy)
  assertEqual "the unlocked ship exposes no permission to fire" False (shipSnapshotFirePermission enemy)
  assertEqual "the unlocked ship exposes its empty reload" 0 (shipSnapshotReloadTicksRemaining enemy)
  assertEqual "the unlocked ship still exposes the total" reloadTicks (shipSnapshotReloadTicksTotal enemy)
  assertEqual "an unlocked ship's port side holds nothing" False (shipSnapshotPortHoldsTarget enemy)
  assertEqual "an unlocked ship's starboard side holds nothing" False (shipSnapshotStarboardHoldsTarget enemy)
  assertEqual "an unlocked ship publishes the same boat tuning" (shipSnapshotBroadsideTuning player) (shipSnapshotBroadsideTuning enemy)

-- | One ship's verdict is computed against the ship it locked rather than
-- against a hardcoded pair of identities: the enemy holds the player it locked
-- while the unlocked player holds nothing, and turning the enemy across the
-- bearing empties its two sides without touching the lock that produced them.
testPerSideVerdictFollowsEachShipsOwnLock :: IO ()
testPerSideVerdictFollowsEachShipsOwnLock = do
  let
    enemyLockedOnPlayer =
      caravelaDuel
        { combatEnemy = (combatEnemy caravelaDuel) {shipLockedTarget = Just PlayerShip}
        }
    facing = combatSnapshotFromState caravelaDuelScenario enemyLockedOnPlayer
    turnedAway =
      combatSnapshotFromState caravelaDuelScenario $
        enemyLockedOnPlayer
          { combatEnemy = (combatEnemy enemyLockedOnPlayer) {shipHeading = Heading 90}
          }
  facingEnemy <- expectShipSnapshot "enemy facing the player" EnemyShip facing
  facingPlayer <- expectShipSnapshot "player the enemy locked" PlayerShip facing
  assertEqual "the enemy holds the player it locked" True (shipSnapshotPortHoldsTarget facingEnemy)
  assertEqual "the other beam of the enemy holds nothing" False (shipSnapshotStarboardHoldsTarget facingEnemy)
  assertEqual "the unlocked player holds nothing on its port side" False (shipSnapshotPortHoldsTarget facingPlayer)
  assertEqual "the unlocked player holds nothing on its starboard side" False (shipSnapshotStarboardHoldsTarget facingPlayer)
  awayEnemy <- expectShipSnapshot "enemy turned across the bearing" EnemyShip turnedAway
  assertEqual "the turned enemy keeps the lock it holds" (Just PlayerShip) (shipSnapshotLockedTarget awayEnemy)
  assertEqual "the turned enemy's guns are loaded" 0 (shipSnapshotReloadTicksRemaining awayEnemy)
  assertEqual "a loaded side turned away from the target holds nothing" False (shipSnapshotPortHoldsTarget awayEnemy)
  assertEqual "neither side of a turned-away ship holds the target" False (shipSnapshotStarboardHoldsTarget awayEnemy)

-- | \"Target inside\" is the envelope test without the reload, so the highlight
-- does not blink off for the whole cooldown. The guns are refused —
-- 'canFireBroadsideWith' answers 'BroadsideReloading' — while the snapshot still
-- reports the side that bears, and only that side.
testReloadingShipStillReportsItsTargetInside :: IO ()
testReloadingShipStillReportsItsTargetInside = do
  let
    fired = tickCombat [Lock PlayerShip EnemyShip, SetFireAtWill PlayerShip True] caravelaDuel
    snapshot = combatSnapshotFromState caravelaDuelScenario fired
  player <- expectShipSnapshot "reloading player snapshot" PlayerShip snapshot
  assertEqual "the volley leaves and starts the shared reload" reloadTicks (shipReload (combatPlayer fired))
  assertEqual "the reloading guns are refused by the reload guard" (BroadsideReloading reloadTicks) (canFireBroadside fired PlayerShip EnemyShip Port)
  assertEqual "the reloading ship still reports its port side holding the target" True (shipSnapshotPortHoldsTarget player)
  assertEqual "the reload does not move the target onto the other side" False (shipSnapshotStarboardHoldsTarget player)
  assertEqual "the reloading ship reports the ticks remaining" reloadTicks (shipSnapshotReloadTicksRemaining player)
  assertEqual "the reloading ship reports the total they count down from" reloadTicks (shipSnapshotReloadTicksTotal player)

-- | A lock the scenario cannot answer is not an error: the read model publishes
-- \"no side holds the target\". Membership is read from the identities the
-- scenario's hulls answer to, so a state whose two hulls both answer to the
-- player's id has no enemy for the player's lock to point at, exactly as
-- 'testLockOnAShipOutsideTheScenarioIsRefused' builds it.
testSnapshotPublishesNoSideHeldForALockItCannotAnswer :: IO ()
testSnapshotPublishesNoSideHeldForALockItCannotAnswer = do
  let
    withoutEnemy =
      caravelaDuel
        { combatPlayer = (combatPlayer caravelaDuel) {shipLockedTarget = Just EnemyShip}
        , combatEnemy = (combatEnemy caravelaDuel) {shipId = PlayerShip}
        }
    selfLocked =
      caravelaDuel
        { combatPlayer = (combatPlayer caravelaDuel) {shipLockedTarget = Just PlayerShip}
        }
    absentSnapshot = combatSnapshotFromState caravelaDuelScenario withoutEnemy
    selfSnapshot = combatSnapshotFromState caravelaDuelScenario selfLocked
  -- Both hulls answer to the same id, so the ships are addressed by the order the
  -- read model publishes them in: player first.
  case combatSnapshotShips absentSnapshot of
    absentPlayer : _ -> do
      assertEqual "the unanswerable lock is still reported" (Just EnemyShip) (shipSnapshotLockedTarget absentPlayer)
      assertEqual "a lock on a ship the scenario does not carry holds no port side" False (shipSnapshotPortHoldsTarget absentPlayer)
      assertEqual "a lock on a ship the scenario does not carry holds no starboard side" False (shipSnapshotStarboardHoldsTarget absentPlayer)
    [] -> die "the absent-target snapshot published no ships"
  selfPlayer <- expectShipSnapshot "self-locked player snapshot" PlayerShip selfSnapshot
  assertEqual "a self-lock is reported as held rather than hidden" (Just PlayerShip) (shipSnapshotLockedTarget selfPlayer)
  assertEqual "a ship's port side never holds its own hull" False (shipSnapshotPortHoldsTarget selfPlayer)
  assertEqual "a ship's starboard side never holds its own hull" False (shipSnapshotStarboardHoldsTarget selfPlayer)

-- | The published tuning is the boat config the ship is flying, not the legacy
-- fixture: the tuned boats reach, bear and reload by different numbers, and each
-- ship's snapshot reports its own boat's.
testSnapshotTuningMatchesTheBoatConfig :: IO ()
testSnapshotTuningMatchesTheBoatConfig = do
  config <- expectRight "load packaged config for snapshot tuning" =<< loadRuntimeCombatConfig
  let tunedConfig = tunedBoatConfig config
  localApi <- newConfiguredLocalCombatApi tunedConfig
  snapshot <- expectRight "start tuned scenario for snapshot tuning" =<< combatApiStartScenario (localCombatApi localApi) caravelaDuelScenarioId
  player <- expectShipSnapshot "tuned player snapshot" PlayerShip snapshot
  enemy <- expectShipSnapshot "tuned enemy snapshot" EnemyShip snapshot
  let
    engagement = configuredDefaultEngagement tunedConfig
    expectedPlayerTuning = broadsideTuningForShip tunedConfig (combatPlayer engagement)
    expectedEnemyTuning = broadsideTuningForShip tunedConfig (combatEnemy engagement)
  assertEqual "the player publishes its own boat's tuning" expectedPlayerTuning (shipSnapshotBroadsideTuning player)
  assertEqual "the enemy publishes its own boat's tuning" expectedEnemyTuning (shipSnapshotBroadsideTuning enemy)
  assertEqual "the two boats' tunings differ" False (expectedPlayerTuning == expectedEnemyTuning)
  assertEqual "the published practical range is the boat's" 70 (broadsideTuningRange (shipSnapshotBroadsideTuning player))
  assertEqual "the published firing arc is the boat's" 15 (broadsideTuningFiringArcDegrees (shipSnapshotBroadsideTuning player))
  assertEqual "the published total reload is the boat's" 4 (shipSnapshotReloadTicksTotal player)
  assertEqual "the other boat publishes its own total reload" 1 (shipSnapshotReloadTicksTotal enemy)
  assertEqual "the other boat publishes its own practical range" 100 (broadsideTuningRange (shipSnapshotBroadsideTuning enemy))

-- | A live hot reload changes what the snapshot publishes: the reloaded range,
-- arc and reload reach the client with no restart, and the verdict moves with
-- them — the target the shipped 48 left outside the envelope is inside the
-- reloaded 90, while the lock that produced it survives untouched.
testHotReloadedGunneryTuningReachesTheSnapshot :: IO ()
testHotReloadedGunneryTuningReachesTheSnapshot = do
  config <- expectRight "load packaged config for gunnery hot reload" =<< loadRuntimeCombatConfig
  localApi <- newConfiguredLocalCombatApi config
  let api = localCombatApi localApi
  _ <- expectRight "start configured scenario for gunnery hot reload" =<< combatApiStartScenario api caravelaDuelScenarioId
  _ <- queueLocalCommand "queue gunnery hot reload lock" api (Lock PlayerShip EnemyShip)
  locked <- advanceLocalApiTick "advance the gunnery hot reload lock" api
  playerBefore <- expectShipSnapshot "player before the gunnery hot reload" PlayerShip locked
  assertEqual "the shipped range reaches the snapshot before the reload" 48 (broadsideTuningRange (shipSnapshotBroadsideTuning playerBefore))
  assertEqual "the shipped arc reaches the snapshot before the reload" 45 (broadsideTuningFiringArcDegrees (shipSnapshotBroadsideTuning playerBefore))
  assertEqual "the shipped total reload reaches the snapshot before the reload" 3 (shipSnapshotReloadTicksTotal playerBefore)
  assertEqual "the lock survives the tick that applies it" (Just EnemyShip) (shipSnapshotLockedTarget playerBefore)
  assertEqual "at 48 the closing engagement still leaves the target out of reach" False (shipSnapshotPortHoldsTarget playerBefore)
  localCombatApiReloadConfig localApi (longReachGunneryConfig config)
  after <- expectRight "observe the reloaded gunnery tuning" =<< combatApiObserveSnapshot api
  playerAfter <- expectShipSnapshot "player after the gunnery hot reload" PlayerShip after
  assertEqual "the reloaded practical range reaches the snapshot" 90 (broadsideTuningRange (shipSnapshotBroadsideTuning playerAfter))
  assertEqual "the reloaded firing arc reaches the snapshot" 30 (broadsideTuningFiringArcDegrees (shipSnapshotBroadsideTuning playerAfter))
  assertEqual "the reloaded total reload reaches the snapshot" 5 (shipSnapshotReloadTicksTotal playerAfter)
  assertEqual "the hot reload releases no lock" (shipSnapshotLockedTarget playerBefore) (shipSnapshotLockedTarget playerAfter)
  assertEqual "the hot reload keeps the reload counter" (shipSnapshotReloadTicksRemaining playerBefore) (shipSnapshotReloadTicksRemaining playerAfter)
  assertEqual "the same lock holds the target under the reloaded reach" True (shipSnapshotPortHoldsTarget playerAfter)
  assertEqual "the reloaded arc still leaves the other beam empty" False (shipSnapshotStarboardHoldsTarget playerAfter)

-- | The shipped geometry with a distinctive reach, arc and reload, so the values
-- a hot reload publishes cannot be confused with the ones it replaced. The 90
-- reaches across the closing engagement the shipped 48 cannot.
longReachGunneryConfig :: CombatConfig -> CombatConfig
longReachGunneryConfig config =
  config
    { combatConfigBoats =
        [ if boatConfigId boat == "big"
            then
              boat
                { boatConfigBroadsideRange = 90
                , boatConfigFiringArcDegrees = 30
                , boatConfigReloadTicks = 5
                }
            else boat
        | boat <- combatConfigBoats config
        ]
    }

-- | The per-side verdicts the snapshot publishes are the same envelope
-- computation 'canFireBroadsideWith' refuses on, and they report the same
-- numbers, so a drawn highlight and the enforced firing condition cannot
-- disagree about where a broadside reaches.
testBroadsideGeometryIsTheEnvelopeCheck :: IO ()
testBroadsideGeometryIsTheEnvelopeCheck = do
  let
    tuning = legacyBroadsideTuning
    attacker = combatPlayer playerReadyToFire
    target = combatEnemy playerReadyToFire
    beyondRange = playerReadyToFire {combatEnemy = target {shipPosition = Point 0 120}}
    outsideArc = playerReadyToFire {combatPlayer = attacker {shipHeading = Heading 90}}
  assertEqual "the opening geometry holds the target on the port side" EnvelopeHoldsTarget (broadsideGeometry tuning attacker target Port)
  assertEqual "the opening geometry leaves the starboard side empty" (EnvelopeTargetOutsideArc 180) (broadsideGeometry tuning attacker target Starboard)
  assertEqual "a target past the reach reports the range it stands at" (EnvelopeTargetBeyondRange 120) (broadsideGeometry tuning (combatPlayer beyondRange) (combatEnemy beyondRange) Port)
  assertEqual "a target off the beam reports the angle it stands at" (EnvelopeTargetOutsideArc 90) (broadsideGeometry tuning (combatPlayer outsideArc) (combatEnemy outsideArc) Port)
  assertEqual "the broadside check accepts where the geometry holds" BroadsideReady (canFireBroadsideWith (const tuning) playerReadyToFire PlayerShip EnemyShip Port)
  assertEqual "the broadside check refuses on the same range" (TargetOutOfRange 120) (canFireBroadsideWith (const tuning) beyondRange PlayerShip EnemyShip Port)
  assertEqual "the broadside check refuses on the same arc" (TargetOutsideFiringArc 90) (canFireBroadsideWith (const tuning) outsideArc PlayerShip EnemyShip Port)

-- | The guard chain's order is part of the broadside check's contract: a finished
-- scenario outranks a disabled attacker, which outranks a disabled target, which
-- outranks the reload, which outranks range, which outranks the arc. Taking the
-- geometry out of the chain must not reshuffle any of it.
testBroadsideRefusalOrderIsUnchanged :: IO ()
testBroadsideRefusalOrderIsUnchanged = do
  let
    ready = playerReadyToFire
    player = combatPlayer ready
    enemy = combatEnemy ready
    beyondRange = ready {combatEnemy = enemy {shipPosition = Point 0 120}}
    reloadingBeyondRange = beyondRange {combatPlayer = player {shipReload = 2}}
    disabledTargetBeyondRange = beyondRange {combatEnemy = (combatEnemy beyondRange) {shipHull = 0}}
    disabledAttackerReloading = ready {combatPlayer = player {shipHull = 0, shipReload = 2}}
    finishedAndDisabled =
      ready
        { combatStatus = ScenarioFinished (Winner PlayerShip)
        , combatPlayer = player {shipHull = 0}
        , combatEnemy = enemy {shipHull = 0}
        }
    outOfRangeAndArc = beyondRange {combatPlayer = player {shipHeading = Heading 90}}
  assertEqual "a finished scenario outranks a disabled attacker" (ScenarioAlreadyFinished (Winner PlayerShip)) (canFireBroadside finishedAndDisabled PlayerShip EnemyShip Port)
  assertEqual "a disabled attacker outranks a disabled target" (AttackerDisabled PlayerShip) (canFireBroadside disabledAttackerReloading PlayerShip EnemyShip Port)
  assertEqual "a disabled target outranks the reload" (TargetDisabled EnemyShip) (canFireBroadside disabledTargetBeyondRange {combatPlayer = player {shipReload = 2}} PlayerShip EnemyShip Port)
  assertEqual "a disabled target outranks the range" (TargetDisabled EnemyShip) (canFireBroadside disabledTargetBeyondRange PlayerShip EnemyShip Port)
  assertEqual "the reload outranks the range" (BroadsideReloading 2) (canFireBroadside reloadingBeyondRange PlayerShip EnemyShip Port)
  assertEqual "the range outranks the arc" (TargetOutOfRange 120) (canFireBroadside outOfRangeAndArc PlayerShip EnemyShip Port)

-- | The battle scene's markers carry the drawing inputs and the verdict the
-- client must not recompute, straight off the snapshot.
testBattleSceneCarriesGunneryState :: IO ()
testBattleSceneCarriesGunneryState = do
  let
    locked =
      caravelaDuel
        { combatPlayer =
            (combatPlayer caravelaDuel)
              { shipLockedTarget = Just EnemyShip
              , shipFirePermission = True
              , shipReload = reloadTicks
              }
        }
    snapshot = combatSnapshotFromState caravelaDuelScenario locked
    scene = battleSceneFromSnapshot snapshot
  playerSnapshot <- expectShipSnapshot "gunnery scene player snapshot" PlayerShip snapshot
  playerMarker <- expectMarker "player marker with gunnery state" PlayerShip scene
  enemyMarker <- expectMarker "enemy marker with gunnery state" EnemyShip scene
  assertEqual "the marker carries the locked target" (Just EnemyShip) (markerLockedTarget playerMarker)
  assertEqual "the marker carries fire permission" True (markerFirePermission playerMarker)
  assertEqual "the marker carries the ticks remaining" reloadTicks (markerReloadTicksRemaining playerMarker)
  assertEqual "the marker carries the total ticks" reloadTicks (markerReloadTicksTotal playerMarker)
  assertEqual "the marker carries the boat's tuning" (shipSnapshotBroadsideTuning playerSnapshot) (markerBroadsideTuning playerMarker)
  assertEqual "the marker carries the port-side verdict" True (markerPortHoldsTarget playerMarker)
  assertEqual "the marker carries the starboard-side verdict" False (markerStarboardHoldsTarget playerMarker)
  assertEqual "an unlocked ship's marker carries no lock" Nothing (markerLockedTarget enemyMarker)
  assertEqual "an unlocked ship's marker carries no permission" False (markerFirePermission enemyMarker)
  assertEqual "an unlocked ship's marker carries no target inside" False (markerPortHoldsTarget enemyMarker)

-- | The marker one ship's drawing reads, found by the side it is on.
expectMarker :: String -> ShipId -> BattleScene -> IO ShipMarker
expectMarker label identity scene =
  case filter ((== isPlayerShip identity) . markerIsPlayer) (battleSceneShips scene) of
    [marker] -> pure marker
    [] -> die $ label <> ": missing marker for " <> show identity
    markers -> die $ label <> ": expected one marker, got " <> show (length markers)

isPlayerShip :: ShipId -> Bool
isPlayerShip identity =
  case identity of
    PlayerShip -> True
    EnemyShip -> False

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
    (NavigationPointerPrimaryDown (PointerSample (Point 0 40) expectedReticleRadius))
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

-- | The reticle is one screen-space number.
--
-- The radius a click is hit-tested with, the radius the hover ring is drawn at
-- and the radius the locked ring is drawn at are the same 24 canvas pixels,
-- converted once through the same screen-to-battle maths the pointer position
-- goes through. That is what makes a ring a promise about where the click lands.
testReticleRadiusIsOneScreenSpaceNumber :: IO ()
testReticleRadiusIsOneScreenSpaceNumber = do
  let
    centre = canvasPointer (ScreenPoint 380 214)
    edge = canvasPointer (ScreenPoint (380 + reticleRadiusPixels) 214)
    justInside = canvasPointer (ScreenPoint (380 + reticleRadiusPixels - 0.5) 214)
    justOutside = canvasPointer (ScreenPoint (380 + reticleRadiusPixels + 0.5) 214)
  assertApprox "the reticle is 24 canvas pixels" 24 reticleRadiusPixels
  assertApprox
    "24 canvas pixels convert to exactly the reticle's battle radius"
    (pointerSampleReticleRadius centre)
    (pointDistance (pointerSamplePoint centre) (pointerSamplePoint edge))
  assertEqual
    "a point half a pixel inside the ring is inside the radius"
    True
    (pointDistance (pointerSamplePoint centre) (pointerSamplePoint justInside) < pointerSampleReticleRadius centre)
  assertEqual
    "a point half a pixel outside the ring is outside the radius"
    True
    (pointDistance (pointerSamplePoint centre) (pointerSamplePoint justOutside) > pointerSampleReticleRadius centre)
  -- The screen space the pointer arrives in is the canvas's displayed size, not
  -- the drawing buffer: the same 24 pixels span twice the world distance when
  -- the element is displayed at half width.
  assertApprox
    "the reticle scales with the canvas's displayed size"
    (2 * pointerSampleReticleRadius centre)
    (screenReticleRadius battleCamera (ScreenSize 380 214))

-- | The screen-space hit test: a hull under the reticle is hit, a hull just
-- outside it is not, open water is not, and the player's own hull never is.
testReticleHitTest :: IO ()
testReticleHitTest = do
  let
    snapshot = combatSnapshotFromState caravelaDuelScenario caravelaDuel
    ships = combatSnapshotShips snapshot
    radius = expectedReticleRadius
  enemy <- expectShipSnapshot "reticle hit test enemy" EnemyShip snapshot
  player <- expectShipSnapshot "reticle hit test player" PlayerShip snapshot
  let
    enemyPosition = shipSnapshotPosition enemy
    playerPosition = shipSnapshotPosition player
    at offset = PointerSample (offsetPoint enemyPosition offset 0) radius
    openWater = PointerSample (Point 60 60) radius
  assertEqual "a point at the reticle's centre hits that ship" (Just EnemyShip) (reticleShip PlayerShip (at 0) ships)
  assertEqual "a point just inside the reticle still hits" (Just EnemyShip) (reticleShip PlayerShip (at (radius - 0.5)) ships)
  assertEqual "a point just outside the reticle misses" Nothing (reticleShip PlayerShip (at (radius + 0.5)) ships)
  assertEqual "the player's own hull is never a lock candidate" Nothing (reticleShip PlayerShip (PointerSample playerPosition radius) ships)
  assertEqual "an unhovered ship is not hit" Nothing (reticleShip PlayerShip openWater ships)
  assertEqual "hovering a hull sets the hover state" (Just EnemyShip) (lockTargetAtSample PlayerShip snapshot (at 0))
  assertEqual "hovering open water clears the hover state" Nothing (lockTargetAtSample PlayerShip snapshot openWater)
  assertEqual "hovering the player's own hull is not a lock action" Nothing (lockTargetAtSample PlayerShip snapshot (PointerSample playerPosition radius))
  -- The same boundary in the pointer's own space: a hull centred under the
  -- pointer is hit, and the same hull one pixel outside the ring is not.
  let
    centrePointer = canvasPointer (ScreenPoint 380 214)
    hullUnderPointer = enemy {shipSnapshotPosition = pointerSamplePoint centrePointer}
    pointerAtPixels pixels = canvasPointer (ScreenPoint pixels 214)
  assertEqual "a hull centred under the pointer is hit" (Just EnemyShip) (reticleShip PlayerShip centrePointer [hullUnderPointer])
  assertEqual
    "a hull one pixel outside the reticle is not hit"
    Nothing
    (reticleShip PlayerShip (pointerAtPixels (380 + reticleRadiusPixels + 1)) [hullUnderPointer])

-- | The gesture split, decided at release from what the press was: a click on a
-- hull the player may lock toggles the lock and navigates nowhere, a click on the
-- player's own hull asks for nothing at all, and every other release — including
-- every drag, and every drag that started on a hull — is a navigation order.
-- | The hover is re-derived from the pointer's last position against every
-- snapshot, not folded from pointer events, because a ship moves under a pointer
-- that is holding still. A hover kept from the last pointer event would leave the
-- ring on a hull the pointer has left — and the click that follows hit-tests the
-- press afresh — so the marker would lie about where the gesture lands.
testReticleHoverFollowsTheSnapshot :: IO ()
testReticleHoverFollowsTheSnapshot = do
  let
    snapshot = combatSnapshotFromState caravelaDuelScenario caravelaDuel
    radius = expectedReticleRadius
  enemy <- expectShipSnapshot "hover follows the snapshot enemy" EnemyShip snapshot
  player <- expectShipSnapshot "hover follows the snapshot player" PlayerShip snapshot
  let
    enemyPosition = shipSnapshotPosition enemy
    playerPosition = shipSnapshotPosition player
    onEnemy = PointerSample enemyPosition radius
    movedSnapshot =
      snapshot
        { combatSnapshotShips = fmap (moveHullAway radius) (combatSnapshotShips snapshot)
        }
    moveHullAway distance ship
      | shipSnapshotId ship == EnemyShip =
          ship {shipSnapshotPosition = offsetPoint (shipSnapshotPosition ship) (2 * distance) 0}
      | otherwise = ship
  assertEqual
    "an unchanged sample on an unchanged snapshot keeps the hover"
    (Just EnemyShip)
    (hoveredShipAt PlayerShip (Just onEnemy) snapshot)
  assertEqual
    "the hover is the click's own hit test"
    (lockTargetAtSample PlayerShip snapshot onEnemy)
    (hoveredShipAt PlayerShip (Just onEnemy) snapshot)
  assertEqual
    "a ship that moves out from under a held pointer loses the hover on that snapshot"
    Nothing
    (hoveredShipAt PlayerShip (Just onEnemy) movedSnapshot)
  assertEqual "no pointer sample clears the hover" Nothing (hoveredShipAt PlayerShip Nothing snapshot)
  assertEqual
    "no pointer sample leaves a moved snapshot nothing"
    Nothing
    (hoveredShipAt PlayerShip Nothing movedSnapshot)
  assertEqual
    "the player's own hull is never the hovered ship"
    Nothing
    (hoveredShipAt PlayerShip (Just (PointerSample playerPosition radius)) snapshot)

testNavigationReleaseSplitsClickFromDrag :: IO ()
testNavigationReleaseSplitsClickFromDrag = do
  let
    snapshot = combatSnapshotFromState caravelaDuelScenario caravelaDuel
    status = combatSnapshotStatus snapshot
    radius = expectedReticleRadius
    waterPoint = Point 60 60
  enemy <- expectShipSnapshot "release split enemy" EnemyShip snapshot
  player <- expectShipSnapshot "release split player" PlayerShip snapshot
  let
    enemyPosition = shipSnapshotPosition enemy
    playerPosition = shipSnapshotPosition player
    at position = PointerSample position radius
    pressAt pointer =
      case planNavigationForSnapshot snapshot PlayerShip (pointerSamplePoint pointer) of
        Nothing -> NoNavigationGesture
        Just plan ->
          beginNavigationGestureAt
            (pointerSamplePoint pointer)
            (navigationPlanReachableWaypoint plan)
            6
            (hullAtReticle pointer (combatSnapshotShips snapshot))
    enemyPress = pressAt (at enemyPosition)
    playerPress = pressAt (at playerPosition)
    waterPress = pressAt (at waterPoint)
    dragFrom gesture =
      case gesture of
        NavigationGesture press _ -> updateNavigationGesture (offsetPoint (navigationPressRequestedWaypoint press) 4 0) gesture
        NoNavigationGesture -> NoNavigationGesture
    enemyClick = navigationReleaseIntent PlayerShip status False enemyPress
    waterClick = navigationReleaseIntent PlayerShip status False waterPress
  assertEqual "a click on an enemy hull locks it" (Just (LockOnRelease EnemyShip)) enemyClick
  assertEqual "a click on an enemy hull issues no navigation order" False (releaseNavigates enemyClick)
  assertEqual "a click on the player's own hull asks for nothing at all" Nothing (navigationReleaseIntent PlayerShip status False playerPress)
  assertEqual
    "a drag that started on the player's own hull still navigates"
    (Just (NavigateOnRelease playerPosition (navigationGestureSelectedSpeed (dragFrom playerPress))))
    (navigationReleaseIntent PlayerShip status False (dragFrom playerPress))
  assertEqual "a click on open water still issues a navigation order" (Just (NavigateOnRelease waterPoint Nothing)) waterClick
  assertEqual "a click on open water navigates" True (releaseNavigates waterClick)
  assertEqual
    "a drag that started on a hull issues a navigation order rather than a lock"
    (Just (NavigateOnRelease enemyPosition (Just 3)))
    (navigationReleaseIntent PlayerShip status False (dragFrom enemyPress))
  assertEqual
    "a drag from open water issues a navigation order with the selected speed"
    (Just (NavigateOnRelease waterPoint (Just 3)))
    (navigationReleaseIntent PlayerShip status False (dragFrom waterPress))
  assertEqual
    "the lock target comes from the press, not the release"
    (Just (NavigateOnRelease waterPoint (navigationGestureSelectedSpeed (updateNavigationGesture enemyPosition waterPress))))
    (navigationReleaseIntent PlayerShip status False (updateNavigationGesture enemyPosition waterPress))
  assertEqual "a release with no press asks for nothing" Nothing (navigationReleaseIntent PlayerShip status False NoNavigationGesture)
  assertEqual "a click on a hull under the setup overlay asks for nothing" Nothing (navigationReleaseIntent PlayerShip status True enemyPress)
  assertEqual
    "a click on a hull in a finished scenario asks for nothing"
    Nothing
    (navigationReleaseIntent PlayerShip (ScenarioFinished (Winner PlayerShip)) False enemyPress)

-- | The two reticles: a hover ring on the ship a click would lock, a ring on the
-- ship already locked — the same size, differing only in colour, above the hull
-- in z, and never drawn on the player's own ship.
testReticleRenderScene :: IO ()
testReticleRenderScene = do
  let
    unlockedSnapshot = combatSnapshotFromState caravelaDuelScenario caravelaDuel
    lockedSnapshot =
      panelSnapshotWith (withPlayerShip (\ship -> ship {shipLockedTarget = Just EnemyShip}))
    hoveredReticle = restingReticleState {reticleStateHoveredShip = Just EnemyShip}
    selfHoveredReticle = restingReticleState {reticleStateHoveredShip = Just PlayerShip}
    sceneWith reticle snapshot =
      battleRenderScene (battleSceneFromSnapshotWithReticle reticle False True Nothing NoNavigationGesture snapshot)
    hoverScene = sceneWith hoveredReticle unlockedSnapshot
    lockedScene = sceneWith restingReticleState lockedSnapshot
    lockedHoverScene = sceneWith hoveredReticle lockedSnapshot
    quietScene = sceneWith restingReticleState unlockedSnapshot
    selfHoverScene = sceneWith selfHoveredReticle unlockedSnapshot
  enemy <- expectShipSnapshot "reticle render enemy" EnemyShip unlockedSnapshot
  (hoverTransform, hoverRadius, hoverStyle) <- expectRingStrokeStyle "hover-reticle:enemy" hoverScene
  (lockedTransform, lockedRadius, lockedStyle) <- expectRingStrokeStyle "locked-reticle:enemy" lockedScene
  enemyHull <- expectMesh "ship:enemy" hoverScene
  let
    hullTransform = renderMeshTransform enemyHull
    hullTop = vec3Z (transformPosition hullTransform) + (vec3Z (transformScale hullTransform) / 2)
    enemyPosition = shipSnapshotPosition enemy
  assertEqual "the hover ring is drawn on the hovered ship" ["hover-reticle:enemy"] (reticleRingNames hoverScene)
  assertEqual "the locked ring is drawn on the player's locked target" ["locked-reticle:enemy"] (reticleRingNames lockedScene)
  assertEqual "no hover and no lock draws no reticle" [] (reticleRingNames quietScene)
  assertEqual "hovering the player's own hull draws no lock candidate" [] (reticleRingNames selfHoverScene)
  assertEqual "the locked ship wears the locked ring rather than a hover ring" ["locked-reticle:enemy"] (reticleRingNames lockedHoverScene)
  assertApproxScalar "the hover ring is the pointer's reticle radius" (realToFrac expectedReticleRadius) hoverRadius
  assertApproxScalar "the locked ring is the same size as the hover ring" hoverRadius lockedRadius
  assertEqual
    "the two reticles differ by colour"
    True
    (materialColor (strokeStyleMaterial hoverStyle) /= materialColor (strokeStyleMaterial lockedStyle))
  assertColor "hover reticle colour" (color 0.82 0.9 1 0.85) (materialColor (strokeStyleMaterial hoverStyle))
  assertColor "locked reticle colour" (color 1 0.72 0.2 1) (materialColor (strokeStyleMaterial lockedStyle))
  assertApproxScalar "the hover ring is anchored to the hovered hull's x" (realToFrac (pointX enemyPosition)) (vec3X (transformPosition hoverTransform))
  assertApproxScalar "the hover ring is anchored to the hovered hull's y" (realToFrac (pointY enemyPosition)) (vec3Y (transformPosition hoverTransform))
  assertApproxScalar "the locked ring is anchored to the locked hull's x" (realToFrac (pointX enemyPosition)) (vec3X (transformPosition lockedTransform))
  assertApproxScalar "the locked ring is anchored to the locked hull's y" (realToFrac (pointY enemyPosition)) (vec3Y (transformPosition lockedTransform))
  assertEqual "the hull's own z extent reaches the 0.1 navigation overlay" True (hullTop > 0.1)
  assertEqual "the hover ring sits above the hull rather than inside it" True (vec3Z (transformPosition hoverTransform) > hullTop)
  assertEqual "the locked ring sits above the hull rather than inside it" True (vec3Z (transformPosition lockedTransform) > hullTop)
  assertApproxScalar "both reticles sit at the same height" (vec3Z (transformPosition hoverTransform)) (vec3Z (transformPosition lockedTransform))

-- | The reload circle is reload progress: empty at the volley that started the
-- reload, full when the guns are loaded. Disengaging does not touch it, because
-- the guns reload whether or not they are permitted to fire — so the sweep runs
-- on to full and the control becomes clickable again when it gets there.
testGunPanelReloadProgress :: IO ()
testGunPanelReloadProgress = do
  let
    loaded = panelStateWith (\ship -> ship {shipReload = 0})
    fresh = panelStateWith (\ship -> ship {shipReload = reloadTicks})
    partway = panelStateWith (\ship -> ship {shipReload = reloadTicks - 1})
    armedMidReload = panelStateWith (\ship -> ship {shipFirePermission = True, shipReload = reloadTicks - 1})
    disengagedMidReload = panelStateWith (\ship -> ship {shipFirePermission = False, shipReload = reloadTicks - 1})
    finishedSweep = panelStateWith (\ship -> ship {shipFirePermission = False, shipReload = 0})
  assertApprox "a loaded ship's circle is full" 1 (gunPanelReloadProgress loaded)
  assertApprox "a reload that has just started leaves the circle empty" 0 (gunPanelReloadProgress fresh)
  assertApprox "a partly finished reload is part-way round" (1 / 3) (gunPanelReloadProgress partway)
  assertEqual
    "the circle reads the snapshot's own reload pair"
    (reloadTicks - 1, reloadTicks)
    (gunPanelReloadTicksRemaining partway, gunPanelReloadTicksTotal partway)
  assertApprox "the sweep interpolates over one tick" 1 (gunPanelReloadSweepSeconds loaded)
  assertApprox
    "disengaging mid-reload leaves the sweep exactly where it was"
    (gunPanelReloadProgress armedMidReload)
    (gunPanelReloadProgress disengagedMidReload)
  assertApprox "the sweep finishes full while still disengaged" 1 (gunPanelReloadProgress finishedSweep)
  assertEqual "the control is not clickable to arm while the sweep runs" False (gunPanelToggleEnabled disengagedMidReload)
  assertEqual "the control is always clickable to disengage" True (gunPanelToggleEnabled armedMidReload)
  assertEqual "the control is clickable again once the sweep finishes" True (gunPanelToggleEnabled finishedSweep)

-- | Arming is offered only when the guns are disengaged and loaded; disengaging
-- is always offered.
testGunPanelToggleIsClickableOnlyWhenItCanAct :: IO ()
testGunPanelToggleIsClickableOnlyWhenItCanAct = do
  let
    disengagedLoaded = panelStateWith (\ship -> ship {shipFirePermission = False, shipReload = 0})
    disengagedReloading = panelStateWith (\ship -> ship {shipFirePermission = False, shipReload = 1})
    armedLoaded = panelStateWith (\ship -> ship {shipFirePermission = True, shipReload = 0})
    armedReloading = panelStateWith (\ship -> ship {shipFirePermission = True, shipReload = 1})
  assertEqual "the toggle shows the snapshot's permission" False (gunPanelArmed disengagedLoaded)
  assertEqual "a disengaged ship with loaded guns can be armed" True (gunPanelToggleEnabled disengagedLoaded)
  assertEqual "arming is not offered while the reload runs" False (gunPanelToggleEnabled disengagedReloading)
  assertEqual "the toggle shows an armed ship as armed" True (gunPanelArmed armedLoaded)
  assertEqual "an armed ship can always be disengaged" True (gunPanelToggleEnabled armedReloading)
  assertEqual "an armed ship with loaded guns can be disengaged" True (gunPanelToggleEnabled armedLoaded)

-- | The toggle is optimistic but honest: it shows the state the player asked for
-- from the click until a later tick has published a snapshot, and that snapshot
-- is then the truth whether it applied the order or refused it.
testGunPanelShowsTheRequestedStateUntilATickDecidesIt :: IO ()
testGunPanelShowsTheRequestedStateUntilATickDecidesIt = do
  let
    request = FireAtWillRequest True 0
    clicked = panelSnapshotAt 0 False 0
    submitted = panelSnapshotAt 0 False 0
    refused = panelSnapshotAt 1 False 1
    applied = panelSnapshotAt 1 True 1
    afterClick = applyFireAtWillRequestUpdate (FireAtWillRequested request) Nothing
    afterSubmission = applyFireAtWillRequestUpdate (FireAtWillSnapshot submitted) afterClick
    afterRefusedTick = applyFireAtWillRequestUpdate (FireAtWillSnapshot refused) afterSubmission
    afterAppliedTick = applyFireAtWillRequestUpdate (FireAtWillSnapshot applied) afterSubmission
    armedOf snapshot outstanding = gunPanelArmed (gunPanelState snapshot outstanding Nothing)
  assertEqual "the click is remembered as the state the player asked for" (Just request) afterClick
  assertEqual "the click is shown before any tick processes it" True (armedOf clicked afterClick)
  assertEqual "the submission's own snapshot leaves the optimistic state alone" True (armedOf clicked afterSubmission)
  assertEqual "a tick that refuses the order reverts the panel to the snapshot" False (armedOf refused afterRefusedTick)
  assertEqual "the refused request is dropped rather than displayed" Nothing afterRefusedTick
  assertEqual
    "the panel stops offering to arm while the refused order's reload runs"
    False
    (gunPanelToggleEnabled (gunPanelState refused afterRefusedTick Nothing))
  assertEqual "a tick that applies the order shows the snapshot's armed state" True (armedOf applied afterAppliedTick)
  assertEqual "the applied request is dropped once the snapshot agrees" Nothing afterAppliedTick

-- | The lock control acts on the hovered ship, or on the locked one, and never
-- offers a lock action with no target — least of all on the player's own hull.
testGunPanelLockControlNeedsALockableTarget :: IO ()
testGunPanelLockControlNeedsALockableTarget = do
  let
    unlockedSnapshot = combatSnapshotFromState caravelaDuelScenario caravelaDuel
    lockedSnapshot = panelSnapshotWith (withPlayerShip (\ship -> ship {shipLockedTarget = Just EnemyShip}))
    selfLockedSnapshot = panelSnapshotWith (withPlayerShip (\ship -> ship {shipLockedTarget = Just PlayerShip}))
    stateOf snapshot hovered = gunPanelState snapshot Nothing hovered
  assertEqual
    "no hover and no lock leaves the panel without a lock action"
    Nothing
    (gunPanelLockTarget (stateOf unlockedSnapshot Nothing))
  assertEqual
    "a hovered ship is the lock control's target"
    (Just EnemyShip)
    (gunPanelLockTarget (stateOf unlockedSnapshot (Just EnemyShip)))
  assertEqual
    "hovering a ship that is not locked offers a lock"
    False
    (gunPanelLockReleases (stateOf unlockedSnapshot (Just EnemyShip)))
  assertEqual
    "an already locked ship is the lock control's target"
    (Just EnemyShip)
    (gunPanelLockTarget (stateOf lockedSnapshot Nothing))
  assertEqual
    "the locked ship's control releases the lock"
    True
    (gunPanelLockReleases (stateOf lockedSnapshot Nothing))
  assertEqual
    "the player's own hull is never a lock control target"
    Nothing
    (gunPanelLockTarget (stateOf unlockedSnapshot (Just PlayerShip)))
  assertEqual
    "a hand-built self-lock is never a lock control target"
    Nothing
    (gunPanelLockTarget (stateOf selfLockedSnapshot Nothing))

-- | The reticle radius the shipped canvas and camera give the pointer, in battle
-- units. Every reticle test starts from this one number.
expectedReticleRadius :: Double
expectedReticleRadius = screenReticleRadius battleCamera battleCanvasSize

-- | A pointer in the shipped canvas's own pixels, converted the way the client
-- converts one.
canvasPointer :: ScreenPoint -> PointerSample
canvasPointer point = pointerSample battleCamera point battleCanvasSize

-- | The gesture a press with an already-selected speed produces, for scenes that
-- need one without walking a whole pointer sequence.
selectedSpeedGesture :: Point -> Double -> Maybe Double -> NavigationGesture
selectedSpeedGesture waypoint maximumSpeed selectedSpeed =
  NavigationGesture (NavigationPress waypoint waypoint maximumSpeed Nothing) selectedSpeed

-- | Whether a release asked for a navigation order at all.
releaseNavigates :: Maybe NavigationReleaseIntent -> Bool
releaseNavigates intent =
  case intent of
    Just NavigateOnRelease {} -> True
    _ -> False

-- | The names of the reticle rings a scene carries.
reticleRingNames :: RenderScene -> [Text]
reticleRingNames scene =
  [ name
  | RingStroke name _ _ _ _ _ <- renderSceneNodes scene
  , "reticle" `Text.isInfixOf` name
  ]

-- | A snapshot of the duel's own state with the player's ship changed.
panelSnapshotWith :: (CombatState -> CombatState) -> CombatSnapshot
panelSnapshotWith change = combatSnapshotFromState caravelaDuelScenario (change caravelaDuel)

withPlayerShip :: (Ship -> Ship) -> CombatState -> CombatState
withPlayerShip change state = state {combatPlayer = change (combatPlayer state)}

-- | The panel's state for a player ship with the given guns.
panelStateWith :: (Ship -> Ship) -> GunPanelState
panelStateWith change = gunPanelState (panelSnapshotWith (withPlayerShip change)) Nothing Nothing

-- | A snapshot on a chosen tick with the player's guns in a chosen state, for
-- walking the optimistic toggle across a tick boundary.
panelSnapshotAt :: Int -> Bool -> Int -> CombatSnapshot
panelSnapshotAt tick permitted remaining =
  panelSnapshotWith
    ( \state ->
        (withPlayerShip (\ship -> ship {shipFirePermission = permitted, shipReload = remaining}) state)
          {combatTick = tick}
    )

expectRingStrokeStyle :: Text -> RenderScene -> IO (Transform, Scalar, StrokeStyle)
expectRingStrokeStyle name scene =
  case matchingNodes of
    [(localTransform, radius, style)] -> pure (localTransform, radius, style)
    [] -> die $ "missing ring stroke " <> show name
    nodes -> die $ "expected one ring stroke " <> show name <> ", got " <> show (length nodes)
 where
  matchingNodes =
    [ (localTransform, radius, style)
    | RingStroke nodeName localTransform _ radius _ style <- renderSceneNodes scene
    , nodeName == name
    ]

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
    gesture = selectedSpeedGesture (Point 40 20) 4 (Just 2)
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
    gesture = selectedSpeedGesture (Point 40 20) 4 (Just 2)
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
