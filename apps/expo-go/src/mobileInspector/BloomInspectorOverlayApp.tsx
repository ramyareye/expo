import React from 'react';
import { AppRegistry } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { BloomInspectorOverlayPanel } from './BloomInspectorOverlayPanel';

function BloomInspectorOverlayRoot() {
  return (
    <SafeAreaProvider>
      <BloomInspectorOverlayPanel />
    </SafeAreaProvider>
  );
}

AppRegistry.registerComponent('BloomInspectorOverlay', () => BloomInspectorOverlayRoot);
