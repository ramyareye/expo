import { ReactNode } from 'react';
import { ViewStyle, View, StyleSheet, Dimensions, type StyleProp } from 'react-native';

import BorderBox from './BorderBox';
import type { Result as Style } from './resolveBoxStyle';
import resolveBoxStyle from './resolveBoxStyle';

export type InspectedElementFrame = { width: number; height: number; top: number; left: number };

type Props = {
  frame: InspectedElementFrame;
  style?: StyleProp<ViewStyle>;
};

function ElementBox({ frame, style }: Props): ReactNode {
  const flattenedStyle = (StyleSheet.flatten(style) || {}) as Record<
    string,
    number | string | undefined
  >;
  const margin = resolveBoxStyle('margin', flattenedStyle);
  const padding = resolveBoxStyle('padding', flattenedStyle);

  const frameStyle = { ...frame };
  const contentStyle: { width: number; height: number } = {
    width: frame.width,
    height: frame.height,
  };

  const numericMargin = margin ? resolveRelativeSizes(margin) : null;
  const numericPadding = padding ? resolveRelativeSizes(padding) : null;

  if (numericMargin) {
    frameStyle.top -= numericMargin.top;
    frameStyle.left -= numericMargin.left;
    frameStyle.height += numericMargin.top + numericMargin.bottom;
    frameStyle.width += numericMargin.left + numericMargin.right;

    if (numericMargin.top < 0) {
      contentStyle.height += numericMargin.top;
    }
    if (numericMargin.bottom < 0) {
      contentStyle.height += numericMargin.bottom;
    }
    if (numericMargin.left < 0) {
      contentStyle.width += numericMargin.left;
    }
    if (numericMargin.right < 0) {
      contentStyle.width += numericMargin.right;
    }
  }

  if (numericPadding) {
    contentStyle.width -= numericPadding.left + numericPadding.right;
    contentStyle.height -= numericPadding.top + numericPadding.bottom;
  }

  return (
    <View style={[styles.frame, frameStyle]} pointerEvents="none">
      <BorderBox box={numericMargin ?? undefined} style={styles.margin}>
        <BorderBox box={numericPadding ?? undefined} style={styles.padding}>
          <View style={[styles.content, contentStyle]} />
        </BorderBox>
      </BorderBox>
    </View>
  );
}

const styles = StyleSheet.create({
  frame: {
    position: 'absolute',
  },
  content: {
    backgroundColor: 'rgba(200, 230, 255, 0.8)', // blue
  },
  padding: {
    borderColor: 'rgba(77, 255, 0, 0.3)', // green
  },
  margin: {
    borderColor: 'rgba(255, 132, 0, 0.3)', // orange
  },
});

/**
 * Resolves relative sizes (percentages and auto) in a style object.
 *
 * @param style the style to resolve
 * @return a modified copy
 */
type NumericStyle = { top: number; right: number; bottom: number; left: number };

function resolveRelativeSizes(style: Style): NumericStyle {
  const resolvedStyle: Style = { ...style };
  resolveSizeInPlace(resolvedStyle, 'top', 'height');
  resolveSizeInPlace(resolvedStyle, 'right', 'width');
  resolveSizeInPlace(resolvedStyle, 'bottom', 'height');
  resolveSizeInPlace(resolvedStyle, 'left', 'width');
  return {
    top: normalizeBoxValue(resolvedStyle.top),
    right: normalizeBoxValue(resolvedStyle.right),
    bottom: normalizeBoxValue(resolvedStyle.bottom),
    left: normalizeBoxValue(resolvedStyle.left),
  };
}

/**
 * Resolves the given size of a style object in place.
 *
 * @param style the style object to modify
 * @param direction the direction to resolve (e.g. 'top')
 * @param dimension the window dimension that this direction belongs to (e.g. 'height')
 */
type DimensionKey = 'width' | 'height';

function resolveSizeInPlace(style: Style, direction: keyof Style, dimension: DimensionKey) {
  const value = style[direction];
  if (value !== null && typeof value === 'string') {
    if (value.indexOf('%') !== -1) {
      style[direction] = (parseFloat(value) / 100.0) * Dimensions.get('window')[dimension];
    }
    if (value === 'auto') {
      // Ignore auto sizing in frame drawing due to complexity of correctly rendering this
      style[direction] = 0;
    }
  }
}

function normalizeBoxValue(value: number | string): number {
  if (typeof value === 'number') {
    return value;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export default ElementBox;
