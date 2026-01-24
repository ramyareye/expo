import {
  useState,
  createContext,
  useContext,
  useCallback,
  useRef,
  type RefObject,
  useEffect,
} from 'react';
import { View, StyleSheet, findNodeHandle, NativeEventEmitter, NativeModules } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import ElementBox from 'src/mobileInspector/ElementBox';
import { ElementPickerOverlay } from 'src/mobileInspector/ElementPickerOverlay';
import ElementProperties from 'src/mobileInspector/ElementProperties';
import {
  getInspectorDataForViewAtPoint,
  getReactMetadataFromViewData,
} from 'src/mobileInspector/getInspectorDataForViewAtPoint';
import type {
  InspectorElementBoxPosition,
  InspectorViewData,
} from 'src/mobileInspector/inspectorTypes';

// type ScreenRootMap = Record<string, React.RefObject<any>>;

type ContextValue = {
  enabled: boolean;
  setEnabled: (value: boolean) => void;
  setInspectedRootRef: (ref: RefObject<View | null> | null) => void;
  // activeRouteKey?: string;
  // setActiveRouteKey: (key: string | undefined) => void;

  // registerScreenRoot: (routeKey: string, ref: React.RefObject<any>) => void;
  // getCurrentInspectedRoot: () => React.RefObject<any> | null;
};

const BloomInspectorContext = createContext<ContextValue | null>(null);

type PickPayload = {
  frame?: InspectorViewData['frame'];
  hierarchy?: { name: string }[];
  props?: Record<string, unknown>;
  selectedIndex?: number;
  componentStack?: string;
  source?: { fileName?: string; lineNumber?: number; columnNumber?: number };
  touchID?: number;
  payloadSource?: 'js' | 'native';
};

const DEBUG_BLOOM_LOGS = false;

export function useBloomInspector() {
  const context = useContext(BloomInspectorContext);

  if (context === null) {
    throw new Error('useBloomInspector must be used within a BloomInspectorProvider');
  }

  return context;
}

export function BloomInspectorProvider({ children }: { children: React.ReactNode }) {
  const inspectedViewRef = useRef<View | null>(null);
  const [inspectedRootRef, setInspectedRootRef] = useState<RefObject<View | null> | null>(null);
  const [enabled, setEnabled] = useState(false);
  const [viewData, setViewData] = useState<InspectorViewData | null>(null);
  const [frame, setFrame] = useState<InspectorViewData['frame'] | null>(null);
  type InspectorStyle = NonNullable<InspectorViewData['props']>['style'];
  const [style, setStyle] = useState<InspectorStyle>();
  const [selectionIndex, setSelectionIndex] = useState<number | null>(null);
  // const [activeRouteKey, setActiveRouteKey] = useState<string | undefined>();
  // const [screenRoots, setScreenRoots] = useState<ScreenRootMap>({});
  const [elementBoxPosition, setElementBoxPosition] = useState<InspectorElementBoxPosition>('top');

  const setSelection = useCallback(
    (index: number) => {
      if (!viewData?.hierarchy) return;

      const item = viewData.hierarchy[index];
      if (!item) return;

      const inspectorData = item.getInspectorData(findNodeHandle);
      if (!inspectorData?.measure) return;
      const { measure, props } = inspectorData;
      measure(
        (_x: number, _y: number, width: number, height: number, left: number, top: number) => {
          setFrame({ left, top, width, height });
          setStyle(props?.style);
          setSelectionIndex(index);
        }
      );
    },
    [viewData]
  );

  const handleNativeTap = useCallback(
    (payload: { x?: number; y?: number; touchID?: number }) => {
      if (DEBUG_BLOOM_LOGS) {
        console.info('Bloom Log: 38-5 handleNativeTap');
      }
      const x = payload?.x;
      const y = payload?.y;
      if (typeof x !== 'number' || typeof y !== 'number') {
        return;
      }

      const inspectedRef = inspectedRootRef?.current ?? inspectedViewRef.current;
      if (!inspectedRef) {
        return;
      }

      inspectedRef.measureInWindow((left, top, _width, _height) => {
        const localX = x - left;
        const localY = y - top;
        getInspectorDataForViewAtPoint(inspectedRef, localX, localY, (data) => {
          if (!data) {
            return false;
          }
          const metadata = getReactMetadataFromViewData(data);
          const pickPayload = toPickPayload(data, metadata);
          if (pickPayload && NativeModules.BloomInspectorOverlay?.sendPick) {
            if (payload?.touchID != null) {
              pickPayload.touchID = payload.touchID;
            }
            pickPayload.payloadSource = 'js';
            if (DEBUG_BLOOM_LOGS) {
              console.info(
                `Bloom Log: 38-4 js payload keys=${Object.keys(pickPayload).join(',')} source=${
                  pickPayload.source ? 'yes' : 'no'
                }`
              );
            }
            NativeModules.BloomInspectorOverlay.sendPick(pickPayload);
          }
          return true;
        });
      });
    },
    [inspectedRootRef]
  );

  useEffect(() => {
    const module = NativeModules.BloomInspector;
    if (!module) {
      return;
    }
    const emitter = new NativeEventEmitter(module);
    const subscription = emitter.addListener('bloomInspectorTap', (payload) => {
      handleNativeTap(payload);
    });
    return () => subscription.remove();
  }, [handleNativeTap]);

  // const registerScreenRoot = useCallback((routeKey: string, ref: React.RefObject<any>) => {
  //   console.log('registerScreenRoot');
  //   setScreenRoots((prev) => ({ ...prev, [routeKey]: ref }));
  // }, []);

  // const getCurrentInspectedRoot = useCallback(() => {
  //   if (activeRouteKey && screenRoots[activeRouteKey]) {
  //     return screenRoots[activeRouteKey];
  //   }
  //   return null;
  // }, [activeRouteKey, screenRoots]);

  // const currentInspectedRoot = useMemo(() => {
  //   if (activeRouteKey && screenRoots[activeRouteKey]) {
  //     return screenRoots[activeRouteKey];
  //   }
  //   return inspectedViewRef;
  // }, [activeRouteKey, screenRoots]);

  // console.log({ activeRouteKey, currentInspectedRoot });
  const handlePick = useCallback((data: InspectorViewData) => {
    // data is what you logged: { hierarchy, props, frame, selectedIndex, ... }
    const { frame, props, selectedIndex } = data;

    setViewData(data);
    setFrame(frame);
    setStyle(props?.style);
    setSelectionIndex(selectedIndex);
  }, []);

  return (
    <BloomInspectorContext.Provider
      value={{
        enabled,
        setEnabled,
        setInspectedRootRef,
        // activeRouteKey,
        // setActiveRouteKey,
        // registerScreenRoot,
      }}>
      <View style={styles.root} ref={inspectedViewRef}>
        {children}
      </View>

      {enabled && (
        <>
          {frame && <ElementBox frame={frame} style={style} />}

          <ElementPickerOverlay
            onPick={handlePick}
            inspectedViewRef={inspectedRootRef ?? inspectedViewRef}
            setElementBoxPosition={setElementBoxPosition}
          />

          <SafeAreaView
            style={[
              styles.panel,
              elementBoxPosition === 'bottom' ? styles.panelTop : styles.panelBottom,
            ]}>
            <ElementProperties
              hierarchy={viewData?.hierarchy}
              style={style}
              frame={frame}
              selection={selectionIndex ?? undefined}
              setSelection={setSelection}
            />
          </SafeAreaView>
        </>
      )}
    </BloomInspectorContext.Provider>
  );
}

