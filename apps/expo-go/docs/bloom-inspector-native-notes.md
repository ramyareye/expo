# Bloom Inspector Native Notes

This doc summarizes what we changed on the native (iOS) side and how React-level inspector data is now flowing into the overlay panel.

For a presentation-friendly, end-to-end walkthrough, see `docs/bloom-inspector-overview.md`.

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
- Note: the native fallback path is currently guarded by `kBloomInspectorEnableNativeFallback` in
  `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm` (currently `YES`).

### 5) Live Edit bridge (native)
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- Added `applyNativePropsAsync` (native path).
- The **default UX** uses the native path for **View** updates (Fabric `synchronouslyUpdateViewOnUIThread`
  + UIKit fallback).
- **Text styles** (color/align/underline) are now routed through the **JS runtime override**
  (`applyLiveEditToAppAsync`) so Fabric can recompute the attributed string.
- **Text content override is disabled** in the UI for now.

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
- Runtime injection exists and evaluates a JS script via `RCTHostRuntimeDelegate` when the runtime
  initializes (see `didInitializeRuntime` in `EXBloomInspectorManager.mm`).
- The JS bridge for tap→payload is implemented in `src/utils/useBloomInspector.tsx`; injection is
  not required for the event flow itself, but is used to improve observability/availability of the
  React DevTools hook/renderers (which power `getInspectorDataForViewAtPoint`).

## Files changed so far (native)

- `ios/Exponent/Versioned/Core/EXBloomInspectorManager.h`
  - public declarations for the overlay manager + modules + runtime delegate
- `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
  - overlay window + hit-testing
  - native modules + event emitters
  - runtime delegate + runtime script evaluation
- `ios/Exponent/Versioned/Core/EXVersionManagerObjC.mm`
  - dev menu toggle
  - module registration in `extraModules`
- `ios/Exponent/Versioned/Core/AppInstance/ExpoAppInstance.mm`
  - runtime delegate attachment logging (currently unused since injection is disabled)

## Quick recap

- **Working now:** native selection + highlight + overlay panel UI + dev menu toggle.
- **Working now:** JS payload with React stack/source/props, merged into the panel.
- **Fallback:** native-only payload when JS is unavailable.
- **Logs:** native Bloom logs are disabled by default (`kBloomInspectorDebugLogs = NO`); JS files
  contain local debug flags (`DEBUG_BLOOM_LOGS`, `DEBUG_OPEN_IN_EDITOR`) which are off by default.

## Latest UI additions (panel)

- Tabs: Overview / Source / Hierarchy / Props / Edit.
- Toggle chips:
  - React Stack: Short / Full
  - Source: Short / Raw (Short shows basename)
  - Hierarchy: Fiber On / Off
- Props: search + copy-to-clipboard.
- Payload (Source tab): toggle show/hide + copy-to-clipboard.
- “Open in editor” uses the dev-server `/open-stack-frame` endpoint when available.
- **Edit tab (Quick Style):** conditional controls based on component type.
  - View: color swatches + hex input for background.
  - Text: color swatches + hex input for text color, alignment toggles, underline toggle, and a
    text-content input.
  - Applies via native path.
- **Advanced JSON:** collapsed by default; expands to the raw JSON editor + Apply buttons.

## Live Edit behavior & limitations (current)

- **Best‑effort only:** live edits do not update React state and can be overwritten on re-render.
- **Text limitations:** Native/KVC updates on `RCTParagraphComponentView` are unreliable; Fabric
  owns the attributed string and may ignore UIKit mutations.
- **DevTools renderer availability:** the DevTools hook can report `renderers=0`, so `overrideProps`
  cannot schedule a commit. This is why text styles use the JS runtime override path instead.
- **Target drift:** some components resolve to parent/native wrappers (e.g. screen containers).

## Lifecycle (current flow)

1) **Experience bundle load**
- **File:** `ios/Exponent/Kernel/ReactAppManager/EXReactAppManager.mm`
- Prepend Bloom inspector bundle prelude when `enablesDeveloperTools` is true.

2) **Host runtime delegate**
- **File:** `ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
- Swizzle `RCTHost start` to attach a runtime delegate and evaluate `kBloomInspectorInjectionScript`
  (used for React-aware payload fallback and better source resolution).

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
