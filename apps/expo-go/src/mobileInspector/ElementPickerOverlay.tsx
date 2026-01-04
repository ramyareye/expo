import React from 'react';
import { View, StyleSheet, GestureResponderEvent, Dimensions } from 'react-native';

import { getInspectorDataForViewAtPoint } from './getInspectorDataForViewAtPoint';
import type { InspectorElementBoxPosition, InspectorViewData } from './inspectorTypes';

type Props = {
  inspectedViewRef: React.RefObject<View | null>;
  onPick: (viewData: InspectorViewData) => void;
  setElementBoxPosition: (positions: InspectorElementBoxPosition) => void;
};

const { height } = Dimensions.get('window');

export const ElementPickerOverlay: React.FC<Props> = ({
  inspectedViewRef,
  onPick,
  setElementBoxPosition,
}) => {
  const handleStartShouldSetResponder = (e: GestureResponderEvent) => {
    if (!inspectedViewRef.current) return false;
    const touch = e.nativeEvent.touches[0];
    if (!touch) return false;

    const { locationX, locationY } = touch;
    setElementBoxPosition(locationY > height / 2 ? 'bottom' : 'top');

    getInspectorDataForViewAtPoint(inspectedViewRef.current, locationX, locationY, (viewData) => {
      if (!viewData || !viewData.hierarchy?.length) return false;
      // console.log(333, viewData);
      // console.log(3334, viewData.hierarchy);
      onPick(viewData);
      return false;
    });

    return true;
  };

  const handleResponderMove = (e: GestureResponderEvent) => {
    if (!inspectedViewRef.current) return;
    const touch = e.nativeEvent.touches[0];
    if (!touch) return;

    const { locationX, locationY } = touch;
    setElementBoxPosition(locationY > height / 2 ? 'bottom' : 'top');

    getInspectorDataForViewAtPoint(inspectedViewRef.current, locationX, locationY, (viewData) => {
      if (!viewData || !viewData.hierarchy?.length) return false;
      onPick(viewData);
      return false;
    });
  };

  return (
    <View
      style={StyleSheet.absoluteFill}
      onStartShouldSetResponder={handleStartShouldSetResponder}
      onResponderMove={handleResponderMove}
    />
  );
};

// const hierarchy = [
//   { getInspectorData: () => {}, name: 'withDevTools(App)' },
//   { getInspectorData: () => {}, name: 'App' },
//   { getInspectorData: () => {}, name: 'HomeApp' },
//   { getInspectorData: () => {}, name: null },
//   { getInspectorData: () => {}, name: 'StackNavigator' },
//   { getInspectorData: () => {}, name: 'SceneView' },
//   { getInspectorData: () => {}, name: 'StackNavigator' },
//   { getInspectorData: () => {}, name: 'SceneView' },
//   { getInspectorData: () => {}, name: 'TabNavigator' },
//   { getInspectorData: () => {}, name: 'NativeBottomTabsNavigator' },
//   { getInspectorData: () => {}, name: 'SceneView' },
//   { getInspectorData: () => {}, name: 'SettingsStackScreen' },
//   { getInspectorData: () => {}, name: 'StackNavigator' },
//   { getInspectorData: () => {}, name: 'SceneView' },
//   { getInspectorData: () => {}, name: 'SettingsScreen' },
//   { getInspectorData: () => {}, name: 'BloomInspectorSwitcher' },
//   { getInspectorData: () => {}, name: 'Switch' },
//   { getInspectorData: () => {}, name: 'RCTSwitch' },
// ];

