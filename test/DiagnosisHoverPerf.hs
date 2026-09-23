-- | Throwaway Phase 1/4 measurement harness for the "app blocks on mouse move"
-- bug. Measures the real hover code path natively:
--
--   hover point -> battleSceneFromSnapshotWithHover -> renderScenePrimitives
--
-- Run with: cabal run diagnosis-hover-perf
module Main (main) where

import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (sort)
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import FlorDoMar.Client.BattleScene
import FlorDoMar.Client.Render.Scene
import FlorDoMar.Client.WebGL.Geometry (Geometry3D (..))
import FlorDoMar.Combat
import System.Exit (exitFailure)
import Text.Printf (printf)

-- These mirror test/CombatTest.hs so the perf scenario matches the existing
-- planner tests.
movement :: MovementPhysics
movement =
  MovementPhysics
    { movementBattleSpeed = 4
    , movementMaxSpeed = 6
    , movementAcceleration = 4
    , movementDeceleration = 4
    , movementTurnRate = 90
    , movementIdealTurnSpeed = 4
    , movementYawAcceleration = 180
    }

tickSeconds :: Double
tickSeconds = 0.25

-- Built with the shipped runtime config's tick seconds AND movement physics.
-- combatSnapshotFromState alone is not enough: it hardcodes tickSeconds = 1 and
-- legacyMovementPhysics, which would plan against physics the ship never uses and
-- make an unreachable arrival look like a planning bug.
snapshotFor :: CombatConfig -> CombatSnapshot
snapshotFor config =
  combatSnapshotFromStateWithPlanning
    (combatConfigTickSeconds config)
    (movementPhysicsForShip config)
    (const legacyBroadsideTuning)
    caravelaDuelScenario
    (configuredDefaultEngagement config)

-- A realistic mouse sweep across the battle view. The player is at roughly
-- (0,0) facing +X with the enemy out at +X, so a sweep covers near, far,
-- ahead-of-bow and behind-the-beam targets.
hoverSweep :: [Point]
hoverSweep =
  [ Point x y
  | x <- [2, 4, 6, 8, 10, 14, 18, 24, 30, 40]
  , y <- [0, 5, 10, 20]
  ]

timeOne :: CombatSnapshot -> Point -> IO (Double, Int, Int, Int)
timeOne snapshot hoverPoint = do
  start <- getCurrentTime
  let scene = battleSceneFromSnapshotWithHover False (Just hoverPoint) snapshot
      primitives = renderScenePrimitives (battleRenderScene scene)
      -- Force everything that the renderer would consume.
      vertices = sum (fmap (length . geometry3DVertices . renderPrimitiveGeometry) primitives)
      indices = sum (fmap (length . geometry3DIndices . renderPrimitiveGeometry) primitives)
      samples = maybe 0 (length . navigationPlanSamples) (battleSceneHoverNavigationPlan scene)
  vertices `seq` indices `seq` samples `seq` pure ()
  end <- getCurrentTime
  pure (realToFrac (diffUTCTime end start) * 1000, samples, vertices, indices)

-- Does the plan terminate early, or does it burn the whole safety budget?
main :: IO ()
main = do
  printf "hover points: %d\n" (length hoverSweep)
  printf "plannerSafetyTickLimit is 2000 ticks\n\n"
  printf "%-18s %9s %9s %9s %9s\n" "hover" "ms" "samples" "verts" "indices"
  printf "%s\n" (replicate 60 '-')
  config <- expectConfig =<< loadRuntimeCombatConfig
  let snapshot = snapshotFor config
  results <- mapM (run snapshot) hoverSweep
  let times = fmap (\(t, _, _, _) -> t) results
      sampleCounts = fmap (\(_, s, _, _) -> fromIntegral s) results :: [Double]
      sampleTotal = sum sampleCounts
      sampleCount = fromIntegral (length sampleCounts)
      timeTotal = sum times
      timeCount = fromIntegral (length times)
      cappedCount = length (filter (> 2000) (fmap (\(_, s, _, _) -> s) results))
  printf "%s\n" (replicate 60 '-')
  printf "total over %d hovers : %8.1f ms\n" (length times) timeTotal
  printf "mean                 : %8.1f ms\n" (timeTotal / timeCount)
  printf "max                  : %8.1f ms\n" (maximum times)
  printf "median               : %8.1f ms\n" (median times)
  printf "max samples          : %8.0f  (limit 2000)\n" (maximum sampleCounts)
  printf "mean samples         : %8.1f\n" (sampleTotal / sampleCount)
  printf "hovers at the cap    : %8d of %d\n" cappedCount (length sampleCounts)

  -- REGRESSION ASSERTIONS. The planner must terminate by ARRIVING, not by
  -- exhausting plannerSafetyTickLimit. When the arrival test is unreachable the
  -- plan burns all 2000 ticks, which both strands the orbit autopilot and
  -- inflates every frame's geometry ~200x.
  printf "\n=== assertions ===\n"
  failures <- newIORef (0 :: Int)
  check failures "planner converges (no hover exhausts the 2000-tick safety cap)" (cappedCount == 0)
  check failures "converged plans stay small (max samples <= 200)" (maximum sampleCounts <= 200)
  check failures "per-hover planner cost stays under 5 ms" (maximum times < 5)
  count <- readIORef failures
  if count == 0
    then printf "\nALL PASS\n"
    else do
      printf "\n%d ASSERTION(S) FAILED\n" count
      exitFailure
 where
  check failures label ok =
    if ok
      then printf "  PASS  %s\n" label
      else do
        printf "  FAIL  %s\n" label
        modifyIORef' failures (+ 1)
  run snapshot hoverPoint = do
    (ms, samples, vertices, indices) <- timeOne snapshot hoverPoint
    printf "%-18s %9.2f %9d %9d %9d\n" (showPoint hoverPoint) ms samples vertices indices
    pure (ms, samples, vertices, indices)

expectConfig :: Either [ConfigDiagnostic] a -> IO a
expectConfig result =
  case result of
    Right value -> pure value
    Left diagnostics -> error ("config error: " <> show (length diagnostics) <> " diagnostics")

showPoint :: Point -> String
showPoint p = printf "(%.0f,%.0f)" (pointX p) (pointY p)

median :: [Double] -> Double
median values =
  case sorted of
    [] -> 0
    _ -> sorted !! (length sorted `div` 2)
 where
  sorted = sort values
