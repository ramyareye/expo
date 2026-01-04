import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  DeviceEventEmitter,
  Dimensions,
  NativeEventEmitter,
  NativeModules,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
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

export function BloomInspectorOverlayPanel() {
  const [enabled, setEnabled] = useState(false);
  const [payload, setPayload] = useState<PickPayload | null>(null);
  const panelRef = useRef<View | null>(null);
  const payloadByTouchID = useRef<Map<number, { native?: PickPayload; js?: PickPayload }>>(
    new Map()
  );

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
      console.info('Bloom Log: 95 overlay pick received keys=' + Object.keys(data ?? {}).join(','));
      console.info(JSON.stringify(data));
      if (!data) {
        setPayload(null);
        return;
      }
      const touchID = typeof data.touchID === 'number' ? data.touchID : null;
      if (touchID != null) {
        const entry = payloadByTouchID.current.get(touchID) ?? {};
        if (data.payloadSource === 'js' && entry.js) {
          console.info(`Bloom Log: 95 merge ignore duplicate js touchID=${touchID}`);
          return;
        }
        if (data.payloadSource !== 'js' && entry.js) {
          console.info(`Bloom Log: 95 merge ignore native touchID=${touchID} (js already present)`);
          return;
        }
        if (data.payloadSource !== 'js' && entry.native) {
          console.info(`Bloom Log: 95 merge ignore duplicate native touchID=${touchID}`);
          return;
        }
        if (data.payloadSource === 'js') {
          entry.js = data;
        } else {
          entry.native = data;
        }
        payloadByTouchID.current.set(touchID, entry);
        const merged = entry.js ?? entry.native ?? data;
        console.info(
          `Bloom Log: 95 merge apply touchID=${touchID} source=${merged.payloadSource ?? 'unknown'}`
        );
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
        if (!data?.enabled) {
          setPayload(null);
        }
      }
    );
    return () => {
      pickSub.remove();
      devicePickSub.remove();
      toggleSub.remove();
    };
  }, []);

  const propsEntries = useMemo(() => {
    if (!payload?.props) {
      return [];
    }
    return Object.entries(payload.props).sort(([a], [b]) => a.localeCompare(b));
  }, [payload]);

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

  const panelPosition = useMemo(() => {
    if (!payload?.frame) {
      return 'bottom';
    }
    const midY = payload.frame.top + payload.frame.height / 2;
    const screenMid = Dimensions.get('window').height / 2;
    return midY < screenMid ? 'bottom' : 'top';
  }, [payload]);

  const handlePanelLayout = useCallback(() => {
    const panel = panelRef.current;
    if (!panel || !NativeModules.BloomInspectorOverlay?.setPanelFrame) {
      return;
    }
    panel.measureInWindow((x, y, width, height) => {
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
              onPress={() => NativeModules.BloomInspectorOverlay?.toggle?.()}
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
              <Text style={styles.sectionTitle}>React Stack</Text>
              {reactStackLines.length ? (
                <Text style={styles.sectionBody}>{reactStackLines.join('\n')}</Text>
              ) : (
                <Text style={styles.sectionBody}>Unavailable</Text>
              )}

              <Text style={styles.sectionTitle}>Source</Text>
              {payload.source?.fileName ? (
                <Text style={styles.sectionBody}>
                  {payload.source.fileName}
                  {payload.source.lineNumber != null ? `:${payload.source.lineNumber}` : ''}
                </Text>
              ) : (
                <Text style={styles.sectionBody}>Unavailable</Text>
              )}

              <Text style={styles.sectionTitle}>Hierarchy</Text>
              {payload.hierarchy?.length ? (
                <Text style={styles.sectionBody}>
                  {payload.hierarchy.map((item) => item.name).join(' > ')}
                </Text>
              ) : (
                <Text style={styles.sectionBody}>Unavailable</Text>
              )}

              <Text style={styles.sectionTitle}>Frame</Text>
              {payload.frame ? (
                <Text style={styles.sectionBody}>
                  {`x: ${payload.frame.left.toFixed(1)}, y: ${payload.frame.top.toFixed(1)}, `}
                  {`w: ${payload.frame.width.toFixed(1)}, h: ${payload.frame.height.toFixed(1)}`}
                </Text>
              ) : (
                <Text style={styles.sectionBody}>Unavailable</Text>
              )}

              <Text style={styles.sectionTitle}>Props</Text>
              {propsEntries.length === 0 ? (
                <Text style={styles.sectionBody}>No props available.</Text>
              ) : (
                propsEntries.map(([key, value]) => (
                  <View key={key} style={styles.propRow}>
                    <Text style={styles.propKey}>{key}</Text>
                    <Text style={styles.propValue}>
                      {formatValue(value)} ({typeof value})
                    </Text>
                  </View>
                ))
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
  sectionTitle: {
    fontSize: 12,
    fontWeight: '600',
    color: '#111',
    marginTop: 8,
  },
  sectionBody: {
    fontSize: 12,
    color: '#333',
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
