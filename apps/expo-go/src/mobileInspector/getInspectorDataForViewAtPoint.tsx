import type { InspectorViewData } from './inspectorTypes';

type ReactRenderer = {
  getFiberRoots?: () => Set<{ current?: unknown }>;
  rendererConfig?: {
    getInspectorDataForViewAtPoint?: (
      inspectedView: unknown,
      locationX: number,
      locationY: number,
      callback: (viewData: InspectorViewData) => void
    ) => void;
  };
};

type ReactDevToolsHook = {
  renderers: Map<number, ReactRenderer>;
  on: (event: 'renderer', handler: (payload: { renderer: ReactRenderer }) => void) => void;
  getFiberRoots?: (rendererID: number) => Set<{ current?: unknown }>;
};

const reactDevToolsHook =
  (globalThis as { __REACT_DEVTOOLS_GLOBAL_HOOK__?: ReactDevToolsHook })
    .__REACT_DEVTOOLS_GLOBAL_HOOK__ ??
  (globalThis as { window?: { __REACT_DEVTOOLS_GLOBAL_HOOK__?: ReactDevToolsHook } }).window
    ?.__REACT_DEVTOOLS_GLOBAL_HOOK__;

if (!reactDevToolsHook) {
  // In production / no DevTools, you probably want to no-op instead of throw
  console.warn(
    '[Inspector] React DevTools hook not found. getInspectorDataForViewAtPoint will be a no-op.'
  );
}

const renderers: ReactRenderer[] = reactDevToolsHook
  ? Array.from(reactDevToolsHook.renderers.values())
  : [];

const DEBUG_BLOOM_LOGS = false;

if (reactDevToolsHook?.on && typeof reactDevToolsHook.on === 'function') {
  reactDevToolsHook.on('renderer', ({ renderer }: { renderer: ReactRenderer }) => {
    renderers.push(renderer);
  });
}

function validateRenderers(): void {
  if (!renderers.length) {
    console.warn(
      '[Inspector] No React Native renderers found on DevTools hook. Inspector may not work.'
    );
  }
}

export function getInspectorDataForViewAtPoint(
  inspectedView: unknown,
  locationX: number,
  locationY: number,
  callback: (viewData: InspectorViewData) => boolean
) {
  if (!reactDevToolsHook) {
    return;
  }

  validateRenderers();

  let shouldBreak = false;
  for (const renderer of renderers) {
    if (shouldBreak) break;

    const fn = renderer?.rendererConfig?.getInspectorDataForViewAtPoint;
    if (typeof fn === 'function') {
      fn(inspectedView, locationX, locationY, (viewData: InspectorViewData) => {
        if (viewData && viewData.hierarchy && viewData.hierarchy.length > 0) {
          shouldBreak = callback(viewData);
        }
      });
    }
  }
}

type Fiber = {
  tag?: number;
  return?: Fiber | null;
  child?: Fiber | null;
  sibling?: Fiber | null;
  type?: unknown;
  elementType?: unknown;
  stateNode?: { _nativeTag?: number } | null;
  memoizedProps?: Record<string, unknown>;
  _debugSource?: { fileName?: string; lineNumber?: number; columnNumber?: number };
  _debugOwner?: Fiber | null;
};

type ReactInspectorMetadata = {
  componentStack?: string;
  source?: { fileName?: string; lineNumber?: number; columnNumber?: number };
  hierarchy?: { name: string }[];
  props?: Record<string, unknown>;
};

const FiberTags = {
  FunctionComponent: 0,
  ClassComponent: 1,
  IndeterminateComponent: 2,
  HostRoot: 3,
  HostComponent: 5,
  HostText: 6,
  ForwardRef: 11,
  MemoComponent: 14,
  SimpleMemoComponent: 15,
};

function isUserComponent(fiber: Fiber | null | undefined): boolean {
  if (!fiber || fiber.tag == null) {
    return false;
  }
  return (
    fiber.tag === FiberTags.FunctionComponent ||
    fiber.tag === FiberTags.ClassComponent ||
    fiber.tag === FiberTags.ForwardRef ||
    fiber.tag === FiberTags.MemoComponent ||
    fiber.tag === FiberTags.SimpleMemoComponent ||
    fiber.tag === FiberTags.IndeterminateComponent
  );
}

