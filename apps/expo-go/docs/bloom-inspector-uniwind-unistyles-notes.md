# Bloom Inspector — Notes on Reusing Uniwind / Unistyles Patterns

This doc captures concrete, realistic patterns from Uniwind and Unistyles that could inform
future Bloom Inspector improvements. It is intentionally narrow: reuse‑friendly logic only.

## Quick take
- **Unistyles** has the most transferable patterns (dependency listeners, registry cleanup, proxy‑based tracking).
- **Uniwind** offers lightweight listener and caching patterns that could be reused in JS‑only layers.
- **Not worth borrowing:** Nitro/JSI or Metro transformer internals.

## Unistyles patterns that map well to the inspector

### 1) Dependency‑based listeners with separate “stylesheet vs component” channels
- **Files:**
  - `apps/expo-go/react-native-unistyles/src/web/listener.ts`
  - `apps/expo-go/react-native-unistyles/src/web/registry.ts`
- **What it does:**
  - Maintains two listener sets: component listeners and stylesheet listeners.
  - Emits by dependency type, enabling narrow invalidation.
- **Inspector reuse idea:**
  - Split inspector updates into “panel state changes” vs “data pipeline changes.”
  - Example: panel UI reacts to selection changes, while data pipeline reacts to renderer availability,
    breakpoint/orientation, or theme changes.

### 2) Registry + ref counting for DOM resources (web)
- **Files:**
  - `apps/expo-go/react-native-unistyles/src/web/registry.ts`
  - `apps/expo-go/react-native-unistyles/src/web/css/state.ts`
- **What it does:**
  - Tracks which styles are still referenced in the DOM and removes when the last ref is gone.
- **Inspector reuse idea:**
  - Apply to web overlay/highlight nodes to avoid leaked overlays or stale styles.
  - Useful if the inspector keeps a history of selections or overlays.

### 3) Proxy‑based dependency tracking
- **Files:**
  - `apps/expo-go/react-native-unistyles/src/core/useProxifiedUnistyles/useProxifiedUnistyles.ts`
- **What it does:**
  - Uses proxies to record which runtime/theme fields are accessed at render time.
  - Registers only the dependencies actually used.
- **Inspector reuse idea:**
  - Track which payload sections are actually rendered (Hierarchy vs Props vs Source).
  - Only recompute those sections when data changes.

## Uniwind patterns that map well to the inspector

### 1) One‑shot listener invalidation
- **File:** `apps/expo-go/uniwind/packages/uniwind/src/core/listener.ts`
- **What it does:**
  - `subscribe` supports `{ once: true }` for “invalidate once then dispose.”
- **Inspector reuse idea:**
  - For “next pick only” flows (one‑off selection) or transient overlay UI.

### 2) Cache with dependency bitmask
- **File:** `apps/expo-go/uniwind/packages/uniwind/src/core/native/store.ts`
- **What it does:**
  - Caches computed styles and invalidates by dependency bitmask.
- **Inspector reuse idea:**
  - Cache computed inspector payload per element/tag.
  - Invalidate only on relevant dependency changes (theme/orientation/screen changes).

### 3) Media query listener consolidation (web)
- **File:** `apps/expo-go/uniwind/packages/uniwind/src/core/web/cssListener.ts`
- **What it does:**
  - Parses stylesheets, aggregates media queries, and listens for changes via `matchMedia`.
- **Inspector reuse idea:**
  - If the inspector overlay or panel needs to react to CSS breakpoints on web,
    this is a ready‑made pattern.

## Patterns that are not good fits
- **Nitro/JSI or native StyleSheet hybrid** (Unistyles): tightly coupled to native engine.
- **Metro transformer‑level compilation** (Uniwind): inspector is runtime‑oriented, not build‑time.

## Suggested “drop‑in” improvements for Bloom Inspector
- **Add dependency channels** in JS overlay (selection vs data pipeline updates).
- **Add one‑shot listeners** for “next pick” or transient overlays.
- **Cache inspector payloads** per selected view with dependency‑based invalidation.
- **Optional:** ref‑count overlay DOM nodes (web) to avoid leaks.

## Reference links in repo
- Unistyles listener: `apps/expo-go/react-native-unistyles/src/web/listener.ts`
- Unistyles registry: `apps/expo-go/react-native-unistyles/src/web/registry.ts`
- Unistyles CSS state: `apps/expo-go/react-native-unistyles/src/web/css/state.ts`
- Unistyles proxified deps: `apps/expo-go/react-native-unistyles/src/core/useProxifiedUnistyles/useProxifiedUnistyles.ts`
- Uniwind listener: `apps/expo-go/uniwind/packages/uniwind/src/core/listener.ts`
- Uniwind store cache: `apps/expo-go/uniwind/packages/uniwind/src/core/native/store.ts`
- Uniwind CSS listener: `apps/expo-go/uniwind/packages/uniwind/src/core/web/cssListener.ts`