function toPickPayload(
  viewData: InspectorViewData,
  metadata?: ReturnType<typeof getReactMetadataFromViewData>
): PickPayload | null {
  if (DEBUG_BLOOM_LOGS) {
    console.info('Bloom Log: 38-6 toPickPayload start');
  }
  if (!viewData?.hierarchy?.length) {
    return null;
  }

  const selectedItem = viewData.hierarchy[viewData.selectedIndex];
  let props: Record<string, unknown> | undefined =
    (viewData.props as Record<string, unknown> | undefined) ?? undefined;
  if (!props && selectedItem?.getInspectorData) {
    const inspectorData = selectedItem.getInspectorData(findNodeHandle);
    if (inspectorData?.props) {
      props = inspectorData.props as Record<string, unknown>;
    }
  }

  const payload: PickPayload = {
    frame: viewData.frame,
    hierarchy:
      metadata?.hierarchy ?? viewData.hierarchy.map((item) => ({ name: item.name ?? 'Anonymous' })),
    props: metadata?.props
      ? (sanitizeValue(stripInternalProps(metadata.props)) as Record<string, unknown>)
      : props
        ? (sanitizeValue(stripInternalProps(props)) as Record<string, unknown>)
        : undefined,
    selectedIndex: viewData.selectedIndex,
  };

  const extra = viewData as InspectorViewData & {
    componentStack?: string;
    source?: { fileName?: string; lineNumber?: number; columnNumber?: number };
  };
  if (DEBUG_BLOOM_LOGS) {
    console.info(
      `Bloom Log: 38-7 source precheck metadata=${
        metadata?.source?.fileName ?? 'none'
      } extra=${extra.source?.fileName ?? 'none'}`
    );
  }
  if (metadata?.componentStack) {
    payload.componentStack = metadata.componentStack;
  } else if (extra.componentStack) {
    payload.componentStack = extra.componentStack;
  }
  const sourceCandidates: NonNullable<PickPayload['source']>[] = [];
  const propsSource =
    getSourceFromProps(props) ??
    getSourceFromProps(metadata?.props) ??
    findSourceInPropsTree(props) ??
    findSourceInPropsTree(metadata?.props);
  if (propsSource) {
    sourceCandidates.push(propsSource);
    if (DEBUG_BLOOM_LOGS) {
      console.info(`Bloom Log: 38-7 props source=${propsSource.fileName ?? 'none'}`);
    }
  }
  if (metadata?.source) {
    sourceCandidates.push(metadata.source);
  }
  if (extra.source) {
    sourceCandidates.push(extra.source);
  }
  if (viewData?.hierarchy && shouldSearchHierarchySources(sourceCandidates)) {
    let logged = 0;
    for (const item of viewData.hierarchy) {
      if (!item?.getInspectorData) {
        continue;
      }
      try {
        const inspectorData = item.getInspectorData(findNodeHandle) as ReturnType<
          typeof item.getInspectorData
        > & {
          source?: { fileName?: string; lineNumber?: number; columnNumber?: number };
        };
        const candidate = inspectorData.source as
          | { fileName?: string; lineNumber?: number; columnNumber?: number }
          | undefined;
        if (candidate?.fileName) {
          sourceCandidates.push(candidate);
          if (DEBUG_BLOOM_LOGS && logged < 12) {
            const name = (item as { name?: string }).name ?? 'unknown';
            console.info(
              `Bloom Log: 38-8 hierarchy source name=${name} file=${candidate.fileName}`
            );
            logged += 1;
          }
        }
      } catch {
        // ignore
      }
    }
  }
  const bestSource = pickBestSource(sourceCandidates);
  if (bestSource) {
    payload.source = bestSource;
  }

  if (DEBUG_BLOOM_LOGS && sourceCandidates.length) {
    const list = sourceCandidates
      .map((item) => item.fileName || 'unknown')
      .filter(Boolean)
      .slice(0, 8)
      .join(', ');
    console.info(`Bloom Log: 38-9 source candidates=${list}`);
  } else if (DEBUG_BLOOM_LOGS) {
    console.info('Bloom Log: 38-9 source candidates=none');
  }

  return payload;
}

