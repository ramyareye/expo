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
  - Includes search + copy-to-clipboard.
- [x] Code Location (file + line).
  - Source prefers `__bloomSource` / `__source` when available (local `*.tsx` paths), otherwise falls back to fiber debug source + symbolication.
  - “Open in editor” uses the dev server `/open-stack-frame` endpoint.

Stack
- [x] Expo Go fork (sdk-54 base).
- [x] React Native + TypeScript + Native iOS.
- [x] iOS-only support.

### Bonus ideas (optional)

- [ ] Live prop editing.
- [x] Code preview snippet.
- [ ] Hierarchy visualization (parent-child tree).
- [x] Props search/filter.

### Deliverables

- [ ] Private GitHub repo + invite **sirian-m**.
- [ ] Screen recording of inspector flow.
- [ ] Brief doc with implementation approach + challenges.

### Implementation notes (current state)

- JS payload merges by touchID; React stack/source/props render in the overlay panel.
- Native overlay + injected JS can also produce React-aware payloads (fallback path retained).
- Panel tabs: Overview / Source / Props / Raw.
- Panel toggles: React Stack short/full, Source short/raw (basename vs full), Fiber on/off.
- Source snippet uses Metro endpoint `/bloom-source-snippet` (served by Metro, typically `:8081`).
- Bloom debug logs are gated off by default.

### Next steps

- [ ] Improve snippet UI readability (background + padding + highlight current line).
- [ ] Decide behavior for library/native components: show `node_modules` file vs “usage site” attribution.
- [ ] Handle stale selection after code changes / refresh (clear or reselect).
