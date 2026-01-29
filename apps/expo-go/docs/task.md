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

- [x] Live prop editing (experimental; uses `setNativeProps`).
- [x] Code preview snippet.
- [x] Hierarchy visualization (parent-child tree).
- [x] Props search/filter.
- [ ] Edit + save props in source (later).

### Deliverables

- [ ] Private GitHub repo + invite **sirian-m**.
- [ ] Screen recording of inspector flow.
- [x] Brief doc with implementation approach + challenges (`apps/expo-go/docs/bloom-inspector-presentation-brief.md`).

### Implementation notes (current state)

- JS payload merges by touchID; React stack/source/props render in the overlay panel.
- Native overlay + injected JS can also produce React-aware payloads (fallback path retained).
- Panel tabs: Overview / Source / Hierarchy / Props / Raw.
- Panel toggles: React Stack short/full, Source short/raw (basename vs full), Fiber on/off.
- Source snippet uses Metro endpoint `/bloom-source-snippet` (served by Metro, typically `:8081`).
- Bloom debug logs are gated off by default.
- Live edit: view-level props (bg/opacity/border) work via native apply.
- Live edit (Text): styles (color/align/underline) now go through the JS runtime override path (`applyLiveEditToAppAsync`) so Fabric can recompute attributed strings.
- Text content override is disabled in the UI for now.
- Live edit changes can be overwritten on re-render (no React state update).

### Next steps

- [ ] Decide behavior for library/native components: show `node_modules` file vs “usage site” attribution (now supported via `ownerSource` heuristic; needs validation/tuning).
- [ ] Handle stale selection after code changes / refresh (clear or reselect).
- [ ] Decide scope for Live Edit on Text: keep view-only for now vs implement Fabric text mutation (attributed string / shadow tree) or overlay approach.