function getComponentName(fiber: Fiber | null | undefined): string {
  if (!fiber) {
    return 'Unknown';
  }
  const type = (fiber.elementType ?? fiber.type) as
    | { displayName?: string; name?: string; type?: { displayName?: string; name?: string } }
    | string
    | undefined;
  if (typeof type === 'string') {
    return type;
  }
  if (type && typeof type === 'object') {
    if (type.displayName || type.name) {
      return type.displayName || type.name || 'Unknown';
    }
    if (type.type && (type.type.displayName || type.type.name)) {
      return type.type.displayName || type.type.name || 'Unknown';
    }
  }
  return fiber.tag != null ? `Fiber(${fiber.tag})` : 'Unknown';
}

function getFiberName(fiber: Fiber | null | undefined): string {
  if (!fiber) {
    return 'Unknown';
  }
  const type = (fiber.elementType ?? fiber.type) as
    | { displayName?: string; name?: string; render?: { displayName?: string; name?: string } }
    | (((...args: any[]) => any) & { displayName?: string })
    | string
    | undefined;
  if (typeof type === 'string') {
    return type;
  }
  if (typeof type === 'function') {
    return type.displayName || type.name || 'Anonymous';
  }
  if (type && typeof type === 'object') {
    if (type.displayName) {
      return type.displayName;
    }
    if (type.render && (type.render.displayName || type.render.name)) {
      return type.render.displayName || type.render.name || 'Anonymous';
    }
    if (
      (type as { type?: { displayName?: string; name?: string } }).type &&
      ((type as { type?: { displayName?: string; name?: string } }).type?.displayName ||
        (type as { type?: { displayName?: string; name?: string } }).type?.name)
    ) {
      return (
        (type as { type?: { displayName?: string; name?: string } }).type?.displayName ||
        (type as { type?: { displayName?: string; name?: string } }).type?.name ||
        'Anonymous'
      );
    }
  }
  return getComponentName(fiber);
}

function getCodeInfoFromFiber(
  fiber: Fiber | null | undefined
): ReactInspectorMetadata['source'] | null {
  if (!fiber || !fiber._debugSource) {
    return null;
  }
  const source = fiber._debugSource;
  return {
    fileName: source.fileName,
    lineNumber: source.lineNumber,
    columnNumber: source.columnNumber ?? 1,
  };
}

function getSourceFromProps(
  props: Record<string, unknown> | null | undefined
): ReactInspectorMetadata['source'] | null {
  if (!props) {
    return null;
  }
  const candidate = (props.__bloomSource ?? props.__source) as
    | { fileName?: unknown; lineNumber?: unknown; columnNumber?: unknown }
    | undefined;
  if (!candidate || typeof candidate !== 'object') {
    return null;
  }
  const fileName = candidate.fileName;
  const lineNumber = candidate.lineNumber;
  const columnNumber = candidate.columnNumber;
  if (typeof fileName !== 'string' || typeof lineNumber !== 'number') {
    return null;
  }
  return {
    fileName,
    lineNumber,
    columnNumber: typeof columnNumber === 'number' ? columnNumber : 1,
  };
}

function isBundleUrl(fileName: string | undefined): boolean {
  if (!fileName) {
    return false;
  }
  if (fileName.startsWith('http://') || fileName.startsWith('https://')) {
    return true;
  }
  return fileName.includes('index.bundle');
}

function isNodeModulesPath(fileName: string | undefined): boolean {
  if (!fileName) {
    return false;
  }
  return fileName.includes('/node_modules/');
}

function scoreSource(fileName: string | undefined): number {
  if (!fileName) {
    return -1;
  }
  let score = 0;
  if (!isBundleUrl(fileName)) {
    score += 2;
  }
  if (!isNodeModulesPath(fileName)) {
    score += 3;
  }
  if (fileName.includes('/apps/')) {
    score += 1;
  }
  return score;
}

function findNearestUserFiberWithSource(fiber: Fiber | null | undefined) {
  let current: Fiber | null | undefined = fiber;
  while (current) {
    const codeInfo = getCodeInfoFromFiber(current);
    if (codeInfo && isUserComponent(current)) {
      return { fiber: current, codeInfo, name: getFiberName(current) };
    }
    if (current._debugOwner) {
      const ownerInfo = getCodeInfoFromFiber(current._debugOwner);
      if (ownerInfo && isUserComponent(current._debugOwner)) {
        return {
          fiber: current._debugOwner,
          codeInfo: ownerInfo,
          name: getFiberName(current._debugOwner),
        };
      }
    }
    current = current.return;
  }
  return null;
}

