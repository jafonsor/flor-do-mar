-- | Phase 1/2 feedback loop for the "curved order weaves instead of turning
-- once" bug.
--
-- Reported symptom: one navigation order toward a distant waypoint should
-- produce one smooth curve. Instead the executed path oscillates left and
-- right (a sinusoidal weave), and gets worse as speed rises.
--
-- The harness drives the real planner/executor pair, 'issueNavigationOrder' +
-- repeated 'moveShip', against the shipped runtime config, and reports the
-- shape of the executed path:
--
--   * how many times the ship reverses its turn direction (sign of yaw rate),
--   * how far the path wanders to each side of the straight line to the
--     waypoint (weave amplitude),
--   * how long the order stays active (orbit instead of arrival).
--
-- Run with: cabal run diagnosis-trajectory-shape
module Main (main) where

import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import FlorDoMar.Combat
import System.Environment (getArgs)
import System.Exit (exitFailure)
import Text.Printf (printf)

main :: IO ()
main = do
  config <- expectConfig =<< loadRuntimeCombatConfig
  let
    tickSeconds = combatConfigTickSeconds config
    initialState = configuredDefaultEngagement config
    player = combatPlayer initialState
    movement = movementPhysicsForShip config player

  printf "runtime config: tick_seconds = %.3f\n" tickSeconds
  printf "player movement: battle_speed=%.1f max_speed=%.1f accel=%.1f turn_rate=%.1f ideal_turn_speed=%.1f yaw_accel=%.1f\n"
    (movementBattleSpeed movement) (movementMaxSpeed movement) (movementAcceleration movement)
    (movementTurnRate movement) (movementIdealTurnSpeed movement) (movementYawAcceleration movement)
  printf "  turning radius at battle speed: %.2f\n\n"
    (movementBattleSpeed movement / (movementTurnRate movement * pi / 180))

  -- Phase 4 trace mode: the interleaved dynamics of one weaving order.
  args <- getArgs
  case args of
    ["trace"] -> traceScenario config player {shipCurrentSpeed = 0, shipTargetSpeed = 4} (Point 60 25)
    _ -> pure ()

  failures <- newIORef (0 :: Int)

  -- Near-lateral order: a single clean 90-degree turn, then straight to the
  -- waypoint. Any reversal of turn direction here is a weave, not a curve.
  runScenario failures config "abeam  (60, 0) from rest"
    player {shipCurrentSpeed = 0, shipTargetSpeed = 4} (Point 60 0)

  -- Long forward order: should be a shallow single curve; the classic place a
  -- weaving controller shows up.
  runScenario failures config "ahead   (60, 25) from rest"
    player {shipCurrentSpeed = 0, shipTargetSpeed = 4} (Point 60 25)

  -- The user's screenshots show a full loop around the waypoint with the ship
  -- at cruise speed. Reproduce the tightened case too.
  runScenario failures config "abeam  (18, 0) at speed 4"
    player {shipCurrentSpeed = 4, shipTargetSpeed = 4} (Point 18 0)

  runScenario failures config "astern  (-40, 5) at speed 4"
    player {shipCurrentSpeed = 4, shipTargetSpeed = 4} (Point (-40) 5)

  count <- readIORef failures
  if count == 0
    then printf "\nALL PASS\n"
    else do
      printf "\n%d CHECK(S) FAILED\n" count
      exitFailure

