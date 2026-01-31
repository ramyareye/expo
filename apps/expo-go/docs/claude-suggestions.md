# Bloom Inspector — Pre-Presentation Code Review

**Reviewer:** Claude  
**Date:** January 30, 2026  
**Focus:** Correctness, stability, demo readiness, and safe improvements

---

## Executive Summary

The Bloom Inspector implementation is **solid and demo-ready**. The architecture is well-thought-out with good separation between native and JS layers. I found no critical bugs that would cause crashes during a demo. Below are categorized findings with risk levels and recommendations.

---

## 1. Bugs & Risky Behavior

### 1.1 🟡 MEDIUM: Race condition in payload merging by touchID

**File:** `BloomInspectorOverlayPanel.tsx` (lines 482-519)

**Issue:** The `payloadByTouchID` ref uses a `Map` that can grow unbounded across selections. While there's a `clearSelection()` that clears it, if the user rapidly taps many elements without closing the panel, the map accumulates stale entries.

```typescript
// Current code
const payloadByTouchID = useRef<Map<number, { native?: PickPayload; js?: PickPayload }>>(new Map());
```

**Risk:** Memory leak over extended use; unlikely to affect a short demo.

**Safe fix (pre-presentation):**

```typescript
// Add size limit check in handlePickEvent
if (payloadByTouchID.current.size > 50) {
  // Keep only recent entries
  const entries = Array.from(payloadByTouchID.current.entries());
  payloadByTouchID.current = new Map(entries.slice(-20));
}
```

**Recommendation:** Low priority — won't affect demo.

---

### 1.2 🟡 MEDIUM: Missing null check in `setSelection` callback

**File:** `useBloomInspector.tsx` (lines 202-221)

**Issue:** The `setSelection` callback accesses `viewData.hierarchy[index]` without checking bounds after the null check.

```typescript
const setSelection = useCallback(
  (index: number) => {
    if (!viewData?.hierarchy) return;
    const item = viewData.hierarchy[index]; // Could be undefined if index out of bounds
    if (!item) return; // ✅ This check exists, good
    // ...
  },
  [viewData]
);
```

**Status:** Actually safe — the `if (!item) return;` handles this. No action needed.

---

### 1.3 🟡 MEDIUM: `inspectedRef.measureInWindow` can fail silently

**File:** `useBloomInspector.tsx` (lines 239-265)

**Issue:** If `measureInWindow` fails or returns invalid values (can happen with unmounted views), the callback still proceeds with potentially `NaN` or `undefined` coordinates.

```typescript
inspectedRef.measureInWindow((left, top, _width, _height) => {
  const localX = x - left; // Could be NaN if left is undefined
  const localY = y - top;
  getInspectorDataForViewAtPoint(inspectedRef, localX, localY, (data) => {
    // ...
  });
});
```

**Safe fix (pre-presentation):**

```typescript
inspectedRef.measureInWindow((left, top, _width, _height) => {
  if (typeof left !== 'number' || typeof top !== 'number') {
    return;
  }
  // ...
});
```

**Risk:** Could cause silent failures; unlikely in normal demo flow.

---

### 1.4 🟢 LOW: Renderers array populated at module load time

**File:** `getInspectorDataForViewAtPoint.tsx` (lines 34-47)

**Issue:** The `renderers` array is populated when the module loads. If the DevTools hook isn't ready yet, it starts empty and relies on the `on('renderer', ...)` listener to populate it later. This is correctly handled, but there's a timing window.

```typescript
const renderers: ReactRenderer[] =
  reactDevToolsHook &&
  reactDevToolsHook.renderers &&
  typeof reactDevToolsHook.renderers.values === 'function'
    ? Array.from(reactDevToolsHook.renderers.values())
    : [];

// This correctly handles late-arriving renderers
if (reactDevToolsHook?.on && typeof reactDevToolsHook.on === 'function') {
  reactDevToolsHook.on('renderer', ({ renderer }) => {
    renderers.push(renderer);
  });
}
```

**Status:** Correctly implemented. The `validateRenderers()` warning is good UX.

---

## 2. Demo Failure Edge Cases

### 2.1 🔴 HIGH: Snippet endpoint hitting wrong server

**File:** `BloomInspectorOverlayPanel.tsx` (lines 720-822)