function buildComponentStackFromFiber(fiber: Fiber | null | undefined): string[] {
  const names: string[] = [];
  let current: Fiber | null | undefined = fiber;
  let depth = 0;
  while (current && depth < 40) {
    if (isUserComponent(current)) {
      names.push(getFiberName(current));
    }
    current = current.return;
    depth += 1;
  }
  if (!names.length && fiber) {
    current = fiber;
    depth = 0;
    while (current && depth < 40) {
      names.push(getFiberName(current));
      current = current.return;
      depth += 1;
    }
  }
  return names.reverse();
}

function buildHierarchyFromFiber(fiber: Fiber | null | undefined): { name: string }[] {
  const items: { name: string }[] = [];
  let current: Fiber | null | undefined = fiber;
  let depth = 0;
  while (current && depth < 40) {
    items.push({ name: getComponentName(current) });
    current = current.return;
    depth += 1;
  }
  return items.reverse();
}

function getFiberFromInstance(instance: unknown): Fiber | null {
  const candidate = instance as
    | (Fiber & {
        _reactInternals?: Fiber;
        _internalFiberInstanceHandleDEV?: Fiber;
        _internalInstanceHandle?: Fiber;
        getNode?: () => unknown;
      })
    | null;
  if (!candidate) {
    return null;
  }
  if (candidate._reactInternals) {
    return candidate._reactInternals;
  }
  if (candidate._internalFiberInstanceHandleDEV) {
    return candidate._internalFiberInstanceHandleDEV;
  }
  if (candidate._internalInstanceHandle) {
    return candidate._internalInstanceHandle;
  }
  try {
    for (const key of Object.keys(candidate)) {
      if (key.startsWith('__reactFiber$') || key.startsWith('__reactInternalInstance$')) {
        return (candidate as Record<string, Fiber>)[key];
      }
    }
  } catch {
    // ignore
  }
  if (candidate.getNode) {
    try {
      const node = candidate.getNode();
      if (node) {
        return getFiberFromInstance(node);
      }
    } catch {
      // ignore
    }
  }
  return null;
}

function getFiberFromViewData(viewData: unknown): Fiber | null {
  const data = viewData as {
    closestInstance?: unknown;
    inspected?: unknown;
    closestPublicInstance?: unknown;
    publicInstance?: unknown;
  } | null;
  if (!data) {
    return null;
  }
  const candidate = data.closestInstance ?? data.inspected ?? null;
  if (candidate && (candidate as Fiber).tag != null && (candidate as Fiber).return !== undefined) {
    return candidate as Fiber;
  }
  const publicInstance = data.closestPublicInstance ?? data.publicInstance ?? null;
  if (
    publicInstance &&
    (publicInstance as { _internalInstanceHandle?: Fiber })._internalInstanceHandle
  ) {
    return (publicInstance as { _internalInstanceHandle?: Fiber })._internalInstanceHandle ?? null;
  }
  if (candidate && (candidate as { _internalInstanceHandle?: Fiber })._internalInstanceHandle) {
    return (candidate as { _internalInstanceHandle?: Fiber })._internalInstanceHandle ?? null;
  }
  if (candidate) {
    return getFiberFromInstance(candidate);
  }
  if (publicInstance) {
    return getFiberFromInstance(publicInstance);
  }
  return null;
}

function extractSourceFromComponentStack(
  componentStack: string | undefined
): ReactInspectorMetadata['source'] | null {
  if (!componentStack) {
    return null;
  }
  const lines = componentStack.split('\n');
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) {
      continue;
    }
    let name = line;
    if (name.startsWith('at ')) {
      name = name.slice(3);
    }
    const parenIndex = name.indexOf(' (');
    if (parenIndex > 0) {
      name = name.slice(0, parenIndex);
    }
    name = name.trim();
    if (!name || isHostComponentName(name)) {
      continue;
    }
    let match = line.match(/\((.*):(\d+):(\d+)\)$/);
    if (!match) {
      match = line.match(/@(.*):(\d+):(\d+)$/);
    }
    if (match) {
      return {
        fileName: match[1],
        lineNumber: Number(match[2]),
        columnNumber: Number(match[3]),
      };
    }
  }
  return null;
}

