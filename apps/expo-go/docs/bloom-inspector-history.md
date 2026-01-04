Bloom Inspector History

This is a short running log of key changes and experiments while building the
Bloom Element Inspector in Expo Go. The goal is to document how we arrived at
the current working pipeline so we can trim dead code later.

Milestones

- Added native overlay + panel window for the inspector.
- Wired native tap capture to emit view tag + frame.
- Implemented overlay panel in JS to render payload (hierarchy, frame, props).
- Added JSI runtime injection to install a DevTools hook and inspect taps.
- Confirmed prelude injection into the bundle, but prelude never executed.
  - Decision: move all bridge logic into the runtime injection script.
- Implemented AppRegistry wrapper to capture a host component reference.
  - Initially failed (ref on function component not called).
  - Fixed by using AppRegistry.setWrapperComponentProvider + host View ref.
- Verified inspector data is returned via getInspectorDataForViewAtPoint.
- Added tracing logs to validate event pipeline:
  native -> JS -> overlay event -> panel update.
- Forwarded JS payloads to the overlay panel and merged by touchID.
- Panel now prefers JS payload (React stack/source/props) over native fallback.

Current State

- Tap selection works in the experience.
- Inspector data (hierarchy/props/frame) arrives in the overlay panel.
- React component stack/source/props are present in JS payload and shown in the panel.
- Native payload remains as fallback only when JS is unavailable.

Notes

- Preludes are injected but do not execute; runtime injection is the source of
  truth for hooks and tap handling.
- react-native-dev-inspector / react-native-sandbox / devtools-frontend were
  reviewed for reference only; no code was pulled from them.