**Issue documented:** The snippet endpoint `/bloom-source-snippet` must hit Metro (`:8081`), not the manifest server (`:80`). Your code handles this with `getSnippetOrigins()`, but demo failure is possible if:

- Metro is running on a non-default port
- The dev server hasn't loaded the snippet middleware

**Demo prep checklist:**

1. Verify Metro is running on expected port before demo
2. Test snippet fetch manually: `curl -X POST http://localhost:8081/bloom-source-snippet -H "Content-Type: application/json" -d '{"file":"/path/to/file.tsx","lineNumber":10,"contextLines":3}'`
3. If snippet fails, the UI gracefully shows nothing (good fallback)

---

### 2.2 🟡 MEDIUM: "Open in Editor" can fail silently

**File:** `BloomInspectorOverlayPanel.tsx` (lines 1225-1393)

**Issue:** The `handleOpenInEditor` function has many fallback paths. If all fail, there's no user-visible feedback — the button just does nothing.

**Demo prep:**

- Pre-test "Open in Editor" on the component you'll demo
- Have VS Code or your editor already open and configured with the dev server

**Post-presentation improvement:**

```typescript
// Add toast/status feedback
if (!response.ok) {
  setLiveEditStatus('Failed to open in editor');
  return;
}
```

---

### 2.3 🟡 MEDIUM: Panel position can jump unexpectedly

**File:** `BloomInspectorOverlayPanel.tsx` (lines 1395-1431)

**Issue:** The `panelPosition` calculation depends on `panelHeight` state, which is measured after render. On first selection, there can be a frame where the panel appears in the wrong position before settling.

**Mitigation:** The `requestAnimationFrame` in the layout effect (lines 1444-1452) helps, but a very fast tap sequence might cause a flicker.

**Demo tip:** Tap elements deliberately (not rapidly) to avoid visual jitter.

---

### 2.4 🟢 LOW: Hierarchy tree can be very deep

**File:** `BloomInspectorOverlayPanel.tsx` (lines 1529-1535)

**Issue:** For deeply nested components (navigation stacks, nested views), the hierarchy string can overflow the panel.

**Current mitigation:** The panel is scrollable, and hierarchy items are filtered. This is acceptable.

**Demo tip:** If showing hierarchy, pick a moderately nested component, not one 30+ levels deep.

---

## 3. Code Clarity Improvements (Non-Behavioral)

### 3.1 Duplicated utility functions

**Files:** `useBloomInspector.tsx` and `getInspectorDataForViewAtPoint.tsx`

**Issue:** Several functions are duplicated:

- `isBundleUrl()` — identical in both files
- `isNodeModulesPath()` — identical in both files
- `scoreSource()` — identical in both files
- `getSourceFromProps()` — nearly identical

**Recommendation (post-presentation):** Extract to shared `inspectorUtils.ts`:

```typescript
// src/mobileInspector/inspectorUtils.ts
export function isBundleUrl(fileName: string | undefined): boolean {
  /* ... */
}
export function isNodeModulesPath(fileName: string | undefined): boolean {
  /* ... */
}
export function scoreSource(fileName: string | undefined): number {
  /* ... */
}
```

---

### 3.2 Magic numbers in panel sizing

**File:** `BloomInspectorOverlayPanel.tsx`

```typescript
const maxPanelHeight = screenHeight * 0.5;  // line 1400
// ...
if (payloadByTouchID.current.size > 50) {  // suggested fix
```

**Recommendation (post-presentation):** Extract to constants:

```typescript
const PANEL_MAX_HEIGHT_RATIO = 0.5;
const TOUCH_ID_CACHE_LIMIT = 50;
```

---

### 3.3 Long file length

**File:** `BloomInspectorOverlayPanel.tsx` — 2915 lines

**Recommendation (post-presentation):** Consider splitting:

- `BloomInspectorTabs.tsx` — Tab content components
- `BloomInspectorQuickEdit.tsx` — Live edit controls
- `BloomInspectorSnippet.tsx` — Source snippet viewer
- `bloomInspectorHelpers.ts` — Utility functions

---

### 3.4 Debug flags scattered

**Files:** Multiple

