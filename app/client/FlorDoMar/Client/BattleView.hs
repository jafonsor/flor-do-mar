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
import FlorDoMar.Client.BattleInput
import FlorDoMar.Client.BattleScene
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
battleView snapshotDynamic setupOverlayOpenDynamic debugOverlaysEnabledDynamic = mdo
  (canvasElement, ()) <- elAttr' "canvas" canvasAttributes blank
  (pointerIntentEvent, firePointerIntent) <- newTriggerEvent
  let
    clearHoverWhenSetupOpens =
      ClearNavigationHover
        <$ ffilter id (updated setupOverlayOpenDynamic)
    hoverInputEvents =
      leftmost
        [ fmapMaybe hoverIntentFromPointerIntent pointerIntentEvent
        , clearHoverWhenSetupOpens
        ]
    pointerMoveEvents = fmapMaybe pointerMoveFromIntent pointerIntentEvent
    pointerDownEvents = fmapMaybe pointerDownFromIntent pointerIntentEvent
    pointerUpEvents = () <$ ffilter isPointerUpIntent pointerIntentEvent
  hoverWaypointDynamic <- foldDyn (flip applyNavigationHoverIntent) Nothing hoverInputEvents
  let
    navigationStartEvents =
      attachWithMaybe
        navigationGestureStart
        (current (zipDyn snapshotDynamic setupOverlayOpenDynamic))
        pointerDownEvents
  navigationGestureDynamic <-
    foldDyn
      const
      NoNavigationGesture
      ( leftmost
          [ (\(_, reachableWaypoint, maximumSpeed) -> beginNavigationGesture reachableWaypoint maximumSpeed) <$> navigationStartEvents
          , attachWithMaybe
              (\gesture point ->
                  case gesture of
                    NoNavigationGesture -> Nothing
                    NavigationGesture _ _ _ -> Just (updateNavigationGesture point gesture)
              )
              (current navigationGestureDynamic)
              pointerMoveEvents
          , NoNavigationGesture <$ pointerUpEvents
          , NoNavigationGesture <$ ffilter id (updated setupOverlayOpenDynamic)
          ]
      )
  let
    releaseSpeedEvents =
      attachWithMaybe
        ( \(gesture, (snapshot, setupIsOpen)) () ->
            if navigationInputAllowed setupIsOpen (combatSnapshotStatus snapshot)
              then navigationGestureSelectedSpeed gesture
              else Nothing
        )
        (current (zipDyn navigationGestureDynamic (zipDyn snapshotDynamic setupOverlayOpenDynamic)))
        pointerUpEvents
  let
    battleSceneDynamic =
      zipDynWith
        (\(((snapshot, hoverWaypoint), navigationGesture), setupIsOpen) debugOverlaysEnabled ->
            battleSceneFromSnapshotWithNavigationGestureAndDebug setupIsOpen debugOverlaysEnabled hoverWaypoint navigationGesture snapshot
        )
        (zipDyn (zipDyn (zipDyn snapshotDynamic hoverWaypointDynamic) navigationGestureDynamic) setupOverlayOpenDynamic)
        debugOverlaysEnabledDynamic
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
  pure $
    leftmost
      [ (\(requestedWaypoint, _, _) -> IssueNavigationOrder PlayerShip requestedWaypoint) <$> navigationStartEvents
      , SetNavigationPostWaypointSpeed PlayerShip <$> releaseSpeedEvents
      ]

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

hoverIntentFromPointerIntent :: NavigationPointerIntent -> Maybe NavigationHoverIntent
hoverIntentFromPointerIntent intent =
  case intent of
    NavigationPointerMoved point -> Just (PreviewNavigation point)
    NavigationPointerLeftBattleView -> Just ClearNavigationHover
    _ -> Nothing

pointerMoveFromIntent :: NavigationPointerIntent -> Maybe Point
pointerMoveFromIntent intent =
  case intent of
    NavigationPointerMoved point -> Just point
    _ -> Nothing

pointerDownFromIntent :: NavigationPointerIntent -> Maybe Point
pointerDownFromIntent intent =
  case intent of
    NavigationPointerPrimaryDown point -> Just point
    _ -> Nothing

isPointerUpIntent :: NavigationPointerIntent -> Bool
isPointerUpIntent intent =
  case intent of
    NavigationPointerPrimaryUp -> True
    _ -> False

navigationGestureStart :: (CombatSnapshot, Bool) -> Point -> Maybe (Point, Point, Double)
navigationGestureStart (snapshot, setupIsOpen) requestedWaypoint
  | not (navigationInputAllowed setupIsOpen (combatSnapshotStatus snapshot)) = Nothing
  | otherwise = do
      plan <- planNavigationForSnapshot snapshot PlayerShip requestedWaypoint
      player <- playerSnapshot snapshot
      pure (requestedWaypoint, navigationPlanReachableWaypoint plan, shipSnapshotMaxSpeed player)

playerSnapshot :: CombatSnapshot -> Maybe ShipSnapshot
playerSnapshot snapshot =
  case filter ((== PlayerShip) . shipSnapshotId) (combatSnapshotShips snapshot) of
    player : _ -> Just player
    [] -> Nothing

callMethod :: (MakeArgs args) => Text -> JSVal -> args -> JSM JSVal
callMethod method target args = do
  functionValue <- target ! method
  call functionValue target args

logBrowserError :: Text -> JSM ()
logBrowserError message = do
  console <- jsg ("console" :: Text)
  void $ callMethod "error" console [message]

canvasAttributes :: Map.Map Text Text
canvasAttributes =
  Map.fromList
    [ ("id", "battle-view")
    , ("width", canvasWidthText)
    , ("height", canvasHeightText)
    , ( "style"
      , "width: 100%; max-width: 760px; aspect-ratio: 16 / 9; border: 1px solid #203447; background: #061019; display: block;"
      )
    ]

canvasWidthText :: Text
canvasWidthText = "760"

canvasHeightText :: Text
canvasHeightText = "428"
