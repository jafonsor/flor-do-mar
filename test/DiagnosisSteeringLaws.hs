-- | Throwaway evidence harness for /diagnosing-bugs/: which part of the steering
-- loop drove the navigation weave?
--
-- Re-implements the shipped integration loop (same equations as 'moveShip') and
-- swaps only the steering law, so the pre-fix law and the shipped fix can be
-- compared side by side. The relay rows are expected to fail their
-- one-turn-direction checks: that is the bug being demonstrated, and it is why
-- this harness exits non-zero. It is evidence, not a gate — the gate is
-- 'testNavigationSteeringDoesNotWeave' in test/CombatTest.hs.
--
--   relay  : the pre-fix law. Aim at the waypoint, command full turn authority
--            in the sign of the heading error, deadband 0.001 deg.
--   prop-K : the fix. Command yaw rate proportional to the heading error,
--            saturated at full authority. K is 1 \/ time constant, in 1\/s;
--            the shipped value is 1 \/ navigationHeadingCorrectionSeconds.
--
-- Run with: cabal run diagnosis-steering-experiment
module Main (main) where

import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import FlorDoMar.Combat
import System.Exit (exitFailure)
import Text.Printf (printf)

data Steering = Steering
  { steeringName :: String
  , steeringLaw :: SteeringContext -> Double
  }

data SteeringContext = SteeringContext
  { contextMovement :: MovementPhysics
  , contextShip :: Ship
  , contextWaypoint :: Point
  }

main :: IO ()
main = do
  config <- expectConfig =<< loadRuntimeCombatConfig
  let
    tickSeconds = combatConfigTickSeconds config
    initialState = configuredDefaultEngagement config
    baseShip = combatPlayer initialState
    movement = movementPhysicsForShip config baseShip
    starts = [("rest  ", 0), ("speed2", 2), ("speed4", 4)]
    waypoints =
      [ ("ahead(60,25)", Point 60 25)
      , ("abeam(60,0) ", Point 60 0)
      , ("astern(-40,5)", Point (-40) 5)
      ]

  printf "tick_seconds = %.3f  turn_rate = %.1f  yaw_accel = %.1f  ideal_turn_speed = %.1f\n"
    tickSeconds (movementTurnRate movement) (movementYawAcceleration movement) (movementIdealTurnSpeed movement)
  printf "columns: revs = turn-direction sign flips, lean = max lateral offset from the\n"
  printf "         direct line, path/dir = path length over direct distance\n\n"

  failures <- newIORef (0 :: Int)
  printf "%-20s %-7s %-13s %5s %7s %9s %6s\n" "law" "start" "order" "revs" "lean" "path/dir" "ticks"
  mapM_
    (reportAll failures tickSeconds movement baseShip starts waypoints)
    [ Steering "relay (shipped)" relayLaw
    , Steering "prop K=0.25" (propLaw 0.25)
    , Steering "prop K=0.5" (propLaw 0.5)
    , Steering "prop K=0.75" (propLaw 0.75)
    , Steering "prop K=1" (propLaw 1)
    , Steering "prop K=1.5" (propLaw 1.5)
    , Steering "prop K=2" (propLaw 2)
    ]

  count <- readIORef failures
  if count == 0
    then printf "\nALL PASS\n"
    else do
      printf "\n%d CHECK(S) FAILED\n" count
      exitFailure

reportAll :: IORef Int -> Double -> MovementPhysics -> Ship -> [(String, Double)] -> [(String, Point)] -> Steering -> IO ()
reportAll failures tickSeconds movement baseShip starts waypoints steering =
  mapM_ (reportOne failures tickSeconds movement baseShip steering)
    [ (startName, speed, orderName, waypoint)
    | (startName, speed) <- starts
    , (orderName, waypoint) <- waypoints
    ]

reportOne :: IORef Int -> Double -> MovementPhysics -> Ship -> Steering -> (String, Double, String, Point) -> IO ()
reportOne failures tickSeconds movement baseShip steering (startName, speed, orderName, waypoint) = do
  let
    start =
      baseShip
        { shipCurrentSpeed = speed
        , shipTargetSpeed = 4
        , shipHeading = Heading 0
        , shipTargetHeading = Heading 0
        , shipCurrentYawRate = 0
        }
    trace = simulate tickSeconds movement (steeringLaw steering) start waypoint
    positions = map shipPosition trace
    reversals = turnReversals (map shipCurrentYawRate (settledTrace trace waypoint))
    lean = maximum (0 : map (abs . signedOffset (Point 0 0) waypoint) positions)
    traversed = sum (zipWith distanceBetween positions (drop 1 positions))
    direct = max 0.001 (distanceBetween (Point 0 0) (last positions))
    label = steeringName steering
  printf "%-20s %-7s %-13s %5d %7.2f %9.3f %6d\n"
    label startName orderName reversals lean (traversed / direct) (length trace)
  check failures (label <> " " <> startName <> " " <> orderName <> ": turns one way") (reversals <= 1)

