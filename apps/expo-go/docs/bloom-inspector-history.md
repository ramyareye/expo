Bloom Inspector History

This is a short running log of key changes and experiments while building the
Bloom Element Inspector in Expo Go. The goal is to document how we arrived at
the current working pipeline so we can trim dead code later.

Milestones

- Added native overlay + panel window for the inspector.
- Wired native tap capture to emit view tag + frame.
- Implemented overlay panel in JS to render payload (hierarchy, frame, props).
- Added runtime injection (JSI via `RCTHostRuntimeDelegate`) to observe/install a DevTools hook.
- Added bundle prelude injection (prepended to the JS bundle in dev) to ensure the DevTools hook
  exists early and to wrap `AppRegistry.registerComponent` to capture a host `View` ref.
- Verified inspector data is returned via getInspectorDataForViewAtPoint.
- Added tracing logs to validate event pipeline:
  native -> JS -> overlay event -> panel update.
- Forwarded JS payloads to the overlay panel and merged by touchID.
- Panel now prefers JS payload (React stack/source/props) over native fallback.
- Added optional UI toggles for source display (short/raw) and fiber filtering.
- Added best-effort "Open in editor" button (dev server endpoint).
- Gated Bloom debug logs (native + JS) behind flags.

Current State

- Tap selection works in the experience.
- Inspector data (hierarchy/props/frame) arrives in the overlay panel.
- React component stack/source/props are present in JS payload and shown in the panel.
- Native payload remains as fallback only when JS is unavailable.
- Native Bloom logs are muted by default.

Notes

- Today there are two “hook availability” mechanisms:
  - **Bundle prelude injection**: prepends JS into the experience bundle in dev.
  - **Runtime injection**: evaluates JS via JSI when the runtime initializes.
  The JS tap→payload bridge is implemented in JS (`src/utils/useBloomInspector.tsx`); injection
  scripts exist primarily to ensure the DevTools hook/renderers are present/observable.
- react-native-dev-inspector / react-native-sandbox / devtools-frontend were
  reviewed for reference only; no code was pulled from them.

Reference review (not integrated)

- react-native-dev-inspector
  - Pure-JS inspector using RN internal `getInspectorDataForViewAtPoint` paths.
  - Uses skip lists to hide internal components and filters hierarchy noise.
  - Optional source heuristics (`testID` encoding, `_debugSource`, `_debugOwner`).
  - Metro middleware endpoint for “open in editor”.
  - No native modules or JSI bindings in this repo.
- react-native-harness
  - Native test runner; no inspector or bridge patterns relevant to this feature.
- rozenite
  - DevTools plugin runtime for browser panels (network, performance, etc.).
  - Not related to in-app element picking or React hierarchy inspection.
