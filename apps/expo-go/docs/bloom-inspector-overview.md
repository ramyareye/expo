# Bloom Element Inspector (Expo Go) — Overview

This doc is a “presentation-ready” explanation of how the Bloom element inspector works in Expo Go.
It focuses on the current pipeline and where to look in code.

## What it is

The Bloom inspector is an **in-app element picker + properties viewer**:

- You enable it from the **iOS dev menu**.
- A **native overlay window** sits on top of the app, captures taps/pans, and draws the highlight box.
- A **React Native overlay panel** (separate RN surface) renders the selected element’s data.
- “React-aware” data (component stack, props, source) is computed in **JS** using the **React DevTools hook** (with a native-injected JS fallback that can also produce React-aware payloads).

## High-level data flow (tap → panel)

1) **User taps/pans on the screen**
- Native overlay view hit-tests the visible app and highlights the target.

2) **Native emits a tap event to the experience runtime**
- Event: `bloomInspectorTap` (with `x/y` and a `touchID`)
- Module: `BloomInspector` (an `RCTEventEmitter`)

3) **JS computes React inspector data for the tapped location**
- JS listens for `bloomInspectorTap`.
- JS calls React renderer’s `getInspectorDataForViewAtPoint(...)` via `__REACT_DEVTOOLS_GLOBAL_HOOK__`.
- JS builds a sanitized payload with:
  - `hierarchy`
  - `props`
  - `componentStack`
  - best-effort `source` (see “Source attribution” below)
  - `touchID`
  - `payloadSource: 'js'`

4) **JS forwards the payload to the overlay panel**
- JS calls `NativeModules.BloomInspectorOverlay.sendPick(payload)`
- Native re-emits `bloomInspectorOverlayPick` to the overlay panel surface.
- The panel merges “native vs JS” payloads by `touchID` and prefers JS when present.

## Key files (map)

### JS / TypeScript

- `apps/expo-go/src/utils/useBloomInspector.tsx`
  - Listens to `bloomInspectorTap`
  - Computes pick payload and calls `BloomInspectorOverlay.sendPick`
  - Provides the in-app inspector UI (ElementPickerOverlay/ElementProperties) for the Expo Go shell
- `apps/expo-go/src/mobileInspector/getInspectorDataForViewAtPoint.tsx`
  - Reads from `__REACT_DEVTOOLS_GLOBAL_HOOK__`
  - Extracts component names and source/stack from Fiber when possible
- `apps/expo-go/src/mobileInspector/BloomInspectorOverlayPanel.tsx`
  - Overlay panel UI (separate RN surface)
  - Consumes `bloomInspectorOverlayPick` and calls `setPanelFrame` to keep overlay hit-testing correct
- `apps/expo-go/src/mobileInspector/BloomInspectorOverlayApp.tsx`
  - Registers `BloomInspectorOverlay` surface via `AppRegistry`

### Build-time (source tagging)

- `apps/expo-go/babel.config.js`
  - In development: `@babel/plugin-transform-react-jsx-source` + `./babel/bloom-source-plugin`
- `apps/expo-go/babel/bloom-source-plugin.js`
  - Adds `__bloomSource = { fileName, lineNumber, columnNumber }` to JSX elements (excluding `node_modules`)

### Native iOS

- `apps/expo-go/ios/Exponent/Versioned/Core/EXBloomInspectorManager.mm`
  - `EXBloomInspectorOverlayManager` + `UIWindow` overlay lifecycle
  - `EXBloomInspectorOverlayView` tap/pan handling + highlight drawing
  - Native modules:
    - `BloomInspector` (emits `bloomInspectorTap`)
    - `BloomInspectorOverlay` (emits `bloomInspectorOverlayPick`, implements `sendPick`, `toggle`, `setPanelFrame`, `getEnabledAsync`)
  - Runtime injection hook (`RCTHostRuntimeDelegate`) to evaluate a JS script at runtime init
- `apps/expo-go/ios/Exponent/Versioned/Core/EXVersionManagerObjC.mm`
  - Dev menu item `bloom-inspector` toggles `EXBloomInspectorOverlayManager`
- `apps/expo-go/ios/Exponent/Kernel/ReactAppManager/EXReactAppManager.mm`
  - Bundle prelude injection in dev: prepends a JS snippet to help ensure the DevTools hook/renderers exist early

## Source attribution (“open in editor”)

The payload’s `source` is best-effort and comes from a few places, in roughly this priority:

1) `__bloomSource` / `__source` on props (from Babel transforms in dev)
2) Fiber `_debugSource` / `_debugOwner` (when available via the renderer hook)
3) Parsing `componentStack` for `(file:line:column)` patterns
4) If everything is “bundle URLs” / `node_modules`, source may be omitted

The overlay panel uses the dev-server endpoint `/open-stack-frame` when it can resolve a dev server origin.
When `source.fileName` is already a local path (e.g. `.../ComponentListScreen.tsx`), “Open in editor” does not require symbolication.

Panel UX notes:
- Source shows the filename (basename) by default; toggle to “Raw” for full path/URL.
- React Stack has a Short/Full toggle.
- Props tab supports search and copy-to-clipboard.
- Source tab shows a small code snippet preview (served by Metro at `/bloom-source-snippet`).
- Hierarchy tab shows the parent→child chain as a collapsible tree view.

Dev server note:
- The snippet endpoint is served by the Metro dev server (typically `:8081`). If you hit the manifest server (often `:80`), you’ll get an Expo manifest JSON instead of a snippet.

## Notes / caveats

- This is primarily an iOS feature (native overlay window).
- There are multiple “DevTools hook availability” mechanisms (bundle prelude + runtime injection). The main tap→payload bridge is the JS code in `useBloomInspector.tsx`.
- Elements rendered with `pointerEvents="none"` won’t be selectable (the overlay hit-test can’t “see” them as a target).