function isHostComponentName(name: string): boolean {
  if (!name) {
    return true;
  }
  if (
    name === 'View' ||
    name === 'Text' ||
    name === 'Image' ||
    name === 'ScrollView' ||
    name === 'Pressable'
  ) {
    return true;
  }
  if (name === 'RCTView' || name === 'RCTText' || name === 'RCTParagraphComponentView') {
    return true;
  }
  return /^(RCT|UI|RN|RNC)/.test(name);
}

function findFiberByNativeTag(fiber: Fiber | null | undefined, tag: number): Fiber | null {
  if (!fiber) {
    return null;
  }
  if (fiber.stateNode && fiber.stateNode._nativeTag === tag) {
    return fiber;
  }
  let child = fiber.child;
  while (child) {
    const found = findFiberByNativeTag(child, tag);
    if (found) {
      return found;
    }
    child = child.sibling ?? null;
  }
  return null;
}

function tryFiberLookup(viewTag: number): Fiber | null {
  for (const renderer of renderers) {
    if (renderer && typeof renderer.getFiberRoots === 'function') {
      try {
        const roots = renderer.getFiberRoots();
        if (roots && roots.size) {
          for (const root of roots.values()) {
            if (root && root.current) {
              const found = findFiberByNativeTag(root.current as Fiber, viewTag);
              if (found) {
                return found;
              }
            }
          }
        }
      } catch {
        // ignore
      }
    }
  }
  if (reactDevToolsHook && typeof reactDevToolsHook.getFiberRoots === 'function') {
    try {
      const ids = Array.from(reactDevToolsHook.renderers.keys());
      const rendererIDs = ids.length ? ids : [1];
      for (const id of rendererIDs) {
        const hookRoots = reactDevToolsHook.getFiberRoots(id);
        if (!hookRoots || !hookRoots.size) {
          continue;
        }
        for (const hookRoot of hookRoots.values()) {
          if (hookRoot && hookRoot.current) {
            const hookFound = findFiberByNativeTag(hookRoot.current as Fiber, viewTag);
            if (hookFound) {
              return hookFound;
            }
          }
        }
      }
    } catch {
      // ignore
    }
  }
  return null;
}

export function getReactMetadataFromViewData(
  viewData: InspectorViewData | null | undefined,
  viewTag?: number
): ReactInspectorMetadata {
  if (!viewData) {
    return {};
  }
  const data = viewData as InspectorViewData & {
    componentStack?: string;
    closestInstance?: unknown;
    inspected?: unknown;
    closestPublicInstance?: unknown;
    publicInstance?: unknown;
  };
  const rawStack = data.componentStack;
  let fiber = getFiberFromViewData(data);
  if (!fiber && typeof viewTag === 'number') {
    fiber = tryFiberLookup(viewTag);
  }

  const metadata: ReactInspectorMetadata = {};
  if (fiber) {
    const stackNames = buildComponentStackFromFiber(fiber);
    const nearestFiber = findNearestUserFiberWithSource(fiber);
    const hierarchy = buildHierarchyFromFiber(fiber);
    const candidateSources: ReactInspectorMetadata['source'][] = [];
    const fiberSource = nearestFiber ? nearestFiber.codeInfo : getCodeInfoFromFiber(fiber);
    const propsSource =
      getSourceFromProps(nearestFiber?.fiber?.memoizedProps) ??
      getSourceFromProps(fiber.memoizedProps);
    // Prefer the raw stack from the renderer (often includes file/line info needed for "Open in editor").
    if (rawStack) {
      metadata.componentStack = rawStack;
    } else if (stackNames.length) {
      metadata.componentStack = stackNames.join('\n');
    }
    if (fiberSource) {
      candidateSources.push(fiberSource);
    }
    if (propsSource) {
      candidateSources.push(propsSource);
    }
    if (DEBUG_BLOOM_LOGS) {
      const fiberFile = fiberSource?.fileName ?? 'none';
      const propsFile = propsSource?.fileName ?? 'none';
      const nearestName = nearestFiber?.name ?? 'none';
      console.info(
        `Bloom Log: 38-6 source scan nearest=${nearestName} fiber=${fiberFile} props=${propsFile}`
      );
    }
    if (hierarchy.length) {
      metadata.hierarchy = hierarchy;
    }
    if (nearestFiber?.fiber?.memoizedProps) {
      metadata.props = nearestFiber.fiber.memoizedProps as Record<string, unknown>;
    }

    let current: Fiber | null | undefined = fiber;
    let depth = 0;
    while (current && depth < 30) {
      const currentSource = getCodeInfoFromFiber(current);
      if (currentSource) {
        candidateSources.push(currentSource);
      }
      const currentPropsSource = getSourceFromProps(current.memoizedProps);
      if (currentPropsSource) {
        candidateSources.push(currentPropsSource);
      }
      if (current._debugOwner) {
        const ownerSource = getCodeInfoFromFiber(current._debugOwner);
        if (ownerSource) {
          candidateSources.push(ownerSource);
        }
        const ownerPropsSource = getSourceFromProps(current._debugOwner.memoizedProps);
        if (ownerPropsSource) {
          candidateSources.push(ownerPropsSource);
        }
      }
      current = current.return;
      depth += 1;
    }

    if (candidateSources.length) {
      let bestSource = candidateSources[0] ?? null;
      let bestScore = scoreSource(bestSource?.fileName);
      for (const source of candidateSources) {
        const score = scoreSource(source?.fileName);
        if (score > bestScore) {
          bestScore = score;
          bestSource = source ?? null;
        }
      }
      if (bestSource) {
        metadata.source = bestSource;
      }
    }
  }
  if (!metadata.source) {
    const stackSource = extractSourceFromComponentStack(rawStack || metadata.componentStack);
    if (stackSource) {
      metadata.source = stackSource;
    }
  }
  if (DEBUG_BLOOM_LOGS) {
    const stackSource = extractSourceFromComponentStack(rawStack || metadata.componentStack);
    const chosen = metadata.source?.fileName ?? 'none';
    console.info(
      `Bloom Log: 38-5 source candidates stack=${stackSource?.fileName ?? 'none'} chosen=${chosen}`
    );
  }
  return metadata;
}

