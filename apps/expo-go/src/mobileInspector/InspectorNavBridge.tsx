// import { useHeaderHeight } from '@react-navigation/elements';
// import { useEffect } from 'react';
// import { useSafeAreaInsets } from 'react-native-safe-area-context';
// import { useBloomInspector } from 'src/utils/useBloomInspector';

// export const InspectorNavBridge = () => {
//   const { setTopOffset } = useBloomInspector();
//   const headerHeight = useHeaderHeight(); // from React Navigation
//   const insets = useSafeAreaInsets(); // optional: status bar

//   useEffect(() => {
//     const offset = headerHeight ?? 0; // or headerHeight + insets.top if needed
//     setTopOffset(offset);
//   }, [headerHeight, insets.top, setTopOffset]);

//   return null; // nothing to render
// };
