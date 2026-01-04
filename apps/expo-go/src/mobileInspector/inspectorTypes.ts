import type { Component, ComponentClass } from 'react';
import type { StyleProp, ViewStyle } from 'react-native';

import type { InspectedElementFrame } from './ElementBox';

export type InspectorMeasureFn = (
  x: number,
  y: number,
  width: number,
  height: number,
  left: number,
  top: number
) => void;

export type InspectorNodeHandleProvider = (
  node: null | number | Component<any, any> | ComponentClass<any>
) => number | null;

export type InspectorDataItem = {
  getInspectorData: (nodeHandleProvider: InspectorNodeHandleProvider) => {
    measure?: (callback: InspectorMeasureFn) => void;
    props: { style?: StyleProp<ViewStyle> };
  };
  name: string | null;
};

export type InspectorViewData = {
  hierarchy: InspectorDataItem[];
  frame: InspectedElementFrame;
  props?: { style?: StyleProp<ViewStyle> };
  selectedIndex: number;
};

export type InspectorElementBoxPosition = 'top' | 'bottom';
