import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Alert,
  Clipboard,
  DeviceEventEmitter,
  Dimensions,
  NativeEventEmitter,
  NativeModules,
  Pressable,
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

const DEBUG_BLOOM_LOGS = false;
const DEBUG_OPEN_IN_EDITOR = false;
const DEBUG_SOURCE_SNIPPET = false;
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

export function BloomInspectorOverlayPanel() {
  const [enabled, setEnabled] = useState(false);
  const [payload, setPayload] = useState<PickPayload | null>(null);
  type TabKey = 'overview' | 'source' | 'props' | 'raw';
  const [activeTab, setActiveTab] = useState<TabKey>('overview');
  const [showRawSource, setShowRawSource] = useState(false);
  const [showFiberNodes, setShowFiberNodes] = useState(false);
  const [showFullStack, setShowFullStack] = useState(false);
  const [propsQuery, setPropsQuery] = useState('');
  const [sourceSnippet, setSourceSnippet] = useState<SourceSnippet | null>(null);
  const [isSnippetLoading, setIsSnippetLoading] = useState(false);
  const [panelHeight, setPanelHeight] = useState<number | null>(null);
  const panelRef = useRef<View | null>(null);
  const payloadByTouchID = useRef<Map<number, { native?: PickPayload; js?: PickPayload }>>(
    new Map()
  );

  const clearSelection = useCallback(() => {
    setPayload(null);
    setPropsQuery('');
    payloadByTouchID.current.clear();
    NativeModules.BloomInspectorOverlay?.clearSelection?.();
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
    const source = payload?.source;
    if (!source?.fileName) {
      return null;
    }
    return formatSourceLabel(source.fileName, source.lineNumber, showRawSource);
  }, [payload, showRawSource]);

  const sourceKindLabel = useMemo(() => {
    const fileName = payload?.source?.fileName;
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
    const fileName = payload?.source?.fileName;
    if (!fileName) {
      return false;
    }
    return normalizeSourceFileName(fileName).includes('/node_modules/');
  }, [payload?.source?.fileName]);

  const sourceFileName = useMemo(() => {
    const source = payload?.source;
    if (!source?.fileName) {
      return null;
    }
    return normalizeSourceFileName(source.fileName);
  }, [payload]);

  const devServerOrigin = useMemo(() => getDevServerOrigin(sourceFileName), [sourceFileName]);

  const canShowSnippet = useMemo(() => {
    const lineNumber = payload?.source?.lineNumber;
    return Boolean(
      enabled &&
        devServerOrigin &&
        sourceFileName &&
        typeof lineNumber === 'number' &&
        lineNumber > 0 &&
        isLocalFilePath(sourceFileName) &&
        activeTab === 'source'
    );
  }, [activeTab, devServerOrigin, enabled, payload?.source?.lineNumber, sourceFileName]);

  useEffect(() => {
    const fileName = sourceFileName;
    const lineNumber = payload?.source?.lineNumber;
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
  }, [canShowSnippet, devServerOrigin, payload?.source?.lineNumber, sourceFileName]);

  const componentStackFrame = useMemo(() => {
    if (!payload?.componentStack) {
      return null;
    }
    return getBestFrameFromComponentStack(payload.componentStack);
  }, [payload?.componentStack]);

  const canOpenInEditor = useMemo(() => {
    return Boolean(
      sourceFileName &&
        devServerOrigin &&
        ((typeof payload?.source?.lineNumber === 'number' && payload.source.lineNumber >= 0) ||
          componentStackFrame)
    );
  }, [componentStackFrame, devServerOrigin, payload, sourceFileName]);

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

  const handleOpenInEditor = useCallback(() => {
    const source = payload?.source;
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
          originalFileName: source?.fileName ?? null,
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
                  onPress={() => setActiveTab('props')}
                  style={[styles.tabChip, activeTab === 'props' && styles.tabChipActive]}>
                  <Text style={styles.tabText}>Props</Text>
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

                  <View style={styles.sectionHeaderRow}>
                    <Text style={styles.sectionTitleInline}>Hierarchy</Text>
                    <Pressable
                      onPress={() => setShowFiberNodes((value) => !value)}
                      style={[styles.toggleChip, showFiberNodes && styles.toggleChipActive]}>
                      <Text style={styles.toggleText}>
                        {showFiberNodes ? 'Fiber On' : 'Fiber Off'}
                      </Text>
                    </Pressable>
                  </View>
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
                      {sourceSnippet?.lines?.length ? (
                        <Text style={styles.snippetBody}>{formatSnippet(sourceSnippet)}</Text>
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
                              `${normalizeSourceFileName(payload?.source?.fileName ?? '')}:${
                                payload?.source?.lineNumber ?? ''
                              }`,
                              'source'
                            )
                          }
                          style={styles.inlineActionButton}>
                          <Text style={styles.inlineActionText}>Copy</Text>
                        </Pressable>
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

function formatSnippet(snippet: SourceSnippet): string {
  const { startLine, lines, lineNumber } = snippet;
  const maxLineNo = startLine + lines.length - 1;
  const padWidth = String(maxLineNo).length;
  return lines
    .map((line, index) => {
      const lineNo = startLine + index;
      const marker = lineNo === lineNumber ? '>' : ' ';
      return `${marker} ${String(lineNo).padStart(padWidth, ' ')} | ${line}`;
    })
    .join('\n');
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
  snippetBody: {
    marginTop: 6,
    fontSize: 11,
    color: '#222',
    fontFamily: 'Menlo',
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
});