```typescript
// useBloomInspector.tsx
const DEBUG_BLOOM_LOGS = false;

// BloomInspectorOverlayPanel.tsx
const DEBUG_BLOOM_LOGS = false;
const DEBUG_OPEN_IN_EDITOR = false;
const DEBUG_SOURCE_SNIPPET = false;
const DEBUG_OWNER_SOURCE = false;
const DEBUG_LIVE_EDIT = false;

// getInspectorDataForViewAtPoint.tsx
const DEBUG_BLOOM_LOGS = false;
```

**Recommendation (post-presentation):** Centralize:

```typescript
// src/mobileInspector/debugConfig.ts
export const DEBUG = {
  BLOOM_LOGS: false,
  OPEN_IN_EDITOR: false,
  SOURCE_SNIPPET: false,
  OWNER_SOURCE: false,
  LIVE_EDIT: false,
} as const;
```

---

## 4. Performance Concerns

### 4.1 🟡 MEDIUM: `propsEntries` sort on every render

**File:** `BloomInspectorOverlayPanel.tsx` (lines 541-546)

```typescript
const propsEntries = useMemo(() => {
  if (!payload?.props) {
    return [];
  }
  return Object.entries(payload.props).sort(([a], [b]) => a.localeCompare(b));
}, [payload]);
```

**Issue:** Sorting happens even when the Props tab isn't visible.

**Safe optimization (post-presentation):**

```typescript
const propsEntries = useMemo(() => {
  if (!payload?.props || activeTab !== 'props') {
    return [];
  }
  return Object.entries(payload.props).sort(([a], [b]) => a.localeCompare(b));
}, [payload, activeTab]);
```

**Note:** For demo purposes, this is fine — props objects are typically small.

---

### 4.2 🟡 MEDIUM: Snippet fetch triggers on every source change

**File:** `BloomInspectorOverlayPanel.tsx` (lines 701-842)

**Issue:** The snippet effect runs whenever `canShowSnippet`, `devServerOrigin`, `sourceFileName`, or `payload?.source` changes. Multiple rapid taps could trigger multiple fetch requests.

**Current mitigation:** The `canceled` flag (line 719) handles this correctly.

**Additional safeguard (post-presentation):** Add debounce:

```typescript
useEffect(() => {
  const timeoutId = setTimeout(() => {
    // ... fetch logic
  }, 150);
  return () => clearTimeout(timeoutId);
}, [dependencies]);
```

---

### 4.3 🟢 LOW: Fiber traversal depth limits

**Files:** `getInspectorDataForViewAtPoint.tsx`

**Good practice observed:** All fiber traversal loops have depth limits:

- `buildComponentStackFromFiber`: `depth < 40`
- `buildHierarchyFromFiber`: `depth < 40`
- `getReactMetadataFromViewData`: `depth < 30`

**Status:** Correctly implemented — prevents infinite loops.

---

## 5. Safe Pre-Presentation Improvements

These are low-risk changes you can make before your presentation:

### 5.1 ✅ Add defensive check in measureInWindow callback

**File:** `useBloomInspector.tsx`

```typescript
// Around line 239, add:
inspectedRef.measureInWindow((left, top, _width, _height) => {
  if (
    typeof left !== 'number' ||
    typeof top !== 'number' ||
    !Number.isFinite(left) ||
    !Number.isFinite(top)
  ) {
    return;
  }
  // ... rest of callback
});
```

**Risk:** None — purely defensive.

---

### 5.2 ✅ Ensure clean state on toggle off

**File:** `BloomInspectorOverlayPanel.tsx`

The `clearSelection()` in the toggle handler (lines 527-533) is good. Verify it's being called:

```typescript
const toggleSub = emitter.addListener(
  'bloomInspectorOverlayToggle',
  (data: { enabled?: boolean }) => {
    setEnabled(Boolean(data?.enabled));
    clearSelection(); // ✅ This is correct
  }
);
```

**Status:** Already implemented correctly.

---

### 5.3 ✅ Add fallback for missing BloomInspectorOverlay module

**File:** `useBloomInspector.tsx` (around line 249)

```typescript
if (pickPayload && NativeModules.BloomInspectorOverlay?.sendPick) {
  // ... existing code
} else if (__DEV__) {
  console.warn('Bloom Inspector: BloomInspectorOverlay module not available');
}
```

**Risk:** None — already has optional chaining; this just adds logging.

---

### 5.4 ✅ Pre-demo checklist items

Add to your demo prep (not code changes):

