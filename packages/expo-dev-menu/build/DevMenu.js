import { DeviceEventEmitter } from 'react-native';
import ExpoDevMenu from './ExpoDevMenu';
export function openMenu() {
    ExpoDevMenu.openMenu();
}
export function openProfile() {
    ExpoDevMenu.openProfile();
}
export function openSettings() {
    ExpoDevMenu.openSettings();
}
let hasRegisteredCallbackListener = false;
function registerCallbackListener() {
    if (!hasRegisteredCallbackListener) {
        DeviceEventEmitter.addListener('registeredCallbackFired', (name) => {
            hasRegisteredCallbackListener = true;
            const handler = handlers.get(name);
            if (handler != null) {
                handler();
            }
        });
    }
}
registerCallbackListener();
let handlers = new Map();
export async function registerDevMenuItems(items) {
    if (!__DEV__) {
        return Promise.resolve();
    }
    handlers = new Map();
    const callbackNames = [];
    items.forEach((item) => {
        handlers.set(item.name, item.callback);
        callbackNames.push(item.name);
    });
    return await ExpoDevMenu.addDevMenuCallbacks(callbackNames);
}
//# sourceMappingURL=DevMenu.js.map