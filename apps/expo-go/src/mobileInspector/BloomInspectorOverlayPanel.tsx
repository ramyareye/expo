import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Alert,
  Clipboard,
  DeviceEventEmitter,
  Dimensions,
  NativeEventEmitter,
  NativeModules,
  Pressable,
  processColor,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

type Frame = { left: number; top: number; width: number; height: number };
type HierarchyItem = { name: string };
type PickPayload = {
  frame?: Frame;
  hierarchy?: HierarchyItem[];
  props?: Record<string, unknown>;
  selectedIndex?: number;
  componentStack?: string;
  source?: { fileName?: string; lineNumber?: number; columnNumber?: number };
  ownerSource?: { fileName?: string; lineNumber?: number; columnNumber?: number };
  touchID?: number;
  payloadSource?: 'js' | 'native';
};

type SourceSnippet = {
  file: string;
  lineNumber: number;
  startLine: number;
  endLine: number;
  lines: string[];
};

type SourceSnippetLine = { lineNumber: number; text: string; isCurrent: boolean };

type LiveEditTargetInfo =
  | { hasTarget: false }
  | {
      hasTarget: true;
      reactTag?: number;
      viewName?: string;
      mode?: 'native' | 'ref' | 'fabric';
      reason?: string;
      availableTags?: number[];
      componentViewClass?: string | null;
    }
  | {
      hasTarget: boolean;
      name?: string | null;
      nativeTag?: number | null;
      mode?: string;
      reason?: string;
      availableTags?: number[];
      componentViewClass?: string | null;
    };

type LiveEditApplyResult =
  | boolean
  | {
      ok: boolean;
      reason?: string;
      reactTag?: number;
      viewName?: string;
      mode?: string;
      componentViewClass?: string | null;
      componentViewFrame?: { x: number; y: number; width: number; height: number };
      componentViewBounds?: { x: number; y: number; width: number; height: number };
      componentViewHidden?: boolean;
      componentViewAlpha?: number;
      componentViewBackgroundColor?: string | null;
    };

const DEBUG_BLOOM_LOGS = false;
const DEBUG_OPEN_IN_EDITOR = false;
const DEBUG_SOURCE_SNIPPET = false;
const DEBUG_OWNER_SOURCE = false;
const DEBUG_LIVE_EDIT = false;

if (__DEV__) {
  (globalThis as any).__bloomInspectorDebugLiveEdit = true;
  (globalThis as any).__bloomInspectorDebugOwnerSource = true;
}

function ensureLiveEditRuntime() {
  try {
    const g = globalThis as any;
    const getFabricManager = () => g.nativeFabricUIManager || g.__nativeFabricUIManager || null;
    const canSetViaFabric = (target: any) => {
      const tag = target?._nativeTag ?? target?.nativeTag ?? null;
      const manager = getFabricManager();
      return Boolean(
        typeof tag === 'number' && manager && typeof manager.setNativeProps === 'function'
      );
    };

    if (typeof g.__bloomInspectorClearNativePropsTarget !== 'function') {
      g.__bloomInspectorClearNativePropsTarget = () => {
        g.__bloomInspectorLastPublicInstance = null;
      };
    }
    if (typeof g.__bloomInspectorHasNativePropsTarget !== 'function') {
      g.__bloomInspectorHasNativePropsTarget = () => {
        const target = g.__bloomInspectorLastPublicInstance;
        return Boolean(
          (target && typeof target.setNativeProps === 'function') ||
            (target && canSetViaFabric(target))
        );
      };
    }
    if (typeof g.__bloomInspectorGetNativePropsTargetInfo !== 'function') {
      g.__bloomInspectorGetNativePropsTargetInfo = () => {
        const target = g.__bloomInspectorLastPublicInstance;
        if (!target || !(typeof target.setNativeProps === 'function' || canSetViaFabric(target))) {
          return { hasTarget: false };
        }
        const name = target?.constructor?.name ?? null;
        const nativeTag = target?._nativeTag ?? target?.nativeTag ?? null;
        return {
          hasTarget: true,
          name,
          nativeTag,
          mode: typeof target.setNativeProps === 'function' ? 'ref' : 'fabric',
        };
      };
    }
    if (typeof g.__bloomInspectorApplyNativeProps !== 'function') {
      g.__bloomInspectorApplyNativeProps = (nextProps: unknown) => {
        const target = g.__bloomInspectorLastPublicInstance;
        if (!target) {
          return false;
        }
        if (!nextProps || typeof nextProps !== 'object') {
          return false;
        }
        if (typeof target.setNativeProps === 'function') {
          target.setNativeProps(nextProps);
          return true;
        }
        const manager = getFabricManager();
        const tag = target?._nativeTag ?? target?.nativeTag ?? null;
        if (typeof tag === 'number' && manager && typeof manager.setNativeProps === 'function') {
          manager.setNativeProps(tag, nextProps);
          return true;
        }
        return false;
      };
    }
  } catch {
    // ignore
  }
}

const INTERNAL_COMPONENT_NAMES = new Set([
  'Anonymous',
  'Unknown',
  'ContextProvider',
  'ContextConsumer',
  'Provider',
  'Consumer',
  'Fragment',
  'Suspense',
  'Profiler',
  'StrictMode',
]);

function looksLikeStyleObject(value: unknown): value is Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return false;
  }
  const keys = Object.keys(value);
  if (!keys.length) {
    return false;
  }
  const styleKeys = new Set([
    'backgroundColor',
    'color',
    'opacity',
    'borderColor',
    'borderWidth',
    'borderRadius',
    'padding',
    'paddingHorizontal',
    'paddingVertical',
    'paddingLeft',
    'paddingRight',
    'paddingTop',
    'paddingBottom',
    'margin',
    'marginHorizontal',
    'marginVertical',
    'marginLeft',
    'marginRight',
    'marginTop',
    'marginBottom',
    'fontSize',
    'fontWeight',
    'lineHeight',
    'textAlign',
    'width',
    'height',
  ]);
  return keys.some((key) => styleKeys.has(key));
}

const COLOR_KEYS = new Set([
  'backgroundColor',
  'borderBottomColor',
  'borderColor',
  'borderEndColor',
  'borderLeftColor',
  'borderRightColor',
  'borderStartColor',
  'borderTopColor',
  'color',
  'overlayColor',
  'shadowColor',
  'textDecorationColor',
  'textShadowColor',
  'tintColor',
]);

function normalizeColor(value: unknown): unknown {
  try {
    const processed = processColor(value as any);
    return processed ?? value;
  } catch {
    return value;
  }
}

function normalizeStyleForNativeProps(value: unknown): unknown {
  if (!value || typeof value !== 'object') {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((entry) => normalizeStyleForNativeProps(entry));
  }
  const next: Record<string, unknown> = { ...(value as Record<string, unknown>) };
  for (const key of Object.keys(next)) {
    if (COLOR_KEYS.has(key)) {
      next[key] = normalizeColor(next[key]);
    }
  }
  return next;
}

function normalizePropsForNativeApply(value: unknown): unknown {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return value;
  }
  const next: Record<string, unknown> = { ...(value as Record<string, unknown>) };
  if ('style' in next) {
    next.style = normalizeStyleForNativeProps(next.style);
  }
  for (const key of Object.keys(next)) {
    if (COLOR_KEYS.has(key)) {
      next[key] = normalizeColor(next[key]);
    }
  }
  return next;
}

function stripInternalKeys(value: unknown, keys: string[]): unknown {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return value;
  }
  const next: Record<string, unknown> = { ...(value as Record<string, unknown>) };
  for (const key of keys) {
    if (key in next) {
      delete next[key];
    }
  }
  return next;
}