1. **Restart Metro** fresh before demo
2. **Kill and relaunch** the Expo Go app
3. **Test these specific flows:**
   - Toggle on/off from dev menu
   - Tap a simple View
   - Tap a Text element
   - Use "Open in Editor"
   - View source snippet
   - Navigate between Overview/Source/Hierarchy/Props tabs
4. **Avoid** tapping elements with `pointerEvents="none"` during demo

---

## 6. Summary Table

| Category | Issue                         | Risk      | Action            |
| -------- | ----------------------------- | --------- | ----------------- |
| Bug      | touchID map unbounded         | 🟡 Medium | Post-presentation |
| Bug      | measureInWindow no validation | 🟡 Medium | Safe to fix now   |
| Demo     | Snippet wrong server          | 🔴 High   | Pre-test manually |
| Demo     | Open in Editor silent fail    | 🟡 Medium | Pre-test manually |
| Demo     | Panel position jump           | 🟡 Medium | Tap deliberately  |
| Clarity  | Duplicated utilities          | 🟢 Low    | Post-presentation |
| Clarity  | Long file length              | 🟢 Low    | Post-presentation |
| Perf     | propsEntries sort             | 🟡 Medium | Post-presentation |
| Perf     | Snippet no debounce           | 🟡 Medium | Post-presentation |

---

## 7. Things You Did Well

1. **Excellent fallback handling** — Native fallback when JS payload unavailable
2. **Good touchID merging logic** — Prefers JS payload correctly
3. **Proper cleanup** — Effect cleanup functions with `canceled` flags
4. **Depth-limited traversals** — Prevents infinite loops in fiber walking
5. **Defensive coding** — Lots of optional chaining and null checks
6. **Clear architecture** — Good separation between native tap → JS payload → panel render
7. **Babel plugin design** — Clean `__bloomSource` injection that skips node_modules
8. **Debug log gating** — All debug logs properly gated behind flags

---

---

## 8. Native Code Review (iOS)

### 8.1 ✅ Well-Implemented: Method Swizzling

**File:** `EXBloomInspectorManager.mm` (lines 155-166)

```objc
__attribute__((constructor))
static void EXBloomInspectorSwizzleHostStart(void)
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Method original = class_getInstanceMethod([RCTHost class], @selector(start));
    Method swizzled = class_getInstanceMethod([RCTHost class], @selector(ex_bloomInspector_start));
    if (original && swizzled) {
      method_exchangeImplementations(original, swizzled);
    }
  });
}
```

**Status:** Correctly uses `dispatch_once` to prevent multiple swizzles. The null checks before `method_exchangeImplementations` are good defensive coding.

---

### 8.2 ✅ Well-Implemented: Hit-Testing with Panel Avoidance

**File:** `EXBloomInspectorManager.mm` (lines 214-224)

```objc
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
  EXBloomInspectorOverlayManager *manager = [EXBloomInspectorOverlayManager sharedInstance];
  if (manager.hasPanelFrame) {
    CGPoint pointInWindow = [self convertPoint:point toView:nil];
    if (CGRectContainsPoint(manager.panelFrame, pointInWindow)) {
      return NO;
    }
  }
  return [super pointInside:point withEvent:event];
}
```

**Status:** Excellent — prevents hit-testing on the panel area so users can interact with panel controls.

---

### 8.3 🟡 MEDIUM: Tag Traversal Depth Limit

**File:** `EXBloomInspectorManager.mm` (lines 278-297)

```objc
while (taggedView) {
  // ...
  taggedView = taggedView.superview;
  tagDepth += 1;
  if (tagDepth > 20) {
    break;
  }
}
```

**Status:** Good — has depth limit. Consider logging a warning when hitting the limit (post-presentation).

---

### 8.4 ✅ Well-Implemented: Native Fallback Suppression

**File:** `EXBloomInspectorManager.mm` (lines 429-442)

```objc
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBloomInspectorFallbackDelaySeconds * NSEC_PER_SEC)),
               dispatch_get_main_queue(), ^{
  NSTimeInterval delta = CFAbsoluteTimeGetCurrent() - kBloomInspectorLastJSPickTime;
  if (delta < kBloomInspectorSuppressWindowSeconds) {
    BLOOM_LOG(@"Bloom Log: 16 fallback native payload suppressed (recent JS pick)");
    return;
  }
  // ...
});
```

