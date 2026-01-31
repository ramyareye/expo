import { HomeFilledIcon, SettingsFilledIcon } from '@expo/styleguide-native';
import { NavigationContainer, useTheme, useNavigationContainerRef } from '@react-navigation/native';
import { createStackNavigator, TransitionPresets } from '@react-navigation/stack';
import * as React from 'react';
import { Platform, StyleSheet, Linking } from 'react-native';
import { BloomInspectorScreenRoot } from 'src/utils/BloomInspectorScreenRoot';

import BottomTab, { getNavigatorProps } from './BottomTabNavigator';
import { HomeStackRoutes, SettingsStackRoutes, ModalStackRoutes } from './Navigation.types';
import defaultNavigationOptions from './defaultNavigationOptions';
import DiagnosticsIcon from '../components/Icons';
import { ColorTheme } from '../constants/Colors';
import Themes from '../constants/Themes';
import { AccountModal } from '../screens/AccountModal';
import { BranchDetailsScreen } from '../screens/BranchDetailsScreen';
import { BranchListScreen } from '../screens/BranchListScreen';
import { DiagnosticsStackScreen } from '../screens/DiagnosticsScreen';
import { FeedbackFormScreen } from '../screens/FeedbackFormScreen';
import { HomeScreen } from '../screens/HomeScreen';
import { InspectorDemoStackScreen } from '../screens/InspectorDemoScreen';
import { ProjectScreen } from '../screens/ProjectScreen';
import { ProjectsListScreen } from '../screens/ProjectsListScreen';
import QRCodeScreen from '../screens/QRCodeScreen';
import { SettingsScreen } from '../screens/SettingsScreen';
import { SnacksListScreen } from '../screens/SnacksListScreen';
import {
  alertWithCameraPermissionInstructions,
  requestCameraPermissionsAsync,
} from '../utils/PermissionUtils';

// TODO(Bacon): Do we need to create a new one each time?
const HomeStack = createStackNavigator<HomeStackRoutes>();
const SettingsStack = createStackNavigator<SettingsStackRoutes>();

// We have to disable this option on Android to not use `react-native-screen`,
// which aren't correcly installed in the Home app.
const shouldDetachInactiveScreens = Platform.OS !== 'android';

function useThemeName() {
  const theme = useTheme();
  return theme.dark ? ColorTheme.DARK : ColorTheme.LIGHT;
}

function HomeStackScreen() {
  const themeName = useThemeName();

  return (
    <HomeStack.Navigator
      initialRouteName="Home"
      detachInactiveScreens={shouldDetachInactiveScreens}
      screenOptions={defaultNavigationOptions(themeName)}>
      <HomeStack.Screen
        name="Home"
        component={HomeScreen}
        options={{
          headerShown: false,
        }}
      />
      <HomeStack.Screen
        name="ProjectsList"
        component={ProjectsListScreen}
        options={{
          title: 'Projects',
        }}
      />
      <HomeStack.Screen
        name="SnacksList"
        component={SnacksListScreen}
        options={{
          title: 'Snacks',
        }}
      />
      <HomeStack.Screen
        name="ProjectDetails"
        component={ProjectScreen}
        options={{
          title: 'Project',
        }}
      />
      <HomeStack.Screen
        name="Branches"
        component={BranchListScreen}
        options={{
          title: 'Branches',
        }}
      />
      <HomeStack.Screen
        name="BranchDetails"
        component={BranchDetailsScreen}
        options={{
          title: 'Branch',
        }}
      />
      <HomeStack.Screen
        name="FeedbackForm"
        component={FeedbackFormScreen}
        options={{
          title: 'Share your feedback',
        }}
      />
    </HomeStack.Navigator>
  );
}