export function BloomInspectorOverlayPanel() {
  ensureLiveEditRuntime();
  const [enabled, setEnabled] = useState(false);
  const [payload, setPayload] = useState<PickPayload | null>(null);
  type TabKey = 'overview' | 'source' | 'hierarchy' | 'props' | 'edit' | 'raw';
  const [activeTab, setActiveTab] = useState<TabKey>('overview');
  const [showRawSource, setShowRawSource] = useState(false);
  const [showFiberNodes, setShowFiberNodes] = useState(false);
  const [showFullStack, setShowFullStack] = useState(false);
  const [propsQuery, setPropsQuery] = useState('');
  const [sourceSnippet, setSourceSnippet] = useState<SourceSnippet | null>(null);
  const [isSnippetLoading, setIsSnippetLoading] = useState(false);
  const [collapsedHierarchyIndex, setCollapsedHierarchyIndex] = useState<number | null>(null);
  const [liveEditJson, setLiveEditJson] = useState('{\n  \n}');
  const [liveEditStatus, setLiveEditStatus] = useState<string | null>(null);
  const [liveEditTargetInfo, setLiveEditTargetInfo] = useState<LiveEditTargetInfo | null>(null);
  const [liveEditTargetIndex, setLiveEditTargetIndex] = useState(0);
  const [liveEditLastResult, setLiveEditLastResult] = useState<LiveEditApplyResult | null>(null);
  const [panelHeight, setPanelHeight] = useState<number | null>(null);
  const panelRef = useRef<View | null>(null);
  const payloadByTouchID = useRef<Map<number, { native?: PickPayload; js?: PickPayload }>>(
    new Map()
  );

  const debugEnabled = useCallback((name: string) => {
    try {
      return Boolean((globalThis as any)[name]);
    } catch {
      return false;
    }
  }, []);

  const clearSelection = useCallback(() => {
    setPayload(null);
    setPropsQuery('');
    setCollapsedHierarchyIndex(null);
    setLiveEditStatus(null);
    setLiveEditTargetInfo(null);
    setLiveEditTargetIndex(0);
    setLiveEditLastResult(null);
    payloadByTouchID.current.clear();
    NativeModules.BloomInspectorOverlay?.clearSelection?.();
    try {
      (globalThis as any).__bloomInspectorClearNativePropsTarget?.();
    } catch {}
  }, []);

  useEffect(() => {
    const module = NativeModules.BloomInspectorOverlay;
    if (!module) {
      return;
    }
    module.getEnabledAsync?.().then((value: boolean) => {
      setEnabled(Boolean(value));
    });
    const emitter = new NativeEventEmitter(module);
    const handlePickEvent = (data: PickPayload) => {
      if (DEBUG_BLOOM_LOGS) {
        console.info(
          'Bloom Log: 95 overlay pick received keys=' + Object.keys(data ?? {}).join(',')
        );
        console.info(JSON.stringify(data));
      }
      if (!data) {
        setPayload(null);
        return;
      }
      if (__DEV__ && (DEBUG_OWNER_SOURCE || debugEnabled('__bloomInspectorDebugOwnerSource'))) {
        const ownerFile = data.ownerSource?.fileName ?? null;
        const sourceFile = data.source?.fileName ?? null;
        if (ownerFile || sourceFile) {
          console.info('Bloom Inspector: pick sources', {
            ownerSource: ownerFile,
            source: sourceFile,
            different: ownerFile && sourceFile ? ownerFile !== sourceFile : null,
          });
        }
      }
      const touchID = typeof data.touchID === 'number' ? data.touchID : null;
      if (touchID != null) {
        const entry = payloadByTouchID.current.get(touchID) ?? {};
        if (data.payloadSource === 'js' && entry.js) {
          if (DEBUG_BLOOM_LOGS) {
            console.info(`Bloom Log: 95 merge ignore duplicate js touchID=${touchID}`);
          }
          return;
        }
        if (data.payloadSource !== 'js' && entry.js) {
          if (DEBUG_BLOOM_LOGS) {
            console.info(
              `Bloom Log: 95 merge ignore native touchID=${touchID} (js already present)`
            );
          }
          return;
        }
        if (data.payloadSource !== 'js' && entry.native) {
          if (DEBUG_BLOOM_LOGS) {
            console.info(`Bloom Log: 95 merge ignore duplicate native touchID=${touchID}`);
          }
          return;
        }
        if (data.payloadSource === 'js') {
          entry.js = data;
        } else {
          entry.native = data;
        }
        payloadByTouchID.current.set(touchID, entry);
        const merged = entry.js ?? entry.native ?? data;
        if (DEBUG_BLOOM_LOGS) {
          console.info(
            `Bloom Log: 95 merge apply touchID=${touchID} source=${merged.payloadSource ?? 'unknown'}`
          );
        }
        setPayload(merged);
        return;
      }
      setPayload(data);
    };
    const pickSub = emitter.addListener('bloomInspectorOverlayPick', handlePickEvent);
    const devicePickSub = DeviceEventEmitter.addListener(
      'bloomInspectorOverlayPick',
      handlePickEvent
    );
    const toggleSub = emitter.addListener(
      'bloomInspectorOverlayToggle',
      (data: { enabled?: boolean }) => {
        setEnabled(Boolean(data?.enabled));
        clearSelection();
      }
    );
    return () => {
      pickSub.remove();
      devicePickSub.remove();
      toggleSub.remove();
    };
  }, [clearSelection]);

  const propsEntries = useMemo(() => {
    if (!payload?.props) {
      return [];
    }
    return Object.entries(payload.props).sort(([a], [b]) => a.localeCompare(b));
  }, [payload]);

  const filteredPropsEntries = useMemo(() => {
    if (!propsQuery.trim()) {
      return propsEntries;
    }
    const query = propsQuery.trim().toLowerCase();
    return propsEntries.filter(([key, value]) => {
      if (key.toLowerCase().includes(query)) {
        return true;
      }
      const valuePreview = formatValue(value).toLowerCase();
      return valuePreview.includes(query);
    });
  }, [propsEntries, propsQuery]);

  const panelKind = useMemo(() => {
    if (!payload) {
      return 'Host';
    }
    if (payload.payloadSource === 'js' || payload.source?.fileName) {
      return 'React';
    }
    return 'Host';
  }, [payload]);

  const reactStackLines = useMemo(() => {
    if (!payload?.componentStack) {
      return [];
    }
    return payload.componentStack
      .split('\n')
      .map((line) => line.trim())
      .filter(Boolean);
  }, [payload]);

  const hierarchyItems = useMemo(() => {
    if (!payload?.hierarchy) {
      return [];
    }
    if (showFiberNodes) {
      return payload.hierarchy.filter((item) => !isInternalComponentName(item.name));
    }
    return payload.hierarchy.filter(
      (item) => !isFiberNode(item.name) && !isInternalComponentName(item.name)
    );
  }, [payload, showFiberNodes]);

  const hierarchyTreeItems = useMemo(() => {
    if (!hierarchyItems.length) {
      return [];
    }
    if (collapsedHierarchyIndex == null) {
      return hierarchyItems;
    }
    return hierarchyItems.slice(0, Math.max(1, collapsedHierarchyIndex + 1));
  }, [collapsedHierarchyIndex, hierarchyItems]);

  const fallbackStackLines = useMemo(() => {
    if (reactStackLines.length) {
      return reactStackLines.map(getComponentNameFromComponentStackLine).filter(Boolean);
    }
    return hierarchyItems
      .map((item) => item.name)
      .filter((name) => !isHostHierarchyName(name) && !isInternalComponentName(name));
  }, [reactStackLines, hierarchyItems]);

  const displayedStackParts = useMemo(() => {
    if (showFullStack) {
      return fallbackStackLines;
    }
    const filtered = fallbackStackLines.filter((name) => !isNoisyStackName(name));
    if (filtered.length <= 12) {
      return filtered;
    }
    return filtered.slice(-12);
  }, [fallbackStackLines, showFullStack]);

  const sourceLabel = useMemo(() => {
    const source = payload?.ownerSource ?? payload?.source;
    if (!source?.fileName) {
      return null;
    }
    return formatSourceLabel(source.fileName, source.lineNumber, showRawSource);
  }, [payload, showRawSource]);

  const componentSourceLabel = useMemo(() => {
    const componentSource = payload?.source;
    if (!payload?.ownerSource?.fileName || !componentSource?.fileName) {
      return null;
    }
    if (componentSource.fileName === payload.ownerSource.fileName) {
      return null;
    }
    return formatSourceLabel(componentSource.fileName, componentSource.lineNumber, false);
  }, [payload]);

  const sourceKindLabel = useMemo(() => {
    const fileName = payload?.ownerSource?.fileName ?? payload?.source?.fileName;
    if (!fileName) {
      return null;
    }
    const normalized = normalizeSourceFileName(fileName);
    if (normalized.includes('/node_modules/')) {
      return 'Library';
    }
    if (normalized.includes('index.bundle')) {
      return 'Bundle';
    }
    if (normalized.includes('/apps/')) {
      return 'App';
    }
    return null;
  }, [payload?.source?.fileName]);

  const isLibrarySource = useMemo(() => {
    const fileName = payload?.ownerSource?.fileName ?? payload?.source?.fileName;
    if (!fileName) {
      return false;
    }
    return normalizeSourceFileName(fileName).includes('/node_modules/');
  }, [payload?.ownerSource?.fileName, payload?.source?.fileName]);

  const sourceFileName = useMemo(() => {
    const source = payload?.ownerSource ?? payload?.source;
    if (!source?.fileName) {
      return null;
    }
    return normalizeSourceFileName(source.fileName);
  }, [payload]);

  const devServerOrigin = useMemo(() => getDevServerOrigin(sourceFileName), [sourceFileName]);

  const canShowSnippet = useMemo(() => {
    const lineNumber = (payload?.ownerSource ?? payload?.source)?.lineNumber;
    return Boolean(
      enabled &&
        devServerOrigin &&
        sourceFileName &&
        typeof lineNumber === 'number' &&
        lineNumber > 0 &&
        isLocalFilePath(sourceFileName) &&
        activeTab === 'source'
    );
  }, [activeTab, devServerOrigin, enabled, payload?.ownerSource, payload?.source, sourceFileName]);

  useEffect(() => {
    const fileName = sourceFileName;
    const lineNumber = (payload?.ownerSource ?? payload?.source)?.lineNumber;
    if (!canShowSnippet || !devServerOrigin || !fileName || typeof lineNumber !== 'number') {
      setSourceSnippet(null);
      setIsSnippetLoading(false);
      if (__DEV__ && DEBUG_SOURCE_SNIPPET) {
        console.info('Bloom Inspector: snippet skip', {
          enabled,
          canShowSnippet,
          devServerOrigin,
          sourceFileName,
          lineNumber,
        });
      }
      return;
    }

    let canceled = false;
    (async () => {
      setIsSnippetLoading(true);
      try {
        const body = JSON.stringify({ file: fileName, lineNumber, contextLines: 3 });
        const origins = getSnippetOrigins(devServerOrigin);
        if (__DEV__ && DEBUG_SOURCE_SNIPPET) {
          console.info('Bloom Inspector: snippet origins', { origins });
        }

        for (const origin of origins) {
          if (canceled) {
            return;
          }
          const url = `${origin}/bloom-source-snippet`;
          if (__DEV__ && DEBUG_SOURCE_SNIPPET) {
            console.info('Bloom Inspector: snippet request', { url, body: JSON.parse(body) });
          }

          const response = await fetchWithSoftTimeout(
            url,
            {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
              body,
            },
            2000,
            'bloom-source-snippet'
          );
          if (__DEV__ && DEBUG_SOURCE_SNIPPET) {
            console.info('Bloom Inspector: snippet response headers', {
              url,
              status: response.status,
              ok: response.ok,
              contentType: response.headers?.get?.('content-type') ?? null,
            });
          }

          const text = await response.text().catch(() => '');
          const trimmedText = text.length > 1200 ? `${text.slice(0, 1200)}…` : text;

          if (!response.ok) {
            if (__DEV__ && DEBUG_SOURCE_SNIPPET) {
              console.warn('Bloom Inspector: snippet non-200', {
                url,
                status: response.status,
                responseText: trimmedText || null,
              });
            }
            continue;
          }

          let parsed: unknown = null;
          try {
            parsed = text ? JSON.parse(text) : null;
          } catch (error) {
            if (__DEV__ && DEBUG_SOURCE_SNIPPET) {
              console.warn('Bloom Inspector: snippet JSON parse failed', {
                url,
                error: String(error),
                responseText: trimmedText || null,
              });
            }
            continue;
          }

          const data = parsed as Partial<SourceSnippet> | null;
          const looksValid =
            !!data &&
            typeof data.file === 'string' &&
            typeof data.startLine === 'number' &&
            typeof data.endLine === 'number' &&
            typeof data.lineNumber === 'number' &&
            Array.isArray(data.lines);
          if (!looksValid) {
            if (__DEV__ && DEBUG_SOURCE_SNIPPET) {
              console.warn('Bloom Inspector: snippet invalid payload', {
                url,
                responseText: trimmedText || null,
                hint:
                  typeof parsed === 'object' && parsed && 'launchAsset' in (parsed as any)
                    ? 'Looks like an Expo manifest response (wrong server/port).'
                    : null,
              });
            }
            continue;
          }

          if (!canceled) {
            if (__DEV__ && DEBUG_SOURCE_SNIPPET) {
              console.info('Bloom Inspector: snippet ok', {
                url,
                file: data.file,
                startLine: data.startLine,
                endLine: data.endLine,
                lineNumber: data.lineNumber,
                linesCount: data.lines?.length,
              });
            }
            setSourceSnippet(data as SourceSnippet);
            setIsSnippetLoading(false);
          }
          return;
        }

        if (!canceled) {
          setSourceSnippet(null);
          setIsSnippetLoading(false);
        }
      } catch (error) {
        if (!canceled) {
          if (__DEV__ && DEBUG_SOURCE_SNIPPET) {
            console.warn('Bloom Inspector: snippet request failed', { error: String(error) });
          }
          setSourceSnippet(null);
          setIsSnippetLoading(false);
        }
      }
    })();

    return () => {
      canceled = true;
    };
  }, [canShowSnippet, devServerOrigin, payload?.ownerSource, payload?.source, sourceFileName]);

  const componentStackFrame = useMemo(() => {
    if (!payload?.componentStack) {
      return null;
    }
    return getBestFrameFromComponentStack(payload.componentStack);
  }, [payload?.componentStack]);

  const canOpenInEditor = useMemo(() => {
    const source = payload?.ownerSource ?? payload?.source;
    return Boolean(
      sourceFileName &&
        devServerOrigin &&
        ((typeof source?.lineNumber === 'number' && source.lineNumber >= 0) || componentStackFrame)
    );
  }, [componentStackFrame, devServerOrigin, payload?.ownerSource, payload?.source, sourceFileName]);

  const snippetLines = useMemo<SourceSnippetLine[]>(() => {
    if (!sourceSnippet?.lines?.length) {
      return [];
    }
    return formatSnippetLines(sourceSnippet);
  }, [sourceSnippet]);

  const copyToClipboard = useCallback((value: string, label: string) => {
    try {
      Clipboard.setString(value);
      if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
        console.info(`Bloom Inspector: copied ${label}`);
      }
      // Avoid noisy alerts while iterating; only show on failure.
    } catch (error) {
      Alert.alert('Clipboard', `Failed to copy ${label}: ${String(error)}`);
    }
  }, []);

  const applyNativeProps = useCallback(
    (nextProps: unknown) => {
      try {
        const jsInfo =
          typeof (globalThis as any).__bloomInspectorGetNativePropsTargetInfo === 'function'
            ? (globalThis as any).__bloomInspectorGetNativePropsTargetInfo()
            : null;
        const jsApply =
          typeof (globalThis as any).__bloomInspectorApplyNativeProps === 'function'
            ? ((globalThis as any).__bloomInspectorApplyNativeProps as
                | ((props: unknown) => boolean)
                | undefined)
            : undefined;

        const nativeApply = NativeModules.BloomInspectorOverlay?.applyNativePropsAsync as
          | ((props: Record<string, unknown>) => Promise<LiveEditApplyResult>)
          | undefined;
        const nativeApplyToTag = NativeModules.BloomInspectorOverlay?.applyNativePropsToTagAsync as
          | ((reactTag: number, props: Record<string, unknown>) => Promise<LiveEditApplyResult>)
          | undefined;

        const availableTags =
          liveEditTargetInfo && 'availableTags' in liveEditTargetInfo
            ? (liveEditTargetInfo.availableTags ?? [])
            : [];
        const tagOverride =
          availableTags.length &&
          liveEditTargetIndex >= 0 &&
          liveEditTargetIndex < availableTags.length
            ? availableTags[liveEditTargetIndex]
            : null;
        const useChild =
          '__bloomInspectorUseChild' in (nextProps as Record<string, unknown>) &&
          Boolean((nextProps as Record<string, unknown>).__bloomInspectorUseChild);
        const componentClass =
          liveEditTargetInfo && 'componentViewClass' in liveEditTargetInfo
            ? liveEditTargetInfo.componentViewClass
            : null;
        const isTextComponent =
          typeof componentClass === 'string' &&
          (componentClass.includes('Paragraph') || componentClass.includes('Text'));
        const hasVisualStyleKeys = (() => {
          if (!nextProps || typeof nextProps !== 'object') {
            return false;
          }
          const styleCandidate =
            'style' in (nextProps as Record<string, unknown>) &&
            (nextProps as Record<string, unknown>).style &&
            typeof (nextProps as Record<string, unknown>).style === 'object' &&
            !Array.isArray((nextProps as Record<string, unknown>).style)
              ? (nextProps as Record<string, unknown>).style
              : null;
          const candidate = (styleCandidate ?? (nextProps as Record<string, unknown>)) as Record<
            string,
            unknown
          >;
          return ['backgroundColor', 'borderColor', 'borderWidth', 'borderRadius', 'opacity'].some(
            (key) => key in candidate
          );
        })();
        const hasTextStyleKeys = (() => {
          if (!nextProps || typeof nextProps !== 'object') {
            return false;
          }
          const styleCandidate =
            'style' in (nextProps as Record<string, unknown>) &&
            (nextProps as Record<string, unknown>).style &&
            typeof (nextProps as Record<string, unknown>).style === 'object' &&
            !Array.isArray((nextProps as Record<string, unknown>).style)
              ? (nextProps as Record<string, unknown>).style
              : null;
          const candidate = (styleCandidate ?? (nextProps as Record<string, unknown>)) as Record<
            string,
            unknown
          >;
          return [
            'color',
            'fontSize',
            'fontWeight',
            'fontStyle',
            'textAlign',
            'textTransform',
            'textDecorationLine',
            'textDecorationStyle',
            'textDecorationColor',
            'textShadowColor',
            'textShadowOffset',
            'textShadowRadius',
            'letterSpacing',
            'lineHeight',
          ].some((key) => key in candidate);
        })();
        const effectiveTagOverride = (() => {
          if (useChild) {
            return availableTags.length ? availableTags[0] : tagOverride;
          }
          if (
            isTextComponent &&
            hasVisualStyleKeys &&
            !hasTextStyleKeys &&
            availableTags.length > 1 &&
            liveEditTargetIndex === 0
          ) {
            return availableTags[1];
          }
          return tagOverride;
        })();

        const jsPayload = stripInternalKeys(nextProps, [
          '__bloomInspectorUseChild',
          '__bloomInspectorForceUIKit',
        ]);

        if (
          jsApply &&
          nextProps &&
          typeof nextProps === 'object' &&
          (!effectiveTagOverride || effectiveTagOverride == null)
        ) {
          if (__DEV__ && (DEBUG_LIVE_EDIT || debugEnabled('__bloomInspectorDebugLiveEdit'))) {
            console.info('Bloom Inspector: live-edit using js apply', {
              name: (jsInfo as any).name ?? null,
              nativeTag: (jsInfo as any).nativeTag ?? null,
            });
          }
          const ok = Boolean(jsApply(jsPayload));
          setLiveEditStatus(ok ? 'Applied' : 'Failed (no target)');
          setLiveEditLastResult({
            ok,
            mode: (jsInfo as any).mode ?? 'ref',
            reactTag: (jsInfo as any).nativeTag ?? undefined,
            componentViewClass: (jsInfo as any).name ?? undefined,
          });
          if (ok) {
            return;
          }
        }

        if (nativeApply && nextProps && typeof nextProps === 'object') {
          if (__DEV__ && (DEBUG_LIVE_EDIT || debugEnabled('__bloomInspectorDebugLiveEdit'))) {
            console.info('Bloom Inspector: live-edit using native apply');
          }
          const forceUIKit =
            '__bloomInspectorForceUIKit' in (nextProps as Record<string, unknown>) &&
            Boolean((nextProps as Record<string, unknown>).__bloomInspectorForceUIKit);
          const nativePayload = stripInternalKeys(nextProps, ['__bloomInspectorUseChild']);
          const normalizedProps = forceUIKit
            ? nativePayload
            : normalizePropsForNativeApply(nativePayload);
          const applyPromise =
            effectiveTagOverride != null && nativeApplyToTag
              ? Promise.resolve(nativeApplyToTag(effectiveTagOverride, normalizedProps as any))
              : Promise.resolve(nativeApply(normalizedProps as any));
          Promise.resolve(applyPromise)
            .then((result) => {
              const ok = typeof result === 'boolean' ? result : Boolean(result?.ok);
              const reason = typeof result === 'boolean' ? null : (result?.reason ?? null);
              setLiveEditStatus(ok ? 'Applied' : `Failed (${reason ?? 'no target'})`);
              setLiveEditLastResult(
                typeof result === 'boolean' ? ({ ok: result } as LiveEditApplyResult) : result
              );
              if (__DEV__ && (DEBUG_LIVE_EDIT || debugEnabled('__bloomInspectorDebugLiveEdit'))) {
                console.info('Bloom Inspector: live-edit native result', {
                  ok,
                  result,
                  tagOverride: effectiveTagOverride,
                });
              }
            })
            .catch((error) => {
              setLiveEditStatus(`Failed (${String(error)})`);
              if (__DEV__ && (DEBUG_LIVE_EDIT || debugEnabled('__bloomInspectorDebugLiveEdit'))) {
                console.warn('Bloom Inspector: live-edit native threw', { error: String(error) });
              }
            });
          return;
        }
        if (!jsApply) {
          setLiveEditStatus('Unavailable (no runtime hook)');
          if (__DEV__ && (DEBUG_LIVE_EDIT || debugEnabled('__bloomInspectorDebugLiveEdit'))) {
            console.warn('Bloom Inspector: live-edit missing runtime hook');
          }
          return;
        }
        if (__DEV__ && (DEBUG_LIVE_EDIT || debugEnabled('__bloomInspectorDebugLiveEdit'))) {
          console.info('Bloom Inspector: live-edit apply', {
            nextPropsType: typeof nextProps,
            nextProps,
            keys:
              nextProps && typeof nextProps === 'object'
                ? Object.keys(nextProps as any).slice(0, 12)
                : null,
          });
        }
        const ok = jsApply(nextProps);
        setLiveEditStatus(ok ? 'Applied' : 'Failed (no target)');
        setLiveEditLastResult({ ok, mode: jsInfo?.mode ?? undefined });
        if (__DEV__ && (DEBUG_LIVE_EDIT || debugEnabled('__bloomInspectorDebugLiveEdit'))) {
          console.info('Bloom Inspector: live-edit result', { ok });
        }
      } catch (error) {
        setLiveEditStatus(`Failed (${String(error)})`);
        if (__DEV__ && (DEBUG_LIVE_EDIT || debugEnabled('__bloomInspectorDebugLiveEdit'))) {
          console.warn('Bloom Inspector: live-edit threw', { error: String(error) });
        }
      }
    },
    [debugEnabled, liveEditTargetIndex, liveEditTargetInfo]
  );

  const parseJson = useCallback((value: string) => {
    try {
      const normalized = value
        .replace(/[\u201c\u201d]/g, '"')
        .replace(/[\u2018\u2019]/g, "'")
        .replace(/\u00a0/g, ' ');
      return { ok: true as const, value: JSON.parse(normalized) as unknown };
    } catch (error) {
      return { ok: false as const, error: String(error) };
    }
  }, []);

  const formatRect = useCallback(
    (rect?: { x: number; y: number; width: number; height: number } | null) => {
      if (!rect) {
        return null;
      }
      return `x:${rect.x} y:${rect.y} w:${rect.width} h:${rect.height}`;
    },
    []
  );

  useEffect(() => {
    if (activeTab !== 'edit' || !payload) {
      setLiveEditTargetInfo(null);
      return;
    }
    try {
      const nativeGetInfo = NativeModules.BloomInspectorOverlay?.getLiveEditTargetInfoAsync as
        | (() => Promise<LiveEditTargetInfo>)
        | undefined;
      if (nativeGetInfo) {
        Promise.resolve(nativeGetInfo())
          .then((info) => {
            setLiveEditTargetInfo(info ?? null);
            const tags =
              info && typeof info === 'object' && 'availableTags' in (info as any)
                ? (((info as any).availableTags as unknown[]) ?? []).filter(
                    (value: unknown): value is number => typeof value === 'number'
                  )
                : [];
            const componentClass =
              info && typeof info === 'object' && 'componentViewClass' in (info as any)
                ? ((info as any).componentViewClass as string | null | undefined)
                : null;
            if (tags.length > 1 && componentClass && componentClass.includes('Paragraph')) {
              setLiveEditTargetIndex(1);
            } else {
              setLiveEditTargetIndex(0);
            }
            if (__DEV__ && (DEBUG_LIVE_EDIT || debugEnabled('__bloomInspectorDebugLiveEdit'))) {
              console.info('Bloom Inspector: live-edit target info (native)', info ?? null);
            }
          })
          .catch((error) => {
            setLiveEditTargetInfo(null);
            if (__DEV__ && (DEBUG_LIVE_EDIT || debugEnabled('__bloomInspectorDebugLiveEdit'))) {
              console.warn('Bloom Inspector: live-edit target info (native) failed', {
                error: String(error),
              });
            }
          });
        return;
      }

      const getter = (globalThis as any).__bloomInspectorGetNativePropsTargetInfo as
        | (() => unknown)
        | undefined;
      const hasTargetFn = (globalThis as any).__bloomInspectorHasNativePropsTarget as
        | (() => boolean)
        | undefined;
      const info = getter?.();
      if (info && typeof info === 'object' && 'hasTarget' in (info as any)) {
        setLiveEditTargetInfo(info as any);
      } else if (hasTargetFn) {
        setLiveEditTargetInfo({ hasTarget: Boolean(hasTargetFn()) });
      } else {
        setLiveEditTargetInfo(null);
      }
      if (__DEV__ && (DEBUG_LIVE_EDIT || debugEnabled('__bloomInspectorDebugLiveEdit'))) {
        console.info('Bloom Inspector: live-edit target info', info ?? null);
      }
    } catch (error) {
      setLiveEditTargetInfo(null);
      if (__DEV__ && (DEBUG_LIVE_EDIT || debugEnabled('__bloomInspectorDebugLiveEdit'))) {
        console.warn('Bloom Inspector: live-edit target info failed', { error: String(error) });
      }
    }
  }, [activeTab, debugEnabled, payload]);

  const handleOpenInEditor = useCallback(() => {
    const source = payload?.ownerSource ?? payload?.source;
    if (
      !sourceFileName ||
      !devServerOrigin ||
      ((!source || typeof source.lineNumber !== 'number' || source.lineNumber < 0) &&
        !componentStackFrame)
    ) {
      if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
        console.warn('Bloom Inspector: open-in-editor precondition failed', {
          sourceFileName,
          devServerOrigin,
          source: payload?.source ?? null,
          componentStackFrame,
        });
      }
      return;
    }

    (async () => {
      if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
        console.info('Bloom Inspector: open-in-editor pressed', {
          devServerOrigin,
          originalFileName: payload?.source?.fileName ?? null,
          ownerFileName: payload?.ownerSource?.fileName ?? null,
          normalizedFileName: sourceFileName,
          lineNumber: source?.lineNumber ?? null,
          columnNumber: source?.columnNumber ?? null,
          hasComponentStack: Boolean(payload?.componentStack),
          componentStackFrame,
          componentStackPreview:
            !componentStackFrame && payload?.componentStack
              ? payload.componentStack.split('\n').slice(0, 8)
              : null,
        });
      }

      if (componentStackFrame && !isBundleUrl(componentStackFrame.file)) {
        const openStackFrameUrl = `${devServerOrigin}/open-stack-frame`;
        const body = JSON.stringify({
          file: componentStackFrame.file,
          lineNumber: componentStackFrame.lineNumber,
          columnNumber: componentStackFrame.columnNumber ?? 1,
        });
        if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
          console.info('Bloom Inspector: open-in-editor using componentStack frame', {
            url: openStackFrameUrl,
            body: JSON.parse(body),
          });
        }
        try {
          const response = await fetchWithSoftTimeout(
            openStackFrameUrl,
            {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body,
            },
            15000,
            'open-stack-frame'
          );
          const text = await response.text().catch(() => '');
          const trimmedText = text.length > 400 ? `${text.slice(0, 400)}…` : text;
          if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
            if (!response.ok) {
              console.warn('Bloom Inspector: open-stack-frame failed', {
                url: openStackFrameUrl,
                status: response.status,
                body: JSON.parse(body),
                responseText: trimmedText || null,
              });
            } else {
              console.info('Bloom Inspector: open-stack-frame ok', {
                url: openStackFrameUrl,
                status: response.status,
                body: JSON.parse(body),
                responseText: trimmedText || null,
              });
            }
          }
          if (response.ok) {
            return;
          }
        } catch (error) {
          if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
            console.warn('Bloom Inspector: open-stack-frame request failed', {
              url: openStackFrameUrl,
              body: JSON.parse(body),
              error: String(error),
            });
          }
        }
      }

      const resolved = await resolveOpenInEditorFrame(
        devServerOrigin,
        sourceFileName,
        typeof source?.lineNumber === 'number' ? source.lineNumber : -1,
        typeof source?.columnNumber === 'number' && source.columnNumber > 0
          ? source.columnNumber
          : 1
      );
      if (!resolved) {
        if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
          console.warn('Bloom Inspector: open-in-editor failed to resolve frame', {
            devServerOrigin,
            sourceFileName,
            lineNumber: source?.lineNumber ?? null,
            columnNumber: source?.columnNumber ?? null,
          });
        }
        return;
      }
      if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
        console.info('Bloom Inspector: open-in-editor resolved frame', resolved);
      }
      const body = JSON.stringify({
        file: resolved.file,
        lineNumber: resolved.lineNumber,
        columnNumber: resolved.columnNumber ?? 1,
      });
      const openStackFrameUrl = `${devServerOrigin}/open-stack-frame`;
      if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
        console.info('Bloom Inspector: open-stack-frame request', {
          url: openStackFrameUrl,
          body: JSON.parse(body),
        });
      }
      try {
        const response = await fetchWithSoftTimeout(
          openStackFrameUrl,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body,
          },
          15000,
          'open-stack-frame'
        );
        const text = await response.text().catch(() => '');
        const trimmedText = text.length > 400 ? `${text.slice(0, 400)}…` : text;
        if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
          if (!response.ok) {
            console.warn('Bloom Inspector: open-stack-frame failed', {
              url: openStackFrameUrl,
              status: response.status,
              body: JSON.parse(body),
              responseText: trimmedText || null,
            });
          } else {
            console.info('Bloom Inspector: open-stack-frame ok', {
              url: openStackFrameUrl,
              status: response.status,
              body: JSON.parse(body),
              responseText: trimmedText || null,
            });
          }
        }
      } catch (error) {
        if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
          console.warn('Bloom Inspector: open-stack-frame request failed', {
            url: openStackFrameUrl,
            body: JSON.parse(body),
            error: String(error),
          });
        }
      }
    })();
  }, [componentStackFrame, devServerOrigin, payload, sourceFileName]);

  const panelPosition = useMemo(() => {
    if (!payload?.frame) {
      return 'bottom';
    }
    const screenHeight = Dimensions.get('window').height;
    const maxPanelHeight = screenHeight * 0.5;
    const effectivePanelHeight = panelHeight ?? maxPanelHeight;
    const spaceBelow = screenHeight - (payload.frame.top + payload.frame.height);
    const spaceAbove = payload.frame.top;
    const wouldOverflowBottom =
      payload.frame.top + payload.frame.height + effectivePanelHeight + 16 > screenHeight;
    if (wouldOverflowBottom) {
      if (DEBUG_BLOOM_LOGS) {
        console.info(
          `Bloom Log: 95 panelPosition=top spaceBelow=${spaceBelow.toFixed(
            1
          )} spaceAbove=${spaceAbove.toFixed(1)} panelHeight=${effectivePanelHeight.toFixed(
            1
          )} overflowBottom=${wouldOverflowBottom}`
        );
      }
      return 'top';
    }
    const midY = payload.frame.top + payload.frame.height / 2;
    const screenMid = screenHeight / 2;
    const position = midY < screenMid ? 'bottom' : 'top';
    if (DEBUG_BLOOM_LOGS) {
      console.info(
        `Bloom Log: 95 panelPosition=${position} midY=${midY.toFixed(
          1
        )} screenMid=${screenMid.toFixed(1)} panelHeight=${effectivePanelHeight.toFixed(
          1
        )} overflowBottom=${wouldOverflowBottom}`
      );
    }
    return position;
  }, [panelHeight, payload]);

  const handlePanelLayout = useCallback(() => {
    const panel = panelRef.current;
    if (!panel || !NativeModules.BloomInspectorOverlay?.setPanelFrame) {
      return;
    }
    panel.measureInWindow((x, y, width, height) => {
      setPanelHeight((prev) => (prev === height ? prev : height));
      NativeModules.BloomInspectorOverlay.setPanelFrame({ x, y, width, height });
    });
  }, []);

  useEffect(() => {
    if (!enabled) {
      return;
    }
    const id = requestAnimationFrame(() => {
      handlePanelLayout();
    });
    return () => cancelAnimationFrame(id);
  }, [enabled, payload, panelPosition, handlePanelLayout]);

  if (!enabled) {
    return null;
  }

  return (
    <SafeAreaView pointerEvents="box-none" style={styles.container}>
      <View
        pointerEvents="box-none"
        style={[
          styles.panelWrap,
          panelPosition === 'top' ? styles.panelWrapTop : styles.panelWrapBottom,
        ]}>
        <View ref={panelRef} onLayout={handlePanelLayout} style={styles.panel}>
          <View style={styles.header}>
            <Text style={styles.title}>Bloom Element Inspector · {panelKind}</Text>
            <Pressable
              onPress={() => {
                clearSelection();
                NativeModules.BloomInspectorOverlay?.toggle?.();
              }}
              style={styles.closeButton}>
              <Text style={styles.closeText}>×</Text>
            </Pressable>
          </View>

          {!payload ? (
            <Text style={styles.placeholder}>Tap an element to inspect.</Text>
          ) : (
            <ScrollView
              style={styles.content}
              contentContainerStyle={styles.contentContainer}
              showsVerticalScrollIndicator>
              <View style={styles.tabRow}>
                <Pressable
                  onPress={() => setActiveTab('overview')}
                  style={[styles.tabChip, activeTab === 'overview' && styles.tabChipActive]}>
                  <Text style={styles.tabText}>Overview</Text>
                </Pressable>
                <Pressable
                  onPress={() => setActiveTab('source')}
                  style={[styles.tabChip, activeTab === 'source' && styles.tabChipActive]}>
                  <Text style={styles.tabText}>Source</Text>
                </Pressable>
                <Pressable
                  onPress={() => setActiveTab('hierarchy')}
                  style={[styles.tabChip, activeTab === 'hierarchy' && styles.tabChipActive]}>
                  <Text style={styles.tabText}>Hierarchy</Text>
                </Pressable>
                <Pressable
                  onPress={() => setActiveTab('props')}
                  style={[styles.tabChip, activeTab === 'props' && styles.tabChipActive]}>
                  <Text style={styles.tabText}>Props</Text>
                </Pressable>
                <Pressable
                  onPress={() => setActiveTab('edit')}
                  style={[styles.tabChip, activeTab === 'edit' && styles.tabChipActive]}>
                  <Text style={styles.tabText}>Edit</Text>
                </Pressable>
                <Pressable
                  onPress={() => setActiveTab('raw')}
                  style={[styles.tabChip, activeTab === 'raw' && styles.tabChipActive]}>
                  <Text style={styles.tabText}>Raw</Text>
                </Pressable>
              </View>

              {activeTab === 'overview' && (
                <>
                  <View style={styles.sectionHeaderRow}>
                    <Text style={styles.sectionTitleInline}>React Stack</Text>
                    <Pressable
                      onPress={() => setShowFullStack((value) => !value)}
                      style={[styles.toggleChip, showFullStack && styles.toggleChipActive]}>
                      <Text style={styles.toggleText}>{showFullStack ? 'Full' : 'Short'}</Text>
                    </Pressable>
                  </View>
                  {displayedStackParts.length ? (
                    <Text style={styles.sectionBody}>{displayedStackParts.join(' > ')}</Text>
                  ) : (
                    <Text style={styles.sectionBody}>Unavailable</Text>
                  )}

                  <Text style={styles.sectionTitle}>Hierarchy</Text>
                  {hierarchyItems.length ? (
                    <Text style={styles.sectionBody}>
                      {hierarchyItems.map((item) => item.name).join(' > ')}
                    </Text>
                  ) : (
                    <Text style={styles.sectionBody}>Unavailable</Text>
                  )}

                  <Text style={styles.sectionTitle}>Frame</Text>
                  {payload.frame ? (
                    <Text style={styles.sectionBody}>
                      {`x: ${payload.frame.left.toFixed(1)}, y: ${payload.frame.top.toFixed(1)}, `}
                      {`w: ${payload.frame.width.toFixed(1)}, h: ${payload.frame.height.toFixed(
                        1
                      )}`}
                    </Text>
                  ) : (
                    <Text style={styles.sectionBody}>Unavailable</Text>
                  )}
                </>
              )}

              {activeTab === 'source' && (
                <>
                  <View style={styles.sectionHeaderRow}>
                    <Text style={styles.sectionTitleInline}>Source</Text>
                    {sourceKindLabel ? (
                      <Text style={styles.badgeText}>{sourceKindLabel}</Text>
                    ) : null}
                    <Pressable
                      onPress={() => setShowRawSource((value) => !value)}
                      style={[styles.toggleChip, showRawSource && styles.toggleChipActive]}>
                      <Text style={styles.toggleText}>{showRawSource ? 'Raw' : 'Short'}</Text>
                    </Pressable>
                  </View>
                  {sourceLabel ? (
                    <>
                      <Text style={styles.sectionBody}>{sourceLabel}</Text>
                      {componentSourceLabel ? (
                        <Text style={styles.sectionHint}>Component: {componentSourceLabel}</Text>
                      ) : null}
                      {snippetLines.length ? (
                        <View style={styles.snippetContainer}>
                          {snippetLines.map((line) => (
                            <Text
                              key={line.lineNumber}
                              style={[
                                styles.snippetLine,
                                line.isCurrent && styles.snippetLineCurrent,
                              ]}>
                              {line.text}
                            </Text>
                          ))}
                        </View>
                      ) : isSnippetLoading ? (
                        <Text style={styles.sectionHint}>Loading source snippet…</Text>
                      ) : canShowSnippet ? (
                        <Text style={styles.sectionHint}>
                          Source snippet unavailable (restart dev server to pick up
                          `/bloom-source-snippet`).
                        </Text>
                      ) : null}
                      <View style={styles.inlineActionsRow}>
                        <Pressable
                          onPress={() =>
                            copyToClipboard(
                              `${normalizeSourceFileName(
                                (payload?.ownerSource ?? payload?.source)?.fileName ?? ''
                              )}:${(payload?.ownerSource ?? payload?.source)?.lineNumber ?? ''}`,
                              'source'
                            )
                          }
                          style={styles.inlineActionButton}>
                          <Text style={styles.inlineActionText}>Copy</Text>
                        </Pressable>
                        {snippetLines.length ? (
                          <Pressable
                            onPress={() =>
                              copyToClipboard(
                                snippetLines.map((line) => line.text).join('\n'),
                                'source snippet'
                              )
                            }
                            style={styles.inlineActionButton}>
                            <Text style={styles.inlineActionText}>Copy snippet</Text>
                          </Pressable>
                        ) : null}
                        {canOpenInEditor ? (
                          <Pressable
                            onPress={handleOpenInEditor}
                            style={styles.inlineActionButtonPrimary}>
                            <Text style={styles.inlineActionTextPrimary}>Open in editor</Text>
                          </Pressable>
                        ) : null}
                      </View>
                      {isLibrarySource ? (
                        <Text style={styles.sectionHint}>
                          This is a library/native component (`node_modules`).
                        </Text>
                      ) : null}
                      {!canOpenInEditor ? (
                        <Text style={styles.sectionHint}>Open in editor unavailable.</Text>
                      ) : null}
                    </>
                  ) : (
                    <Text style={styles.sectionBody}>Unavailable</Text>
                  )}
                </>
              )}

              {activeTab === 'hierarchy' && (
                <>
                  <View style={styles.sectionHeaderRow}>
                    <Text style={styles.sectionTitleInline}>Hierarchy Tree</Text>
                    <Pressable
                      onPress={() => setShowFiberNodes((value) => !value)}
                      style={[styles.toggleChip, showFiberNodes && styles.toggleChipActive]}>
                      <Text style={styles.toggleText}>
                        {showFiberNodes ? 'Fiber On' : 'Fiber Off'}
                      </Text>
                    </Pressable>
                  </View>
                  {!hierarchyItems.length ? (
                    <Text style={styles.sectionBody}>Unavailable</Text>
                  ) : (
                    <>
                      <Text style={styles.sectionHint}>
                        Tap a row to collapse/expand deeper nodes.
                      </Text>
                      <ScrollView style={styles.hierarchyTree}>
                        {hierarchyTreeItems.map((item, index) => {
                          const isCollapsed = collapsedHierarchyIndex === index;
                          const isLeaf = index === hierarchyItems.length - 1;
                          return (
                            <Pressable
                              key={`${index}:${item.name}`}
                              onPress={() =>
                                setCollapsedHierarchyIndex((prev) =>
                                  prev === index ? null : index
                                )
                              }
                              style={styles.hierarchyRow}>
                              <Text style={styles.hierarchyIndent}>
                                {'  '.repeat(Math.max(0, index / 2))}
                              </Text>
                              <Text style={styles.hierarchyRowText} numberOfLines={1}>
                                {isLeaf ? '• ' : isCollapsed ? '▸ ' : '▾ '}
                                {item.name}
                              </Text>
                            </Pressable>
                          );
                        })}
                      </ScrollView>
                      <View style={styles.inlineActionsRow}>
                        <Pressable
                          onPress={() =>
                            copyToClipboard(
                              hierarchyItems.map((item) => item.name).join(' > '),
                              'hierarchy'
                            )
                          }
                          style={styles.inlineActionButton}>
                          <Text style={styles.inlineActionText}>Copy</Text>
                        </Pressable>
                        <Pressable
                          onPress={() => setCollapsedHierarchyIndex(null)}
                          style={styles.inlineActionButton}>
                          <Text style={styles.inlineActionText}>Expand all</Text>
                        </Pressable>
                      </View>
                    </>
                  )}
                </>
              )}

              {activeTab === 'props' && (
                <>
                  <Text style={styles.sectionTitle}>Props</Text>
                  <View style={styles.propsToolbar}>
                    <TextInput
                      value={propsQuery}
                      onChangeText={setPropsQuery}
                      placeholder="Search props…"
                      style={styles.propsSearch}
                      autoCorrect={false}
                      autoCapitalize="none"
                      clearButtonMode="while-editing"
                    />
                    <Pressable
                      onPress={() =>
                        copyToClipboard(JSON.stringify(payload?.props ?? {}, null, 2), 'props')
                      }
                      style={styles.inlineActionButton}>
                      <Text style={styles.inlineActionText}>Copy</Text>
                    </Pressable>
                  </View>
                  {propsEntries.length === 0 ? (
                    <Text style={styles.sectionBody}>No props available.</Text>
                  ) : (
                    filteredPropsEntries.map(([key, value]) => (
                      <View key={key} style={styles.propRow}>
                        <Text style={styles.propKey}>{key}</Text>
                        <Text style={styles.propValue}>
                          {formatValue(value)} ({typeof value})
                        </Text>
                      </View>
                    ))
                  )}
                </>
              )}

              {activeTab === 'edit' && (
                <>
                  <View style={styles.sectionHeaderRow}>
                    <Text style={styles.sectionTitleInline}>Live Edit</Text>
                    <Text style={styles.badgeText}>Experimental</Text>
                  </View>
                  <Text style={styles.sectionHint}>
                    Applies `setNativeProps` to the last selected native view. This changes visuals
                    but does not update React state.
                  </Text>
                  {liveEditTargetInfo ? (
                    <Text style={styles.sectionHint}>
                      Target: {liveEditTargetInfo.hasTarget ? 'available' : 'unavailable'}
                      {'name' in liveEditTargetInfo && liveEditTargetInfo.name
                        ? ` (${liveEditTargetInfo.name})`
                        : 'viewName' in liveEditTargetInfo && liveEditTargetInfo.viewName
                          ? ` (${liveEditTargetInfo.viewName})`
                          : ''}
                      {liveEditTargetInfo.hasTarget && 'reactTag' in liveEditTargetInfo
                        ? ` #${liveEditTargetInfo.reactTag ?? '?'}`
                        : ''}
                      {liveEditTargetInfo.reason ? ` · ${liveEditTargetInfo.reason}` : ''}
                    </Text>
                  ) : null}
                  {liveEditTargetInfo && 'availableTags' in liveEditTargetInfo ? (
                    <View style={styles.inlineActionsRow}>
                      <Text style={styles.sectionHint}>
                        Target depth: {liveEditTargetIndex + 1}/
                        {(liveEditTargetInfo.availableTags?.length ?? 0) || 0}
                      </Text>
                      <Pressable
                        onPress={() => setLiveEditTargetIndex((prev) => Math.max(0, prev - 1))}
                        style={styles.inlineActionButton}>
                        <Text style={styles.inlineActionText}>Child</Text>
                      </Pressable>
                      <Pressable
                        onPress={() =>
                          setLiveEditTargetIndex((prev) =>
                            Math.min((liveEditTargetInfo.availableTags?.length ?? 1) - 1, prev + 1)
                          )
                        }
                        style={styles.inlineActionButton}>
                        <Text style={styles.inlineActionText}>Parent</Text>
                      </Pressable>
                    </View>
                  ) : null}
                  {liveEditLastResult && typeof liveEditLastResult === 'object' ? (
                    <>
                      <Text style={styles.sectionHint}>
                        Result: {liveEditLastResult.ok ? 'ok' : 'failed'}
                        {liveEditLastResult.mode ? ` · ${liveEditLastResult.mode}` : ''}
                        {liveEditLastResult.reactTag != null
                          ? ` · tag ${liveEditLastResult.reactTag}`
                          : ''}
                        {liveEditLastResult.componentViewClass
                          ? ` · ${liveEditLastResult.componentViewClass}`
                          : ''}
                      </Text>
                      {liveEditLastResult.componentViewFrame ? (
                        <Text style={styles.sectionHint}>
                          Frame: {formatRect(liveEditLastResult.componentViewFrame)}
                        </Text>
                      ) : null}
                      {liveEditLastResult.componentViewBounds ? (
                        <Text style={styles.sectionHint}>
                          Bounds: {formatRect(liveEditLastResult.componentViewBounds)}
                        </Text>
                      ) : null}
                      {liveEditLastResult.componentViewAlpha != null ||
                      liveEditLastResult.componentViewHidden != null ? (
                        <Text style={styles.sectionHint}>
                          Alpha:{' '}
                          {liveEditLastResult.componentViewAlpha != null
                            ? liveEditLastResult.componentViewAlpha
                            : '?'}{' '}
                          Hidden:{' '}
                          {liveEditLastResult.componentViewHidden != null
                            ? String(liveEditLastResult.componentViewHidden)
                            : '?'}
                        </Text>
                      ) : null}
                      {liveEditLastResult.componentViewBackgroundColor ? (
                        <Text style={styles.sectionHint}>
                          Background: {liveEditLastResult.componentViewBackgroundColor}
                        </Text>
                      ) : null}
                    </>
                  ) : null}
                  <TextInput
                    style={styles.liveEditInput}
                    value={liveEditJson}
                    onChangeText={(text) => {
                      setLiveEditJson(text);
                      setLiveEditStatus(null);
                    }}
                    autoCapitalize="none"
                    autoCorrect={false}
                    multiline
                    placeholder={'{\n  "backgroundColor": "red"\n}'}
                    placeholderTextColor="#7a7a7a"
                  />
                  {liveEditStatus ? (
                    <Text style={styles.sectionHint}>Status: {liveEditStatus}</Text>
                  ) : null}
                  <View style={styles.inlineActionsRow}>
                    <Pressable
                      onPress={() => {
                        const parsed = parseJson(liveEditJson);
                        if (!parsed.ok) {
                          setLiveEditStatus(parsed.error);
                          return;
                        }
                        if (__DEV__ && debugEnabled('__bloomInspectorDebugLiveEdit')) {
                          console.info('Bloom Inspector: live-edit apply style parsed', {
                            raw: liveEditJson,
                            parsed: parsed.value,
                          });
                        }
                        applyNativeProps({ style: parsed.value });
                      }}
                      style={styles.inlineActionButtonPrimary}>
                      <Text style={styles.inlineActionTextPrimary}>Apply style</Text>
                    </Pressable>
                    <Pressable
                      onPress={() => {
                        const parsed = parseJson(liveEditJson);
                        if (!parsed.ok) {
                          setLiveEditStatus(parsed.error);
                          return;
                        }
                        if (__DEV__ && debugEnabled('__bloomInspectorDebugLiveEdit')) {
                          console.info('Bloom Inspector: live-edit apply props parsed', {
                            raw: liveEditJson,
                            parsed: parsed.value,
                          });
                        }
                        if (looksLikeStyleObject(parsed.value)) {
                          setLiveEditStatus('Applying as style…');
                          if (__DEV__ && debugEnabled('__bloomInspectorDebugLiveEdit')) {
                            console.info('Bloom Inspector: live-edit interpreted props as style', {
                              keys: Object.keys(parsed.value),
                            });
                          }
                          applyNativeProps({ style: parsed.value });
                          return;
                        }
                        applyNativeProps(parsed.value);
                      }}
                      style={styles.inlineActionButton}>
                      <Text style={styles.inlineActionText}>Apply props</Text>
                    </Pressable>
                  </View>
                </>
              )}

              {activeTab === 'raw' && (
                <>
                  <View style={styles.sectionHeaderRow}>
                    <Text style={styles.sectionTitleInline}>Payload</Text>
                    <Pressable
                      onPress={() => copyToClipboard(JSON.stringify(payload, null, 2), 'payload')}
                      style={styles.inlineActionButton}>
                      <Text style={styles.inlineActionText}>Copy</Text>
                    </Pressable>
                  </View>
                  <Text style={styles.rawBody}>
                    {JSON.stringify(payload, null, 2) ?? String(payload)}
                  </Text>
                </>
              )}
            </ScrollView>
          )}
        </View>
      </View>
    </SafeAreaView>
  );
}

