# Bloom Inspector - Video Presentation Plan

This file contains:
- A 6-8 minute plan
- A 3-4 minute plan
- A concise speaking script
- On-screen checklist

## On-screen checklist (use as a run sheet)
- Dev Menu toggle ("bloom-inspector")
- Highlight box on tap
- Overview tab
- Props tab (search + copy)
- Source tab (file/line + Open in editor)
- Snippet preview (/bloom-source-snippet)
- Hierarchy tab (expand tree)
- Edit tab (View background/opacity; Text color/align/underline)
- Known limitations slide
- Next steps slide

## Plan A: 6-8 minute video

0:00-0:20 - Title + goal
- Title card: "Bloom Inspector in Expo Go"
- One-liner: in-app element picker + props + source

0:20-1:00 - Architecture overview (1 slide)
- Tap -> native event -> JS DevTools hook -> overlay panel
- Mention JS payload preferred, native fallback retained

1:00-3:30 - Core demo
- Dev Menu -> enable "bloom-inspector"
- Tap a View: highlight + Overview tab
- Props tab: search + copy
- Source tab: file + line + Open in editor
- Snippet preview

3:30-4:30 - Advanced features
- Hierarchy tab (expand a branch)
- Edit tab: View background/opacity
- Edit tab: Text color/align/underline

4:30-5:30 - Implementation notes
- __bloomSource/__source injected via Babel in dev
- JS payload computed via DevTools hook
- Text edits via JS runtime override for Fabric

5:30-6:30 - Limitations + next steps
- pointerEvents="none" not selectable
- library/native source attribution may point into node_modules
- empty componentStack fallback missing
- stale selection after refresh

6:30-7:00 - Wrap
- "Core UX works; next steps are polish/hardening"

## Plan B: 3-4 minute video

0:00-0:15 - Title + goal

0:15-0:35 - Architecture one-liner
- Tap -> native event -> JS payload -> overlay panel

0:35-2:30 - Core demo (fast)
- Toggle
- Tap + highlight
- Props search + copy
- Source + Open in editor
- Snippet preview

2:30-3:10 - One advanced feature
- Hierarchy tab OR Edit tab (pick one)

3:10-3:40 - Limitations + next steps
- 2 bullets + 2 next steps

3:40-4:00 - Wrap

## Speaking script (concise)

"Hi, this is the Bloom Inspector in Expo Go. The goal is a fast in-app element picker that shows props and jumps to source.

Under the hood, a native overlay window captures taps and draws the highlight. It emits a bloomInspectorTap event, JS listens and uses the React DevTools hook to compute the payload, then forwards it to the overlay panel. JS payloads are preferred, with a native fallback for resilience.

Let me show the flow. I open the Dev Menu and enable bloom-inspector. Tapping a view highlights it and the panel shows Overview. In Props, I can search and copy. In Source, I get file and line, and Open in editor uses /open-stack-frame. The snippet preview comes from /bloom-source-snippet.

For advanced features, the Hierarchy tab shows the parent-child chain, and the Edit tab can apply view styles like background/opacity. For text, styles go through a JS runtime override so Fabric can recompute the attributed string.

Known limitations: pointerEvents=none elements aren’t selectable, library/native components can map into node_modules, some nodes have empty componentStack, and selection can become stale after refresh. Next steps are to polish source attribution, add a componentStack fallback, and handle stale selections.

That’s it - the core UX is working, and the remaining work is mostly hardening and polish."
