import { useIsFocused } from '@react-navigation/native';
import React, { useEffect, useRef } from 'react';
import { View, type StyleProp, type ViewStyle } from 'react-native';

import { useBloomInspector } from './useBloomInspector';

type Props = {
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
};

export function BloomInspectorScreenRoot({ children, style }: Props) {
  const rootRef = useRef<View | null>(null);
  const isFocused = useIsFocused();
  const { setInspectedRootRef } = useBloomInspector();

  useEffect(() => {
    if (!isFocused) {
      return;
    }
    setInspectedRootRef(rootRef);
    return () => {
      setInspectedRootRef(null);
    };
  }, [isFocused, setInspectedRootRef]);

  return (
    <View ref={rootRef} style={style}>
      {children}
    </View>
  );
}
