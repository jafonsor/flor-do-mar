-- | Regression test: a ship must actually arrive at its waypoint and clear its
-- navigation order, instead of orbiting it forever.
--
-- Uses the shipped runtime config (tick_seconds 0.8, battle_speed 4,
-- turn_rate 30 deg/s), where a ship covers 3.2 world units per tick and turns on
-- a 7.64-unit radius. This is the configuration that exposed the bug.
--
-- Run with: cabal run diagnosis-divergence
module Main (main) where

import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import FlorDoMar.Combat
import System.Exit (exitFailure)
import Text.Printf (printf)

main :: IO ()
main = do
  config <- expectConfig =<< loadRuntimeCombatConfig
  let
    tickSeconds = combatConfigTickSeconds config
    initialState = configuredDefaultEngagement config
    movement = movementPhysicsForShip config (combatEnemy initialState)
    player = combatPlayer initialState

  printf "runtime config: tick_seconds = %.3f\n" tickSeconds
  printf "enemy movement: battle_speed=%.1f max_speed=%.1f turn_rate=%.1f\n\n"
    (movementBattleSpeed movement) (movementMaxSpeed movement) (movementTurnRate movement)

  failures <- newIORef (0 :: Int)

  -- --- 1. A plan must terminate by arriving, not by exhausting the safety cap.
  let requestedWaypoint = Point 26 11
      plan = planNavigation tickSeconds movement player requestedWaypoint
      samples = length (navigationPlanSamples plan)
  printf "plan to %s\n" (showPoint requestedWaypoint)
  printf "  samples                        : %d\n" samples
  printf "  reached safety cap             : %s\n" (show (navigationPlanReachedSafetyCap plan))
  check failures "plan terminates by arriving, not by the 2000-tick safety cap"
    (not (navigationPlanReachedSafetyCap plan))
  check failures "a converged plan is small (under 200 samples)" (samples < 200)

  -- --- 2. Single-ship arrival: order clears and speed intent is honoured.
  let singleShip = player {shipCurrentSpeed = 4, shipTargetSpeed = 4}
      ordered = issueNavigationOrder tickSeconds (const movement) requestedWaypoint singleShip
      afterTicks = iterate (moveShip tickSeconds movement) ordered
      arrivedAt = findCleared 200 afterTicks
  printf "\nsingle ship toward waypoint\n"
  printf "  order cleared after            : %s ticks\n" (maybe "NEVER (200 ticks)" show arrivedAt)
  check failures "ship clears its navigation order within 200 ticks" (arrivedAt /= Nothing)
  case arrivedAt of
    Just n | n > 0 -> do
      let settled = afterTicks !! n
          distToWaypoint = distanceBetween (shipPosition settled) (navigationReachableWaypoint (expectOrder ordered))
      printf "  final distance to waypoint     : %.3f\n" distToWaypoint
      -- The arrival tolerance is the ship's turning radius (7.64 at battle
      -- speed), so "arrived" legitimately means within that circle.
      let turnRadius = movementBattleSpeed movement / (movementTurnRate movement * pi / 180)
      check failures
        "ship ends up within one turning radius of its waypoint"
        (distToWaypoint <= turnRadius + navigationArrivalRadius)
    _ -> pure ()

  -- --- 3. The orbit autopilot must advance through waypoints.
  let
    orbitTicks = 300 :: Int
    states = take orbitTicks (iterate (tickCombatWith tickSeconds (const movement) []) initialState)
    finalState = last states
    finalIndex = enemyOrbitNextWaypointIndex (combatEnemyOrbitAutopilot finalState)
  printf "\nenemy orbit autopilot over %d ticks\n" orbitTicks
  printf "  waypoint indices consumed      : %d\n" finalIndex
  check failures "orbit autopilot consumes at least 3 waypoints in 300 ticks" (finalIndex >= 3)

  -- --- 4. The enemy must stay in the neighbourhood of its orbit centre.
  --
  -- The centre is read from the autopilot rather than hardcoded: it used to be
  -- the enemy's starting position, and it is now the arena centre, so the
  -- measured point has to follow whichever the scenario builds.
  let
    finalAutopilot = combatEnemyOrbitAutopilot finalState
    enemyDrift = distanceBetween (shipPosition (combatEnemy finalState)) (enemyOrbitCenter finalAutopilot)
  printf "  enemy distance from orbit centre: %.2f (orbit radius %.1f)\n" enemyDrift enemyOrbitRadius
  check failures "enemy stays within 3x the orbit radius of its centre" (enemyDrift <= 3 * enemyOrbitRadius)

  count <- readIORef failures
  if count == 0
    then printf "\nALL PASS\n"
    else do
      printf "\n%d ASSERTION(S) FAILED\n" count
      exitFailure

-- | Index of the first state whose navigation order has been cleared.
findCleared :: Int -> [Ship] -> Maybe Int
findCleared limit ships = go 0 ships
 where
  go n (s : rest)
    | n > limit = Nothing
    | n > 0 && shipNavigationOrder s == Nothing = Just n
    | otherwise = go (n + 1) rest
  go _ [] = Nothing

expectOrder :: Ship -> NavigationOrder
expectOrder ship =
  case shipNavigationOrder ship of
    Just order -> order
    Nothing -> error "expected an active navigation order"

distanceBetween :: Point -> Point -> Double
distanceBetween a b =
  sqrt ((pointX b - pointX a) ** 2 + (pointY b - pointY a) ** 2)

showPoint :: Point -> String
showPoint p = printf "(%.0f, %.0f)" (pointX p) (pointY p)

check :: IORef Int -> String -> Bool -> IO ()
check ref label ok
  | ok = printf "  PASS  %s\n" label
  | otherwise = do
      printf "  FAIL  %s\n" label
      modifyIORef' ref (+ 1)

expectConfig :: Either [ConfigDiagnostic] a -> IO a
expectConfig result =
  case result of
    Right value -> pure value
    Left diagnostics -> error ("config error: " <> show (length diagnostics) <> " diagnostics")