function formatValue(value: unknown): string {
  if (value == null) {
    return 'null';
  }
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'function') {
    return '[Function]';
  }
  if (typeof value === 'symbol') {
    return value.toString();
  }
  if (typeof value === 'bigint') {
    return value.toString();
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }
  try {
    const json = JSON.stringify(value);
    return json ?? String(value);
  } catch {
    return String(value);
  }
}

function isFiberNode(name: string): boolean {
  return /^Fiber\(\d+\)$/.test(name);
}

function isInternalComponentName(name: string): boolean {
  return INTERNAL_COMPONENT_NAMES.has(name);
}

function isHostHierarchyName(name: string): boolean {
  if (!name) {
    return true;
  }
  if (isFiberNode(name)) {
    return true;
  }
  if (name === 'View' || name === 'Text' || name === 'Image' || name === 'ScrollView') {
    return true;
  }
  return /^(RCT|UI|RN|RNC)/.test(name);
}

function isLocalFilePath(fileName: string): boolean {
  if (!fileName) {
    return false;
  }
  if (fileName.startsWith('http://') || fileName.startsWith('https://')) {
    return false;
  }
  if (fileName.startsWith('/')) {
    return true;
  }
  if (/^[a-zA-Z]:[\\/]/.test(fileName)) {
    return true;
  }
  return false;
}

