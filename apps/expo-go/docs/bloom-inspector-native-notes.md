# Bloom Inspector Native Notes

This doc summarizes what we changed on the native (iOS) side and how React-level inspector data is now flowing into the overlay panel.

## What’s implemented on native iOS

### 1) Native overlay window (selection + highlight)
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- Added `EXBloomInspectorOverlayManager`, `EXBloomInspectorOverlayView`, and `EXBloomInspectorOverlayViewController`.
- The overlay is a transparent `UIWindow` that:
  - draws a pink highlight box around the selected view
  - listens for tap/pan to select a view
  - ignores touches in the panel area (panel frame is pushed down from JS)
- The overlay window is placed below the dev menu (`windowLevel = UIWindowLevelStatusBar - 1`) so the dev menu can sit above it.

### 2) Native module for overlay → JS panel communication
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- Added `RCTEventEmitter` module `BloomInspectorOverlay`:
  - events: `bloomInspectorOverlayPick`, `bloomInspectorOverlayToggle`
  - methods: `toggle`, `getEnabledAsync`, `setPanelFrame`, `sendPick`
- Added listener tracking to avoid “no listeners registered” warning spam.

### 3) Dev menu integration
- **File:** `ios/Exponent/Versioned/Core/EXVersionManagerObjC.mm` (uses `EXBloomInspectorOverlayManager`)
- Dev menu item `bloom-inspector` toggles the overlay.

### 4) Fallback native-only data
- When React inspector data isn’t available, native view info is sent:
  - class chain, frame, basic props (alpha/hidden/userInteractionEnabled, accessibility, reactTag if present).

## Current JS panel (overlay UI)

### 5) React Native panel rendered inside overlay
- **Files:**
  - `src/mobileInspector/BloomInspectorOverlayApp.tsx`
  - `src/mobileInspector/BloomInspectorOverlayPanel.tsx`
- The overlay panel is its own RN surface (`BloomInspectorOverlay`) and listens to native events.
- Panel behavior:
  - positions above/below based on selection
  - max height = 50%
  - scrollable
  - close button in header

## How React component names/source are now delivered

React inspector payloads are generated in JS and sent to the overlay via
`BloomInspectorOverlay.sendPick`:
- **File:** `src/utils/useBloomInspector.tsx`
- The native overlay emits `bloomInspectorTap` with `x/y/touchID`.
- JS computes React inspector data via `getInspectorDataForViewAtPoint`
  and `getReactMetadataFromViewData`.
- The sanitized payload includes `componentStack`, `source`, `hierarchy`,
  and `props`, tagged with `payloadSource: 'js'`.

## Next steps (recommended)

### A) Verify JS-first rendering in the panel
- Ensure the overlay panel renders JS payloads (React stack/source/props) when present.
- Keep native-only payload as fallback when JS is unavailable.

### B) Decide on native fallback timing
- Current native fallback delay is 0.35s with a 1.0s suppression window.
- If JS payload is reliable, we can reduce or remove the delay to avoid lag.
  (See `kBloomInspectorFallbackDelaySeconds` in `EXBloomInspectorManager.mm`.)

## Progress updates (latest)

### Bundle-prelude injection implemented
- **File:** `ios/Exponent/Kernel/ReactAppManager/EXReactAppManager.mm`
- Added `kBloomInspectorBundlePrelude` JS snippet and `EXInjectBloomInspectorPrelude(...)`.
- Prelude is injected only in dev (`enablesDeveloperTools`).
- Logs when injection occurs: `Bloom Log: 32/33`.
- Prelude now installs a minimal React DevTools hook if none exists (`Bloom Log: 3 devtools hook installed`) so renderers can inject early.
- Added `Bloom Log: 34 renderer injected id=...` to confirm React renderer registration.
- Prelude retries attaching to `__RCTDeviceEventEmitter` (`Bloom Log: 4 device event emitter missing (retry=...)`).

### Runtime injection (status)
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- Runtime injection exists but is not relied on for the JS payload; the JS bridge
  in `useBloomInspector` provides the data.

## Files changed so far (native)

- `ios/Exponent/Versioned/Core/EXBloomInspectorManager.h`
  - public declarations for the overlay manager + modules + runtime delegate
- `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
  - overlay window + hit-testing
  - native modules + event emitters
  - runtime delegate (injection disabled)
- `ios/Exponent/Versioned/Core/EXVersionManagerObjC.mm`
  - dev menu toggle
  - module registration in `extraModules`
- `ios/Exponent/Versioned/Core/AppInstance/ExpoAppInstance.mm`
  - runtime delegate attachment logging (currently unused since injection is disabled)

## Quick recap

- **Working now:** native selection + highlight + overlay panel UI + dev menu toggle.
- **Working now:** JS payload with React stack/source/props, merged into the panel.
- **Fallback:** native-only payload when JS is unavailable.

## Lifecycle (current flow)

1) **Experience bundle load**
- **File:** `ios/Exponent/Kernel/ReactAppManager/EXReactAppManager.mm`
- Prepend Bloom inspector bundle prelude when `enablesDeveloperTools` is true.

2) **Host runtime delegate**
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- Swizzle `RCTHost start` to attach a runtime delegate (injection currently disabled).

3) **Dev menu toggle**
- **File:** `ios/Exponent/Versioned/Core/EXVersionManagerObjC.mm`
- Dev menu item `bloom-inspector` calls `EXBloomInspectorOverlayManager toggle`.

4) **Overlay window**
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- `EXBloomInspectorOverlayManager show` creates the overlay `UIWindow`.

5) **React panel surface**
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- `EXBloomInspectorOverlayViewController` builds the `BloomInspectorOverlay` RN surface.

6) **Hit testing + native selection**
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- `EXBloomInspectorOverlayView` handles tap/pan, hit-tests, highlights, and emits native events.

7) **UIManager inspector data**
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- Calls `getInspectorDataForViewAtPoint` / `getInspectorDataForViewTag` when available.

8) **Fallback native payload**
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- If no React inspector data, send native-only payload (class chain + basic props).

9) **JS bridge (runtime)**
- **File:** `src/utils/useBloomInspector.tsx`
- JS listens for native taps, reads React DevTools hook, sends payload to native overlay.
