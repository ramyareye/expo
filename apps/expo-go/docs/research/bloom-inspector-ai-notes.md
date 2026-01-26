# Bloom Inspector — AI Notes (Claude/Gemini)

Date: 2026-01-26  
Purpose: capture all AI suggestions for later implementation (hybrid live edit, Fabric Text, Fiber/shadow tree access, README snippets, etc.).

---

## Summary (high-level)
- **Fabric Text is not UILabel/UITextView.** `RCTParagraphComponentView` renders via attributed strings / layout manager. UIKit tweaks are fragile and overwritten by React.
- **Public API for ParagraphProps doesn’t exist.** `synchronouslyUpdateViewOnUIThread` works but is overwritten on next render.
- **Viable paths:**  
  1) **KVC attributedText hack** for instant visual feedback (temporary).  
  2) **Fiber injection** (memoizedProps + enqueueForceUpdate) for persistence (dev-only, private API).  
  3) **Injected JS in app runtime** to access Fiber in correct context (preferred vs trying from Expo Go runtime).  
  4) **Overlay approach** (mirror Text overlay) for persistent visuals without modifying app state.

---

## Claude notes (verbatim-ish, with code)

### 1) Fabric Text Props (shape)
```ts
// Fabric expects textAttributes for Text, not plain style props
{
  textAttributes: {
    foregroundColor: 0xFF0000FF, // ARGB int
    fontSize: 18,
    fontWeight: "bold",
  },
  paragraphAttributes: {
    alignment: "center",
    lineBreakMode: "clip"
  },
  // backgroundColor -> parent View, not Text
}
```

### 2) `synchronouslyUpdateViewOnUIThread` is overwritten
```objc
// Timing test:
[view setValue:modifiedText forKey:@"attributedText"];
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC),
               dispatch_get_main_queue(), ^{
  NSAttributedString *check = [view valueForKey:@"attributedText"];
  NSLog(@"Still modified? %d", [check isEqual:modifiedText]);
});
```
Expected: `Still modified? 0` (React overwrote it).

### 3) Dev-only Fiber access by tag
```ts
function getFiberFromTag(tag: number) {
  const instance = findNodeHandle(tag);
  return instance?._reactInternals || instance?._reactInternalFiber;
}

function safeGetFiber(tag: number) {
  try {
    const handle = findNodeHandle(tag);
    if (!handle) return null;
    const fiber = handle._reactInternals || handle._reactInternalFiber;
    if (fiber && fiber.stateNode === handle) return fiber;
  } catch {}
  return null;
}
```

### 4) “Hybrid” approach (native + Fiber)
```ts
const propOverrides = new Map<number, any>();

function applyLiveEdit(reactTag: number, styleOverrides: any) {
  const fiber = safeGetFiber(reactTag);
  if (!fiber) return { ok: false };

  fiber.memoizedProps = {
    ...fiber.memoizedProps,
    style: [fiber.memoizedProps.style, styleOverrides],
  };

  const updater = fiber.updater;
  if (updater?.enqueueForceUpdate) {
    updater.enqueueForceUpdate(fiber);
  }
  return { ok: true };
}
```

### 5) Native KVC attributedText hack (temporary)
```objc
UIView *view = viewRegistry[tag];
if ([view isKindOfClass:NSClassFromString(@"RCTParagraphComponentView")]) {
  NSAttributedString *current = [view valueForKey:@"attributedText"];
  NSMutableAttributedString *modified = [current mutableCopy];
  [modified addAttribute:NSForegroundColorAttributeName value:color range:fullRange];
  [view setValue:modified forKey:@"attributedText"];
  [view setNeedsDisplay];
  [view.layer setNeedsDisplay];
}
```

### 6) Injected JS (inside app runtime)
```ts
// In injected JS (app context)
DeviceEventEmitter.addListener('BLOOM_APPLY_EDIT', ({ tag, props }) => {
  const fiber = getFiberByTag(tag);
  if (!fiber) return;
  fiber.memoizedProps = { ...fiber.memoizedProps, style: [fiber.memoizedProps.style, props.style] };
  fiber.updater?.enqueueForceUpdate?.(fiber);
});
```

### 7) BloomInspectorBridge idea
```objc
// Native bridge from Expo Go to injected JS
RCT_EXPORT_METHOD(applyEditToApp:(NSNumber *)tag
                  componentType:(NSString *)type
                  props:(NSDictionary *)props) {
  [self sendEventWithName:@"BLOOM_APPLY_EDIT" body:@{
    @"tag": tag,
    @"componentType": type,
    @"props": props
  }];
}
```