function SettingsStackScreen() {
  const themeName = useThemeName();

  return (
    <SettingsStack.Navigator
      initialRouteName="Settings"
      detachInactiveScreens={shouldDetachInactiveScreens}
      screenOptions={defaultNavigationOptions(themeName)}>
      <SettingsStack.Screen
        name="Settings"
        component={SettingsScreen}
        options={{
          headerBackImage: () => <></>,
        }}
      />
    </SettingsStack.Navigator>
  );
}

const RootStack = createStackNavigator();

function withBloomInspectorRoot<P>(Component: React.ComponentType<P>) {
  function BloomInspectorWrapped(props: P) {
    return (
      <BloomInspectorScreenRoot style={styles.screenRoot}>
        {/* @ts-ignore */}
        <Component {...props} />
      </BloomInspectorScreenRoot>
    );
  }

  const componentName = Component.displayName ?? Component.name ?? 'Anonymous';
  BloomInspectorWrapped.displayName = `BloomInspectorRoot(${componentName})`;

  return BloomInspectorWrapped;
}

const HomeStackScreenWithInspector = withBloomInspectorRoot(HomeStackScreen);
const SettingsStackScreenWithInspector = withBloomInspectorRoot(SettingsStackScreen);
const DiagnosticsStackScreenWithInspector = withBloomInspectorRoot(DiagnosticsStackScreen);
const InspectorDemoStackScreenWithInspector = withBloomInspectorRoot(InspectorDemoStackScreen);

function TabNavigator(props: { theme: string }) {
  return (
    <BottomTab.Navigator
      {...getNavigatorProps(props)}
      initialRouteName="HomeStack"
      detachInactiveScreens={shouldDetachInactiveScreens}>
      <BottomTab.Screen
        name="HomeStack"
        component={HomeStackScreenWithInspector}
        options={{
          tabBarIcon: (props: any) =>
            Platform.OS === 'ios' ? (
              { sfSymbolName: 'house.fill' }
            ) : (
              <HomeFilledIcon {...props} style={styles.icon} size={24} />
            ),
          tabBarLabel: 'Home',
        }}
      />

      {Platform.OS === 'ios' && (
        <BottomTab.Screen
          name="DiagnosticsStack"
          component={DiagnosticsStackScreenWithInspector}
          options={{
            tabBarIcon: (props: any) =>
              Platform.OS === 'ios' ? (
                { sfSymbolName: 'ecg.text.page.fill' }
              ) : (
                <DiagnosticsIcon {...props} style={styles.icon} size={24} />
              ),
            tabBarLabel: 'Diagnostics',
          }}
        />
      )}

      {Platform.OS === 'ios' && (
        <BottomTab.Screen
          name="InspectorStack"
          component={InspectorDemoStackScreenWithInspector}
          options={{
            tabBarIcon: () => ({ sfSymbolName: 'ecg.text.page.fill' }),
            tabBarLabel: 'Inspector',
          }}
        />
      )}

      <BottomTab.Screen
        name="SettingsScreen"
        component={SettingsStackScreenWithInspector}
        options={{
          title: 'Settings',
          tabBarIcon: (props: any) =>
            Platform.OS === 'ios' ? (
              { sfSymbolName: 'gearshape.fill' }
            ) : (
              <SettingsFilledIcon {...props} style={styles.icon} size={24} />
            ),
          tabBarLabel: 'Settings',
        }}
      />
    </BottomTab.Navigator>
  );
}

const ModalStack = createStackNavigator<ModalStackRoutes>();

// function getActiveRoute(state: NavigationState | undefined): Route<string> {
//   if (!state) {
//     throw new Error('No navigation state');
//   }

//   let currentState: NavigationState = state;

//   // Drill down through nested navigators
//   while (true) {
//     const route = currentState.routes[currentState.index ?? 0] as any;
//     if (!route.state) {
//       return route;
//     }
//     currentState = route.state as NavigationState;
//   }
// }