function formatSnippetLines(snippet: SourceSnippet): SourceSnippetLine[] {
  const { startLine, lines, lineNumber } = snippet;
  const maxLineNo = startLine + lines.length - 1;
  const padWidth = String(maxLineNo).length;
  return lines.map((line, index) => {
    const lineNo = startLine + index;
    return {
      lineNumber: lineNo,
      isCurrent: lineNo === lineNumber,
      text: `${String(lineNo).padStart(padWidth, ' ')} | ${line}`,
    };
  });
}

function getSnippetOrigins(devServerOrigin: string): string[] {
  const origins: string[] = [];
  if (devServerOrigin) {
    origins.push(devServerOrigin);
  }
  try {
    const url = new URL(devServerOrigin);
    const port = url.port ? Number(url.port) : url.protocol === 'https:' ? 443 : 80;
    // If we are hitting a "manifest" server (80/443), Metro is often on 8081.
    if (port === 80 || port === 443) {
      const metro = new URL(devServerOrigin);
      metro.port = '8081';
      origins.push(metro.origin);
    }
  } catch {
    // ignore
  }
  return Array.from(new Set(origins));
}

function isNoisyStackName(name: string): boolean {
  if (!name) {
    return true;
  }
  if (isInternalComponentName(name)) {
    return true;
  }
  if (isHostHierarchyName(name)) {
    return true;
  }
  if (/^Animated\(/.test(name)) {
    return true;
  }
  return false;
}

function getComponentNameFromComponentStackLine(line: string): string {
  let name = line.trim();
  if (name.startsWith('in ')) {
    name = name.slice(3);
  } else if (name.startsWith('at ')) {
    name = name.slice(3);
  }
  const parenIndex = name.indexOf(' (');
  if (parenIndex > 0) {
    name = name.slice(0, parenIndex);
  }
  return name.trim();
}

function normalizeSourceFileName(fileName: string): string {
  if (!fileName) {
    return fileName;
  }
  const httpMatchIndex = fileName.search(/https?:\/\//);
  if (httpMatchIndex >= 0) {
    return normalizeMetroBundleUrl(fileName.slice(httpMatchIndex));
  }
  if (fileName.startsWith('file://')) {
    return normalizeMetroBundleUrl(fileName.replace('file://', ''));
  }
  return normalizeMetroBundleUrl(fileName);
}

function getDevServerOrigin(fileName: string | null): string | null {
  if (fileName && (fileName.startsWith('http://') || fileName.startsWith('https://'))) {
    try {
      return new URL(fileName).origin;
    } catch {
      return null;
    }
  }
  const scriptURL = NativeModules?.SourceCode?.getConstants?.().scriptURL;
  if (typeof scriptURL === 'string') {
    try {
      return new URL(scriptURL).origin;
    } catch {
      return null;
    }
  }
  return null;
}

function isBundleUrl(fileName: string): boolean {
  if (!fileName) {
    return false;
  }
  if (fileName.startsWith('http://') || fileName.startsWith('https://')) {
    return true;
  }
  return fileName.includes('index.bundle');
}

async function fetchWithSoftTimeout(
  url: string,
  options: RequestInit,
  timeoutMs: number,
  context: string
): Promise<Response> {
  let timeoutHandle: ReturnType<typeof setTimeout> | null = null;
  const timeoutPromise = new Promise<never>((_, reject) => {
    timeoutHandle = setTimeout(() => {
      reject(new Error(`${context} timed out after ${timeoutMs}ms`));
    }, timeoutMs);
  });

  try {
    // "Soft" timeout: we don't abort the underlying fetch (RN support is inconsistent),
    // but we surface a useful error quickly.
    const response = (await Promise.race([fetch(url, options), timeoutPromise])) as Response;
    return response;
  } finally {
    if (timeoutHandle) {
      clearTimeout(timeoutHandle);
    }
  }
}

function normalizeMetroBundleUrl(fileName: string): string {
  if (!fileName.includes('index.bundle') || fileName.includes('index.bundle?')) {
    return fileName;
  }
  return (
    fileName
      // Some sources produce `index.bundle//&platform=...` (missing `?`).
      .replace(/index\.bundle\/+&/g, 'index.bundle?')
      .replace(/index\.bundle&/g, 'index.bundle?')
  );
}

async function resolveOpenInEditorFrame(
  devServerOrigin: string,
  fileName: string,
  lineNumber: number,
  columnNumber: number
): Promise<{ file: string; lineNumber: number; columnNumber: number } | null> {
  const normalizedFileName = normalizeMetroBundleUrl(fileName);
  if (!isBundleUrl(normalizedFileName)) {
    return { file: normalizedFileName, lineNumber, columnNumber };
  }
  try {
    const symbolicateUrl = `${devServerOrigin}/symbolicate`;
    const requestBody = JSON.stringify({
      stack: [
        {
          file: normalizedFileName,
          lineNumber,
          column: columnNumber,
          methodName: 'BloomInspector',
        },
      ],
    });
    if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
      console.info('Bloom Inspector: symbolicate request', {
        url: symbolicateUrl,
        file: normalizedFileName,
        lineNumber,
        columnNumber,
      });
    }
    const response = await fetchWithSoftTimeout(
      symbolicateUrl,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: requestBody,
      },
      8000,
      'symbolicate'
    );
    if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
      console.info('Bloom Inspector: symbolicate response headers', {
        status: response.status,
        ok: response.ok,
        contentType: response.headers?.get?.('content-type') ?? null,
      });
    }
    if (!response.ok) {
      if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
        const text = await response.text().catch(() => '');
        const trimmedText = text.length > 400 ? `${text.slice(0, 400)}…` : text;
        console.warn('Bloom Inspector: symbolicate failed', {
          url: symbolicateUrl,
          status: response.status,
          requestBody: requestBody.length > 400 ? `${requestBody.slice(0, 400)}…` : requestBody,
          responseText: trimmedText || null,
        });
      }
      return null;
    }

    const data = (await response.json()) as {
      stack?: { file?: string; lineNumber?: number; column?: number }[];
    };
    const frame = data.stack?.[0];
    if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
      console.info('Bloom Inspector: symbolicate parsed frame', frame ?? null);
    }
    if (!frame?.file || isBundleUrl(frame.file)) {
      return null;
    }
    return {
      file: frame.file,
      lineNumber: frame.lineNumber ?? lineNumber,
      columnNumber: frame.column ?? columnNumber,
    };
  } catch (error) {
    if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
      console.warn('Bloom Inspector: symbolicate request failed', {
        error: String(error),
        devServerOrigin,
        file: normalizedFileName,
        lineNumber,
        columnNumber,
      });
    }
    return null;
  }
}