function stripInternalProps(props: Record<string, unknown>): Record<string, unknown> {
  if (!props) {
    return props;
  }
  const result = { ...props };
  delete result.__bloomSource;
  delete result.__source;
  delete result.__self;
  return result;
}

function getSourceFromProps(
  props: Record<string, unknown> | null | undefined
): { fileName?: string; lineNumber?: number; columnNumber?: number } | null {
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

function findSourceInPropsTree(
  props: Record<string, unknown> | null | undefined,
  depth = 0
): { fileName?: string; lineNumber?: number; columnNumber?: number } | null {
  if (!props || depth > 2) {
    return null;
  }
  const direct = getSourceFromProps(props);
  if (direct) {
    return direct;
  }
  const children = props.children;
  if (!children) {
    return null;
  }
  if (Array.isArray(children)) {
    for (const child of children) {
      const source = findSourceInElement(child, depth + 1);
      if (source) {
        return source;
      }
    }
    return null;
  }
  return findSourceInElement(children, depth + 1);
}

function findSourceInElement(
  node: unknown,
  depth: number
): { fileName?: string; lineNumber?: number; columnNumber?: number } | null {
  if (!node || depth > 2) {
    return null;
  }
  if (typeof node === 'object') {
    const element = node as { props?: Record<string, unknown> };
    if (element.props) {
      const direct = getSourceFromProps(element.props);
      if (direct) {
        return direct;
      }
      return findSourceInPropsTree(element.props, depth + 1);
    }
  }
  return null;
}

function shouldSearchHierarchySources(
  sources: { fileName?: string; lineNumber?: number; columnNumber?: number }[]
): boolean {
  if (!sources.length) {
    return true;
  }
  return !sources.some((source) => isGoodSource(source?.fileName));
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

function isGoodSource(fileName: string | undefined): boolean {
  if (!fileName) {
    return false;
  }
  return !isBundleUrl(fileName) && !isNodeModulesPath(fileName);
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

function pickBestSource(
  sources: { fileName?: string; lineNumber?: number; columnNumber?: number }[]
): { fileName?: string; lineNumber?: number; columnNumber?: number } | null {
  if (!sources.length) {
    return null;
  }
  if (DEBUG_BLOOM_LOGS) {
    const details = sources
      .map((source) => {
        const name = source.fileName ?? 'unknown';
        const score = scoreSource(source.fileName);
        return `${name} (score=${score})`;
      })
      .slice(0, 12)
      .join(' | ');
    console.info(`Bloom Log: 38-10 source candidates detailed=${details}`);
  }
  let best = sources[0] ?? null;
  let bestScore = scoreSource(best?.fileName);
  for (const source of sources) {
    const score = scoreSource(source?.fileName);
    if (score > bestScore) {
      bestScore = score;
      best = source ?? null;
    }
  }
  return best ?? null;
}

function sanitizeValue(value: unknown, depth = 0): unknown {
  if (depth > 3) {
    return '[MaxDepth]';
  }
  if (value == null) {
    return value;
  }
  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((item) => sanitizeValue(item, depth + 1));
  }
  if (typeof value === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
      result[key] = sanitizeValue(item, depth + 1);
    }
    return result;
  }
  return String(value);
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  panel: {
    position: 'absolute',
    left: 0,
    right: 0,
    backgroundColor: 'rgb(236, 237, 239)',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 4,
    },
    shadowOpacity: 0.32,
    shadowRadius: 5.46,

    elevation: 9,
  },
  panelTop: {
    top: 0,
  },
  panelBottom: {
    bottom: 0,
  },
});
