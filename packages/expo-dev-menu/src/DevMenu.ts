import { DeviceEventEmitter } from 'react-native';

import ExpoDevMenu from './ExpoDevMenu';
import { ExpoDevMenuItem } from './ExpoDevMenu.types';

export function openMenu(): void {
  ExpoDevMenu.openMenu();
}

export function openProfile(): void {
  ExpoDevMenu.openProfile();
}

export function openSettings(): void {
  ExpoDevMenu.openSettings();
}

let hasRegisteredCallbackListener = false;

function registerCallbackListener() {
  if (!hasRegisteredCallbackListener) {
    DeviceEventEmitter.addListener('registeredCallbackFired', (name: string) => {
      hasRegisteredCallbackListener = true;
      const handler = handlers.get(name);

      if (handler != null) {
        handler();
      }
    });
  }
}

registerCallbackListener();

let handlers = new Map<string, () => void>();

export async function registerDevMenuItems(items: ExpoDevMenuItem[]) {
  if (!__DEV__) {
    return Promise.resolve();
  }

  handlers = new Map();
  const callbackNames: string[] = [];

  items.forEach((item) => {
    handlers.set(item.name, item.callback);
    callbackNames.push(item.name);
  });

  return await ExpoDevMenu.addDevMenuCallbacks(callbackNames);
}