**Status:** Excellent — the 50ms delay with JS pick suppression prevents duplicate payloads.

---

### 8.5 🟢 LOW: Exception Handling in KVC Paths

**File:** `EXBloomInspectorHelpers.inc` (multiple locations)

```objc
@try {
  id presenter = [host valueForKey:@"surfacePresenter"];
  // ...
} @catch (__unused NSException *exception) {
  // ignore
}
```

**Status:** Correctly uses `@try/@catch` around KVC calls that might fail. This is essential since the code uses private APIs.

---

### 8.6 🟡 MEDIUM: UI Queue Dispatch Pattern

**File:** `EXBloomInspectorHelpers.inc` (lines 122-166)

The code correctly dispatches to the UI queue before accessing `viewForReactTag:` and back to main queue for resolve:

```objc
dispatch_async(uiQueue, ^{
  // ...
  dispatch_async(dispatch_get_main_queue(), ^{
    resolve(@{...});
  });
});
```

**Status:** Correct, but nested dispatches add latency. Acceptable for inspector tooling.

---

### 8.7 ✅ Well-Implemented: Runtime Script Installation

**File:** `EXBloomInspectorRuntimeScript.inc`

The runtime script:

- Properly guards against double-installation (`__bloomInspectorRuntimeInstalled`)
- Wraps DevTools hook methods without breaking existing behavior
- Has timeout-based polling for late-loading bridges
- Correctly handles both TurboModules and legacy NativeModules

**Notable:** The `observeHook()` function wraps `renderers.set` and `inject` methods to track renderer registration — this is a clever way to ensure late-arriving renderers are captured.

---

### 8.8 🟢 LOW: Color Parsing Robustness

**File:** `EXBloomInspectorHelpers.inc` (lines 169-207)

```objc
static UIColor *EXBloomInspectorColorFromString(NSString *value)
{
  // Handles #RRGGBB, #AARRGGBB, and named colors
}
```

**Status:** Good coverage for common color formats. Note: doesn't handle `rgb()` or `rgba()` CSS syntax, but this is acceptable for quick demo.

---

### 8.9 🟡 MEDIUM: Deprecated API Usage

**File:** `EXBloomInspectorHelpers.inc` (lines 60-63)

```objc
if ([presenter respondsToSelector:@selector(findComponentViewWithTag_DO_NOT_USE_DEPRECATED:)]) {
  UIView *view = [(RCTSurfacePresenter *)presenter
      findComponentViewWithTag_DO_NOT_USE_DEPRECATED:reactTag.integerValue];
}
```

**Status:** The API is marked `DO_NOT_USE_DEPRECATED` but it's the only way to get a Fabric view by tag. This is fine for dev tooling but document it in your notes.

---

### 8.10 ✅ Thread Safety

**Files:** `EXBloomInspectorManager.mm`, `EXBloomInspectorHelpers.inc`

- All UI work is dispatched to main queue
- `kBloomInspectorLastJSPickTime` access is main-queue-only (set in `sendPick:`)
- Singleton access uses `dispatch_once`
- UIManager queue is correctly used for view name lookups

**Status:** Thread safety is well-handled throughout.

---

## 9. Runtime Script Deep Dive

### 9.1 ✅ Good: Multiple Fallback Paths

The runtime script (`EXBloomInspectorRuntimeScript.inc`) has excellent fallback logic:

1. First tries `getInspectorDataForViewAtPoint` (best path)
2. Falls back to `getInspectorDataForInstance` if available
3. Final fallback: direct fiber lookup via `tryFiberLookup`

### 9.2 🟡 MEDIUM: Polling Timeout

```javascript
if (attempts > 40) {
  log('54 attach timeout');
  return;
}
g.setTimeout(poll, 250);
```

40 attempts × 250ms = 10 seconds timeout. This is reasonable, but could fail on very slow devices or when debugging.

**Demo tip:** Ensure app is fully loaded before triggering inspector.

---

## 10. Final Verdict

**The code is demo-ready.** The architecture is sound, the main flows work correctly, and edge cases are handled gracefully. Focus your pre-demo time on:

1. Testing the specific flows you'll show
2. Ensuring Metro is running correctly
3. Pre-testing "Open in Editor" with your editor

**Native code quality is high** — good thread safety, proper exception handling, and smart fallback mechanisms.

Good luck with your presentation! 🎉
