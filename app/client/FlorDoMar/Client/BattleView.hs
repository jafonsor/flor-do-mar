{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RecursiveDo #-}

module FlorDoMar.Client.BattleView
  ( battleView
  , initializeBattleRenderer
  , renderBattleScene
  )
where

import Control.Monad (void)
import Control.Monad.Fix (MonadFix)
import Control.Monad.IO.Class (liftIO)
import Data.Map qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import FlorDoMar.Client.BattleInput
import FlorDoMar.Client.BattleScene
import FlorDoMar.Client.GunPanel
import FlorDoMar.Client.WebGL.Renderer qualified as WebGL
import FlorDoMar.Combat
import Language.Javascript.JSaddle
import Language.Javascript.JSaddle.Value qualified as JS
import Reflex.Dom.Core

battleView ::
  ( DomBuilder t m
  , ToJSVal (RawElement (DomBuilderSpace m))
  , MonadJSM (Performable m)
  , MonadHold t m
  , MonadFix m
  , PerformEvent t m
  , PostBuild t m
  , TriggerEvent t m
  ) =>
  Dynamic t CombatSnapshot ->
  Dynamic t Bool ->
  Dynamic t Bool ->
  m (Event t CombatCommand)
battleView snapshotDynamic setupOverlayOpenDynamic debugOverlaysEnabledDynamic = do
  (pointerIntentEvent, firePointerIntent) <- newTriggerEvent
  (canvasElement, battleSceneDynamic, commandEvents) <-
    elClass "div" "battle-view" $ mdo
      (canvasElement, ()) <- elAttr' "canvas" canvasAttributes blank
      let
        setupOpened = () <$ ffilter id (updated setupOverlayOpenDynamic)
        clearHoverWhenSetupOpens = ClearNavigationHover <$ setupOpened
        hoverInputEvents =
          leftmost
            [ fmapMaybe hoverIntentFromPointerIntent pointerIntentEvent
            , clearHoverWhenSetupOpens
            ]
        pointerSamples = fmapMaybe pointerSampleFromIntent pointerIntentEvent
        pointerMoveSamples = fmapMaybe pointerMoveSampleFromIntent pointerIntentEvent
        pointerDownSamples = fmapMaybe pointerDownSampleFromIntent pointerIntentEvent
        pointerUpEvents = () <$ ffilter isPointerUpIntent pointerIntentEvent
        pointerLeaveEvents = () <$ ffilter isPointerLeaveIntent pointerIntentEvent
      hoverWaypointDynamic <- foldDyn (flip applyNavigationHoverIntent) Nothing hoverInputEvents
      -- The reticle's radius arrives with every pointer sample, so the last one
      -- seen is the radius both rings are drawn at — the same number the hit test
      -- that set the hover ran with.
      reticleRadiusDynamic <-
        holdDyn
          (reticleStateRadius restingReticleState)
          (pointerSampleReticleRadius <$> pointerSamples)
      -- The pointer's last position, cleared when it leaves the canvas or the
      -- setup overlay opens. The hover is derived from this and the snapshot
      -- together rather than folded from pointer events, so a ship that moves out
      -- from under a pointer holding still loses its ring on the tick that moves
      -- it: the hover is always the hit test a click at that position would run.
      hoverSampleDynamic <-
        holdDyn
          Nothing
          ( leftmost
              [ Just <$> pointerSamples
              , Nothing <$ pointerLeaveEvents
              , Nothing <$ setupOpened
              ]
          )
      let hoveredShipDynamic = zipDynWith (hoveredShipAt PlayerShip) hoverSampleDynamic snapshotDynamic
      let
        navigationStartEvents =
          attachWithMaybe
            navigationGestureStart
            (current (zipDyn snapshotDynamic setupOverlayOpenDynamic))
            pointerDownSamples
      navigationGestureDynamic <-
        foldDyn
          const
          NoNavigationGesture
          ( leftmost
              [ navigationStartEvents
              , attachWithMaybe
                  (\gesture moved ->
                      case gesture of
                        NoNavigationGesture -> Nothing
                        NavigationGesture _ _ -> Just (updateNavigationGesture (pointerSamplePoint moved) gesture)
                  )
                  (current navigationGestureDynamic)
                  pointerMoveSamples
              , NoNavigationGesture <$ pointerUpEvents
              , NoNavigationGesture <$ setupOpened
              ]
          )
      let
        releaseIntents =
          attachWithMaybe
            (\(gesture, (snapshot, setupIsOpen)) () ->
                navigationReleaseIntent PlayerShip (combatSnapshotStatus snapshot) setupIsOpen gesture
            )
            (current (zipDyn navigationGestureDynamic (zipDyn snapshotDynamic setupOverlayOpenDynamic)))
            pointerUpEvents
        releaseWaypoints = fmapMaybe releaseWaypoint releaseIntents
        releaseSpeedEvents = fmapMaybe releaseSpeed releaseIntents
        releaseLockEvents = fmapMaybe releaseLockTarget releaseIntents
        reticleDynamic =
          ReticleState
            <$> reticleRadiusDynamic
            <*> hoveredShipDynamic
        sceneDynamic =
          ( \snapshot hoverWaypoint navigationGesture setupIsOpen debugOverlaysEnabled reticle ->
              battleSceneFromSnapshotWithReticle reticle setupIsOpen debugOverlaysEnabled hoverWaypoint navigationGesture snapshot
          )
            <$> snapshotDynamic
            <*> hoverWaypointDynamic
            <*> navigationGestureDynamic
            <*> setupOverlayOpenDynamic
            <*> debugOverlaysEnabledDynamic
            <*> reticleDynamic
      panelCommands <- gunPanel snapshotDynamic hoveredShipDynamic
      pure
        ( canvasElement
        , sceneDynamic
        , leftmost
            [ IssueNavigationOrder PlayerShip <$> releaseWaypoints
            , SetNavigationPostWaypointSpeed PlayerShip <$> releaseSpeedEvents
            , (\target -> Lock PlayerShip target) <$> releaseLockEvents
            , panelCommands
            ]
        )
  postBuild <- getPostBuild
  initializedRenderer <-
    performEvent $
      fmap
        ( \scene ->
            liftJSM $ do
              canvas <- toJSVal (_element_raw canvasElement)
              listenForNavigationInput canvas firePointerIntent
              rendererMaybe <- initializeBattleRenderer canvas
              case rendererMaybe of
                Nothing -> pure ()
                Just renderer -> renderBattleScene renderer scene
              pure rendererMaybe
        )
        (current battleSceneDynamic <@ postBuild)
  rendererDynamic <- holdDyn Nothing initializedRenderer
  performEvent_ $
    attachWithMaybe
      ( \rendererMaybe scene ->
          fmap
            ( \renderer ->
                liftJSM $
                  renderBattleScene renderer scene
            )
            rendererMaybe
      )
      (current rendererDynamic)
      (updated battleSceneDynamic)
  pure commandEvents

-- | The screen-anchored gun panel: the fire-at-will toggle, the reload circle
-- and the lock control for whichever ship is hovered or already locked.
--
-- The panel is an overlay on the canvas and must not swallow it. Its container
-- takes no pointer events; only its controls ask for them back. A full-canvas
-- overlay that captured events would break navigation, which needs the canvas to
-- see mousedown, mousemove and mouseup.
--
-- The panel deliberately carries no ship labels: the client's DOM text is the
-- diagnosis harnesses' ground truth (see docs/agents/testing-and-tooling.md),
-- and they split the body text on the words Player and Enemy.
gunPanel ::
  ( DomBuilder t m
  , MonadHold t m
  , MonadFix m
  , PostBuild t m
  ) =>
  Dynamic t CombatSnapshot ->
  Dynamic t (Maybe ShipId) ->
  m (Event t CombatCommand)
gunPanel snapshotDynamic hoveredShipDynamic =
  elClass "div" "gun-panel" $ mdo
    (toggleElement, ()) <-
      elDynAttr' "button" (fireToggleAttributes <$> panelStateDynamic) (text "Fire at will")
    reloadCircle panelStateDynamic
    (lockElement, ()) <-
      elDynAttr' "button" (lockControlAttributes <$> panelStateDynamic) (dynText (lockControlLabel <$> panelStateDynamic))
    fireRequestDynamic <-
      foldDyn
        applyFireAtWillRequestUpdate
        Nothing
        ( leftmost
            [ FireAtWillRequested <$> requestEvents
            , FireAtWillSnapshot <$> updated snapshotDynamic
            ]
        )
    let
      panelStateDynamic =
        gunPanelState <$> snapshotDynamic <*> fireRequestDynamic <*> hoveredShipDynamic
      -- Armed is clickable only with the guns loaded, and disengaging is always
      -- clickable, so a request the domain would refuse is never sent — and the
      -- request itself is what the panel shows until a tick decides it.
      requestEvents =
        attachWithMaybe
          ( \state () ->
              if gunPanelToggleEnabled state
                then Just (FireAtWillRequest (not (gunPanelArmed state)) (gunPanelTick state))
                else Nothing
          )
          (current panelStateDynamic)
          (domEvent Click toggleElement)
      lockEvents =
        attachWithMaybe
          (\state () -> Lock PlayerShip <$> gunPanelLockTarget state)
          (current panelStateDynamic)
          (domEvent Click lockElement)
    pure
      ( leftmost
          [ (\request -> SetFireAtWill PlayerShip (fireAtWillRequestArmed request)) <$> requestEvents
          , lockEvents
          ]
      )

-- | The reload circle: a track and a fill whose sweep is reload progress.
--
-- The fill is a stroke-dashoffset on a circle whose circumference is 100, so the
-- attribute the snapshot changes *is* the fraction of the reload that is done: it
-- reaches full when the guns are loaded. The smooth part is the DOM's: a
-- transition of one tick makes the browser interpolate between the snapshots the
-- simulation publishes, so no frame loop and no animation clock are introduced.
-- Disengaging mid-reload changes nothing here — the guns reload whether or not
-- they are permitted to fire, so the sweep runs on to full.
reloadCircle :: (DomBuilder t m, PostBuild t m) => Dynamic t GunPanelState -> m ()
reloadCircle panelStateDynamic =
  elDynAttrNS (Just svgNamespace) "svg" (reloadCircleAttributes <$> panelStateDynamic) $ do
    elDynAttrNS (Just svgNamespace) "circle" (pure reloadTrackAttributes) blank
    elDynAttrNS (Just svgNamespace) "circle" (reloadFillAttributes <$> panelStateDynamic) blank

-- | SVG elements and their children have to be created in the SVG namespace.
-- 'elDynAttr' would build an HTML element that merely happens to be named
-- @svg@ or @circle@, which draws nothing — and would lower-case @viewBox@.
svgNamespace :: Text
svgNamespace = "http://www.w3.org/2000/svg"

-- | Register the pointer listeners.
--
-- The browser does the coordinate conversion and hands this side plain numbers.
-- That is deliberate: jsaddle-warp transports a callback synchronously (an
-- @XMLHttpRequest@ opened with @async=false@), so every property read costs a
-- round trip that blocks the browser main thread. Reading @left@, @top@,
-- @width@, @height@, @clientX@, @clientY@ and @button@ one at a time cost seven
-- blocking round trips per pointer event; at 60-120 events per second that
-- alone saturated the main thread and stalled the page. Passing the numbers as
-- callback arguments costs one round trip per event.
listenForNavigationInput :: JSVal -> (NavigationPointerIntent -> IO ()) -> JSM ()
listenForNavigationInput canvas firePointerIntent = do
  makePositionListener <- eval positionListenerSource
  makePrimaryButtonListener <- eval primaryButtonListenerSource
  window <- jsg ("window" :: Text)
  moveListener <- positionListener canvas makePositionListener RawPointerMoved firePointerIntent
  addEventListener canvas "mousemove" moveListener
  downListener <- positionListener canvas makePositionListener RawPrimaryPointerDown firePointerIntent
  addEventListener canvas "mousedown" downListener
  upListener <- primaryButtonListener window makePrimaryButtonListener firePointerIntent
  addEventListener window "mouseup" upListener
  leaveListener <- function $ \_ _ _ ->
    liftIO (firePointerIntent (navigationPointerIntentFromRawPointer battleCamera RawPointerLeftBattleView))
  leaveListenerValue <- toJSVal leaveListener
  addEventListener canvas "mouseleave" leaveListenerValue

-- | @callback(clientX - rect.left, clientY - rect.top, rect.width, rect.height)@
positionListenerSource :: Text
positionListenerSource =
  "(function (target, callback) {\n\
  \  return function (event) {\n\
  \    var rect = target.getBoundingClientRect();\n\
  \    callback(event.clientX - rect.left, event.clientY - rect.top, rect.width, rect.height);\n\
  \  };\n\
  \})"

-- | @callback()@ for the primary button only, so the button test is not a round trip.
primaryButtonListenerSource :: Text
primaryButtonListenerSource =
  "(function (target, callback) {\n\
  \  return function (event) {\n\
  \    if (event.button === 0) { callback(); }\n\
  \  };\n\
  \})"

positionListener ::
  JSVal ->
  JSVal ->
  (ScreenPoint -> ScreenSize -> RawPointerEvent) ->
  (NavigationPointerIntent -> IO ()) ->
  JSM JSVal
positionListener target makeListener rawEvent firePointerIntent = do
  callback <- function $ \_ _ arguments ->
    case arguments of
      [x, y, width, height] -> do
        screenX <- JS.valToNumber x
        screenY <- JS.valToNumber y
        widthValue <- JS.valToNumber width
        heightValue <- JS.valToNumber height
        liftIO $
          firePointerIntent $
            navigationPointerIntentFromRawPointer battleCamera $
              rawEvent (ScreenPoint screenX screenY) (ScreenSize widthValue heightValue)
      _ -> pure ()
  callbackValue <- toJSVal callback
  call makeListener target [target, callbackValue]

primaryButtonListener :: JSVal -> JSVal -> (NavigationPointerIntent -> IO ()) -> JSM JSVal
primaryButtonListener target makeListener firePointerIntent = do
  callback <- function $ \_ _ _ ->
    liftIO (firePointerIntent (navigationPointerIntentFromRawPointer battleCamera RawPrimaryPointerUp))
  callbackValue <- toJSVal callback
  call makeListener target [target, callbackValue]

addEventListener :: JSVal -> Text -> JSVal -> JSM ()
addEventListener target name listener =
  void (callMethod "addEventListener" target (name, listener))

navigationGestureStart :: (CombatSnapshot, Bool) -> PointerSample -> Maybe NavigationGesture
navigationGestureStart (snapshot, setupIsOpen) pressed
  | not (navigationInputAllowed setupIsOpen (combatSnapshotStatus snapshot)) = Nothing
  | otherwise = do
      plan <- planNavigationForSnapshot snapshot PlayerShip (pointerSamplePoint pressed)
      player <- findSnapshotShip PlayerShip snapshot
      pure $
        beginNavigationGestureAt
          (pointerSamplePoint pressed)
          (navigationPlanReachableWaypoint plan)
          (shipSnapshotMaxSpeed player)
          (hullAtReticle pressed (combatSnapshotShips snapshot))

hoverIntentFromPointerIntent :: NavigationPointerIntent -> Maybe NavigationHoverIntent
hoverIntentFromPointerIntent intent =
  case intent of
    NavigationPointerMoved moved -> Just (PreviewNavigation (pointerSamplePoint moved))
    NavigationPointerLeftBattleView -> Just ClearNavigationHover
    _ -> Nothing

pointerSampleFromIntent :: NavigationPointerIntent -> Maybe PointerSample
pointerSampleFromIntent intent =
  case intent of
    NavigationPointerMoved moved -> Just moved
    NavigationPointerPrimaryDown pressed -> Just pressed
    _ -> Nothing

pointerMoveSampleFromIntent :: NavigationPointerIntent -> Maybe PointerSample
pointerMoveSampleFromIntent intent =
  case intent of
    NavigationPointerMoved moved -> Just moved
    _ -> Nothing

pointerDownSampleFromIntent :: NavigationPointerIntent -> Maybe PointerSample
pointerDownSampleFromIntent intent =
  case intent of
    NavigationPointerPrimaryDown pressed -> Just pressed
    _ -> Nothing

isPointerUpIntent :: NavigationPointerIntent -> Bool
isPointerUpIntent intent =
  case intent of
    NavigationPointerPrimaryUp -> True
    _ -> False

isPointerLeaveIntent :: NavigationPointerIntent -> Bool
isPointerLeaveIntent intent =
  case intent of
    NavigationPointerLeftBattleView -> True
    _ -> False

releaseWaypoint :: NavigationReleaseIntent -> Maybe Point
releaseWaypoint intent =
  case intent of
    NavigateOnRelease waypoint _ -> Just waypoint
    LockOnRelease _ -> Nothing

releaseSpeed :: NavigationReleaseIntent -> Maybe Double
releaseSpeed intent =
  case intent of
    NavigateOnRelease _ speed -> speed
    LockOnRelease _ -> Nothing

releaseLockTarget :: NavigationReleaseIntent -> Maybe ShipId
releaseLockTarget intent =
  case intent of
    LockOnRelease target -> Just target
    NavigateOnRelease {} -> Nothing

fireToggleAttributes :: GunPanelState -> Map.Map Text Text
fireToggleAttributes state =
  Map.fromList
    ( [ ("type", "button")
      , ("class", "gun-control fire-toggle " <> armedClass state)
      , ("aria-pressed", if gunPanelArmed state then "true" else "false")
      ]
        <> [("disabled", "disabled") | not (gunPanelToggleEnabled state)]
    )

lockControlAttributes :: GunPanelState -> Map.Map Text Text
lockControlAttributes state =
  Map.fromList
    [ ("type", "button")
    , ("class", "gun-control lock-control" <> if gunPanelLockTarget state == Nothing then " inactive" else "")
    ]

lockControlLabel :: GunPanelState -> Text
lockControlLabel state =
  if gunPanelLockReleases state then "Unlock" else "Lock"

reloadCircleAttributes :: GunPanelState -> Map.Map Text Text
reloadCircleAttributes state =
  Map.fromList
    [ ("class", "reload-circle " <> armedClass state)
    , ("viewBox", reloadCircleViewBox)
    , ("width", "34")
    , ("height", "34")
    , ("role", "img")
    , ( "aria-label"
      , "Reload "
          <> showValue (gunPanelReloadTicksRemaining state)
          <> " of "
          <> showValue (gunPanelReloadTicksTotal state)
      )
    ]

reloadTrackAttributes :: Map.Map Text Text
reloadTrackAttributes =
  Map.fromList
    [ ("class", "reload-track")
    , ("cx", reloadCircleCenter)
    , ("cy", reloadCircleCenter)
    , ("r", reloadCircleRadius)
    ]

reloadFillAttributes :: GunPanelState -> Map.Map Text Text
reloadFillAttributes state =
  Map.fromList
    [ ("class", "reload-fill")
    , ("cx", reloadCircleCenter)
    , ("cy", reloadCircleCenter)
    , ("r", reloadCircleRadius)
    , ("transform", "rotate(-90 18 18)")
    , ("style", reloadFillStyle state)
    ]

reloadFillStyle :: GunPanelState -> Text
reloadFillStyle state =
  "stroke-dasharray: "
    <> reloadCircleCircumference
    <> "; stroke-dashoffset: "
    <> hundredths (100 * (1 - gunPanelReloadProgress state))
    <> "; transition: stroke-dashoffset "
    <> showValue (gunPanelReloadSweepSeconds state)
    <> "s linear;"

armedClass :: GunPanelState -> Text
armedClass state =
  if gunPanelArmed state then "armed" else "disengaged"

reloadCircleViewBox :: Text
reloadCircleViewBox = "0 0 36 36"

-- | The circle's radius is chosen so the circumference is exactly 100, which is
-- what lets the dash offset be the reload fraction.
reloadCircleRadius :: Text
reloadCircleRadius = "15.9155"

reloadCircleCircumference :: Text
reloadCircleCircumference = "100"

reloadCircleCenter :: Text
reloadCircleCenter = "18"

hundredths :: Double -> Text
hundredths number =
  Text.pack (show (fromIntegral (round (number * 100) :: Int) / 100 :: Double))

showValue :: (Show value) => value -> Text
showValue = Text.pack . show

canvasAttributes :: Map.Map Text Text
canvasAttributes =
  Map.fromList
    [ ("id", "battle-view")
    , ("width", wholeNumberText (screenSizeWidth battleCanvasSize))
    , ("height", wholeNumberText (screenSizeHeight battleCanvasSize))
    , ( "style"
      , "width: 100%; max-width: 760px; aspect-ratio: 16 / 9; border: 1px solid #203447; background: #061019; display: block;"
      )
    ]

wholeNumberText :: Double -> Text
wholeNumberText = Text.pack . show . (round :: Double -> Int)

initializeBattleRenderer :: JSVal -> JSM (Maybe WebGL.Renderer)
initializeBattleRenderer canvas = do
  canvasMaybe <- JS.maybeNullOrUndefined canvas
  case canvasMaybe of
    Nothing -> do
      logBrowserError "Could not initialize battle renderer: canvas element is missing."
      pure Nothing
    Just canvasValue -> do
      gl <- callMethod "getContext" canvasValue ["webgl" :: Text]
      glMaybe <- JS.maybeNullOrUndefined gl
      case glMaybe of
        Nothing -> do
          logBrowserError "Could not initialize battle renderer: WebGL context is unavailable."
          pure Nothing
        Just glValue -> WebGL.initRenderer glValue

renderBattleScene :: WebGL.Renderer -> BattleScene -> JSM ()
renderBattleScene renderer =
  WebGL.renderScene renderer . battleRenderScene

callMethod :: (MakeArgs args) => Text -> JSVal -> args -> JSM JSVal
callMethod method target args = do
  functionValue <- target ! method
  call functionValue target args

logBrowserError :: Text -> JSM ()
logBrowserError message = do
  console <- jsg ("console" :: Text)
  void $ callMethod "error" console [message]