function getBestFrameFromComponentStack(
  componentStack: string
): { file: string; lineNumber: number; columnNumber?: number } | null {
  const frames = parseComponentStackFrames(componentStack);
  if (!frames.length) {
    return null;
  }
  const preferNonNodeModules = frames.find((frame) => !/\/node_modules\//.test(frame.file));
  return preferNonNodeModules ?? frames[0];
}

function parseComponentStackFrames(
  componentStack: string
): { file: string; lineNumber: number; columnNumber?: number }[] {
  const lines = componentStack
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);

  const frames: { file: string; lineNumber: number; columnNumber?: number }[] = [];
  for (const line of lines) {
    // Common RN componentStack line format:
    // `in ComponentName (at path/to/File.tsx:123:45)`
    // Some variants omit column.
    const match =
      line.match(/\(at (.+?):(\d+)(?::(\d+))?\)/) ??
      // Some stacks use `at path/to/File.tsx:123:45` (without parentheses).
      line.match(/\bat (.+?):(\d+)(?::(\d+))?\b/);
    if (!match) {
      continue;
    }
    const file = match[1];
    const lineNumber = Number(match[2]);
    const columnNumber = match[3] ? Number(match[3]) : undefined;
    if (!file || !Number.isFinite(lineNumber) || lineNumber <= 0) {
      continue;
    }
    frames.push({ file, lineNumber, columnNumber });
  }
  return frames;
}

