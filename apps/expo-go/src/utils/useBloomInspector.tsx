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
            console.info(
              `Bloom Log: 38-4 js payload keys=${Object.keys(pickPayload).join(',')} source=${
                pickPayload.source ? 'yes' : 'no'
              }`
            );
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
    const subscription = emitter.addListener('bloomInspectorTap', handleNativeTap);
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
      metadata?.hierarchy ??
      viewData.hierarchy.map((item) => ({ name: item.name ?? 'Anonymous' })),
    props: metadata?.props
      ? (sanitizeValue(metadata.props) as Record<string, unknown>)
      : props
      ? (sanitizeValue(props) as Record<string, unknown>)
      : undefined,
    selectedIndex: viewData.selectedIndex,
  };

  const extra = viewData as InspectorViewData & {
    componentStack?: string;
    source?: { fileName?: string; lineNumber?: number; columnNumber?: number };
  };
  if (metadata?.componentStack) {
    payload.componentStack = metadata.componentStack;
  } else if (extra.componentStack) {
    payload.componentStack = extra.componentStack;
  }
  if (metadata?.source) {
    payload.source = metadata.source;
  } else if (extra.source) {
    payload.source = extra.source;
  }

  return payload;
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
