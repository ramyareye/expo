import { ReactNode } from 'react';
import { View, Text, StyleSheet, ViewStyle, TextStyle } from 'react-native';

import type { InspectedElementFrame } from './ElementBox';
import resolveBoxStyle from './resolveBoxStyle';

const blank = {
  top: 0,
  left: 0,
  right: 0,
  bottom: 0,
};

export type BoxInspectorProps = {
  style?: ViewStyle;
  frame: InspectedElementFrame;
};

function BoxInspector({ style, frame }: BoxInspectorProps): ReactNode {
  const flattenedStyle = StyleSheet.flatten(style) as
    | Record<string, number | string | undefined>
    | undefined;
  const margin = normalizeBox(
    (flattenedStyle && resolveBoxStyle('margin', flattenedStyle)) || blank
  );
  const padding = normalizeBox(
    (flattenedStyle && resolveBoxStyle('padding', flattenedStyle)) || blank
  );

  return (
    <BoxContainer title="margin" titleStyle={styles.marginLabel} box={margin}>
      <BoxContainer title="padding" box={padding}>
        <View>
          <Text style={styles.innerText}>
            ({(frame?.left || 0).toFixed(1)}, {(frame?.top || 0).toFixed(1)})
          </Text>
          <Text style={styles.innerText}>
            {(frame?.width || 0).toFixed(1)} &times; {(frame?.height || 0).toFixed(1)}
          </Text>
        </View>
      </BoxContainer>
    </BoxContainer>
  );
}

type BoxContainerProps = {
  title: string;
  titleStyle?: TextStyle;
  box: {
    top: number;
    left: number;
    right: number;
    bottom: number;
  };
  children: ReactNode;
};

function BoxContainer({ title, titleStyle, box, children }: BoxContainerProps): ReactNode {
  return (
    <View style={styles.box}>
      <View style={styles.row}>
        {}
        <Text style={[titleStyle, styles.label]}>{title}</Text>
        <Text style={styles.boxText}>{box.top}</Text>
      </View>
      <View style={styles.row}>
        <Text style={styles.boxText}>{box.left}</Text>
        {children}
        <Text style={styles.boxText}>{box.right}</Text>
      </View>
      <Text style={styles.boxText}>{box.bottom}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-around',
  },
  marginLabel: {
    width: 60,
  },
  label: {
    fontSize: 10,
    color: 'rgb(255,100,0)',
    marginLeft: 5,
    flex: 1,
    textAlign: 'left',
    top: -3,
  },
  innerText: {
    color: 'rgb(255,100,100)',
    fontSize: 12,
    textAlign: 'center',
    width: 70,
  },
  box: {
    borderWidth: 1,
    borderColor: 'grey',
  },
  boxText: {
    color: 'black',
    fontSize: 12,
    marginHorizontal: 3,
    marginVertical: 2,
    textAlign: 'center',
  },
});

function normalizeBox(box: {
  top: number | string;
  left: number | string;
  right: number | string;
  bottom: number | string;
}): { top: number; left: number; right: number; bottom: number } {
  return {
    top: normalizeBoxValue(box.top),
    left: normalizeBoxValue(box.left),
    right: normalizeBoxValue(box.right),
    bottom: normalizeBoxValue(box.bottom),
  };
}

function normalizeBoxValue(value: number | string): number {
  return typeof value === 'number' ? value : Number.isFinite(Number(value)) ? Number(value) : 0;
}

export default BoxInspector;
