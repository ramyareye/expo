import { ReactNode } from 'react';
import { View, type ViewStyle } from 'react-native';

type Props = {
  children: ReactNode;
  box?: {
    top: number;
    right: number;
    bottom: number;
    left: number;
  };
  style?: ViewStyle;
};

function BorderBox({ children, box, style }: Props): ReactNode {
  if (!box) {
    return children;
  }
  const borderStyle = {
    borderTopWidth: box.top,
    borderBottomWidth: box.bottom,
    borderLeftWidth: box.left,
    borderRightWidth: box.right,
  };
  return <View style={[borderStyle, style]}>{children}</View>;
}

export default BorderBox;
