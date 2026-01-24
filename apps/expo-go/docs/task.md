## Bloom — Take-Home Challenge: Mobile Element Inspector

⚠️ Confidential — do not share publicly or outside Bloom.

### Goal

Build a mobile element inspector in Expo Go (iOS only) that lets users tap UI elements, inspect props, and link to source.

### Must-have checklist

Test App
- [x] Use a local Expo app for testing (native-component-list).

UX
- [x] Element Picker Mode (toggle enable/disable).
- [x] Visual Selection (highlight border on tap).
- [x] Props Inspector (props list with name/value/type).
- [x] Code Location (file + line).  
  - Note: source currently shows bundle URL + line; “Open in editor” works when a real path is available.

Stack
- [x] Expo Go fork (sdk-54 base).
- [x] React Native + TypeScript + Native iOS.
- [x] iOS-only support.

### Bonus ideas (optional)

- [ ] Live prop editing.
- [ ] Code preview snippet.
- [ ] Hierarchy visualization (parent-child tree).
- [ ] Props search/filter.

### Deliverables

- [ ] Private GitHub repo + invite **sirian-m**.
- [ ] Screen recording of inspector flow.
- [ ] Brief doc with implementation approach + challenges.

### Implementation notes (current state)

- JS payload merges by touchID; React stack/source/props render in the overlay panel.
- Native payload fallback is disabled (code retained for later use).
- Panel toggles: Source short/raw, Fiber on/off.
- “Open in editor” button attempts symbolication and uses dev server `/open-stack-frame`.
- Bloom debug logs are gated off by default.

### Next steps

- [ ] Verify “Open in editor” works on a non-bundle source path.
- [ ] Decide whether to keep native fallback or disable entirely.