// const c = {
//   closestInstance: {
//     _debugHookTypes: [
//       'useRef',
//       'useCallback',
//       'useRef',
//       'useCallback',
//       'useState',
//       'useLayoutEffect',
//     ],
//     _debugInfo: null,
//     _debugNeedsRemount: false,
//     _debugOwner: {
//       _debugHookTypes: [],
//       _debugInfo: null,
//       _debugNeedsRemount: false,
//       _debugOwner: [],
//       _debugStack: [],
//       _debugTask: null,
//       actualDuration: 0.3265869915485382,
//       actualStartTime: 228579062.878333,
//       alternate: [],
//       child: [],
//       childLanes: 0,
//       deletions: null,
//       dependencies: [],
//       elementType: [],
//       flags: 524289,
//       index: 0,
//       key: null,
//       lanes: 0,
//       memoizedProps: [],
//       memoizedState: null,
//       mode: 3,
//       pendingProps: [],
//       ref: null,
//       refCleanup: null,
//       return: [],
//       selfBaseDuration: 0.05425000190734863,
//       sibling: [],
//       stateNode: null,
//       subtreeFlags: 4980741,
//       tag: 0,
//       treeBaseDuration: 0.2235439419746399,
//       type: [],
//       updateQueue: null,
//     },
//     _debugStack: [],
//     _debugTask: null,
//     actualDuration: 0.11954301595687866,
//     actualStartTime: 228579063.098041,
//     alternate: {
//       _debugHookTypes: [],
//       _debugInfo: null,
//       _debugNeedsRemount: false,
//       _debugOwner: [],
//       _debugStack: [],
//       _debugTask: null,
//       actualDuration: 0.09404200315475464,
//       actualStartTime: 228574847.950208,
//       alternate: [],
//       child: [],
//       childLanes: 0,
//       deletions: null,
//       dependencies: null,
//       elementType: [],
//       flags: 5242885,
//       index: 1,
//       key: null,
//       lanes: 2,
//       memoizedProps: [],
//       memoizedState: [],
//       mode: 3,
//       pendingProps: [],
//       ref: null,
//       refCleanup: null,
//       return: [],
//       selfBaseDuration: 0.026250004768371582,
//       sibling: null,
//       stateNode: null,
//       subtreeFlags: 4194816,
//       tag: 0,
//       treeBaseDuration: 0.028416991233825684,
//       type: [],
//       updateQueue: [],
//     },
//     child: {
//       _debugHookTypes: null,
//       _debugInfo: null,
//       _debugNeedsRemount: false,
//       _debugOwner: [],
//       _debugStack: [],
//       _debugTask: null,
//       actualDuration: 0.06099998950958252,
//       actualStartTime: 228579063.155791,
//       alternate: [],
//       child: null,
//       childLanes: 0,
//       deletions: null,
//       dependencies: null,
//       elementType: 'RCTSwitch',
//       flags: 4194308,
//       index: 0,
//       key: null,
//       lanes: 0,
//       memoizedProps: [],
//       memoizedState: null,
//       mode: 3,
//       pendingProps: [],
//       ref: [],
//       refCleanup: undefined,
//       return: [],
//       selfBaseDuration: 0.0046669840812683105,
//       sibling: null,
//       stateNode: [],
//       subtreeFlags: 0,
//       tag: 5,
//       treeBaseDuration: 0.0046669840812683105,
//       type: 'RCTSwitch',
//       updateQueue: null,
//     },
//     childLanes: 0,
//     deletions: null,
//     dependencies: null,
//     elementType: [],
//     flags: 4194309,
//     index: 1,
//     key: null,
//     lanes: 0,
//     memoizedProps: { onValueChange: [], value: true },
//     memoizedState: { baseQueue: null, baseState: null, memoizedState: [], next: [], queue: null },
//     mode: 3,
//     pendingProps: { onValueChange: [], value: true },
//     ref: null,
//     refCleanup: null,
//     return: {
//       _debugHookTypes: null,
//       _debugInfo: null,
//       _debugNeedsRemount: false,
//       _debugOwner: [],
//       _debugStack: [],
//       _debugTask: null,
//       actualDuration: 0.2347950041294098,
//       actualStartTime: 228579062.968916,
//       alternate: [],
//       child: [],
//       childLanes: 0,
//       deletions: null,
//       dependencies: null,
//       elementType: 'RCTView',
//       flags: 0,
//       index: 0,
//       key: null,
//       lanes: 0,
//       memoizedProps: [],
//       memoizedState: null,
//       mode: 3,
//       pendingProps: [],
//       ref: null,
//       refCleanup: null,
//       return: [],
//       selfBaseDuration: 0.02133399248123169,
//       sibling: null,
//       stateNode: [],
//       subtreeFlags: 4980741,
//       tag: 5,
//       treeBaseDuration: 0.1347939670085907,
//       type: 'RCTView',
//       updateQueue: null,
//     },
//     selfBaseDuration: 0.056834012269973755,
//     sibling: null,
//     stateNode: null,
//     subtreeFlags: 4194308,
//     tag: 0,
//     treeBaseDuration: 0.061500996351242065,
//     type: [],
//     updateQueue: { events: null, lastEffect: [], memoCache: null, stores: null },
//   },
//   closestPublicInstance: {
//     __internalInstanceHandle: {
//       _debugHookTypes: null,
//       _debugInfo: null,
//       _debugNeedsRemount: false,
//       _debugOwner: [],
//       _debugStack: [],
//       _debugTask: null,
//       actualDuration: 0.06691700220108032,
//       actualStartTime: 228574847.976958,
//       alternate: [],
//       child: null,
//       childLanes: 0,
//       deletions: null,
//       dependencies: null,
//       elementType: 'RCTSwitch',
//       flags: 4194816,
//       index: 0,
//       key: null,
//       lanes: 0,
//       memoizedProps: [],
//       memoizedState: null,
//       mode: 3,
//       pendingProps: [],
//       ref: [],
//       refCleanup: undefined,
//       return: [],
//       selfBaseDuration: 0.0021669864654541016,
//       sibling: null,
//       stateNode: [],
//       subtreeFlags: 0,
//       tag: 5,
//       treeBaseDuration: 0.0021669864654541016,
//       type: 'RCTSwitch',
//       updateQueue: null,
//     },
//     __nativeTag: 466,
//     _viewConfig: {
//       Commands: [],
//       bubblingEventTypes: [],
//       directEventTypes: [],
//       uiViewClassName: 'RCTSwitch',
//       validAttributes: [],
//     },
//   },
//   componentStack: '',
//   frame: { height: 31.00000762939453, left: 324, top: 113.66666412353516, width: 53 },
//   hierarchy: [
//     { getInspectorData: [], name: 'withDevTools(App)' },
//     { getInspectorData: [], name: 'App' },
//     { getInspectorData: [], name: 'HomeApp' },
//     { getInspectorData: [], name: null },
//     { getInspectorData: [], name: 'StackNavigator' },
//     { getInspectorData: [], name: 'SceneView' },
//     { getInspectorData: [], name: 'StackNavigator' },
//     { getInspectorData: [], name: 'SceneView' },
//     { getInspectorData: [], name: 'TabNavigator' },
//     { getInspectorData: [], name: 'NativeBottomTabsNavigator' },
//     { getInspectorData: [], name: 'SceneView' },
//     { getInspectorData: [], name: 'SettingsStackScreen' },
//     { getInspectorData: [], name: 'StackNavigator' },
//     { getInspectorData: [], name: 'SceneView' },
//     { getInspectorData: [], name: 'SettingsScreen' },
//     { getInspectorData: [], name: 'BloomInspectorSwitcher' },
//     { getInspectorData: [], name: 'Switch' },
//     { getInspectorData: [], name: 'RCTSwitch' },
//   ],
//   pointerY: 136,
//   props: {
//     accessibilityRole: 'switch',
//     disabled: undefined,
//     onChange: [],
//     onResponderTerminationRequest: [],
//     onStartShouldSetResponder: [],
//     onTintColor: undefined,
//     ref: [],
//     style: { alignSelf: 'flex-start' },
//     thumbTintColor: undefined,
//     tintColor: undefined,
//     value: true,
//   },
//   selectedIndex: 16,
//   touchedViewTag: 466,
// };