### 8) README snippet (Claude)
```md
## Live Editing Architecture

Challenge: Fabric Text doesn’t use UILabel.
Solution: Dual-path updates.
- Native: attributedText mutation (instant feedback)
- Fiber: memoizedProps injection (persistence)

Known limitations:
- Uses private APIs
- Edits reset on remount
- Dev-only Fiber access
```

---

## Gemini notes (verbatim-ish, with code)

### 1) Public hooks
No public API for ParagraphProps. Shadow nodes are immutable.

### 2) attributedString prop shape (dangerous but possible)
```json
{
  "attributedString": {
    "string": "The original text content",
    "fragments": [
      {
        "string": "The original text content",
        "textAttributes": {
          "foregroundColor": -65536,
          "fontSize": 20
        }
      }
    ]
  }
}
```

### 3) Shadow tree updates via Fiber
```ts
DeviceEventEmitter.addListener('Bloom:ApplyEdit', ({ tag, styleOverrides }) => {
  const fiber = findFiberByTag(tag);
  if (fiber?.updater?.enqueueForceUpdate) {
    const existingStyle = fiber.memoizedProps.style || {};
    fiber.memoizedProps.style = [existingStyle, styleOverrides];
    fiber.updater.enqueueForceUpdate(fiber);
  }
});
```

### 4) findFiberByTag (in injected JS)
```ts
function findFiberByTag(targetTag) {
  const nativeInstance = ReactNative.findNodeHandle(targetTag);
  return nativeInstance?._reactInternals ||
         nativeInstance?._reactInternalFiber ||
         nativeInstance?.__reactFiber$;
}
```

### 5) Why this matters
- React reconciler will re‑create ParagraphShadowNode and re‑render text with new props.
- This is the only path that “sticks” across renders.

---

## Questions answered

**Q: Can we edit shadow node directly?**  
Not directly. You can **trigger a new ShadowNode** by updating Fiber props and forcing reconciliation.

**Q: Does `synchronouslyUpdateViewOnUIThread` work for text?**  
Only ephemeral; overwritten on next render.

**Q: Is Fiber injection safe?**  
Dev-only, private API. Suitable for inspector tooling in Expo Go dev context.

**Q: Public hook for ParagraphProps?**  
No. `UIManager.updateView` doesn’t support Fabric Text props. Only internal/gray‑area hacks (KVC or Fiber injection).

**Q: Can we edit shadow node directly?**  
Not directly from JS. You can trigger a new ShadowNode by updating Fiber props and forcing reconciliation.

---

## Implementation ideas (later)

### A) Hybrid (recommended)
1) Native KVC: instant visual feedback (Text).  
2) Injected JS: Fiber update for persistence.  
3) Optional: overlay to avoid flicker.

### B) Pure injected JS approach (no native hacks)
- Inject JS into app runtime; use event emitter to apply prop overrides.
- Use `enqueueForceUpdate` to re‑reconcile.

---

## TODOs if we continue
- Create `BloomInspectorBridge` emitter (native → app runtime).
- Inject JS handler that updates Fiber in app runtime.
- Add “Live Edit (persistent)” toggle in UI (warn about dev‑only).
- Formalize “Text is temporary” messaging if only KVC is used.

---

## Additional notes (follow‑up)

### DevTools hook / renderer lookup
```ts
// In injected JS (app context)
const hook = global.__REACT_DEVTOOLS_GLOBAL_HOOK__;
for (const renderer of hook?.renderers?.values?.() ?? []) {
  // renderer.findFiberByHostInstance / renderer.findHostInstanceByFiber
  // or traverse renderer roots to locate a fiber by native tag
}
```

### Expo Go‑safe inspector data path
```ts
// Native / DevSettings can return inspector data by tag (dev only)
// Used by RN inspector menu; useful for source + hierarchy
NativeModules.DevSettings.getInspectorDataForViewTag?.(reactTag);
```

### Injected JS bridge (best context)
```ts
// Native emits → injected JS handles
DeviceEventEmitter.addListener('BLOOM_APPLY_EDIT', ({ tag, props }) => {
  const fiber = getFiberByTag(tag);
  if (!fiber) return;
  fiber.memoizedProps = {
    ...fiber.memoizedProps,
    style: [fiber.memoizedProps.style, props.style],
  };
  fiber.updater?.enqueueForceUpdate?.(fiber);
});
```

### Demo framing (hybrid)
- Native/KVC = instant feedback (temporary).  
- Injected JS/Fiber = persistence across renders.  
- Optional overlay to avoid flicker.
