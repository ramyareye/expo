import { ReactNode } from 'react';
import { StyleSheet, View, Text, type StyleProp, type ViewStyle } from 'react-native';

type Props = {
  style?: StyleProp<ViewStyle>;
};

function StyleInspector({ style }: Props): ReactNode {
  const flattenedStyle = StyleSheet.flatten(style);
  if (!flattenedStyle) {
    return <Text style={styles.noStyle}>No style</Text>;
  }
  const names = Object.keys(flattenedStyle);
  return (
    <View style={styles.container}>
      <View>
        {names.map((name) => (
          <Text key={name} style={styles.attr}>
            {name}:
          </Text>
        ))}
      </View>

      <View>
        {names.map((name) => {
          const value = (flattenedStyle as Record<string, unknown>)[name];
          return (
            <Text key={name} style={styles.value}>
              {typeof value !== 'string' && typeof value !== 'number'
                ? JSON.stringify(value)
                : value}
            </Text>
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
  },
  attr: {
    fontSize: 10,
    color: '#333',
  },
  value: {
    fontSize: 10,
    color: 'black',
    marginLeft: 10,
  },
  noStyle: {
    color: 'black',
    fontSize: 10,
    paddingVertical: 10,
  },
});

export default StyleInspector;
