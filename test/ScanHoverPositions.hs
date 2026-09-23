-- | Position sweep: does any hover position produce a crash or invalid geometry?
--
-- The reported symptom is that the app freezes only for *certain mouse
-- positions*. That points at a position-dependent failure in the preview path
-- rather than load, so this sweeps the battle area and traps, for every position:
--
--   * a Haskell exception while forcing the render scene
--   * a non-finite (NaN / Infinity) coordinate in the generated geometry
--
-- Forcing matters: the geometry is lazy, so a NaN or a divide-by-zero only
-- surfaces when the vertices are actually demanded.
--
-- Run with: cabal run scan-hover-positions
{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Control.Exception (SomeException, evaluate, try)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (nub)
import FlorDoMar.Client.BattleScene
import FlorDoMar.Client.Render.Scene
import FlorDoMar.Client.WebGL.Geometry (Geometry3D (..))
import FlorDoMar.Client.WebGL.Math (Scalar, Vec3, vec3X, vec3Y, vec3Z)
import FlorDoMar.Combat
import System.Exit (exitFailure)
import Text.Printf (printf)

-- | Hover positions to test: every whole world unit across the battle area, plus
-- the exact ship position and its immediate neighbourhood, which are the
-- degenerate cases.
hoverPositions :: [Point]
hoverPositions =
  [Point x y | x <- [-40 .. 40], y <- [-20 .. 60]]
    <> [Point dx dy | dx <- [-2, -1, -0.5, 0, 0.5, 1, 2], dy <- [-2, -1, -0.5, 0, 0.5, 1, 2]]

-- | Fully force the geometry the renderer would consume, so laziness cannot hide
-- a NaN behind an unevaluated thunk.
forceGeometry :: Point -> CombatSnapshot -> CombatConfig -> IO (Either SomeException (Int, Int))
forceGeometry hoverPoint snapshot config = do
  result <- try $ do
    let
      scene = battleSceneFromSnapshotWithHover False (Just hoverPoint) snapshot
      primitives = renderScenePrimitives (battleRenderScene scene)
      vertices = concatMap (geometry3DVertices . renderPrimitiveGeometry) primitives
      indices = concatMap (geometry3DIndices . renderPrimitiveGeometry) primitives
      -- Demand every coordinate, so a NaN anywhere is a real allocation here.
      coords = concatMap (\v -> [vec3X v, vec3Y v, vec3Z v]) vertices
      bad = [c | c <- coords, not (isFinite c)]
    _ <- evaluate (length coords)
    _ <- evaluate (length indices)
    _ <- evaluate (length bad)
    if null bad
      then pure (length vertices, length indices)
      else errorWithoutStackTrace "non-finite coordinate produced"
  _ <- evaluate (configTickSecondsForcing config)
  pure result
 where
  configTickSecondsForcing c = combatConfigTickSeconds c

isFinite :: Scalar -> Bool
isFinite v = not (isNaN v) && not (isInfinite v)

main :: IO ()
main = do
  config <- either (error . show . length) pure =<< loadRuntimeCombatConfig
  let
    tickSeconds = combatConfigTickSeconds config
    movement = movementPhysicsForShip config
    initial = configuredDefaultEngagement config
    -- A spread of states: the initial duel, mid-manoeuvre states, and a state
    -- carrying a committed player order. The geometry only becomes interesting
    -- once ships are moving and turning.
    commanded =
      tickCombatWith tickSeconds movement
        [IssueNavigationOrder PlayerShip (Point 20 30), SetHeading PlayerShip (Heading 45), SetTargetSpeed PlayerShip 7]
        initial
    states = take 40 (iterate (tickCombatWith tickSeconds movement []) initial)
      <> take 40 (iterate (tickCombatWith tickSeconds movement []) commanded)
    snapshots =
      [ combatSnapshotFromStateWithPlanning
          tickSeconds
          movement
          (const legacyBroadsideTuning)
          caravelaDuelScenario
          st
        | st <- states
      ]

  printf "hover positions per state : %d\n" (length hoverPositions)
  printf "simulation states         : %d\n" (length snapshots)
  printf "total checks              : %d\n" (length hoverPositions * length snapshots)
  printf "tick_seconds              : %.3f\n\n" tickSeconds

  failures <- newIORef ([] :: [(Point, Int, String)])
  checked <- newIORef (0 :: Int)

  mapM_
    ( \snapshot -> do
        let stateTick = combatSnapshotTick snapshot
        mapM_
          ( \point -> do
              outcome <- forceGeometry point snapshot config
              modifyIORef' checked (+ 1)
              case outcome of
                Left exception -> do
                  let msg = takeWhile (/= '\n') (show exception)
                  modifyIORef' failures ((point, stateTick, "EXCEPTION: " <> msg) :)
                  printf "  CRASH tick=%d at %s -> %s\n" stateTick (showPoint point) msg
                Right _ -> pure ()
          )
          hoverPositions
    )
    snapshots

  total <- readIORef checked
  bad <- readIORef failures
  printf "\nscanned %d combinations, %d failed\n" total (length bad)

  if null bad
    then do
      printf "\nALL PASS - no hover position crashed or produced non-finite geometry\n"
    else do
      printf "\ndistinct failure modes:\n"
      mapM_ (printf "  %s\n") (nub (fmap (\(_,_,m) -> m) bad))
      printf "\nfirst 10 failures:\n"
      mapM_ (\(p, t, m) -> printf "  tick=%-4d %s  %s\n" t (showPoint p) m) (take 10 bad)
      exitFailure

showPoint :: Point -> String
showPoint p = printf "(%.1f, %.1f)" (pointX p) (pointY p)
