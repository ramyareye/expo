import { I18nManager } from 'react-native';

export type Result = {
  bottom: number | string;
  left: number | string;
  right: number | string;
  top: number | string;
};

const resolveBoxStyle = (
  prefix: string,
  style: Record<string, number | string | undefined>
): null | Result => {
  let hasParts = false;
  const result: Result = {
    bottom: 0,
    left: 0,
    right: 0,
    top: 0,
  };

  const styleForAll = style[prefix];
  if (styleForAll != null) {
    for (const key of Object.keys(result) as (keyof Result)[]) {
      result[key] = styleForAll;
    }
    hasParts = true;
  }

  const styleForHorizontal = style[prefix + 'Horizontal'];
  if (styleForHorizontal != null) {
    result.left = styleForHorizontal;
    result.right = styleForHorizontal;
    hasParts = true;
  } else {
    const styleForLeft = style[prefix + 'Left'];
    if (styleForLeft != null) {
      result.left = styleForLeft;
      hasParts = true;
    }

    const styleForRight = style[prefix + 'Right'];
    if (styleForRight != null) {
      result.right = styleForRight;
      hasParts = true;
    }

    const styleForEnd = style[prefix + 'End'];
    if (styleForEnd != null) {
      const constants = I18nManager.getConstants();
      if (constants.isRTL && constants.doLeftAndRightSwapInRTL) {
        result.left = styleForEnd;
      } else {
        result.right = styleForEnd;
      }
      hasParts = true;
    }
    const styleForStart = style[prefix + 'Start'];
    if (styleForStart != null) {
      const constants = I18nManager.getConstants();
      if (constants.isRTL && constants.doLeftAndRightSwapInRTL) {
        result.right = styleForStart;
      } else {
        result.left = styleForStart;
      }
      hasParts = true;
    }
  }

  const styleForVertical = style[prefix + 'Vertical'];
  if (styleForVertical != null) {
    result.bottom = styleForVertical;
    result.top = styleForVertical;
    hasParts = true;
  } else {
    const styleForBottom = style[prefix + 'Bottom'];
    if (styleForBottom != null) {
      result.bottom = styleForBottom;
      hasParts = true;
    }

    const styleForTop = style[prefix + 'Top'];
    if (styleForTop != null) {
      result.top = styleForTop;
      hasParts = true;
    }
  }

  return hasParts ? result : null;
};

export default resolveBoxStyle;