/* Old implementation kept for reference while debugging:
async function resolveOpenInEditorFrame(
  devServerOrigin: string,
  fileName: string,
  lineNumber: number,
  columnNumber: number
): Promise<{ file: string; lineNumber: number; columnNumber: number } | null> {
  const normalizedFileName = normalizeMetroBundleUrl(fileName);
  if (!isBundleUrl(normalizedFileName)) {
    return { file: normalizedFileName, lineNumber, columnNumber };
  }
  try {
    if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
      console.info('Bloom Inspector: symbolicate request', {
        devServerOrigin,
        file: normalizedFileName,
        lineNumber,
        columnNumber,
      });
    }
    const response = await fetch(`${devServerOrigin}/symbolicate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        stack: [
          {
            file: normalizedFileName,
            lineNumber,
            column: columnNumber,
            methodName: 'BloomInspector',
          },
        ],
      }),
    });
    if (!response.ok) {
      if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
        const text = await response.text().catch(() => '');
        const trimmedText = text.length > 400 ? `${text.slice(0, 400)}…` : text;
        console.warn('Bloom Inspector: symbolicate failed', {
          status: response.status,
          responseText: trimmedText || null,
        });
      }
      return null;
    }
    const data = (await response.json()) as {
      stack?: { file?: string; lineNumber?: number; column?: number }[];
    };
    const frame = data.stack?.[0];
    if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
      console.info('Bloom Inspector: symbolicate response', frame ?? null);
    }
    if (!frame?.file || isBundleUrl(frame.file)) {
      return null;
    }
    return {
      file: frame.file,
      lineNumber: frame.lineNumber ?? lineNumber,
      columnNumber: frame.column ?? columnNumber,
    };
  } catch (error) {
    if (__DEV__ && (DEBUG_BLOOM_LOGS || DEBUG_OPEN_IN_EDITOR)) {
      console.warn('Bloom Inspector: symbolicate request failed', { error: String(error) });
    }
    return null;
  }
}
*/

