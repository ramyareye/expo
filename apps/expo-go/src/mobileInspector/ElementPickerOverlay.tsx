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
