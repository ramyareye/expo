import { PureComponent, ReactElement, ReactNode } from 'react';
import {
  TouchableHighlight,
  TouchableWithoutFeedback,
  View,
  StyleSheet,
  Text,
  Image,
  type StyleProp,
  type ViewStyle,
} from 'react-native';

import BoxInspector from './BoxInspector';
import { InspectedElementFrame } from './ElementBox';
import StyleInspector from './StyleInspector';
import type { InspectorDataItem, InspectorViewData } from './inspectorTypes';
import BloomLogo from '../assets/bloom-logo.png';

declare type MeasureOnSuccessCallback = (
  x: number,
  y: number,
  width: number,
  height: number,
  pageX: number,
  pageY: number
) => void;

export type InspectorData = {
  closestInstance?: unknown;
  hierarchy: InspectorDataItem[];
  selectedIndex: number;
  props: Record<string, string>;
  componentStack: string;
};

function mapWithSeparator<TFrom, TTo>(
  items: TFrom[],
  itemRenderer: (item: TFrom, index: number, items: TFrom[]) => TTo,
  spacerRenderer: (index: number) => TTo
): TTo[] {
  const mapped = [];
  if (items.length > 0) {
    mapped.push(itemRenderer(items[0], 0, items));
    for (let ii = 1; ii < items.length; ii++) {
      mapped.push(spacerRenderer(ii - 1), itemRenderer(items[ii], ii, items));
    }
  }
  return mapped;
}

type Props = {
  hierarchy?: InspectorViewData['hierarchy'];
  style?: StyleProp<ViewStyle>;
  frame?: InspectedElementFrame | null;
  selection?: number;
  setSelection?: (selection: number) => void;
};

class ElementProperties extends PureComponent<Props> {
  render(): ReactNode {
    const style = StyleSheet.flatten(this.props.style);
    const selection = this.props.selection;

    // Without the `TouchableWithoutFeedback`, taps on this inspector pane
    // would change the inspected element to whatever is under the inspector
    return (
      <TouchableWithoutFeedback>
        <View style={styles.info}>
          <View style={styles.header}>
            <Image source={BloomLogo} style={{ width: 20, height: 20 }} />
            <Text>Bloom Element Inspector</Text>
          </View>
          <View style={styles.breadcrumb}>
            {this.props.hierarchy &&
              mapWithSeparator(
                this.props.hierarchy,
                (hierarchyItem, i): ReactElement => (
                  <TouchableHighlight
                    key={'item-' + i}
                    underlayColor="rgb(251, 107, 165)"
                    style={[styles.breadItem, i === selection && styles.selected]}
                    // $FlowFixMe[not-a-function] found when converting React.createClass to ES6
                    onPress={() => this.props.setSelection?.(i)}>
                    <Text style={styles.breadItemText}>{hierarchyItem.name ?? 'Anonymous'}</Text>
                  </TouchableHighlight>
                ),
                (i): ReactElement => (
                  <Text key={'sep-' + i} style={styles.breadSep}>
                    &#9656;
                  </Text>
                )
              )}
          </View>
          <View style={styles.row}>
            <View style={styles.col}>
              <StyleInspector style={this.props.style} />
            </View>
            {this.props.frame && <BoxInspector style={style} frame={this.props.frame} />}
          </View>
        </View>
      </TouchableWithoutFeedback>
    );
  }
}

const styles = StyleSheet.create({
  breadSep: {
    fontSize: 8,
    color: 'black',
  },
  header: {
    flexDirection: 'row',
    gap: 5,
    marginBottom: 5,
    alignItems: 'center',
    borderBottomColor: 'rgba(251, 107, 165, .3)',
    borderBottomWidth: 1,
    paddingBottom: 5,
  },
  breadcrumb: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'flex-start',
    marginBottom: 5,
  },
  selected: {
    borderColor: 'rgb(251, 107, 165)',
    borderRadius: 5,
  },
  breadItem: {
    borderWidth: 1,
    borderColor: 'transparent',
    marginHorizontal: 2,
  },
  breadItemText: {
    fontSize: 10,
    color: 'black',
    marginHorizontal: 5,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  col: {
    flex: 1,
  },
  info: {
    padding: 10,
  },
});

export default ElementProperties;