-- | The part of the run after the approach turn, used for weave detection. A
-- 180-degree order legitimately turns one way for a long time; weaving is what
-- happens once the ship is nearly pointed at the waypoint and should be
-- settling onto a straight approach.
settledTrace :: [Ship] -> Point -> [Ship]
settledTrace trace waypoint =
  case dropWhile (not . nearlyPointed) trace of
    [] -> trace
    remaining -> remaining
  where
    nearlyPointed ship =
      abs (signedDegrees (bearingTo waypoint (shipPosition ship) - headingDegrees (shipHeading ship))) < 20

-- | Integrate until the ship is within its arrival tolerance of the waypoint,
-- mirroring 'moveShip' plus the shipped arrival rule.
simulate :: Double -> MovementPhysics -> (SteeringContext -> Double) -> Ship -> Point -> [Ship]
simulate tickSeconds movement law start waypoint = take horizon (go start)
  where
    horizon = 400
    go ship
      | distanceBetween (shipPosition ship) waypoint <= tolerance ship = [ship]
      | otherwise =
          let
            desired = law (SteeringContext movement ship waypoint)
            nextSpeed = approach (shipCurrentSpeed ship) (shipTargetSpeed ship) speedStep
            nextYaw = approach (shipCurrentYawRate ship) desired yawStep
            nextHeading = Heading (normalizeDegrees (headingDegrees (shipHeading ship) + nextYaw * tickSeconds))
            nextPosition = advancePosition (shipPosition ship) nextHeading (nextSpeed * tickSeconds)
           in
            ship : go ship {shipPosition = nextPosition, shipHeading = nextHeading, shipCurrentSpeed = nextSpeed, shipCurrentYawRate = nextYaw}
    speedStep = tickSeconds * if shipTargetSpeed start >= shipCurrentSpeed start then movementAcceleration movement else movementDeceleration movement
    yawStep = tickSeconds * movementYawAcceleration movement
    -- Mirrors 'arrivalTolerance' in the domain: turning radius at battle speed
    -- scaled by the sine of the still-required heading change.
    tolerance ship =
      max navigationArrivalRadius (turnRadius * sin (min (pi / 2) (abs (signedDegrees (bearingTo waypoint (shipPosition ship) - headingDegrees (shipHeading ship))))))
    turnRadius = movementBattleSpeed movement / (movementTurnRate movement * pi / 180)

advancePosition :: Point -> Heading -> Double -> Point
advancePosition point heading distanceMoved =
  Point
    { pointX = pointX point + distanceMoved * cos radians
    , pointY = pointY point + distanceMoved * sin radians
    }
  where
    radians = headingDegrees heading * pi / 180

-- | The shipped law: aim at the waypoint, command full authority in the sign of
-- the heading error.
relayLaw :: SteeringContext -> Double
relayLaw context =
  if abs delta <= 0.001
    then 0
    else signum delta * authority context
  where
    delta = signedDegrees (bearingTo (contextWaypoint context) (shipPosition ship) - headingDegrees (shipHeading ship))
    ship = contextShip context

-- | Proportional law: the yaw-rate command tapers as the ship closes on the
-- bearing and saturates at full authority.
propLaw :: Double -> SteeringContext -> Double
propLaw gain context = clampAuthority context (gain * bearingError context (contextWaypoint context))

bearingError :: SteeringContext -> Point -> Double
bearingError context target =
  signedDegrees (bearingTo target (shipPosition (contextShip context)) - headingDegrees (shipHeading (contextShip context)))

authority :: SteeringContext -> Double
authority context =
  movementTurnRate movement * max 0 (min 1 (shipCurrentSpeed ship / movementIdealTurnSpeed movement))
  where
    movement = contextMovement context
    ship = contextShip context

clampAuthority :: SteeringContext -> Double -> Double
clampAuthority context command = max (-limit) (min limit command)
  where
    limit = authority context

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

signedDegrees :: Double -> Double
signedDegrees degrees
  | degrees > 180 = degrees - 360
  | degrees < -180 = degrees + 360
  | otherwise = degrees

approach :: Double -> Double -> Double -> Double
approach current target maximumChange
  | current < target = min target (current + maximumChange)
  | otherwise = max target (current - maximumChange)

turnReversals :: [Double] -> Int
turnReversals rates = length (filter id (zipWith flipped signs (drop 1 signs)))
  where
    signs = map (\value -> if value > 0 then 1 :: Int else -1) (filter ((> 1e-9) . abs) rates)
    flipped previous current = previous /= current

signedOffset :: Point -> Point -> Point -> Double
signedOffset start waypoint point =
  (dx * (pointY point - pointY start) - dy * (pointX point - pointX start)) / max 0.001 lineLength
  where
    dx = pointX waypoint - pointX start
    dy = pointY waypoint - pointY start
    lineLength = sqrt (dx * dx + dy * dy)

distanceBetween :: Point -> Point -> Double
distanceBetween from to =
  sqrt (((pointX to - pointX from) ** 2) + ((pointY to - pointY from) ** 2))

expectConfig :: Either [ConfigDiagnostic] CombatConfig -> IO CombatConfig
expectConfig result =
  case result of
    Right config -> pure config
    Left diagnostics -> do
      mapM_ (printf "config error: %s\n" . renderConfigDiagnostic) diagnostics
      exitFailure

check :: IORef Int -> String -> Bool -> IO ()
check failures label ok =
  if ok
    then pure ()
    else do
      printf "    FAIL %s\n" label
      modifyIORef' failures (+ 1)