export default (props: { theme: ColorTheme }) => {
  const navigationRef = useNavigationContainerRef<ModalStackRoutes>();
  const isNavigationReadyRef = React.useRef(false);
  const initialURLWasConsumed = React.useRef(false);
  // const { inspectedViewRef, setActiveRouteKey } = useBloomInspector();

  React.useEffect(() => {
    const handleDeepLinks = async ({ url }: { url: string | null }) => {
      if (Platform.OS === 'ios' || !url || !isNavigationReadyRef.current) {
        return;
      }
      const nav = navigationRef.current;
      if (!nav) {
        return;
      }

      if (url.startsWith('expo-home://qr-scanner')) {
        if (await requestCameraPermissionsAsync()) {
          nav.navigate('QRCode');
        } else {
          await alertWithCameraPermissionInstructions();
        }
      }
    };
    if (!initialURLWasConsumed.current) {
      initialURLWasConsumed.current = true;
      Linking.getInitialURL().then((url) => {
        handleDeepLinks({ url });
      });
    }

    const deepLinkSubscription = Linking.addEventListener('url', handleDeepLinks);

    return () => {
      isNavigationReadyRef.current = false;
      deepLinkSubscription.remove();
    };
  }, []);

  // const handleStateChange = () => {
  //   const state = navigationRef.current?.getRootState();
  //   if (!state) return;

  //   const activeRoute = getActiveRoute(state);
  //   setActiveRouteKey(activeRoute.key);
  // };

  return (
    <NavigationContainer
      theme={Themes[props.theme]}
      ref={navigationRef}
      // onStateChange={handleStateChange}
      onReady={() => {
        isNavigationReadyRef.current = true;
        // handleStateChange();
      }}>
      {/* <View style={{ flex: 1 }} ref={inspectedViewRef}> */}
      <ModalStack.Navigator
        initialRouteName="RootStack"
        detachInactiveScreens={shouldDetachInactiveScreens}
        screenOptions={({ route: _route, navigation: _navigation }) => ({
          headerShown: false,
          gestureEnabled: true,
          cardOverlayEnabled: true,
          cardStyle: { backgroundColor: 'transparent' },
          presentation: 'modal',
          // NOTE(brentvatne): it is unclear what this was intended for, it doesn't appear to be needed?
          // headerStatusBarHeight: navigation.getState().routes.indexOf(route) > 0 ? 0 : undefined,
          ...TransitionPresets.ModalPresentationIOS,
        })}>
        <ModalStack.Screen name="RootStack">
          {() => (
            <RootStack.Navigator
              initialRouteName="Tabs"
              detachInactiveScreens={shouldDetachInactiveScreens}
              screenOptions={{ presentation: 'modal' }}>
              <RootStack.Screen name="Tabs" options={{ headerShown: false }}>
                {() => <TabNavigator theme={props.theme} />}
              </RootStack.Screen>
              <RootStack.Screen
                name="Account"
                component={AccountModal}
                options={({ route: _route, navigation: _navigation }) => ({
                  headerShown: false,
                  ...(Platform.OS === 'ios' && {
                    gestureEnabled: true,
                    cardOverlayEnabled: true,
                    // NOTE(brentvatne): it is unclear what this was intended for, it doesn't appear to be needed?
                    // headerStatusBarHeight:
                    //   navigation
                    //     .getState()
                    //     .routes.findIndex((r: RouteProp<any, any>) => r.key === route.key) > 0
                    //     ? 0
                    //     : undefined,
                    ...TransitionPresets.ModalPresentationIOS,
                  }),
                })}
              />
            </RootStack.Navigator>
          )}
        </ModalStack.Screen>
        <ModalStack.Screen name="QRCode" component={QRCodeScreen} />
      </ModalStack.Navigator>
      {/* </View> */}
    </NavigationContainer>
  );
};

const styles = StyleSheet.create({
  icon: {
    marginBottom: Platform.OS === 'ios' ? -3 : 0,
  },
  screenRoot: {
    flex: 1,
  },
});