runScenario :: IORef Int -> CombatConfig -> String -> Ship -> Point -> IO ()
runScenario failures config label ship waypoint = do
  let
    tickSeconds = combatConfigTickSeconds config
    movement = movementPhysicsForShip config ship
    ordered = issueNavigationOrder tickSeconds (const movement) waypoint ship
    states = take stateHorizon (iterate (moveShip tickSeconds movement) ordered)
    reachedIndex = length (takeWhile (maybe False (const True) . shipNavigationOrder) states)
    executed = take (min (reachedIndex + 1) stateHorizon) states

  printf "--- %s\n" label
  printf "    reachable waypoint      : %s\n" (showPoint (navigationReachableWaypoint (expectOrder ordered)))
  printf "    order cleared after     : %s\n" (describeArrival reachedIndex)

  case executed of
    [] -> pure ()
    _ -> do
      let
        positions = map shipPosition executed
        headings = map (headingDegrees . shipHeading) executed
        yawRates = map shipCurrentYawRate (settledTrace executed (navigationReachableWaypoint (expectOrder ordered)))
        start = head positions
        -- Measure wander against the line the settled ship actually runs,
        -- not the line from the start: a legitimate 180-degree order leaves a
        -- wide arc but still runs straight once it is pointed at its waypoint.
        settled = settledTrace executed (navigationReachableWaypoint (expectOrder ordered))
        settledStart = case settled of
          first : _ -> shipPosition first
          [] -> start
        deviations = map (signedOffset settledStart (navigationReachableWaypoint (expectOrder ordered))) (map shipPosition settled)
        reversals = turnReversals yawRates
        maxLeft = maximum (0 : deviations)
        maxRight = negate (minimum (0 : deviations))
        headingSwings = turnRunMagnitudes headings
        pathLength = sum (zipWith distanceBetween positions (drop 1 positions))
        directDistance = distanceBetween start (last positions)
      printf "    ticks executed          : %d\n" (length executed)
      printf "    turn-direction reversals: %d\n" reversals
      printf "    heading swing per turn  : %s\n" (showDegrees headingSwings)
      printf "    settled lean (left/right)  : %.2f / %.2f world units\n" maxLeft maxRight
      printf "    path length / direct    : %.3f (%.1f / %.1f)\n"
        (pathLength / max 0.001 directDistance) pathLength directDistance
      -- The weave is a limit cycle in the steering loop: once the ship is
      -- nearly pointed at its waypoint it should settle, not dither. The
      -- shipped relay law reverses turn direction once per overshoot, so this
      -- is the assertion that goes red on the reported bug.
      check failures (label <> ": steering settles instead of reversing once pointed at the waypoint")
        (reversals == 0)
      check failures (label <> ": settled path runs straight at the waypoint")
        (max maxLeft maxRight <= 2)
      check failures (label <> ": order clears instead of orbiting the waypoint")
        (reachedIndex < stateHorizon)
  printf "\n"

stateHorizon :: Int
stateHorizon = 600

-- | The part of a run after the approach turn, used for weave detection. A
-- 180-degree order legitimately turns one way for a long time; weaving is what
-- happens once the ship is nearly pointed at its waypoint and should be
-- settling onto a straight approach.
settledTrace :: [Ship] -> Point -> [Ship]
settledTrace executed waypoint =
  case dropWhile (not . nearlyPointed) executed of
    [] -> executed
    remaining -> remaining
  where
    nearlyPointed ship =
      abs (signedDegrees (bearingTo waypoint (shipPosition ship) - headingDegrees (shipHeading ship))) < 20

bearingTo :: Point -> Point -> Double
bearingTo target from =
  let
    radians = atan2 (pointY target - pointY from) (pointX target - pointX from)
    degrees = radians * 180 / pi
   in normalizeDegrees degrees

normalizeDegrees :: Double -> Double
normalizeDegrees degrees =
  let wrapped = degrees - 360 * fromIntegral (floor (degrees / 360) :: Int)
   in if wrapped < 0 then wrapped + 360 else wrapped

-- | Print the interleaved loop dynamics of one order: at each tick, where the
-- ship is, which way the waypoint lies, how big the heading error is, what yaw
-- rate the controller asks for, and what yaw rate the ship actually carries.
traceScenario :: CombatConfig -> Ship -> Point -> IO ()
traceScenario config ship waypoint = do
  let
    tickSeconds = combatConfigTickSeconds config
    movement = movementPhysicsForShip config ship
    ordered = issueNavigationOrder tickSeconds (const movement) waypoint ship
    target = navigationReachableWaypoint (expectOrder ordered)
    states = take 60 (iterate (moveShip tickSeconds movement) ordered)
  printf "tick      x       y   heading  bearing    error   yawReq   yawAct  speed\n"
  mapM_ (printRow target) (take 45 (zip [0 ..] states))
  printf "\n"
  where
    printRow target (index, state) =
      printf "%4d %7.2f %7.2f %8.2f %8.2f %8.2f %8.2f %8.2f %6.2f\n"
        (index :: Int)
        (pointX (shipPosition state))
        (pointY (shipPosition state))
        (headingDegrees (shipHeading state))
        (bearingTo target (shipPosition state))
        (signedDegrees (headingDegrees (shipTargetHeading state) - headingDegrees (shipHeading state)))
        (requestedYawRate (movementPhysicsForShip config ship) state)
        (shipCurrentYawRate state)
        (shipCurrentSpeed state)