// const renderers1 = [
//   {
//     bundleType: 1,
//     currentDispatcherRef: {
//       A: null,
//       H: [Object],
//       S: [],
//       T: null,
//       V: null,
//       actQueue: null,
//       didScheduleLegacyUpdate: false,
//       didUsePromise: false,
//       getCurrentStack: null,
//       isBatchingLegacy: false,
//       recentlyCreatedOwnerStacks: 687,
//       thrownErrors: [Array],
//     },
//     getCurrentFiber: [],
//     getLaneLabelMap: [],
//     injectProfilingHooks: [],
//     overrideHookState: [],
//     overrideHookStateDeletePath: [],
//     overrideHookStateRenamePath: [],
//     overrideProps: [],
//     overridePropsDeletePath: [],
//     overridePropsRenamePath: [],
//     reconcilerVersion: '19.1.0',
//     rendererConfig: {
//       getInspectorDataForInstance: [],
//       getInspectorDataForViewAtPoint: [],
//       getInspectorDataForViewTag: [],
//     },
//     rendererPackageName: 'react-native-renderer',
//     scheduleRefresh: [],
//     scheduleRoot: [],
//     scheduleUpdate: [],
//     setErrorHandler: [],
//     setRefreshHandler: [],
//     setSuspenseHandler: [],
//     version: '19.1.0',
//   },
//   {
//     bundleType: 1,
//     currentDispatcherRef: {
//       A: null,
//       H: [Object],
//       S: [],
//       T: null,
//       V: null,
//       actQueue: null,
//       didScheduleLegacyUpdate: false,
//       didUsePromise: false,
//       getCurrentStack: null,
//       isBatchingLegacy: false,
//       recentlyCreatedOwnerStacks: 687,
//       thrownErrors: [Array],
//     },
//     getCurrentFiber: [],
//     getLaneLabelMap: [],
//     injectProfilingHooks: [],
//     overrideHookState: [],
//     overrideHookStateDeletePath: [],
//     overrideHookStateRenamePath: [],
//     overrideProps: [],
//     overridePropsDeletePath: [],
//     overridePropsRenamePath: [],
//     reconcilerVersion: '19.1.0',
//     rendererConfig: {
//       getInspectorDataForInstance: [],
//       getInspectorDataForViewAtPoint: [],
//       getInspectorDataForViewTag: [],
//     },
//     rendererPackageName: 'react-native-renderer',
//     scheduleRefresh: [],
//     scheduleRoot: [],
//     scheduleUpdate: [],
//     setErrorHandler: [],
//     setRefreshHandler: [],
//     setSuspenseHandler: [],
//     version: '19.1.0',
//   },
// ];