function formatSourceLabel(fileName: string, lineNumber?: number, showRawSource?: boolean): string {
  const normalized = normalizeSourceFileName(fileName);
  if (showRawSource) {
    return `${normalized}${lineNumber != null ? `:${lineNumber}` : ''}`;
  }
  const label = getBasename(normalized);
  return `${label}${lineNumber != null ? `:${lineNumber}` : ''}`;
}

function getBasename(fileName: string): string {
  if (!fileName) {
    return fileName;
  }
  if (fileName.startsWith('http://') || fileName.startsWith('https://')) {
    try {
      const url = new URL(fileName);
      const path = (url.pathname || '').replace(/\/+$/, '');
      const lastSlash = path.lastIndexOf('/');
      return lastSlash >= 0 ? path.slice(lastSlash + 1) : path || fileName;
    } catch {
      // Fall through to string parsing.
    }
  }
  const trimmed = fileName.replace(/\/+$/, '');
  const lastSlash = Math.max(trimmed.lastIndexOf('/'), trimmed.lastIndexOf('\\'));
  return lastSlash >= 0 ? trimmed.slice(lastSlash + 1) : trimmed;
}

const styles = StyleSheet.create({
  container: {
    ...StyleSheet.absoluteFillObject,
  },
  panelWrap: {
    flex: 1,
    padding: 10,
  },
  panelWrapBottom: {
    justifyContent: 'flex-end',
  },
  panelWrapTop: {
    justifyContent: 'flex-start',
  },
  panel: {
    backgroundColor: 'rgba(255, 255, 255, 0.96)',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(0, 0, 0, 0.08)',
    maxHeight: '50%',
    overflow: 'hidden',
  },
  header: {
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(0, 0, 0, 0.08)',
    flexDirection: 'row',
    alignItems: 'center',
  },
  title: {
    fontSize: 14,
    fontWeight: '600',
    color: '#111',
    flex: 1,
  },
  closeButton: {
    width: 28,
    height: 28,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 14,
    backgroundColor: 'rgba(0,0,0,0.06)',
  },
  closeText: {
    fontSize: 18,
    color: '#111',
    lineHeight: 20,
  },
  placeholder: {
    padding: 12,
    color: '#555',
  },
  content: {
    paddingHorizontal: 12,
  },
  contentContainer: {
    paddingVertical: 10,
    gap: 6,
  },
  tabRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
    marginBottom: 6,
  },
  tabChip: {
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(0,0,0,0.1)',
    paddingHorizontal: 10,
    paddingVertical: 6,
    backgroundColor: 'rgba(0,0,0,0.04)',
  },
  tabChipActive: {
    backgroundColor: 'rgba(0,0,0,0.12)',
    borderColor: 'rgba(0,0,0,0.2)',
  },
  tabText: {
    fontSize: 11,
    color: '#222',
    fontWeight: '600',
  },
  sectionTitle: {
    fontSize: 12,
    fontWeight: '600',
    color: '#111',
    marginTop: 8,
  },
  sectionTitleInline: {
    fontSize: 12,
    fontWeight: '600',
    color: '#111',
    flex: 1,
  },
  sectionHeaderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginTop: 8,
  },
  inlineActionsRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
    marginTop: 4,
    alignItems: 'center',
  },
  inlineActionButton: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 10,
    backgroundColor: 'rgba(0,0,0,0.06)',
  },
  inlineActionButtonPrimary: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 10,
    backgroundColor: 'rgba(0,0,0,0.1)',
  },
  inlineActionText: {
    fontSize: 11,
    color: '#222',
    fontWeight: '600',
  },
  inlineActionTextPrimary: {
    fontSize: 11,
    color: '#111',
    fontWeight: '700',
  },
  sectionBody: {
    fontSize: 12,
    color: '#333',
  },
  rawBody: {
    fontSize: 11,
    color: '#333',
  },
  snippetContainer: {
    marginTop: 6,
    backgroundColor: 'rgba(0,0,0,0.04)',
    borderColor: 'rgba(0,0,0,0.08)',
    borderWidth: 1,
    borderRadius: 10,
    paddingVertical: 8,
    paddingHorizontal: 10,
    gap: 2,
  },
  snippetLine: {
    fontSize: 11,
    color: '#222',
    fontFamily: 'Menlo',
  },
  snippetLineCurrent: {
    backgroundColor: 'rgba(255, 230, 150, 0.6)',
    borderRadius: 6,
    overflow: 'hidden',
    paddingHorizontal: 4,
    paddingVertical: 1,
  },
  sectionHint: {
    fontSize: 11,
    color: '#666',
  },
  toggleRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
    marginBottom: 6,
  },
  toggleChip: {
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(0,0,0,0.1)',
    paddingHorizontal: 8,
    paddingVertical: 4,
    backgroundColor: 'rgba(0,0,0,0.04)',
  },
  toggleChipActive: {
    backgroundColor: 'rgba(0,0,0,0.12)',
    borderColor: 'rgba(0,0,0,0.2)',
  },
  toggleText: {
    fontSize: 11,
    color: '#222',
  },
  badgeText: {
    fontSize: 11,
    color: '#444',
    backgroundColor: 'rgba(0,0,0,0.06)',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 10,
    overflow: 'hidden',
  },
  propsToolbar: {
    flexDirection: 'row',
    gap: 6,
    marginTop: 6,
    alignItems: 'center',
  },
  propsSearch: {
    flex: 1,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(0,0,0,0.12)',
    paddingHorizontal: 10,
    paddingVertical: 6,
    fontSize: 12,
    backgroundColor: 'rgba(255,255,255,0.9)',
    color: '#111',
  },
  liveEditInput: {
    marginTop: 8,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(0,0,0,0.12)',
    paddingHorizontal: 10,
    paddingVertical: 8,
    fontSize: 12,
    backgroundColor: 'rgba(255,255,255,0.9)',
    color: '#111',
    fontFamily: 'Menlo',
    minHeight: 120,
  },
  propRow: {
    marginTop: 4,
  },
  propKey: {
    fontSize: 12,
    color: '#222',
    fontWeight: '600',
  },
  propValue: {
    fontSize: 12,
    color: '#444',
  },
  hierarchyTree: {
    marginTop: 6,
    borderWidth: 1,
    borderColor: 'rgba(0,0,0,0.08)',
    borderRadius: 10,
    backgroundColor: 'rgba(0,0,0,0.03)',
    paddingVertical: 6,
    paddingHorizontal: 8,
    height: 150,
    gap: 2,
  },
  hierarchyRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 2,
  },
  hierarchyIndent: {
    fontSize: 11,
    fontFamily: 'Menlo',
    color: 'transparent',
  },
  hierarchyRowText: {
    flex: 1,
    fontSize: 11,
    fontFamily: 'Menlo',
    color: '#222',
  },
});
