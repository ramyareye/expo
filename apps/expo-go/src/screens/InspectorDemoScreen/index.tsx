import { useTheme } from '@react-navigation/native';
import { createStackNavigator } from '@react-navigation/stack';
import { View, Text, StyleSheet, Switch, Pressable, Alert } from 'react-native';
import { ColorTheme } from 'src/constants/Colors';
import { InspectorDemoStackRoutes } from 'src/navigation/Navigation.types';
import defaultNavigationOptions from 'src/navigation/defaultNavigationOptions';
import { useBloomInspector } from 'src/utils/useBloomInspector';

const InspectorDemoStack = createStackNavigator<InspectorDemoStackRoutes>();

function useThemeName() {
  const theme = useTheme();
  return theme.dark ? ColorTheme.DARK : ColorTheme.LIGHT;
}

export function InspectorDemoStackScreen() {
  const theme = useThemeName();

  return (
    <InspectorDemoStack.Navigator
      initialRouteName="InspectorDemo"
      screenOptions={defaultNavigationOptions(theme)}>
      <InspectorDemoStack.Screen
        name="InspectorDemo"
        component={InspectorDemoScreen}
        options={{
          title: 'Bloom Inspector',
          headerBackButtonDisplayMode: 'minimal',
          headerBackImage: () => <></>,
        }}
      />
    </InspectorDemoStack.Navigator>
  );
}

export const InspectorDemoScreen: React.FC = () => {
  const { enabled, setEnabled } = useBloomInspector();

  return (
    // <MiniInspector enabled={enabled}>
    <View style={styles.root}>
      <View style={styles.toggleRow}>
        <Text style={styles.toggleLabel}>Element Picker Mode</Text>
        <Switch value={enabled} onValueChange={setEnabled} />
      </View>

      <View style={styles.card}>
        <Text style={styles.title}>Hello Inspector 👀</Text>
        <Text style={styles.body}>
          Turn on Element Picker Mode and tap around. The panel below will show props, styles, and
          element hierarchy.
        </Text>

        <View style={styles.button}>
          <Pressable onPress={() => Alert.alert('12')}>
            <Text style={styles.buttonText}>Fake Button</Text>
          </Pressable>
        </View>
      </View>

      <View style={styles.card}>
        <Text style={styles.title}>Hello Inspector 👀</Text>
        <Text style={styles.body}>
          Turn on Element Picker Mode and tap around. The panel below will show props, styles, and
          element hierarchy.
        </Text>

        <View style={styles.button}>
          <Pressable onPress={() => Alert.alert('12')}>
            <Text style={styles.buttonText}>Fake Button</Text>
          </Pressable>
        </View>
      </View>

      <View style={styles.card}>
        <Text style={styles.title}>Hello Inspector 👀</Text>
        <Text style={styles.body}>
          Turn on Element Picker Mode and tap around. The panel below will show props, styles, and
          element hierarchy.
        </Text>

        <View style={styles.button}>
          <Pressable onPress={() => Alert.alert('12')}>
            <Text style={styles.buttonText}>Fake Button</Text>
          </Pressable>
        </View>
      </View>
    </View>
    // </MiniInspector>
  );
};

const styles = StyleSheet.create({
  root: {
    flex: 1,
    padding: 16,
    backgroundColor: '#111827',
  },
  toggleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
  },
  toggleLabel: {
    flex: 1,
    color: 'white',
    fontSize: 14,
  },
  card: {
    backgroundColor: '#1f2937',
    borderRadius: 12,
    padding: 16,
  },
  title: {
    color: 'white',
    fontWeight: 'bold',
    fontSize: 18,
    marginBottom: 8,
  },
  body: {
    color: '#d1d5db',
    marginBottom: 16,
  },
  button: {
    backgroundColor: '#2563eb',
    borderRadius: 8,
    paddingVertical: 8,
    paddingHorizontal: 12,
    alignSelf: 'flex-start',
  },
  buttonText: {
    color: 'white',
    fontWeight: '600',
  },
});
