# Bloom Inspector — Implementation Map (Hierarchy + Call Graph)

This file is a code-oriented map of “everything Bloom Inspector” in Expo Go, grouped by area.

## iOS native (Objective-C++)

### `EXBloomInspectorOverlayManager` (overlay window lifecycle)
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.h`
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- **Responsibility:** Owns a transparent `UIWindow` containing the overlay view and the RN panel surface.
- **Key properties**
  - `window`: overlay `UIWindow`
  - `viewController`: `EXBloomInspectorOverlayViewController`
  - `visible` (`isVisible`)
  - `panelFrame`, `hasPanelFrame`: used to ignore touches in the panel area
- **Key methods**
  - `sharedInstance`
  - `toggle`
  - `show`
  - `hide`

### `EXBloomInspectorOverlayViewController` (hosts RN panel surface + overlay view)
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- **Responsibility:** Creates the `BloomInspectorOverlay` RN surface and the native overlay view.
- **Key behavior**
  - Creates the RN root view with module name `BloomInspectorOverlay`
  - Adds `EXBloomInspectorOverlayView` on top for hit-testing / highlight drawing

### `EXBloomInspectorOverlayView` (hit-testing + selection + highlight)
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- **Responsibility:** Captures taps/pans, hit-tests the visible app view hierarchy, draws highlight, emits tap events.
- **Key methods**
  - `pointInside:withEvent:`: ignores touches inside `panelFrame` when `hasPanelFrame` is true
  - `_handleTap:` / `_handlePan:`: routes to `_inspectAtPoint:`
  - `_inspectAtPoint:`:
    - computes a `touchID`
    - hit-tests the visible app root view
    - highlights the hit view
    - emits a `bloomInspectorTap` event via `EXBloomInspector`
    - may emit fallback payloads to `EXBloomInspectorOverlay` when enabled (guarded by `kBloomInspectorEnableNativeFallback`)

### `EXBloomInspector` (native → JS tap event emitter)
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.h`
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- **Module name:** `BloomInspector` (`RCT_EXPORT_MODULE(BloomInspector)`)
- **Events** (`supportedEvents`)
  - `bloomInspectorToggle`
  - `bloomInspectorTap`
- **Lifecycle**
  - `startObserving`: marks `_hasListeners = YES`
  - `stopObserving`: marks `_hasListeners = NO`
- **Event helpers**
  - `emitToggle`: sends `bloomInspectorToggle` when listeners exist
  - `emitTap:`: sends `bloomInspectorTap` with `{ x, y, touchID, ... }` when listeners exist
- **Forwarder**
  - `sendPick:`: forwards a payload to `EXBloomInspectorOverlay.emitPick` (used as a backstop when the overlay module is available)