signedDegrees :: Double -> Double
signedDegrees degrees
  | degrees > 180 = degrees - 360
  | degrees < -180 = degrees + 360
  | otherwise = degrees

-- Mirrors 'targetYawRate' in the domain so the trace can show the requested
-- value without exporting planner internals.
requestedYawRate :: MovementPhysics -> Ship -> Double
requestedYawRate movement state
  | abs delta <= 0.001 = 0
  | otherwise = signum delta * movementTurnRate movement * authority
  where
    delta = signedDegrees (headingDegrees (shipTargetHeading state) - headingDegrees (shipHeading state))
    authority = max 0 (min 1 (shipCurrentSpeed state / movementIdealTurnSpeed movement))

describeArrival :: Int -> String
describeArrival index
  | index >= stateHorizon = printf "NEVER (still active after %d ticks = %.0f s)" stateHorizon (fromIntegral stateHorizon * 0.8 :: Double)
  | otherwise = printf "%d ticks" index

-- | Number of times the signed turn direction flips while the order is active.
-- A single curve has 0 or 1; a weave has many.
turnReversals :: [Double] -> Int
turnReversals rates = length (filter id (zipWith flipped signs (drop 1 signs)))
  where
    signs = map signOf (filter ((> 1e-9) . abs) rates)
    signOf value = if value > 0 then 1 :: Int else -1
    flipped previous current = previous /= current

-- | Degrees turned in each run of same-direction turning. One run means one
-- committed turn; many small runs mean the ship is dithering.
turnRunMagnitudes :: [Double] -> [Double]
turnRunMagnitudes headings = reverse (map abs (finish (foldl step ([], 0) deltas)))
  where
    deltas = zipWith signedDelta headings (drop 1 headings)
    step (runs, current) delta
      | abs delta < 1e-9 = (runs, current)
      | current == 0 = (runs, delta)
      | signum current == signum delta = (runs, current + delta)
      | otherwise = (current : runs, delta)
    finish (runs, current)
      | abs current < 1e-9 = runs
      | otherwise = current : runs

signedDelta :: Double -> Double -> Double
signedDelta from to =
  let raw = to - from
   in if raw > 180 then raw - 360 else if raw < -180 then raw + 360 else raw

-- | Perpendicular offset of a point from the straight line start -> waypoint.
-- Positive is to the left of that line.
signedOffset :: Point -> Point -> Point -> Double
signedOffset start waypoint point =
  (dx * (pointY point - pointY start) - dy * (pointX point - pointX start)) / max 0.001 lineLength
  where
    dx = pointX waypoint - pointX start
    dy = pointY waypoint - pointY start
    lineLength = sqrt (dx * dx + dy * dy)

expectOrder :: Ship -> NavigationOrder
expectOrder ship =
  case shipNavigationOrder ship of
    Just order -> order
    Nothing -> error "expected the ship to carry a navigation order"

expectConfig :: Either [ConfigDiagnostic] CombatConfig -> IO CombatConfig
expectConfig result =
  case result of
    Right config -> pure config
    Left diagnostics -> do
      mapM_ (printf "config error: %s\n" . renderConfigDiagnostic) diagnostics
      exitFailure

showPoint :: Point -> String
showPoint point = printf "(%.2f, %.2f)" (pointX point) (pointY point)

distanceBetween :: Point -> Point -> Double
distanceBetween from to =
  sqrt (((pointX to - pointX from) ** 2) + ((pointY to - pointY from) ** 2))

showDegrees :: [Double] -> String
showDegrees values
  | null values = "-"
  | otherwise = unwords (map (printf "%.1f" ) values)

check :: IORef Int -> String -> Bool -> IO ()
check failures label ok =
  if ok
    then printf "    OK   %s\n" label
    else do
      printf "    FAIL %s\n" label
      modifyIORef' failures (+ 1)
