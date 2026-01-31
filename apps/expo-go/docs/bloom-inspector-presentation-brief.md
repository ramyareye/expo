# Bloom Inspector - Presentation Brief

## Goal
Build an iOS-only, in-app element inspector in Expo Go that lets users pick a UI element, inspect props, and jump to source.

## Scope shipped
- Element picker toggle (Dev Menu -> "bloom-inspector")
- Native overlay window for hit-testing + highlight
- Overlay panel (RN surface) with tabs: Overview, Source, Hierarchy, Props, Raw, Edit
- Props list with search + copy
- Source location with "Open in editor" via /open-stack-frame
- Source snippet preview via /bloom-source-snippet
- Live edit (experimental): View styles via native apply; Text styles via JS runtime override

## Architecture (tap -> panel)
1) Native overlay hit-tests and emits bloomInspectorTap (x, y, touchID).
2) JS listens, calls React DevTools hook getInspectorDataForViewAtPoint, builds payload.
3) JS sends payload to BloomInspectorOverlay.sendPick.
4) Overlay panel merges payloads by touchID and renders details.

## Key implementation decisions
- Prefer JS-derived payloads for React stack/source/props; keep native fallback for resilience.
- Source attribution prefers __bloomSource/__source from Babel transforms; fall back to Fiber/debug info.
- Live Edit: View updates use native apply; Text styles use JS runtime override to let Fabric recompute text.

## Limitations / known issues (post-presentation)
- Elements with pointerEvents="none" cannot be selected.
- Source attribution for library/native components can point into node_modules.
- Some nodes have empty componentStack, so names/source can be missing.
- Selection can become stale after refresh or code changes.
- JS payload forwarding does not fall back to BloomInspector.sendPick when the overlay module is missing.

## Demo checklist
- Start dev server and launch the native-component-list test app.
- Open Dev Menu and enable "bloom-inspector".
- Tap a component: show highlight, props, hierarchy, and source.
- Trigger "Open in editor" and show snippet preview.
- Show live edit on View (background/opacity) and Text styles (color/align/underline).

## Testing notes
- Test at least one screen per navigator to confirm hierarchy/source render correctly.
- Verify source paths resolve to local *.tsx when __bloomSource is present.
- Confirm snippet endpoint is served by Metro (typically :8081).

## Next steps (post-presentation)
- Decide and polish source attribution for library/native components (ownerSource heuristic).
- Add componentStack empty fallback.
- Handle stale selection after refresh.
- Add JS payload fallback via BloomInspector.sendPick (multi-runtime case).