### `EXBloomInspectorOverlay` (native ↔ overlay panel event emitter)
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.h`
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- **Module name:** `BloomInspectorOverlay` (`RCT_EXPORT_MODULE(BloomInspectorOverlay)`)
- **Events** (`supportedEvents`)
  - `bloomInspectorOverlayPick`
  - `bloomInspectorOverlayToggle`
  - `bloomInspectorOverlayPing`
- **Lifecycle**
  - `startObserving`: marks `_hasListeners = YES`
  - `stopObserving`: marks `_hasListeners = NO`
- **Methods exported to JS**
  - `toggle`: toggles `EXBloomInspectorOverlayManager`
  - `getEnabledAsync`: resolves whether overlay is visible
  - `setPanelFrame`: sets `panelFrame/hasPanelFrame` so native overlay can ignore panel touches
  - `sendPick`: updates `kBloomInspectorLastJSPickTime` and re-emits a pick to the panel
  - `log`: gated debug logging bridge (native logs are also gated)
- **Event helpers**
  - `emitPick:`: emits `bloomInspectorOverlayPick`
  - `emitToggle:`: emits `bloomInspectorOverlayToggle`
  - `emitPing:`: emits `bloomInspectorOverlayPing`

### Runtime / bundle injection helpers (DevTools hook availability)
- **File:** `ios/Exponent/Kernel/ReactAppManager/EXReactAppManager.mm`
  - `kBloomInspectorBundlePrelude` + `EXInjectBloomInspectorPrelude(...)`
  - Prepends JS to the experience bundle in dev to help ensure `__REACT_DEVTOOLS_GLOBAL_HOOK__` exists early and to wrap `AppRegistry.registerComponent` (host `View` capture).
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
  - `EXBloomInspectorRuntimeDelegate` (`RCTHostRuntimeDelegate`)
  - `host:didInitializeRuntime:` evaluates `kBloomInspectorInjectionScript` via JSI

### Dev menu integration (toggle entry point)
- **File:** `ios/Exponent/Versioned/Core/EXVersionManagerObjC.mm`
- **Menu item:** `bloom-inspector`
- **Action:** `[[EXBloomInspectorOverlayManager sharedInstance] toggle]`

## JS / TypeScript (Expo Go shell)

### `BloomInspectorProvider` (in-app inspector UI + native tap bridge)
- **File:** `src/utils/useBloomInspector.tsx`
- **Responsibilities**
  - Provides the in-app inspector UI (ElementPickerOverlay + ElementProperties) when `enabled` is true
  - Listens for native `bloomInspectorTap` and forwards JS-computed payloads to the overlay panel (`BloomInspectorOverlay.sendPick`)
- **Key pieces**
  - `handleNativeTap(payload)`: converts screen coordinates to local coordinates and calls `getInspectorDataForViewAtPoint(...)`
  - `toPickPayload(viewData, metadata)`: builds a payload including `hierarchy`, `props`, `componentStack`, best-effort `source`, and `touchID`
  - `NativeEventEmitter(NativeModules.BloomInspector).addListener('bloomInspectorTap', ...)`

### React inspector data extraction
- **File:** `src/mobileInspector/getInspectorDataForViewAtPoint.tsx`
- **Responsibilities**
  - Reads renderers from `__REACT_DEVTOOLS_GLOBAL_HOOK__`
  - Calls `renderer.rendererConfig.getInspectorDataForViewAtPoint(...)`
  - Extracts React metadata (stack/source/props/hierarchy) from `InspectorViewData` + Fiber heuristics

### Overlay panel RN surface (what the native overlay window displays)
- **File:** `src/mobileInspector/BloomInspectorOverlayApp.tsx`
  - `AppRegistry.registerComponent('BloomInspectorOverlay', ...)`
- **File:** `src/mobileInspector/BloomInspectorOverlayPanel.tsx`
  - Subscribes to `bloomInspectorOverlayPick` and renders the selected element
  - Calls `NativeModules.BloomInspectorOverlay.setPanelFrame(...)` on layout so native overlay ignores touches over the panel
  - Merges native vs JS pick payloads by `touchID` (prefers `payloadSource: 'js'`)
  - Panel features: Overview/Props/Raw tabs, React Stack Short/Full toggle, props search + copy, open-in-editor via `/open-stack-frame`

### Build-time source injection (for `source.fileName/lineNumber/columnNumber`)
- **File:** `babel.config.js` (development only)
  - `@babel/plugin-transform-react-jsx-source` adds `__source`
  - `./babel/bloom-source-plugin` adds `__bloomSource`
- **File:** `babel/bloom-source-plugin.js`
  - Injects `__bloomSource` onto JSX opening elements (skips `node_modules`)

## Call graph (tap → payload → panel)

1) **Dev menu toggle**
- `EXVersionManagerObjC` dev menu item `bloom-inspector`
  → `EXBloomInspectorOverlayManager.toggle()`
  → `show()` creates overlay `UIWindow` and `EXBloomInspectorOverlayViewController`

2) **Native selection**
- `EXBloomInspectorOverlayView._handleTap/_handlePan`
  → `_inspectAtPoint`
  → `EXBloomInspector.emitTap({ x, y, touchID, ... })`

3) **JS computes React payload**
- `BloomInspectorProvider` listens to `bloomInspectorTap`
  → `getInspectorDataForViewAtPoint(inspectedRoot, localX, localY, cb)`
  → `getReactMetadataFromViewData(viewData)`
  → `toPickPayload(...)` builds payload with `payloadSource: 'js'`
  → `NativeModules.BloomInspectorOverlay.sendPick(payload)`

4) **Overlay panel receives + renders**
- Native `EXBloomInspectorOverlay.sendPick` / `emitPick`
  → event `bloomInspectorOverlayPick`
  → `BloomInspectorOverlayPanel` merges by `touchID`
  → panel renders hierarchy/props/source and calls `setPanelFrame` for touch passthrough

Notes
- Best source resolution comes from `__bloomSource` / `__source` on props; this is injected at build-time by `bloom-source-plugin` and is preferred over bundle URLs.
