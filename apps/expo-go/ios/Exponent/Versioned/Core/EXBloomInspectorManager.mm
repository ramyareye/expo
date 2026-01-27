// Copyright 2015-present 650 Industries. All rights reserved.

#import "EXBloomInspectorManager.h"

#import <React/UIView+React.h>
#import "EXDevMenuManager.h"
#import "EXKernel.h"
#import "EXReactAppManager.h"

#import <Expo/RCTAppDelegateUmbrella.h>
#import <React/RCTLog.h>
#import <React/RCTSurfacePresenter.h>
#import <React/RCTUIManager.h>
#import <React/RCTUtils.h>
#import <ReactCommon/RCTHost.h>
#import <jsi/jsi.h>
#import <memory>
#import <objc/runtime.h>
#import <string>

static const BOOL kBloomInspectorDebugLogs = NO;
static const BOOL kBloomInspectorEnableNativeFallback = YES;
#define BLOOM_LOG(...)         \
  do {                         \
    if (kBloomInspectorDebugLogs) { \
      NSLog(__VA_ARGS__);      \
    }                          \
  } while (0)

static UIView *EXBloomInspectorFindTextView(UIView *view);

static const char kBloomInspectorInjectionScript[] = R"JS(
(function () {
  var g = typeof globalThis !== 'undefined' ? globalThis : typeof global !== 'undefined' ? global : typeof window !== 'undefined' ? window : this;
  if (!g || g.__bloomInspectorRuntimeInstalled) {
    return;
  }
  g.__bloomInspectorRuntimeInstalled = true;
  var DEBUG_LOGS = !!g.__bloomInspectorDebugLogs;

  var pendingLogs = [];
  function flushLogs() {
    if (!pendingLogs.length) {
      return;
    }
    if (g.console && g.console.info) {
      for (var i = 0; i < pendingLogs.length; i++) {
        g.console.info(pendingLogs[i]);
      }
      pendingLogs = [];
      return;
    }
    try {
      var module = null;
      if (g.__turboModuleProxy) {
        module = g.__turboModuleProxy('BloomInspectorOverlay');
      }
      if (!module && g.NativeModules && g.NativeModules.BloomInspectorOverlay) {
        module = g.NativeModules.BloomInspectorOverlay;
      }
      if (module && typeof module.log === 'function') {
        for (var j = 0; j < pendingLogs.length; j++) {
          module.log(pendingLogs[j]);
        }
        pendingLogs = [];
      }
    } catch (e) {}
  }

  function log(message) {
    if (!DEBUG_LOGS) {
      return;
    }
    var hostId = g.__bloomInspectorHostId != null ? g.__bloomInspectorHostId : 'unknown';
    var text = 'Bloom Log: ' + message + ' host=' + hostId;
    pendingLogs.push(text);
    flushLogs();
    try {
      var module = null;
      if (g.__turboModuleProxy) {
        module = g.__turboModuleProxy('BloomInspectorOverlay');
      }
      if (!module && g.NativeModules && g.NativeModules.BloomInspectorOverlay) {
        module = g.NativeModules.BloomInspectorOverlay;
      }
      if (module && typeof module.log === 'function') {
        module.log(text);
      }
    } catch (e) {}
  }

  g.__bloomInspectorLastPublicInstance = null;
  g.__bloomInspectorClearNativePropsTarget = function () {
    g.__bloomInspectorLastPublicInstance = null;
  };
  g.__bloomInspectorHasNativePropsTarget = function () {
    var target = g.__bloomInspectorLastPublicInstance;
    return !!(target && typeof target.setNativeProps === 'function');
  };
  g.__bloomInspectorGetNativePropsTargetInfo = function () {
    try {
      var target = g.__bloomInspectorLastPublicInstance;
      if (!target || typeof target.setNativeProps !== 'function') {
        return { hasTarget: false };
      }
      var name = null;
      try {
        name = target && target.constructor && target.constructor.name ? target.constructor.name : null;
      } catch (e) {}
      var nativeTag = null;
      try {
        nativeTag =
          target && (target._nativeTag != null ? target._nativeTag : target.nativeTag != null ? target.nativeTag : null);
      } catch (e) {}
      return { hasTarget: true, name: name, nativeTag: nativeTag };
    } catch (e) {
      return { hasTarget: false };
    }
  };
  g.__bloomInspectorApplyNativeProps = function (nextProps) {
    try {
      var target = g.__bloomInspectorLastPublicInstance;
      if (!target || typeof target.setNativeProps !== 'function') {
        return false;
      }
      if (!nextProps || typeof nextProps !== 'object') {
        return false;
      }
      if (
        Object.prototype.hasOwnProperty.call(nextProps, 'children') &&
        (typeof nextProps.children === 'string' || typeof nextProps.children === 'number')
      ) {
        var textValue = String(nextProps.children);
        var textProps = {};
        for (var key in nextProps) {
          if (!Object.prototype.hasOwnProperty.call(nextProps, key) || key === 'children') {
            continue;
          }
          textProps[key] = nextProps[key];
        }
        try {
          textProps.text = textValue;
          target.setNativeProps(textProps);
          return true;
        } catch (e) {}
        try {
          textProps.children = textValue;
          target.setNativeProps(textProps);
          return true;
        } catch (e) {}
      }
      target.setNativeProps(nextProps);
      return true;
    } catch (e) {
      return false;
    }
  };

  log('34 runtime script loaded');
  log('34 prelude installed=' + String(g.__bloomInspectorPreludeInstalled));
  log('34 prelude hook installed=' + String(g.__bloomInspectorHookInstalled));
  try {
    var hookState = g.__REACT_DEVTOOLS_GLOBAL_HOOK__;
    var rendererCount = hookState && hookState.renderers ? hookState.renderers.size : 0;
    log('34 prelude hook renderers=' + String(rendererCount));
  } catch (e) {}
  try {
    var fabricManager = g.nativeFabricUIManager || g.__nativeFabricUIManager;
    var fabricKeys = fabricManager ? Object.keys(fabricManager) : [];
    log('34 nativeFabricUIManager=' + String(!!fabricManager) + ' keys=' + fabricKeys.slice(0, 6).join(','));
  } catch (e) {}

  function observeHook(targetHook, label) {
    if (!targetHook || targetHook.__bloomInspectorObserved) {
      return;
    }
    targetHook.__bloomInspectorObserved = true;
    log('70 devtools hook observed ' + label);
    if (!g.__bloomInspectorRenderers) {
      g.__bloomInspectorRenderers = [];
    }
    if (targetHook.renderers && typeof targetHook.renderers.set === 'function') {
      var originalSet = targetHook.renderers.set.bind(targetHook.renderers);
      targetHook.renderers.set = function (id, renderer) {
        if (targetHook.__bloomInspectorDummyRenderer) {
          try {
            if (typeof targetHook.renderers.delete === 'function') {
              targetHook.renderers.delete('__bloomInspectorDummy');
            } else if (typeof targetHook.renderers === 'object') {
              delete targetHook.renderers.__bloomInspectorDummy;
            }
          } catch (e) {}
          targetHook.__bloomInspectorDummyRenderer = null;
          log('70 devtools hook dummy renderer cleared');
        }
        g.__bloomInspectorRenderers.push(renderer);
        return originalSet(id, renderer);
      };
    }
    if (typeof targetHook.inject === 'function') {
      var originalInject = targetHook.inject.bind(targetHook);
      targetHook.inject = function (renderer) {
        var id = originalInject(renderer);
        if (targetHook.__bloomInspectorDummyRenderer) {
          try {
            if (targetHook.renderers && typeof targetHook.renderers.delete === 'function') {
              targetHook.renderers.delete('__bloomInspectorDummy');
            } else if (targetHook.renderers && typeof targetHook.renderers === 'object') {
              delete targetHook.renderers.__bloomInspectorDummy;
            }
          } catch (e) {}
          targetHook.__bloomInspectorDummyRenderer = null;
          log('70 devtools hook dummy renderer cleared');
        }
        g.__bloomInspectorRenderers.push(renderer);
        return id;
      };
    }
  }

  function ensureHook() {
    var hook = g.__REACT_DEVTOOLS_GLOBAL_HOOK__;
    if (!hook) {
      return null;
    }
    if (!hook.renderers) {
      try {
        hook.renderers = new Map();
        log('70 devtools hook patched renderers');
      } catch (e) {}
    }
    if (!hook.__bloomInspectorListeners) {
      hook.__bloomInspectorListeners = {};
    }
    if (typeof hook.on !== 'function') {
      hook.on = function (event, handler) {
        var listeners = hook.__bloomInspectorListeners;
        if (!listeners[event]) {
          listeners[event] = [];
        }
        listeners[event].push(handler);
      };
    }
    if (typeof hook.off !== 'function') {
      hook.off = function (event, handler) {
        var listeners = hook.__bloomInspectorListeners;
        var handlers = listeners[event];
        if (!handlers) {
          return;
        }
        var index = handlers.indexOf(handler);
        if (index >= 0) {
          handlers.splice(index, 1);
        }
      };
    }
    if (typeof hook.emit !== 'function') {
      hook.emit = function (event, payload) {
        var listeners = hook.__bloomInspectorListeners;
        var handlers = listeners[event];
        if (!handlers) {
          return;
        }
        handlers.forEach(function (handler) {
          try {
            handler(payload);
          } catch (e) {}
        });
      };
    }
    observeHook(hook, 'runtime');
    return hook;
  }

  if (g.setTimeout) {
    var flushAttempts = 0;
    (function retryFlush() {
      flushLogs();
      flushAttempts += 1;
      if (pendingLogs.length && flushAttempts < 40) {
        g.setTimeout(retryFlush, 500);
      }
    })();
  }

  function sendPayload(data, touchID, viewTagValue) {
    function sanitize(value, depth) {
      if (depth > 3) {
        return '[MaxDepth]';
      }
      if (value == null || typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
        return value;
      }
      if (Array.isArray(value)) {
        return value.map(function (item) {
          return sanitize(item, depth + 1);
        });
      }
      if (typeof value === 'object') {
        var result = {};
        for (var key in value) {
          try {
            result[key] = sanitize(value[key], depth + 1);
          } catch (e) {}
        }
        return result;
      }
      return String(value);
    }

    var hierarchy = data.hierarchy || [];
    if (hierarchy.length) {
      var inspectableCount = 0;
      for (var hi = 0; hi < hierarchy.length; hi++) {
        if (hierarchy[hi] && typeof hierarchy[hi].getInspectorData === 'function') {
          inspectableCount++;
        }
      }
      log('39 hierarchy items=' + hierarchy.length + ' inspectable=' + inspectableCount);
    } else {
      log('39 hierarchy empty');
    }
    var selectedIndex = data.selectedIndex != null ? data.selectedIndex : Math.max(hierarchy.length - 1, 0);

    function buildPayload(detailData) {
      var normalizedStack = normalizeStackParts(detailData && detailData.componentStack
        ? detailData.componentStack
        : data.componentStack);
        var resolvedViewTag = data.viewTag != null ? data.viewTag : viewTagValue;
        var payloadToSend = {
          frame: data.frame,
          viewTag: resolvedViewTag != null ? resolvedViewTag : undefined,
          hierarchy: hierarchy.map(function (item) {
            return { name: item && item.name ? item.name : 'Anonymous' };
          }),
        props: undefined,
        selectedIndex: selectedIndex,
        source: undefined,
        ownerSource: undefined,
        componentStack: normalizedStack.length ? normalizedStack.join('\n') : undefined,
        touchID: touchID != null ? touchID : undefined,
        payloadSource: 'js',
      };
      if (detailData && detailData.props) {
        payloadToSend.props = sanitize(detailData.props, 0);
      } else if (data.props) {
        payloadToSend.props = sanitize(data.props, 0);
      }
      payloadToSend.source = detailData && detailData.source ? detailData.source : data.source;
      payloadToSend.ownerSource = detailData && detailData.ownerSource ? detailData.ownerSource : data.ownerSource;
      return payloadToSend;
    }

    function getNativeModules() {
      if (g.NativeModules) {
        return g.NativeModules;
      }
      var r = g.__r;
      if (!r || typeof r !== 'function' || !r.getModules || typeof r.getModules !== 'function') {
        return null;
      }
      var modules = r.getModules();
      if (!modules) {
        return null;
      }
      var foundId = null;
      var foundName = null;
      function checkModule(key, value) {
        if (!value || !value.verboseName) {
          return;
        }
        var name = value.verboseName;
        if (name.indexOf('BatchedBridge/NativeModules') !== -1 ||
            name.indexOf('Libraries/BatchedBridge/NativeModules') !== -1 ||
            name.indexOf('NativeModules') !== -1) {
          foundId = key;
          foundName = name;
        }
      }
      if (typeof modules.forEach === 'function') {
        modules.forEach(function (value, key) {
          if (foundId == null) {
            checkModule(key, value);
          }
        });
      } else if (typeof modules === 'object') {
        for (var key in modules) {
          if (foundId != null) {
            break;
          }
          checkModule(key, modules[key]);
        }
      }
      if (foundId == null) {
        return null;
      }
      try {
        var resolved = r(foundId);
        if (!g.__bloomInspectorNativeModulesLogged) {
          log('38 nativeModules resolved name=' + foundName + ' id=' + String(foundId));
          g.__bloomInspectorNativeModulesLogged = true;
        }
        if (resolved && resolved.NativeModules) {
          return resolved.NativeModules;
        }
        if (resolved && resolved.default && resolved.default.NativeModules) {
          return resolved.default.NativeModules;
        }
        if (resolved && resolved.default) {
          return resolved.default;
        }
        return resolved || null;
      } catch (e) {
        return null;
      }
    }

    function emitPayload(payloadToSend, label) {
      var overlayModule = null;
      var inspectorForwarder = null;
      var deviceEmitter = null;
      var nativeModules = getNativeModules();
      if (!g.__bloomInspectorForwarderLogged) {
        try {
          var keys = nativeModules ? Object.keys(nativeModules) : [];
          log('38-0 nativeModules keys=' + (keys.length ? keys.slice(0, 8).join(',') : 'none'));
          log('38-0 BloomInspector=' + String(!!(nativeModules && nativeModules.BloomInspector)) +
            ' sendPick=' + String(!!(nativeModules && nativeModules.BloomInspector &&
              typeof nativeModules.BloomInspector.sendPick === 'function')));
          log('38-0 BloomInspectorOverlay=' + String(!!(nativeModules && nativeModules.BloomInspectorOverlay)) +
            ' sendPick=' + String(!!(nativeModules && nativeModules.BloomInspectorOverlay &&
              typeof nativeModules.BloomInspectorOverlay.sendPick === 'function')));
        } catch (e) {}
        g.__bloomInspectorForwarderLogged = true;
      }
      if (g.__turboModuleProxy) {
        overlayModule = g.__turboModuleProxy('BloomInspectorOverlay');
      }
      if (!overlayModule && nativeModules && nativeModules.BloomInspectorOverlay) {
        overlayModule = nativeModules.BloomInspectorOverlay;
      }
      if (!overlayModule && nativeModules && nativeModules.BloomInspector &&
          typeof nativeModules.BloomInspector.sendPick === 'function') {
        inspectorForwarder = nativeModules.BloomInspector;
      }
      if (!overlayModule && !inspectorForwarder) {
        try {
          var r = g.__r;
          if (r && typeof r.getModules === 'function') {
            var modules = r.getModules();
            var deviceEmitterId = null;
            var deviceEmitterName = null;
            function checkEmitter(key, value) {
              if (!value || !value.verboseName) {
                return;
              }
              var name = value.verboseName;
              if (name.indexOf('RCTDeviceEventEmitter') !== -1 ||
                  name.indexOf('DeviceEventEmitter') !== -1 ||
                  name.indexOf('Libraries/EventEmitter/RCTDeviceEventEmitter') !== -1) {
                deviceEmitterId = key;
                deviceEmitterName = name;
              }
            }
            if (typeof modules.forEach === 'function') {
              modules.forEach(function (value, key) {
                if (deviceEmitterId == null) {
                  checkEmitter(key, value);
                }
              });
            } else if (typeof modules === 'object') {
              for (var key in modules) {
                if (deviceEmitterId != null) {
                  break;
                }
                checkEmitter(key, modules[key]);
              }
            }
            if (deviceEmitterId != null) {
              var emitterModule = r(deviceEmitterId);
              deviceEmitter = emitterModule && (emitterModule.default || emitterModule);
              if (!g.__bloomInspectorEmitterLogged) {
                log('38 device emitter resolved name=' + deviceEmitterName + ' id=' + String(deviceEmitterId));
                g.__bloomInspectorEmitterLogged = true;
              }
            }
          }
        } catch (e) {}
      }
      if (!overlayModule) {
        log('38 overlay module missing');
      } else if (typeof overlayModule.sendPick !== 'function') {
        log('38 overlay module missing sendPick');
      } else {
        log('38 overlay module sendPick');
      }
      if (overlayModule && overlayModule.sendPick) {
        overlayModule.sendPick(payloadToSend);
      } else if (inspectorForwarder) {
        log('38 overlay forwarder BloomInspector.sendPick');
        inspectorForwarder.sendPick(payloadToSend);
      } else if (deviceEmitter && typeof deviceEmitter.emit === 'function') {
        log('38 overlay device emitter emit');
        deviceEmitter.emit('bloomInspectorOverlayPick', payloadToSend);
      } else if (!nativeModules) {
        log('38 overlay forwarder missing nativeModules');
      } else {
        log('38 overlay forwarder missing sendPick');
      }
      log(label);
    }

    var detailHandled = false;
    var fallbackTimer = null;
    var candidates = [];
    var added = {};
    function addCandidate(index) {
      if (index == null || index < 0 || index >= hierarchy.length) {
        return;
      }
      if (added[index]) {
        return;
      }
      added[index] = true;
      candidates.push({ item: hierarchy[index], index: index });
    }
    addCandidate(selectedIndex);
    addCandidate(hierarchy.length - 1);
    addCandidate(0);
    for (var i = 0; i < hierarchy.length; i++) {
      addCandidate(i);
    }

    function tryNextCandidate(pos) {
      if (detailHandled) {
        return;
      }
      if (pos >= candidates.length) {
        return;
      }
      var candidate = candidates[pos];
      var item = candidate.item;
      if (!item || typeof item.getInspectorData !== 'function') {
        tryNextCandidate(pos + 1);
        return;
      }
      try {
        log('39-1 detail item idx=' + candidate.index + ' invoking getInspectorData');
        var result = item.getInspectorData(function (detailData) {
          if (detailHandled) {
            return;
          }
          try {
            var keys = detailData ? Object.keys(detailData) : [];
            log('39-2 detail item idx=' + candidate.index + ' keys=' + keys.join(','));
          } catch (e) {}
          var hasStack = detailData && detailData.componentStack;
          var hasSource = detailData && detailData.source;
          var hasProps = detailData && detailData.props;
          log('39-1 detail item idx=' + candidate.index +
              ' stack=' + String(!!hasStack) +
              ' source=' + String(!!hasSource) +
              ' props=' + String(!!hasProps));
          if (detailData && (hasStack || hasSource)) {
            detailHandled = true;
            if (fallbackTimer) {
              clearTimeout(fallbackTimer);
            }
            emitPayload(buildPayload(detailData), '38 sent JS payload (detail)');
            return;
          }
          tryNextCandidate(pos + 1);
        });
        if (!detailHandled && result) {
          try {
            var resultKeys = result ? Object.keys(result) : [];
            log('39-2 detail item idx=' + candidate.index + ' sync keys=' + resultKeys.join(','));
          } catch (e) {}
          var resStack = result.componentStack;
          var resSource = result.source;
          var resProps = result.props;
          log('39-1 detail item idx=' + candidate.index +
              ' sync stack=' + String(!!resStack) +
              ' source=' + String(!!resSource) +
              ' props=' + String(!!resProps));
          if (resStack || resSource) {
            detailHandled = true;
            if (fallbackTimer) {
              clearTimeout(fallbackTimer);
            }
            emitPayload(buildPayload(result), '38 sent JS payload (detail-sync)');
            return;
          }
        }
      } catch (e) {
        tryNextCandidate(pos + 1);
      }
    }

    tryNextCandidate(0);

    if (typeof setTimeout === 'function') {
      fallbackTimer = setTimeout(function () {
        if (detailHandled) {
          return;
        }
        emitPayload(buildPayload(null), '38 sent JS payload (fallback)');
      }, 500);
    } else {
      emitPayload(buildPayload(null), '38 sent JS payload (fallback)');
    }
  }

  function getComponentName(fiber) {
    if (!fiber) {
      return 'Unknown';
    }
    var type = fiber.elementType || fiber.type;
    if (typeof type === 'string') {
      return type;
    }
    if (type && (type.displayName || type.name)) {
      return type.displayName || type.name;
    }
    return fiber.tag != null ? 'Fiber(' + fiber.tag + ')' : 'Unknown';
  }

  var FiberTags = {
    FunctionComponent: 0,
    ClassComponent: 1,
    IndeterminateComponent: 2,
    HostRoot: 3,
    HostComponent: 5,
    HostText: 6,
    ForwardRef: 11,
    MemoComponent: 14,
    SimpleMemoComponent: 15,
  };

  function isUserComponent(fiber) {
    return fiber && (
      fiber.tag === FiberTags.FunctionComponent ||
      fiber.tag === FiberTags.ClassComponent ||
      fiber.tag === FiberTags.ForwardRef ||
      fiber.tag === FiberTags.MemoComponent ||
      fiber.tag === FiberTags.SimpleMemoComponent ||
      fiber.tag === FiberTags.IndeterminateComponent
    );
  }

  function getFiberName(fiber) {
    if (!fiber) {
      return 'Unknown';
    }
    var type = fiber.elementType || fiber.type;
    if (typeof type === 'string') {
      return type;
    }
    if (typeof type === 'function') {
      return type.displayName || type.name || 'Anonymous';
    }
    if (type && typeof type === 'object') {
      if (type.displayName) {
        return type.displayName;
      }
      if (type.render && (type.render.displayName || type.render.name)) {
        return type.render.displayName || type.render.name;
      }
      if (type.type && (type.type.displayName || type.type.name)) {
        return type.type.displayName || type.type.name;
      }
    }
    return getComponentName(fiber);
  }

  function getCodeInfoFromFiber(fiber) {
    if (!fiber || !fiber._debugSource) {
      return null;
    }
    var source = fiber._debugSource;
    return {
      fileName: source.fileName,
      lineNumber: source.lineNumber,
      columnNumber: source.columnNumber != null ? source.columnNumber : 1,
    };
  }

  function getSourceFromProps(props) {
    if (!props) {
      return null;
    }
    var candidate = props.__bloomSource || props.__source;
    if (!candidate || typeof candidate !== 'object') {
      return null;
    }
    var fileName = candidate.fileName;
    var lineNumber = candidate.lineNumber;
    var columnNumber = candidate.columnNumber;
    if (typeof fileName !== 'string' || typeof lineNumber !== 'number') {
      return null;
    }
    return {
      fileName: fileName,
      lineNumber: lineNumber,
      columnNumber: typeof columnNumber === 'number' ? columnNumber : 1,
    };
  }

  function isBundleUrl(fileName) {
    if (!fileName) {
      return false;
    }
    return (
      (typeof fileName === 'string' && (fileName.indexOf('http://') === 0 || fileName.indexOf('https://') === 0)) ||
      (typeof fileName === 'string' && fileName.indexOf('index.bundle') !== -1)
    );
  }

  function isNodeModulesPath(fileName) {
    if (!fileName || typeof fileName !== 'string') {
      return false;
    }
    return fileName.indexOf('/node_modules/') !== -1;
  }

  function scoreSource(fileName) {
    if (!fileName) {
      return -1;
    }
    var score = 0;
    if (!isBundleUrl(fileName)) {
      score += 2;
    }
    if (!isNodeModulesPath(fileName)) {
      score += 3;
    }
    if (typeof fileName === 'string' && fileName.indexOf('/apps/') !== -1) {
      score += 1;
    }
    return score;
  }

  function pickOwnerSource(candidateSources) {
    if (!candidateSources || !candidateSources.length) {
      return null;
    }
    var best = null;
    for (var i = 0; i < candidateSources.length; i++) {
      var candidate = candidateSources[i];
      if (!candidate || !candidate.fileName) {
        continue;
      }
      var fileName = candidate.fileName;
      if (isBundleUrl(fileName)) {
        continue;
      }
      if (isNodeModulesPath(fileName)) {
        continue;
      }
      if (!best) {
        best = candidate;
        continue;
      }
      var bestIsApps = typeof best.fileName === 'string' && best.fileName.indexOf('/apps/') !== -1;
      var candidateIsApps = typeof fileName === 'string' && fileName.indexOf('/apps/') !== -1;
      if (!bestIsApps && candidateIsApps) {
        best = candidate;
      }
    }
    return best;
  }

  function findNearestUserFiberWithSource(fiber) {
    var current = fiber;
    while (current) {
      var codeInfo = getCodeInfoFromFiber(current);
      if (codeInfo && isUserComponent(current)) {
        return { fiber: current, codeInfo: codeInfo, name: getFiberName(current) };
      }
      if (current._debugOwner) {
        var ownerInfo = getCodeInfoFromFiber(current._debugOwner);
        if (ownerInfo && isUserComponent(current._debugOwner)) {
          return { fiber: current._debugOwner, codeInfo: ownerInfo, name: getFiberName(current._debugOwner) };
        }
      }
      current = current.return;
    }
    return null;
  }

  function buildComponentStackFromFiber(fiber) {
    var names = [];
    var current = fiber;
    var depth = 0;
    while (current && depth < 40) {
      if (isUserComponent(current)) {
        names.push(getFiberName(current));
      }
      current = current.return;
      depth += 1;
    }
    if (!names.length && fiber) {
      current = fiber;
      depth = 0;
      while (current && depth < 40) {
        names.push(getFiberName(current));
        current = current.return;
        depth += 1;
      }
    }
    return names.reverse();
  }

  function getFiberFromInstance(instance) {
    if (!instance) {
      return null;
    }
    if (instance._reactInternals) {
      return instance._reactInternals;
    }
    if (instance._internalFiberInstanceHandleDEV) {
      return instance._internalFiberInstanceHandleDEV;
    }
    if (instance._internalInstanceHandle) {
      return instance._internalInstanceHandle;
    }
    try {
      var keys = Object.keys(instance);
      for (var i = 0; i < keys.length; i++) {
        var key = keys[i];
        if (key.indexOf('__reactFiber$') === 0 || key.indexOf('__reactInternalInstance$') === 0) {
          return instance[key];
        }
      }
    } catch (e) {}
    if (instance.getNode) {
      try {
        var node = instance.getNode();
        if (node) {
          return getFiberFromInstance(node);
        }
      } catch (e) {}
    }
    return null;
  }

  function getFiberFromViewData(viewData) {
    if (!viewData) {
      return null;
    }
    var candidate = viewData.closestInstance || viewData.inspected || null;
    if (candidate && candidate.tag != null && candidate.return !== undefined) {
      return candidate;
    }
    var publicInstance = viewData.closestPublicInstance || viewData.publicInstance || null;
    if (publicInstance && publicInstance._internalInstanceHandle) {
      return publicInstance._internalInstanceHandle;
    }
    if (candidate && candidate._internalInstanceHandle) {
      return candidate._internalInstanceHandle;
    }
    if (candidate) {
      return getFiberFromInstance(candidate);
    }
    if (publicInstance) {
      return getFiberFromInstance(publicInstance);
    }
    return null;
  }

  function buildHierarchyFromFiber(fiber) {
    var items = [];
    var current = fiber;
    var depth = 0;
    while (current && depth < 40) {
      items.push({
        name: getComponentName(current),
        fiber: current,
        codeInfo: current._debugSource || null,
      });
      current = current.return;
      depth++;
    }
    return items.reverse();
  }

  function isHostComponentName(name) {
    if (!name) {
      return true;
    }
    if (name === 'View' || name === 'Text' || name === 'Image' || name === 'ScrollView' || name === 'Pressable') {
      return true;
    }
    if (name === 'RCTView' || name === 'RCTText' || name === 'RCTParagraphComponentView') {
      return true;
    }
    return /^(RCT|UI|RN|RNC)/.test(name);
  }

  function normalizeStackParts(stack) {
    if (!stack) {
      return [];
    }
    var rawParts = [];
    if (stack.indexOf('\n') !== -1) {
      rawParts = stack.split('\n');
    } else {
      rawParts = stack.split(' > ');
    }
    var parts = [];
    for (var i = 0; i < rawParts.length; i++) {
      var line = rawParts[i].trim();
      if (!line) {
        continue;
      }
      if (line.indexOf('at ') === 0) {
        line = line.slice(3);
      }
      var parenIndex = line.indexOf(' (');
      if (parenIndex > 0) {
        line = line.slice(0, parenIndex);
      }
      line = line.trim();
      if (line) {
        parts.push(line);
      }
    }
    return parts;
  }

  function extractSourceFromComponentStack(stack) {
    if (!stack) {
      return null;
    }
    var lines = stack.split('\n');
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (!line) {
        continue;
      }
      var name = line;
      if (name.indexOf('at ') === 0) {
        name = name.slice(3);
      }
      var parenIndex = name.indexOf(' (');
      if (parenIndex > 0) {
        name = name.slice(0, parenIndex);
      }
      name = name.trim();
      if (!name || isHostComponentName(name)) {
        continue;
      }
      var match = line.match(/\((.*):(\d+):(\d+)\)$/);
      if (!match) {
        match = line.match(/@(.*):(\d+):(\d+)$/);
      }
      if (match) {
        return {
          fileName: match[1],
          lineNumber: Number(match[2]),
          columnNumber: Number(match[3]),
        };
      }
    }
    return null;
  }

  function hasReactComponentStack(componentStack) {
    var parts = normalizeStackParts(componentStack);
    if (!parts.length) {
      return false;
    }
    for (var i = 0; i < parts.length; i++) {
      if (!isHostComponentName(parts[i])) {
        return true;
      }
    }
    return false;
  }

  function findFiberByNativeTag(fiber, tag) {
    if (!fiber) {
      return null;
    }
    if (fiber.stateNode && fiber.stateNode._nativeTag === tag) {
      return fiber;
    }
    var child = fiber.child;
    while (child) {
      var found = findFiberByNativeTag(child, tag);
      if (found) {
        return found;
      }
      child = child.sibling;
    }
    return null;
  }

  function tryFiberLookup(viewTag, renderer) {
    if (!renderer) {
      return null;
    }
    if (typeof renderer.getFiberRoots === 'function') {
      try {
        var roots = renderer.getFiberRoots();
        if (roots && roots.size) {
          var iter = roots.values();
          var next = iter.next();
          while (!next.done) {
            var root = next.value;
            if (root && root.current) {
              var found = findFiberByNativeTag(root.current, viewTag);
              if (found) {
                return found;
              }
            }
            next = iter.next();
          }
        }
      } catch (e) {}
    }
    var hook = g.__REACT_DEVTOOLS_GLOBAL_HOOK__;
    if (hook && typeof hook.getFiberRoots === 'function') {
      try {
        var ids = [];
        if (hook.renderers && hook.renderers.size) {
          hook.renderers.forEach(function (_renderer, id) {
            ids.push(id);
          });
        }
        if (!ids.length) {
          ids = [1];
        }
        for (var i = 0; i < ids.length; i++) {
          var hookRoots = hook.getFiberRoots(ids[i]);
          if (!hookRoots || !hookRoots.size) {
            continue;
          }
          var hookIter = hookRoots.values();
          var hookNext = hookIter.next();
          while (!hookNext.done) {
            var hookRoot = hookNext.value;
            if (hookRoot && hookRoot.current) {
              var hookFound = findFiberByNativeTag(hookRoot.current, viewTag);
              if (hookFound) {
                return hookFound;
              }
            }
            hookNext = hookIter.next();
          }
        }
      } catch (e) {}
    }
    return null;
  }

  function findReactNativeModuleId() {
    var r = g.__r;
    if (!r || typeof r !== 'function' || !r.getModules || typeof r.getModules !== 'function') {
      return null;
    }
    var modules = r.getModules();
    if (!modules) {
      return null;
    }
    var foundId = null;
    var exactId = null;
    var candidateId = null;
    var candidateName = null;
    if (typeof modules.forEach === 'function') {
      modules.forEach(function (value, key) {
        if (!value || !value.verboseName) {
          return;
        }
        var name = value.verboseName;
        if (name === 'react-native') {
          exactId = key;
        }
        if (!candidateId && name.indexOf('/node_modules/react-native/index') !== -1) {
          candidateId = key;
          candidateName = name;
        }
      });
    } else if (typeof modules === 'object') {
      for (var key in modules) {
        var value = modules[key];
        if (!value || !value.verboseName) {
          continue;
        }
        var name = value.verboseName;
        if (name === 'react-native') {
          exactId = key;
          break;
        }
        if (!candidateId && name.indexOf('/node_modules/react-native/index') !== -1) {
          candidateId = key;
          candidateName = name;
        }
      }
    }
    foundId = exactId != null ? exactId : candidateId;
    if (!g.__bloomInspectorRnIdLogged) {
      log('67 react-native id exact=' + (exactId != null ? exactId : 'none') +
          ' candidate=' + (candidateId != null ? candidateId : 'none') +
          ' name=' + (candidateName || 'none'));
      g.__bloomInspectorRnIdLogged = true;
    }
    return foundId;
  }

  function findDevtoolsModuleId(matchers) {
    var r = g.__r;
    if (!r || typeof r !== 'function' || !r.getModules || typeof r.getModules !== 'function') {
      return null;
    }
    var modules = r.getModules();
    if (!modules) {
      return null;
    }
    var foundId = null;
    function matchesName(name) {
      if (!name) {
        return false;
      }
      for (var i = 0; i < matchers.length; i++) {
        if (name.indexOf(matchers[i]) !== -1) {
          return true;
        }
      }
      return false;
    }
    if (typeof modules.forEach === 'function') {
      modules.forEach(function (value, key) {
        if (foundId != null || !value || !value.verboseName) {
          return;
        }
        if (matchesName(value.verboseName)) {
          foundId = key;
        }
      });
    } else if (typeof modules === 'object') {
      for (var key in modules) {
        if (foundId != null) {
          break;
        }
        var value = modules[key];
        if (!value || !value.verboseName) {
          continue;
        }
        if (matchesName(value.verboseName)) {
          foundId = key;
          break;
        }
      }
    }
    return foundId;
  }

  function bootstrapDevtoolsBackend(requireFn, hook, force) {
    if (!requireFn || !hook) {
      return false;
    }
    var state = g.__bloomInspectorDevtoolsBootstrap;
    if (!state || typeof state !== 'object') {
      state = { attempts: 0, lastAttempt: 0, success: false };
      g.__bloomInspectorDevtoolsBootstrap = state;
    }
    if (state.success) {
      return true;
    }
    var now = g.Date && typeof g.Date.now === 'function' ? g.Date.now() : 0;
    if (!force && state.attempts >= 5 && now && state.lastAttempt && now - state.lastAttempt < 2000) {
      return false;
    }
    state.attempts += 1;
    state.lastAttempt = now;
    try {
      if (hook.rendererInterfaces && hook.rendererInterfaces.size) {
        state.success = true;
        return true;
      }
    } catch (e) {}
    try {
      if (hook.renderers && hook.renderers.size) {
        state.success = true;
        return true;
      }
    } catch (e) {}
    var backendId = findDevtoolsModuleId([
      'react-devtools-core/backend',
      'react-devtools-core/backend.js',
    ]);
    if (backendId != null) {
      try {
        var backend = requireFn(backendId);
        if (backend && typeof backend.initialize === 'function') {
          backend.initialize(hook);
          log('72 devtools backend initialized');
          state.success = true;
          return true;
        }
      } catch (e) {
        log('72 devtools backend init failed');
      }
    } else if (force) {
      log('72 devtools backend module missing');
    }
    var standaloneId = findDevtoolsModuleId([
      'react-devtools-core/standalone',
      'react-devtools-core/standalone.js',
      'react-devtools-core',
    ]);
    if (standaloneId != null) {
      try {
        var standalone = requireFn(standaloneId);
        if (standalone && typeof standalone.connectToDevTools === 'function') {
          standalone.connectToDevTools({
            host: 'localhost',
            port: 8097,
            resolveRNStyle: hook.resolveRNStyle || undefined,
          });
          log('72 devtools standalone connect');
          state.success = true;
          return true;
        }
      } catch (e) {
        log('72 devtools standalone failed');
      }
    } else if (force) {
      log('72 devtools standalone module missing');
    }
    return false;
  }

  function findReactModuleId() {
    var r = g.__r;
    if (!r || typeof r !== 'function' || !r.getModules || typeof r.getModules !== 'function') {
      return null;
    }
    var modules = r.getModules();
    if (!modules) {
      return null;
    }
    var exactId = null;
    var candidateId = null;
    if (typeof modules.forEach === 'function') {
      modules.forEach(function (value, key) {
        if (!value || !value.verboseName) {
          return;
        }
        var name = value.verboseName;
        if (name === 'react') {
          exactId = key;
        }
        if (!candidateId && name.indexOf('/node_modules/react/index') !== -1) {
          candidateId = key;
        }
      });
    } else if (typeof modules === 'object') {
      for (var key in modules) {
        var value = modules[key];
        if (!value || !value.verboseName) {
          continue;
        }
        var name = value.verboseName;
        if (name === 'react') {
          exactId = key;
          break;
        }
        if (!candidateId && name.indexOf('/node_modules/react/index') !== -1) {
          candidateId = key;
        }
      }
    }
    return exactId != null ? exactId : candidateId;
  }

  function tryWrapAppRegistry(attempt, RN, requireFn) {
    if (g.__bloomInspectorAppRegistryWrapped) {
      return true;
    }
    if (!RN || !RN.AppRegistry || typeof RN.AppRegistry.registerComponent !== 'function') {
      if (attempt === 0) {
        log('90 failed to wrap AppRegistry (module missing)');
      }
      if (attempt < 20 && g.setTimeout) {
        g.setTimeout(function () {
          tryWrapAppRegistry(attempt + 1, RN, requireFn);
        }, 250);
      }
      return false;
    }
    var React = null;
    var reactId = findReactModuleId();
    if (reactId != null && typeof requireFn === 'function') {
      try {
        React = requireFn(reactId);
      } catch (e) {}
    }
    if (!React || typeof React.createElement !== 'function' || typeof React.forwardRef !== 'function') {
      log('90 failed to wrap AppRegistry (react missing)');
      return false;
    }
    var AppRegistry = RN.AppRegistry;
    if (typeof AppRegistry.setWrapperComponentProvider === 'function' && !g.__bloomInspectorWrapperInstalled) {
      var View = RN.View;
      if (typeof View === 'function') {
        try {
          AppRegistry.setWrapperComponentProvider(function () {
            return function (props) {
              return React.createElement(
                View,
                {
                  ref: function (instance) {
                    if (instance && !g.__bloomInspectorHostComponent) {
                      g.__bloomInspectorHostComponent = instance;
                      log('91 host component captured');
                    }
                  },
                  collapsable: false,
                  pointerEvents: 'box-none',
                  style: { flex: 1 },
                },
                props ? props.children : null
              );
            };
          });
          g.__bloomInspectorWrapperInstalled = true;
          log('90 wrapped AppRegistry.setWrapperComponentProvider');
        } catch (e) {
          log('90 failed to wrap AppRegistry.setWrapperComponentProvider');
        }
      } else {
        log('90 failed to wrap AppRegistry.setWrapperComponentProvider (View missing)');
      }
    }
    if (AppRegistry.registerComponent.__bloomInspectorWrapped) {
      g.__bloomInspectorAppRegistryWrapped = true;
      return true;
    }
    var originalRegister = AppRegistry.registerComponent;
    AppRegistry.registerComponent = function (appKey, componentProvider) {
      if (typeof componentProvider !== 'function') {
        return originalRegister.apply(this, arguments);
      }
      return originalRegister.call(this, appKey, function () {
        var Component = componentProvider();
        if (!Component || Component.__bloomInspectorWrapped) {
          return Component;
        }
        var Wrapped = React.forwardRef(function (props, ref) {
          var mergedProps = Object.assign({}, props, {
            ref: function (instance) {
              if (instance && !g.__bloomInspectorHostComponent) {
                g.__bloomInspectorHostComponent = instance;
                log('91 host component captured');
              }
              if (typeof ref === 'function') {
                ref(instance);
              } else if (ref && typeof ref === 'object') {
                ref.current = instance;
              }
            },
          });
          return React.createElement(Component, mergedProps);
        });
        Wrapped.displayName =
          (Component.displayName || Component.name || 'Component') + 'BloomInspectorWrapper';
        Wrapped.__bloomInspectorWrapped = true;
        return Wrapped;
      });
    };
    AppRegistry.registerComponent.__bloomInspectorWrapped = true;
    g.__bloomInspectorAppRegistryWrapped = true;
    log('90 wrapped AppRegistry.registerComponent');
    return true;
  }

  function attachWithRequire() {
    var requireFn = g.__r || g.require;
    if (typeof requireFn !== 'function') {
      log('61 react-native module not ready');
      return false;
    }

    var RN = null;
    var rnId = findReactNativeModuleId();
    if (rnId != null) {
      try {
        RN = requireFn(rnId);
      } catch (e) {}
    }
    if (!RN) {
      log('61 react-native id not ready');
      return false;
    }
    if (!RN.NativeModules || !RN.NativeEventEmitter) {
      var hasNativeModules = !!RN.NativeModules;
      var hasEmitter = !!RN.NativeEventEmitter;
      log('61 react-native exports missing nm=' + hasNativeModules + ' emitter=' + hasEmitter);
      return false;
    }
    var inspectorModule = RN.NativeModules.BloomInspector;
    if (!inspectorModule) {
      log('61 BloomInspector module missing');
      return false;
    }
    tryWrapAppRegistry(0, RN, requireFn);
    var hook = ensureHook();
    if (!hook || !hook.renderers) {
      log('52 devtools hook missing');
      return false;
    }
    bootstrapDevtoolsBackend(requireFn, hook, false);

    var renderers = Array.from(hook.renderers.values());
    if (!renderers.length && Array.isArray(g.__bloomInspectorRenderers) && g.__bloomInspectorRenderers.length) {
      renderers = g.__bloomInspectorRenderers.slice();
    }
    if (hook.on && typeof hook.on === 'function') {
      hook.on('renderer', function (payload) {
        if (payload && payload.renderer) {
          renderers.push(payload.renderer);
          log('68 renderer added count=' + renderers.length);
        }
      });
    }

    var emitter = new RN.NativeEventEmitter(inspectorModule);
    var fiberByTag = g.__bloomInspectorFiberByTag;
    if (!fiberByTag) {
      try {
        fiberByTag = new Map();
      } catch (e) {
        fiberByTag = {};
      }
      g.__bloomInspectorFiberByTag = fiberByTag;
    }
    var rendererByTag = g.__bloomInspectorRendererByTag;
    if (!rendererByTag) {
      try {
        rendererByTag = new Map();
      } catch (e) {
        rendererByTag = {};
      }
      g.__bloomInspectorRendererByTag = rendererByTag;
    }

    function cacheFiberForTag(tag, fiber, source, renderer) {
      if (tag == null || !fiber) {
        return;
      }
      try {
        if (fiberByTag && typeof fiberByTag.set === 'function') {
          fiberByTag.set(tag, fiber);
        } else {
          fiberByTag[tag] = fiber;
        }
        if (renderer) {
          if (rendererByTag && typeof rendererByTag.set === 'function') {
            rendererByTag.set(tag, renderer);
          } else if (rendererByTag) {
            rendererByTag[tag] = renderer;
          }
        }
        if (DEBUG_LOGS) {
          log('live edit cached fiber tag=' + String(tag) + ' source=' + (source || 'unknown'));
        }
      } catch (e) {}
    }

    function getCachedFiber(tag) {
      if (tag == null) {
        return null;
      }
      try {
        if (fiberByTag && typeof fiberByTag.get === 'function') {
          return fiberByTag.get(tag) || null;
        }
        return fiberByTag ? fiberByTag[tag] || null : null;
      } catch (e) {
        return null;
      }
    }

    function getCachedRenderer(tag) {
      if (tag == null) {
        return null;
      }
      try {
        if (rendererByTag && typeof rendererByTag.get === 'function') {
          return rendererByTag.get(tag) || null;
        }
        return rendererByTag ? rendererByTag[tag] || null : null;
      } catch (e) {
        return null;
      }
    }

    function mergeStyles(existing, override) {
      if (override == null) {
        return existing;
      }
      if (Array.isArray(override)) {
        if (existing == null) {
          return override.slice();
        }
        if (Array.isArray(existing)) {
          return existing.concat(override);
        }
        return [existing].concat(override);
      }
      if (existing == null) {
        return [override];
      }
      if (Array.isArray(existing)) {
        return existing.concat(override);
      }
      return [existing, override];
    }

    function stripInspectorKeys(rawProps) {
      if (!rawProps || typeof rawProps !== 'object') {
        return null;
      }
      var cleaned = {};
      for (var key in rawProps) {
        if (!Object.prototype.hasOwnProperty.call(rawProps, key)) {
          continue;
        }
        if (
          key === '__bloomInspectorUseChild' ||
          key === '__bloomInspectorForceUIKit' ||
          key === '__bloomInspectorDebug' ||
          key === 'reactTag' ||
          key === 'viewTag'
        ) {
          continue;
        }
        cleaned[key] = rawProps[key];
      }
      return cleaned;
    }

    function buildMergedProps(fiber, nextProps) {
      if (!fiber || !nextProps || typeof nextProps !== 'object') {
        return null;
      }
      var cleaned = stripInspectorKeys(nextProps);
      if (!cleaned) {
        return null;
      }
      var currentProps = fiber.memoizedProps || {};
      var mergedProps = {};
      for (var key in currentProps) {
        mergedProps[key] = currentProps[key];
      }
      for (var propKey in cleaned) {
        if (!Object.prototype.hasOwnProperty.call(cleaned, propKey)) {
          continue;
        }
        if (propKey === 'style') {
          mergedProps.style = mergeStyles(currentProps.style, cleaned.style);
        } else {
          mergedProps[propKey] = cleaned[propKey];
        }
      }
      return mergedProps;
    }

    function applyPropsToFiber(fiber, mergedProps) {
      if (!fiber || !mergedProps || typeof mergedProps !== 'object') {
        return false;
      }
      fiber.memoizedProps = mergedProps;
      fiber.pendingProps = mergedProps;
      return true;
    }

    function extractTextValue(nextProps) {
      if (!nextProps || typeof nextProps !== 'object') {
        return null;
      }
      var value = null;
      if (Object.prototype.hasOwnProperty.call(nextProps, 'children')) {
        value = nextProps.children;
      } else if (Object.prototype.hasOwnProperty.call(nextProps, 'text')) {
        value = nextProps.text;
      } else if (Object.prototype.hasOwnProperty.call(nextProps, 'value')) {
        value = nextProps.value;
      }
      if (typeof value === 'string' || typeof value === 'number') {
        return String(value);
      }
      return null;
    }

    function applyTextViaStateNode(fiber, textValue) {
      if (!fiber || textValue == null) {
        return false;
      }
      var queue = [fiber];
      var visited = 0;
      while (queue.length && visited < 40) {
        var node = queue.shift();
        if (!node) {
          visited += 1;
          continue;
        }
        var state = node.stateNode;
        if (state && typeof state.setNativeProps === 'function') {
          try {
            state.setNativeProps({ text: textValue });
            return true;
          } catch (e) {}
          try {
            state.setNativeProps({ children: textValue });
            return true;
          } catch (e) {}
        }
        if (node.child) {
          queue.push(node.child);
        }
        if (node.sibling) {
          queue.push(node.sibling);
        }
        visited += 1;
      }
      return false;
    }

    function tryFindFiberForTag(viewTagValue) {
      if (viewTagValue == null) {
        return null;
      }
      for (var i = 0; i < renderers.length; i++) {
        var renderer = renderers[i];
        if (!renderer) {
          continue;
        }
        var found = tryFiberLookup(viewTagValue, renderer);
        if (!found && renderer.rendererConfig && typeof renderer.rendererConfig.getInspectorDataForViewTag === 'function') {
          try {
            var viewData = renderer.rendererConfig.getInspectorDataForViewTag(viewTagValue);
            if (viewData) {
              found = getFiberFromViewData(viewData);
            }
          } catch (e) {}
        }
        if (found) {
          cacheFiberForTag(viewTagValue, found, 'renderer', renderer);
          return found;
        }
      }
      var hook = g.__REACT_DEVTOOLS_GLOBAL_HOOK__;
      if (hook && typeof hook.getFiberRoots === 'function') {
        try {
          var ids = [];
          if (hook.renderers && hook.renderers.size) {
            hook.renderers.forEach(function (_renderer, id) {
              ids.push(id);
            });
          }
          if (!ids.length) {
            ids = [1];
          }
          for (var h = 0; h < ids.length; h++) {
            var roots = hook.getFiberRoots(ids[h]);
            if (!roots || !roots.size) {
              continue;
            }
            var iter = roots.values();
            var next = iter.next();
            while (!next.done) {
              var root = next.value;
              if (root && root.current) {
                var hookFound = findFiberByNativeTag(root.current, viewTagValue);
                if (hookFound) {
                  return hookFound;
                }
              }
              next = iter.next();
            }
          }
        } catch (e) {}
      }
      return null;
    }

    function findRootForFiber(fiber) {
      var current = fiber;
      while (current && current.return) {
        current = current.return;
      }
      return current && current.stateNode ? current.stateNode : null;
    }

    function isFabricRuntime() {
      return !!(g.nativeFabricUIManager || g.__nativeFabricUIManager);
    }

    function getOverrideDriver(preferredRenderer) {
      var hook = g.__REACT_DEVTOOLS_GLOBAL_HOOK__;
      var preferredId = preferredRenderer && (preferredRenderer.id || preferredRenderer.rendererID);
      if (hook && hook.rendererInterfaces) {
        try {
          if (preferredId != null) {
            if (typeof hook.rendererInterfaces.get === 'function') {
              var preferredInterface = hook.rendererInterfaces.get(preferredId);
              if (preferredInterface) {
                return { driver: preferredInterface, source: 'interface' };
              }
            } else if (typeof hook.rendererInterfaces === 'object') {
              if (hook.rendererInterfaces[preferredId]) {
                return { driver: hook.rendererInterfaces[preferredId], source: 'interface' };
              }
            }
          }
          if (!preferredRenderer) {
            if (typeof hook.rendererInterfaces.values === 'function') {
              var iter = hook.rendererInterfaces.values();
              var next = iter.next();
              if (!next.done) {
                return { driver: next.value, source: 'interface' };
              }
            } else if (typeof hook.rendererInterfaces === 'object') {
              var keys = Object.keys(hook.rendererInterfaces);
              if (keys.length) {
                return { driver: hook.rendererInterfaces[keys[0]], source: 'interface' };
              }
            }
          }
        } catch (e) {}
      }
      if (isFabricRuntime()) {
        return null;
      }
      if (preferredRenderer && typeof preferredRenderer.overrideProps === 'function') {
        return { driver: preferredRenderer, source: 'renderer' };
      }
      if (!preferredRenderer && hook && hook.renderers) {
        try {
          if (typeof hook.renderers.values === 'function') {
            var rendererIter = hook.renderers.values();
            var rendererNext = rendererIter.next();
            while (!rendererNext.done) {
              var renderer = rendererNext.value;
              if (renderer && typeof renderer.overrideProps === 'function') {
                return { driver: renderer, source: 'renderer' };
              }
              rendererNext = rendererIter.next();
            }
          } else if (typeof hook.renderers === 'object') {
            var rendererKeys = Object.keys(hook.renderers);
            for (var i = 0; i < rendererKeys.length; i++) {
              var candidate = hook.renderers[rendererKeys[i]];
              if (candidate && typeof candidate.overrideProps === 'function') {
                return { driver: candidate, source: 'renderer' };
              }
            }
          }
        } catch (e) {}
      }
      if (!preferredRenderer && Array.isArray(g.__bloomInspectorRenderers)) {
        for (var j = 0; j < g.__bloomInspectorRenderers.length; j++) {
          var cached = g.__bloomInspectorRenderers[j];
          if (cached && typeof cached.overrideProps === 'function') {
            return { driver: cached, source: 'renderer' };
          }
        }
      }
      return null;
    }

    function logDevtoolsHookState(label) {
      if (g.__bloomInspectorLoggedHookState) {
        return;
      }
      g.__bloomInspectorLoggedHookState = true;
      try {
        var hook = g.__REACT_DEVTOOLS_GLOBAL_HOOK__;
        if (!hook) {
          log('live edit hook missing ' + (label || 'unknown'));
          return;
        }
        var renderersSize = 0;
        var renderersType = hook.renderers ? typeof hook.renderers : 'none';
        var renderersKeysCount = 0;
        if (hook.renderers && typeof hook.renderers.size === 'number') {
          renderersSize = hook.renderers.size;
        } else if (hook.renderers && typeof hook.renderers === 'object') {
          try {
            renderersKeysCount = Object.keys(hook.renderers).length;
          } catch (e) {}
        }
        var interfacesSize = 0;
        var interfacesType = hook.rendererInterfaces ? typeof hook.rendererInterfaces : 'none';
        var interfacesKeysCount = 0;
        if (hook.rendererInterfaces && typeof hook.rendererInterfaces.size === 'number') {
          interfacesSize = hook.rendererInterfaces.size;
        } else if (hook.rendererInterfaces && typeof hook.rendererInterfaces === 'object') {
          try {
            interfacesKeysCount = Object.keys(hook.rendererInterfaces).length;
          } catch (e) {}
        }
        var hookKeys = [];
        try {
          hookKeys = Object.keys(hook);
        } catch (e) {}
        log(
          'live edit hook state ' +
            (label || 'unknown') +
            ' renderers=' +
            String(renderersSize) +
            ' renderersType=' +
            String(renderersType) +
            ' renderersKeys=' +
            String(renderersKeysCount) +
            ' interfaces=' +
            String(interfacesSize) +
            ' interfacesType=' +
            String(interfacesType) +
            ' interfacesKeys=' +
            String(interfacesKeysCount) +
            ' keys=' +
            hookKeys.slice(0, 8).join(',')
        );
        if (hook.rendererInterfaces && hook.rendererInterfaces.size) {
          var idx = 0;
          hook.rendererInterfaces.forEach(function (value, key) {
            if (idx >= 3) {
              return;
            }
            var hasOverride = value && typeof value.overrideProps === 'function';
            log(
              'live edit rendererInterface id=' +
                String(key) +
                ' override=' +
                String(hasOverride)
            );
            idx += 1;
          });
        }
        if (hook.renderers && hook.renderers.size) {
          var rIdx = 0;
          hook.renderers.forEach(function (value, key) {
            if (rIdx >= 3) {
              return;
            }
            var hasOverride = value && typeof value.overrideProps === 'function';
            log(
              'live edit renderer id=' + String(key) + ' override=' + String(hasOverride)
            );
            rIdx += 1;
          });
        } else if (hook.renderers && typeof hook.renderers === 'object') {
          var rKeys = Object.keys(hook.renderers);
          for (var r = 0; r < rKeys.length && r < 3; r++) {
            var val = hook.renderers[rKeys[r]];
            var hasOverride2 = val && typeof val.overrideProps === 'function';
            log(
              'live edit renderer key=' + String(rKeys[r]) + ' override=' + String(hasOverride2)
            );
          }
        }
      } catch (e) {
        log('live edit hook log error=' + (e && e.message ? e.message : 'unknown'));
      }
    }

    function applyOverrideProps(driver, fiber, mergedProps, nextProps) {
      if (!driver || !fiber || !mergedProps) {
        return false;
      }
      if (typeof driver.overrideProps !== 'function') {
        return false;
      }
      var applied = false;
      try {
        if (mergedProps.style != null) {
          driver.overrideProps(fiber, ['style'], mergedProps.style);
          applied = true;
        }
        var textValue = extractTextValue(nextProps);
        if (textValue != null) {
          driver.overrideProps(fiber, ['children'], textValue);
          applied = true;
        }
        for (var key in mergedProps) {
          if (!Object.prototype.hasOwnProperty.call(mergedProps, key)) {
            continue;
          }
          if (key === 'style') {
            continue;
          }
          driver.overrideProps(fiber, [key], mergedProps[key]);
          applied = true;
        }
      } catch (e) {
        if (DEBUG_LOGS) {
          log('live edit overrideProps error=' + (e && e.message ? e.message : 'unknown'));
        }
      }
      return applied;
    }

    function scheduleUpdateWithRenderer(renderer, fiber) {
      if (!renderer || typeof renderer.scheduleUpdateOnFiber !== 'function') {
        if (
          renderer &&
          typeof renderer.markUpdateLaneFromFiberToRoot === 'function' &&
          typeof renderer.ensureRootIsScheduled === 'function'
        ) {
          try {
            var lane = 0;
            if (typeof renderer.requestUpdateLane === 'function') {
              lane = renderer.requestUpdateLane(fiber);
            }
            var rootFromMark = renderer.markUpdateLaneFromFiberToRoot(fiber, lane);
            if (rootFromMark) {
              var eventTime = 0;
              if (typeof renderer.requestEventTime === 'function') {
                eventTime = renderer.requestEventTime();
              }
              renderer.ensureRootIsScheduled(rootFromMark, eventTime);
              return true;
            }
          } catch (e) {}
        }
        return false;
      }
      try {
        var root = findRootForFiber(fiber);
        var eventTime = 0;
        var lane = 0;
        if (typeof renderer.requestEventTime === 'function') {
          eventTime = renderer.requestEventTime();
        }
        if (typeof renderer.requestUpdateLane === 'function') {
          lane = renderer.requestUpdateLane(fiber);
        }
        try {
          if (root) {
            renderer.scheduleUpdateOnFiber(root, fiber, lane, eventTime);
            return true;
          }
        } catch (e) {}
        try {
          renderer.scheduleUpdateOnFiber(fiber, lane, eventTime);
          return true;
        } catch (e) {}
        try {
          renderer.scheduleUpdateOnFiber(fiber, lane);
          return true;
        } catch (e) {}
        try {
          renderer.scheduleUpdateOnFiber(fiber);
          return true;
        } catch (e) {}
      } catch (e) {}
      return false;
    }

    function forceUpdateFiber(fiber) {
      var current = fiber;
      while (current) {
        var updater = current.updater || (current.stateNode && current.stateNode.updater);
        if (updater && typeof updater.enqueueForceUpdate === 'function') {
          try {
            updater.enqueueForceUpdate(current);
            return true;
          } catch (e) {}
        }
        if (current.stateNode && typeof current.stateNode.forceUpdate === 'function') {
          try {
            current.stateNode.forceUpdate();
            return true;
          } catch (e) {}
        }
        for (var ri = 0; ri < renderers.length; ri++) {
          if (scheduleUpdateWithRenderer(renderers[ri], current)) {
            return true;
          }
        }
        current = current.return;
      }
      for (var rj = 0; rj < renderers.length; rj++) {
        if (scheduleUpdateWithRenderer(renderers[rj], fiber)) {
          return true;
        }
      }
      return false;
    }

    emitter.addListener('bloomInspectorLiveEdit', function (payload) {
      if (!payload) {
        return;
      }
      var debug = !!payload.debug;
      if (!debug && payload.props && payload.props.__bloomInspectorDebug) {
        debug = true;
      }
      if (debug) {
        DEBUG_LOGS = true;
      }
      var viewTagValue = payload.reactTag != null ? payload.reactTag : payload.viewTag;
      if (typeof viewTagValue === 'string') {
        var parsedTag = Number(viewTagValue);
        if (!isNaN(parsedTag)) {
          viewTagValue = parsedTag;
        }
      }
      var nextProps = payload.props != null ? payload.props : payload.nextProps != null ? payload.nextProps : payload;
      if (!nextProps || typeof nextProps !== 'object') {
        log('live edit missing props');
        return;
      }
      if (!renderers.length) {
        try {
          var latestRenderers = Array.from(hook.renderers.values());
          if (latestRenderers.length) {
            renderers = latestRenderers;
          }
        } catch (e) {}
      }
      var fiber = getCachedFiber(viewTagValue);
      if (!fiber) {
        fiber = tryFindFiberForTag(viewTagValue);
      }
      if (!fiber) {
        log('live edit fiber not found tag=' + String(viewTagValue));
        return;
      }
      var mergedProps = buildMergedProps(fiber, nextProps);
      var applied = applyPropsToFiber(fiber, mergedProps);
      var overrideApplied = false;
      var cachedRenderer = getCachedRenderer(viewTagValue);
      var overrideInfo = getOverrideDriver(cachedRenderer);
      if (!overrideInfo && hook) {
        bootstrapDevtoolsBackend(requireFn, hook, true);
        overrideInfo = getOverrideDriver(cachedRenderer);
      }
      var overrideDriver = overrideInfo ? overrideInfo.driver : null;
      var overrideSource = overrideInfo ? overrideInfo.source : 'none';
      if (overrideDriver && mergedProps) {
        overrideApplied = applyOverrideProps(overrideDriver, fiber, mergedProps, nextProps);
        if (!overrideApplied && fiber.return) {
          overrideApplied = applyOverrideProps(overrideDriver, fiber.return, mergedProps, nextProps);
        }
      }
      var updated = forceUpdateFiber(fiber);
      if (overrideApplied) {
        updated = true;
      }
      if (!overrideApplied) {
        logDevtoolsHookState('override-missing');
      }
      var textValue = extractTextValue(nextProps);
      var textApplied = false;
      if (!updated && textValue != null) {
        textApplied = applyTextViaStateNode(fiber, textValue);
      }
      var fallbackApplied = false;
      if (!updated && !textApplied && typeof g.__bloomInspectorApplyNativeProps === 'function') {
        try {
          fallbackApplied = !!g.__bloomInspectorApplyNativeProps(nextProps);
        } catch (e) {}
      }
      log(
        'live edit applied=' +
          String(applied) +
          ' override=' +
          String(overrideApplied) +
          ' overrideSource=' +
          String(overrideSource) +
          ' updated=' +
          String(updated) +
          ' text=' +
          String(textApplied) +
          ' fallback=' +
          String(fallbackApplied) +
          ' tag=' +
          String(viewTagValue)
      );
    });

    emitter.addListener('bloomInspectorTap', function (payload) {
      if (!payload) {
        return;
      }
      var viewTagValue = payload.viewTag;
      if (typeof viewTagValue === 'string') {
        var parsed = Number(viewTagValue);
        if (!isNaN(parsed)) {
          log('78 coerced viewTag from string to number');
          viewTagValue = parsed;
        }
      }
      if (!renderers.length) {
        try {
          var latestRenderers = Array.from(hook.renderers.values());
          if (latestRenderers.length) {
            renderers = latestRenderers;
            log('72 refreshed renderers count=' + renderers.length);
          } else if (Array.isArray(g.__bloomInspectorRenderers) && g.__bloomInspectorRenderers.length) {
            renderers = g.__bloomInspectorRenderers.slice();
            log('72 refreshed renderers from cache count=' + renderers.length);
          } else {
            log('69 no renderers available');
          }
        } catch (e) {
          log('69 no renderers available');
        }
      }
      var handled = false;
      var hadAnyData = false;
      var fiberHandled = false;
      var pendingViewData = null;
      var pendingTimer = null;
      var hostComponent = g.__bloomInspectorHostComponent;
      for (var i = 0; i < renderers.length; i++) {
        var renderer = renderers[i];
        if (!renderer || !renderer.rendererConfig) {
          continue;
        }
        var rendererName = renderer.rendererPackageName || 'unknown';
        var rendererVersion = renderer.reconcilerVersion || renderer.version || 'unknown';
        if (viewTagValue != null && typeof renderer.rendererConfig.getInspectorDataForViewTag === 'function') {
          var dataByTag = null;
          try {
            dataByTag = renderer.rendererConfig.getInspectorDataForViewTag(viewTagValue);
          } catch (e) {
            log('75 getInspectorDataForViewTag error=' + (e && e.message ? e.message : 'unknown'));
          }
          if (!dataByTag && payload.rootTag != null) {
            try {
              dataByTag = renderer.rendererConfig.getInspectorDataForViewTag(payload.rootTag);
              log('76 getInspectorDataForViewTag fallback rootTag=' + payload.rootTag);
            } catch (e) {
              log('75 getInspectorDataForViewTag(rootTag) error=' + (e && e.message ? e.message : 'unknown'));
            }
          }
          if (dataByTag && dataByTag.hierarchy && dataByTag.hierarchy.length) {
            var fiberFromDataByTag = getFiberFromViewData(dataByTag);
            if (fiberFromDataByTag && viewTagValue != null) {
              cacheFiberForTag(viewTagValue, fiberFromDataByTag, 'viewTag', renderer);
            }
            handled = true;
            hadAnyData = true;
            sendPayload(dataByTag, payload.touchID, viewTagValue);
            log('59 used getInspectorDataForViewTag');
            break;
          } else if (dataByTag) {
            hadAnyData = true;
          }
        }
        if (!handled && hostComponent && typeof renderer.rendererConfig.getInspectorDataForViewAtPoint === 'function') {
          try {
            renderer.rendererConfig.getInspectorDataForViewAtPoint(
              hostComponent,
              payload.x,
              payload.y,
              function (viewData) {
                if (handled || fiberHandled) {
                  return;
                }
                if (viewData && viewData.hierarchy && viewData.hierarchy.length) {
                  var publicInstanceForEdit = viewData.closestPublicInstance || viewData.publicInstance || null;
                  if (publicInstanceForEdit && typeof publicInstanceForEdit.setNativeProps === 'function') {
                    g.__bloomInspectorLastPublicInstance = publicInstanceForEdit;
                  } else if (
                    publicInstanceForEdit &&
                    (publicInstanceForEdit._nativeTag != null || publicInstanceForEdit.nativeTag != null)
                  ) {
                    g.__bloomInspectorLastPublicInstance = publicInstanceForEdit;
                  } else {
                    var instanceForEdit = viewData.closestInstance || viewData.inspected || null;
                    if (instanceForEdit && typeof instanceForEdit.setNativeProps === 'function') {
                      g.__bloomInspectorLastPublicInstance = instanceForEdit;
                    } else if (
                      instanceForEdit &&
                      (instanceForEdit._nativeTag != null || instanceForEdit.nativeTag != null)
                    ) {
                      g.__bloomInspectorLastPublicInstance = instanceForEdit;
                    } else if (
                      instanceForEdit &&
                      instanceForEdit.stateNode &&
                      typeof instanceForEdit.stateNode.setNativeProps === 'function'
                    ) {
                      g.__bloomInspectorLastPublicInstance = instanceForEdit.stateNode;
                    } else if (
                      instanceForEdit &&
                      instanceForEdit.stateNode &&
                      (instanceForEdit.stateNode._nativeTag != null ||
                        instanceForEdit.stateNode.nativeTag != null)
                    ) {
                      g.__bloomInspectorLastPublicInstance = instanceForEdit.stateNode;
                    }
                  }
                  var rawStack = viewData.componentStack;
                  var fiberFromViewData = getFiberFromViewData(viewData);
                  if (fiberFromViewData) {
                    if (viewTagValue != null) {
                      cacheFiberForTag(viewTagValue, fiberFromViewData, 'tap', renderer);
                    }
                    try {
                      var taggedInstance =
                        (viewData.closestPublicInstance &&
                          (viewData.closestPublicInstance._nativeTag != null
                            ? viewData.closestPublicInstance._nativeTag
                            : viewData.closestPublicInstance.nativeTag != null
                              ? viewData.closestPublicInstance.nativeTag
                              : null)) ||
                        (viewData.closestInstance &&
                          (viewData.closestInstance._nativeTag != null
                            ? viewData.closestInstance._nativeTag
                            : viewData.closestInstance.nativeTag != null
                              ? viewData.closestInstance.nativeTag
                              : null)) ||
                        null;
                      if (taggedInstance != null) {
                        cacheFiberForTag(taggedInstance, fiberFromViewData, 'viewData', renderer);
                      }
                    } catch (e) {}
                    var stackNames = buildComponentStackFromFiber(fiberFromViewData);
                    var nearestFiber = findNearestUserFiberWithSource(fiberFromViewData);
                    var fiberHierarchy = buildHierarchyFromFiber(fiberFromViewData);
                    var fiberStack = stackNames.length ? stackNames.join(' > ') : undefined;
                    var candidateSources = [];
                    var fiberSource = nearestFiber ? nearestFiber.codeInfo : getCodeInfoFromFiber(fiberFromViewData);
                    if (fiberSource) {
                      candidateSources.push(fiberSource);
                    }
                    var nearestPropsSource = getSourceFromProps(nearestFiber && nearestFiber.fiber ? nearestFiber.fiber.memoizedProps : null);
                    var fiberPropsSource = getSourceFromProps(fiberFromViewData.memoizedProps);
                    if (nearestPropsSource) {
                      candidateSources.push(nearestPropsSource);
                    }
                    if (fiberPropsSource) {
                      candidateSources.push(fiberPropsSource);
                    }
                    var current = fiberFromViewData;
                    var depth = 0;
                    while (current && depth < 30) {
                      var currentSource = getCodeInfoFromFiber(current);
                      if (currentSource) {
                        candidateSources.push(currentSource);
                      }
                      var currentPropsSource = getSourceFromProps(current.memoizedProps);
                      if (currentPropsSource) {
                        candidateSources.push(currentPropsSource);
                      }
                      if (current._debugOwner) {
                        var ownerSource = getCodeInfoFromFiber(current._debugOwner);
                        if (ownerSource) {
                          candidateSources.push(ownerSource);
                        }
                        var ownerPropsSource = getSourceFromProps(current._debugOwner.memoizedProps);
                        if (ownerPropsSource) {
                          candidateSources.push(ownerPropsSource);
                        }
                      }
                      current = current.return;
                      depth += 1;
                    }
                    if (!rawStack && fiberStack) {
                      viewData.componentStack = fiberStack;
                    }
                    if (candidateSources.length) {
                      var bestSource = candidateSources[0] || null;
                      var bestScore = scoreSource(bestSource ? bestSource.fileName : null);
                      for (var cs = 0; cs < candidateSources.length; cs++) {
                        var score = scoreSource(candidateSources[cs] ? candidateSources[cs].fileName : null);
                        if (score > bestScore) {
                          bestScore = score;
                          bestSource = candidateSources[cs];
                        }
                      }
                      if (bestSource) {
                        viewData.source = bestSource;
                      }
                    }
                    viewData.ownerSource = pickOwnerSource(candidateSources);
                    if (fiberHierarchy.length) {
                      viewData.hierarchy = fiberHierarchy;
                      viewData.selectedIndex = fiberHierarchy.length - 1;
                    }
                    if (nearestFiber && nearestFiber.fiber && nearestFiber.fiber.memoizedProps) {
                      viewData.props = nearestFiber.fiber.memoizedProps;
                    }
                    log('A: fiber from viewData');
                  }
                  if (!viewData.source) {
                    var stackSource = extractSourceFromComponentStack(rawStack || viewData.componentStack);
                    if (stackSource) {
                      viewData.source = stackSource;
                      log('A: source from componentStack');
                    }
                  }
                  var hasSource = !!viewData.source;
                  var stackParts = normalizeStackParts(viewData.componentStack);
                  var firstNonHost = null;
                  for (var sp = 0; sp < stackParts.length; sp++) {
                    if (!isHostComponentName(stackParts[sp])) {
                      firstNonHost = stackParts[sp];
                      break;
                    }
                  }
                  var hasReactStack = hasReactComponentStack(viewData.componentStack);
                  log('A: stack parts=' + stackParts.length +
                    ' firstNonHost=' + (firstNonHost || 'none') +
                    ' hasReactStack=' + String(!!hasReactStack) +
                    ' hasSource=' + String(!!hasSource));
                  if (hasReactStack || hasSource) {
                    handled = true;
                    hadAnyData = true;
                    sendPayload(viewData, payload.touchID, viewTagValue);
                    log('A: used getInspectorDataForViewAtPoint');
                    if (pendingTimer) {
                      clearTimeout(pendingTimer);
                    }
                    return;
                  }
                  hadAnyData = true;
                  pendingViewData = viewData;
                  if (!pendingTimer && typeof setTimeout === 'function') {
                    pendingTimer = setTimeout(function () {
                      if (!handled && !fiberHandled && pendingViewData) {
                        sendPayload(pendingViewData, payload.touchID, viewTagValue);
                        log('A: used getInspectorDataForViewAtPoint (fallback)');
                      }
                    }, 300);
                  }
                }
              }
            );
          } catch (e) {
            log('A: getInspectorDataForViewAtPoint error=' + (e && e.message ? e.message : 'unknown'));
          }
        } else if (!handled && !hostComponent) {
          log('A: no host component');
        }
        if (!handled && viewTagValue != null && typeof renderer.rendererConfig.getInspectorDataForInstance === 'function') {
          var instance = null;
          try {
            if (typeof renderer.findHostInstanceByNativeTag === 'function') {
              instance = renderer.findHostInstanceByNativeTag(viewTagValue);
            } else if (renderer.rendererConfig &&
              typeof renderer.rendererConfig.findHostInstanceByNativeTag === 'function') {
              instance = renderer.rendererConfig.findHostInstanceByNativeTag(viewTagValue);
            }
          } catch (e) {
            log('75 findHostInstanceByNativeTag error=' + (e && e.message ? e.message : 'unknown'));
          }
          if (instance) {
            try {
              var dataByInstance = renderer.rendererConfig.getInspectorDataForInstance(instance);
              if (dataByInstance && dataByInstance.hierarchy && dataByInstance.hierarchy.length) {
                handled = true;
                hadAnyData = true;
                sendPayload(dataByInstance, payload.touchID, viewTagValue);
                log('57 used getInspectorDataForInstance');
                break;
              } else if (dataByInstance) {
                hadAnyData = true;
              }
            } catch (e) {
              log('75 getInspectorDataForInstance error=' + (e && e.message ? e.message : 'unknown'));
            }
          } else {
            log('77 host instance not found for viewTag=' + viewTagValue);
          }
        }
        if (!handled && viewTagValue != null) {
          var fiber = null;
          if (hostComponent) {
            fiber = getFiberFromInstance(hostComponent);
            if (fiber) {
              log('B: fiber from host component');
            }
          }
          if (!fiber) {
            fiber = tryFiberLookup(viewTagValue, renderer);
          }
          if (fiber) {
            var stackNames = buildComponentStackFromFiber(fiber);
            var nearest = findNearestUserFiberWithSource(fiber);
            var hierarchy = buildHierarchyFromFiber(fiber);
            var candidateSources = [];
            var fiberSource = nearest ? nearest.codeInfo : (fiber._debugSource || null);
            if (fiberSource) {
              candidateSources.push(fiberSource);
            }
            var nearestPropsSource = getSourceFromProps(nearest && nearest.fiber ? nearest.fiber.memoizedProps : null);
            var fiberPropsSource = getSourceFromProps(fiber.memoizedProps);
            if (nearestPropsSource) {
              candidateSources.push(nearestPropsSource);
            }
            if (fiberPropsSource) {
              candidateSources.push(fiberPropsSource);
            }
            var current = fiber;
            var depth = 0;
            while (current && depth < 30) {
              var currentSource = getCodeInfoFromFiber(current);
              if (currentSource) {
                candidateSources.push(currentSource);
              }
              var currentPropsSource = getSourceFromProps(current.memoizedProps);
              if (currentPropsSource) {
                candidateSources.push(currentPropsSource);
              }
              if (current._debugOwner) {
                var ownerSource = getCodeInfoFromFiber(current._debugOwner);
                if (ownerSource) {
                  candidateSources.push(ownerSource);
                }
                var ownerPropsSource = getSourceFromProps(current._debugOwner.memoizedProps);
                if (ownerPropsSource) {
                  candidateSources.push(ownerPropsSource);
                }
              }
              current = current.return;
              depth += 1;
            }
            var bestSource = null;
            if (candidateSources.length) {
              bestSource = candidateSources[0] || null;
              var bestScore = scoreSource(bestSource ? bestSource.fileName : null);
              for (var cs = 0; cs < candidateSources.length; cs++) {
                var score = scoreSource(candidateSources[cs] ? candidateSources[cs].fileName : null);
                if (score > bestScore) {
                  bestScore = score;
                  bestSource = candidateSources[cs];
                }
              }
            }
            var fiberData = {
              hierarchy: hierarchy,
              selectedIndex: hierarchy.length ? hierarchy.length - 1 : 0,
              props: fiber.memoizedProps,
              source: bestSource,
              ownerSource: pickOwnerSource(candidateSources),
              componentStack: stackNames.length ? stackNames.join(' > ') : undefined,
              frame: payload.frame || null,
            };
            handled = true;
            fiberHandled = true;
            if (pendingTimer) {
              clearTimeout(pendingTimer);
            }
            hadAnyData = true;
            sendPayload(fiberData, payload.touchID, viewTagValue);
            log('B: used fiber lookup');
            break;
          } else {
            log('B: no fiber for viewTag=' + viewTagValue);
          }
        }
        if (!handled && !hadAnyData) {
          log('78 renderer no data name=' + rendererName + ' version=' + rendererVersion);
        }
      }
      if (!handled) {
        log('49 no JS payload for viewTag=' + viewTagValue);
      }
    });
    log('35 hook attached renderers=' + renderers.length);
    return true;
  }

  function attach() {
    return attachWithRequire();
  }
  if (!attach()) {
    if (g.setTimeout) {
      var attempts = 0;
      (function poll() {
        if (attach()) {
          return;
        }
        attempts += 1;
        if (attempts > 40) {
          log('54 attach timeout');
          return;
        }
        g.setTimeout(poll, 250);
      })();
    }
  }
})();
)JS";

static NSTimeInterval kBloomInspectorLastJSPickTime = 0;
static const NSTimeInterval kBloomInspectorFallbackDelaySeconds = 0.05;
static const NSTimeInterval kBloomInspectorSuppressWindowSeconds = 1.0;

// ------------------------------------------------------------
// Runtime delegate + RCTHost swizzle
// ------------------------------------------------------------

@interface EXBloomInspectorRuntimeDelegate : NSObject <RCTHostRuntimeDelegate>
@end

@implementation EXBloomInspectorRuntimeDelegate

- (void)host:(RCTHost *)host didInitializeRuntime:(facebook::jsi::Runtime &)runtime
{
  BLOOM_LOG(@"Bloom Log: 39 injecting JS runtime for host: %@", host);
  try {
    auto script = std::make_shared<facebook::jsi::StringBuffer>(kBloomInspectorInjectionScript);
    runtime.evaluateJavaScript(script, "BloomInspectorRuntime.js");
    BLOOM_LOG(@"Bloom Log: 44 runtime script evaluated");
    bool hasFlag = runtime.global().hasProperty(runtime, "__bloomInspectorRuntimeInstalled");
    BLOOM_LOG(@"Bloom Log: 50 runtime flag=%@", hasFlag ? @"YES" : @"NO");
    bool preludeFlag = runtime.global().hasProperty(runtime, "__bloomInspectorPreludeInstalled");
    BLOOM_LOG(@"Bloom Log: 52 prelude flag=%@", preludeFlag ? @"YES" : @"NO");
    NSString *hostId = [NSString stringWithFormat:@"%p", host];
    NSString *setHostIdScript =
        [NSString stringWithFormat:@"try{var g=globalThis||global||this;g.__bloomInspectorHostId='%@';}catch(e){}",
                                   hostId];
    runtime.evaluateJavaScript(std::make_shared<facebook::jsi::StringBuffer>(setHostIdScript.UTF8String),
                               "BloomInspectorRuntimeHostId.js");
    const char *pingScript =
        "try{var g=globalThis||global||this;var m=null;if(g.__turboModuleProxy){m=g.__turboModuleProxy('BloomInspectorOverlay');}"
        "if(!m&&g.NativeModules&&g.NativeModules.BloomInspectorOverlay){m=g.NativeModules.BloomInspectorOverlay;}"
        "if(m&&m.log){m.log('Bloom Log: 51 runtime log bridge ok');}}catch(e){}";
    runtime.evaluateJavaScript(std::make_shared<facebook::jsi::StringBuffer>(pingScript), "BloomInspectorRuntimePing.js");
  } catch (const std::exception &e) {
    BLOOM_LOG(@"Bloom Log: 44 runtime script failed: %s", e.what());
  }
}

@end

id<RCTHostRuntimeDelegate> EXGetBloomInspectorRuntimeDelegate(void)
{
  static EXBloomInspectorRuntimeDelegate *delegate;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    delegate = [EXBloomInspectorRuntimeDelegate new];
  });
  return delegate;
}

@interface RCTHost (EXBloomInspector)
@end

@implementation RCTHost (EXBloomInspector)

- (void)ex_bloomInspector_start
{
  id hostDelegate = nil;
  @try {
    hostDelegate = [self valueForKey:@"hostDelegate"];
  } @catch (__unused NSException *exception) {
    hostDelegate = nil;
  }
  if (!hostDelegate) {
    @try {
      hostDelegate = [self valueForKey:@"_hostDelegate"];
    } @catch (__unused NSException *exception) {
      hostDelegate = nil;
    }
  }

  NSString *delegateName = hostDelegate ? NSStringFromClass([hostDelegate class]) : @"<nil>";
  BOOL shouldAttach = [delegateName containsString:@"ExpoAppInstance"] || [delegateName containsString:@"ExpoGoReactNativeFactory"];
  if (!self.runtimeDelegate && shouldAttach) {
    self.runtimeDelegate = EXGetBloomInspectorRuntimeDelegate();
    BLOOM_LOG(@"Bloom Log: 48 runtime delegate attached via swizzle (delegate=%@)", delegateName);
  } else if (!self.runtimeDelegate) {
    BLOOM_LOG(@"Bloom Log: 48 runtime delegate skipped (delegate=%@)", delegateName);
  }

  [self ex_bloomInspector_start];
}

@end

__attribute__((constructor))
static void EXBloomInspectorSwizzleHostStart(void)
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Method original = class_getInstanceMethod([RCTHost class], @selector(start));
    Method swizzled = class_getInstanceMethod([RCTHost class], @selector(ex_bloomInspector_start));
    if (original && swizzled) {
      method_exchangeImplementations(original, swizzled);
    }
  });
}

// ------------------------------------------------------------
// Overlay view (hit-testing + selection)
// ------------------------------------------------------------

@interface EXBloomInspectorOverlayView : UIView
@property (nonatomic, strong) UIView *highlightView;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong, nullable) NSNumber *selectedViewTag;
@property (nonatomic, strong, nullable) NSArray<NSNumber *> *selectedViewTags;
@property (nonatomic, weak, nullable) UIView *selectedHitView;
- (void)resetSelection;
@end

@implementation EXBloomInspectorOverlayView

static EXBloomInspectorOverlay *EXGetBloomInspectorOverlayModule(void);
static EXBloomInspector *EXGetBloomInspectorModuleForVisibleApp(void);

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;

    _highlightView = [[UIView alloc] initWithFrame:CGRectZero];
    _highlightView.backgroundColor = [UIColor clearColor];
    _highlightView.layer.borderColor = [UIColor colorWithRed:0.98 green:0.43 blue:0.65 alpha:0.9].CGColor;
    _highlightView.layer.borderWidth = 2.0;
    _highlightView.hidden = YES;
    [self addSubview:_highlightView];

    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.hidden = YES;
    [self addSubview:_label];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTap:)];
    [self addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_handlePan:)];
    [self addGestureRecognizer:pan];
  }
  return self;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
  EXBloomInspectorOverlayManager *manager = [EXBloomInspectorOverlayManager sharedInstance];
  if (manager.hasPanelFrame) {
    CGPoint pointInWindow = [self convertPoint:point toView:nil];
    if (CGRectContainsPoint(manager.panelFrame, pointInWindow)) {
      return NO;
    }
  }
  return [super pointInside:point withEvent:event];
}

- (void)_handleTap:(UITapGestureRecognizer *)gesture
{
  CGPoint point = [gesture locationInView:self];
  BLOOM_LOG(@"Bloom Log: 9 tap %.1f %.1f", point.x, point.y);
  [self _inspectAtPoint:point];
}

- (void)_handlePan:(UIPanGestureRecognizer *)gesture
{
  CGPoint point = [gesture locationInView:self];
  BLOOM_LOG(@"Bloom Log: 10 pan %.1f %.1f", point.x, point.y);
  [self _inspectAtPoint:point];
}

- (UIView *)_visibleAppRootView
{
  EXKernelAppRecord *visibleApp = [EXKernel sharedInstance].visibleApp;
  return visibleApp ? [visibleApp.appManager rootView] : nil;
}

- (void)_inspectAtPoint:(CGPoint)point
{
  NSNumber *touchID = @((long long)(CFAbsoluteTimeGetCurrent() * 1000));
  UIView *rootView = [self _visibleAppRootView];
  UIWindow *rootWindow = rootView.window;
  if (!rootView || !rootWindow || !self.window) {
    BLOOM_LOG(@"Bloom Log: 11 missing rootView/window");
    _highlightView.hidden = YES;
    _label.hidden = YES;
    _selectedViewTag = nil;
    return;
  }

  CGPoint pointInRootWindow = [self.window convertPoint:point toWindow:rootWindow];
  CGPoint pointInRoot = [rootView convertPoint:pointInRootWindow fromView:rootWindow];

  UIView *hitView = [rootView hitTest:pointInRoot withEvent:nil];
  if (!hitView) {
    BLOOM_LOG(@"Bloom Log: 12 hitTest returned nil");
    _highlightView.hidden = YES;
    _label.hidden = YES;
    _selectedViewTag = nil;
    return;
  }
  BLOOM_LOG(@"Bloom Log: 13 hitView=%@", NSStringFromClass([hitView class]));
  _selectedHitView = hitView;

  NSNumber *viewTag = nil;
  EXBloomInspector *inspectorModule = EXGetBloomInspectorModuleForVisibleApp();
  if (inspectorModule) {
    UIView *taggedView = hitView;
    NSMutableArray<NSNumber *> *tags = [NSMutableArray array];
    NSUInteger tagDepth = 0;
    while (taggedView) {
      NSNumber *candidateTag = taggedView.reactTag;
      if (!candidateTag && taggedView.tag > 0) {
        candidateTag = @(taggedView.tag);
      }
      if (candidateTag) {
        if (!viewTag) {
          viewTag = candidateTag;
        }
        if (![tags containsObject:candidateTag]) {
          [tags addObject:candidateTag];
        }
      }
      taggedView = taggedView.superview;
      tagDepth += 1;
      if (tagDepth > 20) {
        break;
      }
    }
    _selectedViewTags = tags.count ? [tags copy] : nil;
    NSNumber *rootTag = nil;
    if ([rootView respondsToSelector:@selector(reactTag)]) {
      rootTag = rootView.reactTag;
    }
    if (viewTag) {
      BLOOM_LOG(@"Bloom Log: 14 emitTap viewTag=%@", viewTag);
      _selectedViewTag = viewTag;
    } else {
      BLOOM_LOG(@"Bloom Log: 14 emitTap viewTag=<nil>");
      _selectedViewTag = nil;
    }
    NSMutableDictionary *payload = [@{
      @"x": @(pointInRootWindow.x),
      @"y": @(pointInRootWindow.y),
      @"touchID": touchID,
    } mutableCopy];
    if (rootTag) {
      payload[@"rootTag"] = rootTag;
    }
    if (viewTag) {
      payload[@"viewTag"] = viewTag;
    }
    [inspectorModule emitTap:payload];
  } else {
    BLOOM_LOG(@"Bloom Log: 14 emitTap skipped (no module)");
  }

  // JS-side listener is attached via NativeEventEmitter on BloomInspector.

  BOOL inspectorAvailable = [self _emitReactInspectorDataForPoint:pointInRoot hitView:hitView touchID:touchID];
  BLOOM_LOG(@"Bloom Log: 15 inspectorAvailable=%@", inspectorAvailable ? @"YES" : @"NO");

  CGRect rectInRootWindow = [hitView convertRect:hitView.bounds toView:rootWindow];
  CGRect rectInOverlayWindow = [self.window convertRect:rectInRootWindow fromWindow:rootWindow];
  CGRect rectInOverlay = [self convertRect:rectInOverlayWindow fromView:self.window];

  _highlightView.frame = rectInOverlay;
  _highlightView.hidden = NO;

  NSMutableArray<NSString *> *names = [NSMutableArray array];
  UIView *current = hitView;
  NSUInteger depth = 0;
  while (current && depth < 10) {
    [names addObject:NSStringFromClass([current class])];
    if (current == rootView) {
      break;
    }
    current = current.superview;
    depth += 1;
  }

  if (!inspectorAvailable && kBloomInspectorEnableNativeFallback) {
    NSMutableArray<NSDictionary *> *hierarchy = [NSMutableArray arrayWithCapacity:names.count];
    for (NSString *name in names) {
      [hierarchy addObject:@{ @"name": name }];
    }

    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    props[@"nativeClass"] = NSStringFromClass([hitView class]);
    if (hitView.accessibilityLabel) {
      props[@"accessibilityLabel"] = hitView.accessibilityLabel;
    }
    if (hitView.accessibilityIdentifier) {
      props[@"accessibilityIdentifier"] = hitView.accessibilityIdentifier;
    }
    if ([hitView respondsToSelector:@selector(reactTag)] && hitView.reactTag) {
      props[@"reactTag"] = hitView.reactTag;
    }
    props[@"alpha"] = @(hitView.alpha);
    props[@"hidden"] = @(hitView.hidden);
    props[@"userInteractionEnabled"] = @(hitView.userInteractionEnabled);

    if ([hitView isKindOfClass:[UILabel class]]) {
      UILabel *label = (UILabel *)hitView;
      if (label.text) {
        props[@"text"] = label.text;
      }
    } else if ([hitView isKindOfClass:[UIButton class]]) {
      UIButton *button = (UIButton *)hitView;
      NSString *title = [button titleForState:UIControlStateNormal];
      if (title) {
        props[@"title"] = title;
      }
    } else {
      UIView *textView = EXBloomInspectorFindTextView(hitView);
      if (textView) {
        NSAttributedString *attributedText = nil;
        @try {
          if ([textView respondsToSelector:@selector(attributedText)]) {
            attributedText = [textView valueForKey:@"attributedText"];
          }
        } @catch (NSException *exception) {
        }
        if (attributedText && [attributedText isKindOfClass:[NSAttributedString class]]) {
          NSString *stringValue = attributedText.string;
          if (stringValue.length) {
            props[@"text"] = stringValue;
          }
        } else {
          NSString *plainText = nil;
          @try {
            if ([textView respondsToSelector:@selector(text)]) {
              plainText = [textView valueForKey:@"text"];
            }
          } @catch (NSException *exception) {
          }
          if (plainText.length) {
            props[@"text"] = plainText;
          }
        }
      }
    }

    NSDictionary *payload = @{
      @"payloadSource": @"native",
      @"touchID": touchID,
      @"viewTag": viewTag ?: [NSNull null],
      @"frame": @{
        @"left": @(CGRectGetMinX(rectInRootWindow)),
        @"top": @(CGRectGetMinY(rectInRootWindow)),
        @"width": @(CGRectGetWidth(rectInRootWindow)),
        @"height": @(CGRectGetHeight(rectInRootWindow)),
      },
      @"hierarchy": hierarchy,
      @"props": props,
      @"selectedIndex": @((NSInteger)names.count - 1),
      @"componentStack": [names componentsJoinedByString:@" > "],
    };

    BLOOM_LOG(@"Bloom Log: 16 scheduling fallback native payload");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBloomInspectorFallbackDelaySeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      NSTimeInterval delta = CFAbsoluteTimeGetCurrent() - kBloomInspectorLastJSPickTime;
      if (delta < kBloomInspectorSuppressWindowSeconds) {
        BLOOM_LOG(@"Bloom Log: 16 fallback native payload suppressed (recent JS pick)");
        return;
      }
      EXBloomInspectorOverlay *module = EXGetBloomInspectorOverlayModule();
      if (module) {
        [module emitPick:payload];
      } else {
        BLOOM_LOG(@"Bloom Log: 16 fallback emitPick skipped (no module)");
      }
    });
  }
}

- (BOOL)_emitReactInspectorDataForPoint:(CGPoint)pointInRoot hitView:(UIView *)hitView touchID:(NSNumber *)touchID
{
  EXKernelAppRecord *visibleApp = [EXKernel sharedInstance].visibleApp;
  id host = visibleApp.appManager.reactHost;
  if (!host || ![host respondsToSelector:@selector(moduleRegistry)]) {
    BLOOM_LOG(@"Bloom Log: 17 no react host/moduleRegistry");
    return NO;
  }
  id moduleRegistry = [host moduleRegistry];
  id uiManager = [moduleRegistry moduleForName:"UIManager"];
  if (!uiManager) {
    uiManager = [moduleRegistry moduleForName:"RCTUIManager"];
  }
  if (!uiManager) {
    BLOOM_LOG(@"Bloom Log: 18 UIManager not found");
    return NO;
  }
  BLOOM_LOG(@"Bloom Log: 19 UIManager=%@", NSStringFromClass([uiManager class]));

  SEL selector = NSSelectorFromString(@"getInspectorDataForViewAtPoint:callback:");
  if ([uiManager respondsToSelector:selector]) {
    BLOOM_LOG(@"Bloom Log: 20 calling getInspectorDataForViewAtPoint");
    NSMethodSignature *signature = [uiManager methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments < 4) {
      BLOOM_LOG(@"Bloom Log: 21 invalid signature for getInspectorDataForViewAtPoint");
      return NO;
    }

    void (^callback)(id) = ^(id result) {
      NSDictionary *payload = nil;
      BLOOM_LOG(@"Bloom Log: 22 inspector raw=%@", result);
      if ([result isKindOfClass:[NSArray class]] && [(NSArray *)result count] > 0) {
        id first = [(NSArray *)result firstObject];
        if ([first isKindOfClass:[NSDictionary class]]) {
          payload = (NSDictionary *)first;
        }
      } else if ([result isKindOfClass:[NSDictionary class]]) {
        payload = (NSDictionary *)result;
      }

      if (payload) {
        NSMutableDictionary *mutablePayload = [payload mutableCopy];
        mutablePayload[@"payloadSource"] = @"native";
        if (touchID) {
          mutablePayload[@"touchID"] = touchID;
        }
        EXBloomInspectorOverlay *module = EXGetBloomInspectorOverlayModule();
        if (module) {
          [module emitPick:mutablePayload];
        } else {
          BLOOM_LOG(@"Bloom Log: 23 emitPick skipped (no overlay module)");
        }
      }
    };

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setSelector:selector];
    [invocation setTarget:uiManager];
    CGPoint pointCopy = pointInRoot;
    [invocation setArgument:&pointCopy atIndex:2];
    id callbackCopy = [callback copy];
    [invocation setArgument:&callbackCopy atIndex:3];
    [invocation invoke];
    BLOOM_LOG(@"Bloom Log: 24 invoked getInspectorDataForViewAtPoint");
    return YES;
  }

  SEL tagSelector = NSSelectorFromString(@"getInspectorDataForViewTag:callback:");
  if ([uiManager respondsToSelector:tagSelector] && [hitView respondsToSelector:@selector(reactTag)]) {
    NSNumber *tag = hitView.reactTag;
    if (!tag) {
      BLOOM_LOG(@"Bloom Log: 25 viewTag missing");
      return NO;
    }

    BLOOM_LOG(@"Bloom Log: 26 calling getInspectorDataForViewTag tag=%@", tag);
    NSMethodSignature *signature = [uiManager methodSignatureForSelector:tagSelector];
    if (!signature || signature.numberOfArguments < 4) {
      BLOOM_LOG(@"Bloom Log: 27 invalid signature for getInspectorDataForViewTag");
      return NO;
    }

    void (^callback)(id) = ^(id result) {
      NSDictionary *payload = nil;
      BLOOM_LOG(@"Bloom Log: 28 inspector raw=%@", result);
      if ([result isKindOfClass:[NSArray class]] && [(NSArray *)result count] > 0) {
        id first = [(NSArray *)result firstObject];
        if ([first isKindOfClass:[NSDictionary class]]) {
          payload = (NSDictionary *)first;
        }
      } else if ([result isKindOfClass:[NSDictionary class]]) {
        payload = (NSDictionary *)result;
      }

      if (payload) {
        EXBloomInspectorOverlay *module = EXGetBloomInspectorOverlayModule();
        if (module) {
          [module emitPick:payload];
        } else {
          BLOOM_LOG(@"Bloom Log: 29 emitPick skipped (no overlay module)");
        }
      }
    };

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setSelector:tagSelector];
    [invocation setTarget:uiManager];
    NSNumber *tagCopy = tag;
    [invocation setArgument:&tagCopy atIndex:2];
    id callbackCopy = [callback copy];
    [invocation setArgument:&callbackCopy atIndex:3];
    [invocation invoke];
    BLOOM_LOG(@"Bloom Log: 30 invoked getInspectorDataForViewTag");
    return YES;
  }

  BLOOM_LOG(@"Bloom Log: 31 UIManager missing inspector selectors");
  return NO;
}

- (void)resetSelection
{
  _highlightView.hidden = YES;
  _label.hidden = YES;
  _highlightView.frame = CGRectZero;
  _selectedViewTag = nil;
  _selectedViewTags = nil;
  _selectedHitView = nil;
}

@end

// ------------------------------------------------------------
// Overlay view controller (React panel + overlay view)
// ------------------------------------------------------------

@interface EXBloomInspectorOverlayViewController : UIViewController
@property (nonatomic, strong) EXBloomInspectorOverlayView *overlayView;
@property (nonatomic, strong) UIView *reactRootView;
@end

@implementation EXBloomInspectorOverlayViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor clearColor];
  RCTReactNativeFactory *reactNativeFactory = [[EXDevMenuManager sharedInstance] mainAppFactory];
  if (reactNativeFactory) {
    _reactRootView = [reactNativeFactory.rootViewFactory viewWithModuleName:@"BloomInspectorOverlay"
                                                         initialProperties:@{}];
    _reactRootView.backgroundColor = [UIColor clearColor];
    _reactRootView.frame = self.view.bounds;
    _reactRootView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_reactRootView];
  }

  _overlayView = [[EXBloomInspectorOverlayView alloc] initWithFrame:self.view.bounds];
  _overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:_overlayView];
}

@end

// ------------------------------------------------------------
// Overlay manager (window lifecycle)
// ------------------------------------------------------------

@implementation EXBloomInspectorOverlayManager
static EXBloomInspectorOverlay *EXGetBloomInspectorOverlayModule(void)
{
  id host = [[EXDevMenuManager sharedInstance] mainReactHost];
  if (!host || ![host respondsToSelector:@selector(moduleRegistry)]) {
    return nil;
  }
  id module = [[host moduleRegistry] moduleForName:"BloomInspectorOverlay"];
  if ([module isKindOfClass:[EXBloomInspectorOverlay class]]) {
    return (EXBloomInspectorOverlay *)module;
  }
  return nil;
}

BOOL EXBloomInspectorEmitPing(NSDictionary *payload)
{
  EXBloomInspectorOverlay *module = EXGetBloomInspectorOverlayModule();
  if (!module) {
    return NO;
  }
  [module emitPing:payload ?: @{}];
  return YES;
}

static EXBloomInspector *EXGetBloomInspectorModuleForVisibleApp(void)
{
  EXKernelAppRecord *visibleApp = [EXKernel sharedInstance].visibleApp;
  id host = visibleApp.appManager.reactHost;
  if (!host || ![host respondsToSelector:@selector(moduleRegistry)]) {
    return nil;
  }
  id module = [[host moduleRegistry] moduleForName:"BloomInspector"];
  if ([module isKindOfClass:[EXBloomInspector class]]) {
    return (EXBloomInspector *)module;
  }
  return nil;
}

+ (instancetype)sharedInstance
{
  static EXBloomInspectorOverlayManager *manager;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    manager = [[EXBloomInspectorOverlayManager alloc] init];
  });
  return manager;
}

- (void)toggle
{
  if (self.isVisible) {
    [self hide];
  } else {
    [self show];
  }
}

- (void)show
{
  if (self.isVisible) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.window) {
      self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
      self.window.windowLevel = UIWindowLevelStatusBar - 1;
      self.window.backgroundColor = [UIColor clearColor];
      self.window.rootViewController = [EXBloomInspectorOverlayViewController new];
      self.viewController = (EXBloomInspectorOverlayViewController *)self.window.rootViewController;
    }
    if (@available(iOS 13.0, *)) {
      for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:[UIWindowScene class]]) {
          UIWindowScene *windowScene = (UIWindowScene *)scene;
          for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) {
              self.previousKeyWindow = window;
              break;
            }
          }
        }
        if (self.previousKeyWindow) {
          break;
        }
      }
    } else {
      self.previousKeyWindow = [UIApplication sharedApplication].keyWindow;
    }
    self.window.hidden = NO;
    [self.window makeKeyAndVisible];
    self.visible = YES;
    self.hasPanelFrame = NO;
    [self.viewController.overlayView resetSelection];
    EXBloomInspectorOverlay *module = EXGetBloomInspectorOverlayModule();
    if (module) {
      [module emitToggle:YES];
    }
  });
}

- (void)hide
{
  if (!self.isVisible) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.viewController.overlayView resetSelection];
    self.window.hidden = YES;
    [self.previousKeyWindow makeKeyWindow];
    self.visible = NO;
    self.hasPanelFrame = NO;
    EXBloomInspectorOverlay *module = EXGetBloomInspectorOverlayModule();
    if (module) {
      [module emitToggle:NO];
    }
  });
}

@end

// ------------------------------------------------------------
// BloomInspector module (tap events)
// ------------------------------------------------------------

@interface EXBloomInspector () {
  BOOL _hasListeners;
}
@end

@implementation EXBloomInspector

RCT_EXPORT_MODULE(BloomInspector)

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"bloomInspectorToggle", @"bloomInspectorTap", @"bloomInspectorLiveEdit"];
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

- (void)startObserving
{
  _hasListeners = YES;
}

- (void)stopObserving
{
  _hasListeners = NO;
}

- (void)emitToggle
{
  if (_hasListeners) {
    [self sendEventWithName:@"bloomInspectorToggle" body:@{}];
  }
}

- (void)emitTap:(NSDictionary *)payload
{
  if (_hasListeners) {
    [self sendEventWithName:@"bloomInspectorTap" body:payload];
  }
}

- (void)emitLiveEdit:(NSDictionary *)payload
{
  if (_hasListeners) {
    [self sendEventWithName:@"bloomInspectorLiveEdit" body:payload];
  }
}

RCT_EXPORT_METHOD(sendPick:(NSDictionary *)payload)
{
  EXBloomInspectorOverlay *module = EXGetBloomInspectorOverlayModule();
  if (!module) {
    BLOOM_LOG(@"Bloom Log: 95 sendPick forwarder missing overlay module");
    return;
  }
  BLOOM_LOG(@"Bloom Log: 95 sendPick forwarder emitPick");
  [module emitPick:payload];
}

@end

// ------------------------------------------------------------
// BloomInspectorOverlay module (panel events + commands)
// ------------------------------------------------------------

@interface EXBloomInspectorOverlay () {
  BOOL _hasListeners;
}
- (void)emitPing:(NSDictionary *)payload;
@end

@implementation EXBloomInspectorOverlay

RCT_EXPORT_MODULE(BloomInspectorOverlay)

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"bloomInspectorOverlayPick", @"bloomInspectorOverlayToggle", @"bloomInspectorOverlayPing"];
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

- (void)startObserving
{
  _hasListeners = YES;
}

- (void)stopObserving
{
  _hasListeners = NO;
}

RCT_EXPORT_METHOD(toggle)
{
  [[EXBloomInspectorOverlayManager sharedInstance] toggle];
}

RCT_EXPORT_METHOD(clearSelection)
{
  [[[EXBloomInspectorOverlayManager sharedInstance] viewController].overlayView resetSelection];
}

RCT_EXPORT_METHOD(setPanelFrame:(NSDictionary *)frame)
{
  NSNumber *x = frame[@"x"];
  NSNumber *y = frame[@"y"];
  NSNumber *width = frame[@"width"];
  NSNumber *height = frame[@"height"];
  if (!x || !y || !width || !height) {
    return;
  }
  EXBloomInspectorOverlayManager *manager = [EXBloomInspectorOverlayManager sharedInstance];
  manager.panelFrame = CGRectMake(x.doubleValue, y.doubleValue, width.doubleValue, height.doubleValue);
  manager.hasPanelFrame = YES;
}

RCT_REMAP_METHOD(getEnabledAsync,
                 getEnabledWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  resolve(@([EXBloomInspectorOverlayManager sharedInstance].isVisible));
}

RCT_REMAP_METHOD(getLiveEditTargetInfoAsync,
                 getLiveEditTargetInfoWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  EXKernelAppRecord *visibleApp = [EXKernel sharedInstance].visibleApp;
  id host = visibleApp.appManager.reactHost;
  if (!host || ![host respondsToSelector:@selector(moduleRegistry)]) {
    resolve(@{@"hasTarget": @NO, @"reason": @"no-host"});
    return;
  }
  EXBloomInspectorOverlayView *overlayView =
      [[EXBloomInspectorOverlayManager sharedInstance] viewController].overlayView;
  NSArray<NSNumber *> *availableTags = overlayView.selectedViewTags ?: @[];
  NSNumber *reactTag = overlayView.selectedViewTag ?: (availableTags.count ? availableTags[0] : nil);
  if (!reactTag) {
    UIView *hitView = overlayView.selectedHitView;
    if (hitView) {
      NSString *hitText = EXBloomInspectorGetPlainTextFromView(hitView);
      resolve(@{
        @"hasTarget": @YES,
        @"reason": @"no-reactTag-uikit",
        @"mode": @"uikit",
        @"availableTags": availableTags,
        @"componentViewClass": NSStringFromClass([hitView class]),
        @"text": hitText ?: [NSNull null],
      });
    } else {
      resolve(@{@"hasTarget": @NO, @"reason": @"no-reactTag", @"availableTags": availableTags});
    }
    return;
  }
  id moduleRegistry = [host moduleRegistry];
  RCTUIManager *uiManager = [moduleRegistry moduleForName:"UIManager"];
  if (!uiManager) {
    uiManager = [moduleRegistry moduleForName:"RCTUIManager"];
  }
  if (!uiManager) {
    resolve(@{
      @"hasTarget": @YES,
      @"reactTag": reactTag,
      @"reason": @"no-uiManager",
      @"availableTags": availableTags,
    });
    return;
  }

  // RCTUIManager asserts if `viewNameForReactTag:` is called off the UIManager queue.
  dispatch_queue_t uiQueue = [uiManager methodQueue];
  if (!uiQueue) {
    resolve(@{
      @"hasTarget": @YES,
      @"reactTag": reactTag,
      @"reason": @"no-uiManager-queue",
      @"availableTags": availableTags,
    });
    return;
  }
  dispatch_async(uiQueue, ^{
    NSString *viewName = nil;
    if ([uiManager respondsToSelector:@selector(viewNameForReactTag:)]) {
      viewName = [uiManager viewNameForReactTag:reactTag];
    }
    BOOL hasSurfacePresenter = NO;
    @try {
      id presenter = [host valueForKey:@"surfacePresenter"];
      hasSurfacePresenter =
          presenter && [presenter respondsToSelector:@selector(synchronouslyUpdateViewOnUIThread:props:)];
    } @catch (__unused NSException *exception) {
      hasSurfacePresenter = NO;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      BOOL fabricViewExists = NO;
      NSString *fabricViewClass = nil;
      NSDictionary *fabricViewFrame = nil;
      NSDictionary *fabricViewBounds = nil;
      NSNumber *fabricViewAlpha = nil;
      NSNumber *fabricViewHidden = nil;
      id fabricViewBackground = [NSNull null];
      NSString *fabricViewText = nil;
      if (hasSurfacePresenter) {
        @try {
          id presenter = [host valueForKey:@"surfacePresenter"];
          if (presenter &&
              [presenter respondsToSelector:@selector(findComponentViewWithTag_DO_NOT_USE_DEPRECATED:)]) {
            UIView *view = [(RCTSurfacePresenter *)presenter
                findComponentViewWithTag_DO_NOT_USE_DEPRECATED:reactTag.integerValue];
            fabricViewExists = (view != nil);
            fabricViewClass = view ? NSStringFromClass([view class]) : nil;
            if (view) {
              fabricViewFrame = EXBloomInspectorRectInfo(view.frame);
              fabricViewBounds = EXBloomInspectorRectInfo(view.bounds);
              fabricViewAlpha = @(view.alpha);
              fabricViewHidden = @(view.hidden);
              fabricViewBackground = EXBloomInspectorColorToString(view.backgroundColor) ?: [NSNull null];
              fabricViewText = EXBloomInspectorGetPlainTextFromView(view);
            }
          }
        } @catch (__unused NSException *exception) {
          fabricViewExists = NO;
        }
      }

      if (viewName) {
        resolve(@{
          @"hasTarget": @YES,
          @"reactTag": reactTag,
          @"viewName": viewName,
          @"mode": @"native",
          @"text": fabricViewText ?: [NSNull null],
          @"availableTags": availableTags,
        });
      } else {
        resolve(@{
          @"hasTarget": @YES,
          @"reactTag": reactTag,
          @"mode": hasSurfacePresenter ? @"fabric" : @"native",
          @"reason": hasSurfacePresenter
              ? (fabricViewExists ? @"viewName-missing-fallback-fabric" : @"fabric-view-missing")
              : @"viewName-missing",
          @"componentViewClass": fabricViewClass ?: [NSNull null],
          @"componentViewFrame": fabricViewFrame ?: [NSNull null],
          @"componentViewBounds": fabricViewBounds ?: [NSNull null],
          @"componentViewHidden": fabricViewHidden ?: [NSNull null],
          @"componentViewAlpha": fabricViewAlpha ?: [NSNull null],
          @"componentViewBackgroundColor": fabricViewBackground ?: [NSNull null],
          @"text": fabricViewText ?: [NSNull null],
          @"availableTags": availableTags,
        });
      }
    });
  });
}

static void EXBloomInspectorApplyNativePropsToReactTag(
    id host,
    NSNumber *reactTag,
    NSDictionary *props,
    RCTPromiseResolveBlock resolve)
{
  if (!host || ![host respondsToSelector:@selector(moduleRegistry)] || !reactTag) {
    resolve(@{@"ok": @NO, @"reason": @"invalid-args"});
    return;
  }

  BOOL forceUIKit = NO;
  NSDictionary *effectiveProps = props;
  id forceUIKitValue = props[@"__bloomInspectorForceUIKit"];
  if ([forceUIKitValue respondsToSelector:@selector(boolValue)]) {
    forceUIKit = [forceUIKitValue boolValue];
  }
  if (forceUIKit) {
    NSMutableDictionary *mutableProps = [props mutableCopy];
    [mutableProps removeObjectForKey:@"__bloomInspectorForceUIKit"];
    effectiveProps = [mutableProps copy];
    @try {
      id presenter = [host valueForKey:@"surfacePresenter"];
      if (presenter &&
          [presenter respondsToSelector:@selector(findComponentViewWithTag_DO_NOT_USE_DEPRECATED:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          UIView *view = [(RCTSurfacePresenter *)presenter
              findComponentViewWithTag_DO_NOT_USE_DEPRECATED:reactTag.integerValue];
          if (view) {
            EXBloomInspectorApplyUIKitStyleToView(view, effectiveProps, resolve);
          } else {
            EXBloomInspectorOverlayView *overlayView =
                [[EXBloomInspectorOverlayManager sharedInstance] viewController].overlayView;
            UIView *fallbackView = overlayView.selectedHitView;
            if (fallbackView) {
              EXBloomInspectorApplyUIKitStyleToView(fallbackView, effectiveProps, resolve);
            } else {
              resolve(@{
                @"ok": @NO,
                @"mode": @"uikit",
                @"reason": @"forceUIKit-no-view",
                @"reactTag": reactTag,
              });
            }
          }
        });
        return;
      }
    } @catch (__unused NSException *exception) {
      // ignore
    }
  }

  // Fabric path (no viewName needed): `RCTSurfacePresenter synchronouslyUpdateViewOnUIThread:props:`
  @try {
    id presenter = [host valueForKey:@"surfacePresenter"];
    if (presenter && [presenter respondsToSelector:@selector(synchronouslyUpdateViewOnUIThread:props:)]) {
      dispatch_async(dispatch_get_main_queue(), ^{
        UIView *view = nil;
        if ([presenter respondsToSelector:@selector(findComponentViewWithTag_DO_NOT_USE_DEPRECATED:)]) {
          view = [(RCTSurfacePresenter *)presenter
              findComponentViewWithTag_DO_NOT_USE_DEPRECATED:reactTag.integerValue];
        }
        if (!view) {
          resolve(@{
            @"ok": @NO,
            @"reactTag": reactTag,
            @"mode": @"fabric",
            @"reason": @"fabric-view-missing",
          });
          return;
        }
        [(RCTSurfacePresenter *)presenter synchronouslyUpdateViewOnUIThread:reactTag
                                                                     props:effectiveProps];
        NSDictionary *style = [effectiveProps isKindOfClass:[NSDictionary class]]
          ? (NSDictionary *)effectiveProps[@"style"]
          : nil;
        if (![style isKindOfClass:[NSDictionary class]]) {
          style = nil;
        }
        if (style) {
          EXBloomInspectorApplyTextStyleToView(view, style);
        }
        NSString *textOverride = EXBloomInspectorExtractTextOverride(effectiveProps);
        if (textOverride) {
          EXBloomInspectorApplyTextOverrideToView(view, textOverride);
        }
        resolve(@{
          @"ok": @YES,
          @"reactTag": reactTag,
          @"mode": @"fabric",
          @"componentViewClass": NSStringFromClass([view class]),
          @"componentViewFrame": EXBloomInspectorRectInfo(view.frame),
          @"componentViewBounds": EXBloomInspectorRectInfo(view.bounds),
          @"componentViewHidden": @(view.hidden),
          @"componentViewAlpha": @(view.alpha),
          @"componentViewBackgroundColor": EXBloomInspectorColorToString(view.backgroundColor) ?: [NSNull null],
        });
      });
      return;
    }
  } @catch (__unused NSException *exception) {
    // ignore
  }

  id moduleRegistry = [host moduleRegistry];
  RCTUIManager *uiManager = [moduleRegistry moduleForName:"UIManager"];
  if (!uiManager) {
    uiManager = [moduleRegistry moduleForName:"RCTUIManager"];
  }
  if (!uiManager) {
    resolve(@{@"ok": @NO, @"reason": @"no-uiManager", @"reactTag": reactTag});
    return;
  }

  dispatch_queue_t uiQueue = [uiManager methodQueue];
  if (!uiQueue) {
    resolve(@{@"ok": @NO, @"reason": @"no-uiManager-queue", @"reactTag": reactTag});
    return;
  }

  dispatch_async(uiQueue, ^{
    if (forceUIKit && [uiManager respondsToSelector:@selector(viewForReactTag:)]) {
      UIView *view = [uiManager viewForReactTag:reactTag];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (view) {
          EXBloomInspectorApplyUIKitStyleToView(view, effectiveProps, resolve);
        } else {
          EXBloomInspectorOverlayView *overlayView =
              [[EXBloomInspectorOverlayManager sharedInstance] viewController].overlayView;
          UIView *fallbackView = overlayView.selectedHitView;
          if (fallbackView) {
            EXBloomInspectorApplyUIKitStyleToView(fallbackView, effectiveProps, resolve);
          } else {
            resolve(@{
              @"ok": @NO,
              @"mode": @"uikit",
              @"reason": @"forceUIKit-no-view",
              @"reactTag": reactTag,
            });
          }
        }
      });
      return;
    }
    if (![uiManager respondsToSelector:@selector(viewNameForReactTag:)] ||
        ![uiManager respondsToSelector:@selector(synchronouslyUpdateViewOnUIThread:viewName:props:)]) {
      dispatch_async(dispatch_get_main_queue(), ^{
        resolve(@{@"ok": @NO, @"reason": @"missing-selectors", @"reactTag": reactTag});
      });
      return;
    }

    NSString *viewName = [uiManager viewNameForReactTag:reactTag];
    if (!viewName) {
      dispatch_async(dispatch_get_main_queue(), ^{
        resolve(@{@"ok": @NO, @"reason": @"viewName-missing", @"reactTag": reactTag});
      });
      return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      [uiManager synchronouslyUpdateViewOnUIThread:reactTag viewName:viewName props:effectiveProps];
      resolve(@{@"ok": @YES, @"reactTag": reactTag, @"viewName": viewName, @"mode": @"native"});
    });
  });
}

static UIColor *EXBloomInspectorColorFromString(NSString *value)
{
  if (!value || ![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *lower = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
  if ([lower hasPrefix:@"#"]) {
    NSString *hex = [lower substringFromIndex:1];
    unsigned int a = 255, r = 0, g = 0, b = 0;
    if (hex.length == 6) {
      NSScanner *scanner = [NSScanner scannerWithString:hex];
      unsigned int rgb = 0;
      if (![scanner scanHexInt:&rgb]) {
        return nil;
      }
      r = (rgb >> 16) & 0xFF;
      g = (rgb >> 8) & 0xFF;
      b = rgb & 0xFF;
    } else if (hex.length == 8) {
      NSScanner *scanner = [NSScanner scannerWithString:hex];
      unsigned int argb = 0;
      if (![scanner scanHexInt:&argb]) {
        return nil;
      }
      a = (argb >> 24) & 0xFF;
      r = (argb >> 16) & 0xFF;
      g = (argb >> 8) & 0xFF;
      b = argb & 0xFF;
    } else {
      return nil;
    }
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:a / 255.0];
  }
  if ([lower isEqualToString:@"red"]) return UIColor.redColor;
  if ([lower isEqualToString:@"green"]) return UIColor.greenColor;
  if ([lower isEqualToString:@"blue"]) return UIColor.blueColor;
  if ([lower isEqualToString:@"black"]) return UIColor.blackColor;
  if ([lower isEqualToString:@"white"]) return UIColor.whiteColor;
  if ([lower isEqualToString:@"gray"] || [lower isEqualToString:@"grey"]) return UIColor.grayColor;
  if ([lower isEqualToString:@"clear"] || [lower isEqualToString:@"transparent"]) return UIColor.clearColor;
  return nil;
}

static UIColor *EXBloomInspectorColorFromNumber(id value)
{
  if (!value || ![value respondsToSelector:@selector(unsignedIntValue)]) {
    return nil;
  }
  uint32_t argb = (uint32_t)[(NSNumber *)value unsignedIntValue];
  CGFloat alpha = ((argb >> 24) & 0xFF) / 255.0;
  CGFloat red = ((argb >> 16) & 0xFF) / 255.0;
  CGFloat green = ((argb >> 8) & 0xFF) / 255.0;
  CGFloat blue = (argb & 0xFF) / 255.0;
  return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

static NSTextAlignment EXBloomInspectorTextAlignmentFromString(NSString *value)
{
  if (!value || ![value isKindOfClass:[NSString class]]) {
    return NSTextAlignmentNatural;
  }
  NSString *lower = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
  if ([lower isEqualToString:@"left"]) return NSTextAlignmentLeft;
  if ([lower isEqualToString:@"right"]) return NSTextAlignmentRight;
  if ([lower isEqualToString:@"center"]) return NSTextAlignmentCenter;
  if ([lower isEqualToString:@"justify"]) return NSTextAlignmentJustified;
  return NSTextAlignmentNatural;
}

static NSString *EXBloomInspectorColorToString(UIColor *color)
{
  if (!color) {
    return nil;
  }
  CGFloat r = 0, g = 0, b = 0, a = 0;
  if (![color getRed:&r green:&g blue:&b alpha:&a]) {
    return [color description];
  }
  return [NSString stringWithFormat:@"rgba(%d,%d,%d,%.3f)",
          (int)roundf(r * 255.0f),
          (int)roundf(g * 255.0f),
          (int)roundf(b * 255.0f),
          a];
}

static NSAttributedString *EXBloomInspectorCopyAttributedText(UIView *view)
{
  if (!view) {
    return nil;
  }
  id value = nil;
  @try {
    if ([view respondsToSelector:@selector(attributedText)]) {
      value = [view valueForKey:@"attributedText"];
      if ([value isKindOfClass:[NSAttributedString class]]) {
        return (NSAttributedString *)value;
      }
    }
  } @catch (__unused NSException *exception) {}
  @try {
    value = [view valueForKey:@"attributedString"];
    if ([value isKindOfClass:[NSAttributedString class]]) {
      return (NSAttributedString *)value;
    }
  } @catch (__unused NSException *exception) {}
  @try {
    value = [view valueForKey:@"_attributedString"];
    if ([value isKindOfClass:[NSAttributedString class]]) {
      return (NSAttributedString *)value;
    }
  } @catch (__unused NSException *exception) {}
  @try {
    value = [view valueForKey:@"textStorage"];
    if ([value isKindOfClass:[NSTextStorage class]]) {
      return [(NSTextStorage *)value copy];
    }
  } @catch (__unused NSException *exception) {}
  return nil;
}

static BOOL EXBloomInspectorApplyAttributedText(UIView *view, NSAttributedString *value)
{
  if (!view || !value) {
    return NO;
  }
  @try {
    if ([view respondsToSelector:@selector(setAttributedText:)]) {
      [view setValue:value forKey:@"attributedText"];
      return YES;
    }
  } @catch (__unused NSException *exception) {}
  @try {
    [view setValue:value forKey:@"attributedString"];
    return YES;
  } @catch (__unused NSException *exception) {}
  @try {
    [view setValue:value forKey:@"_attributedString"];
    return YES;
  } @catch (__unused NSException *exception) {}
  @try {
    id layoutManager = [view valueForKey:@"_layoutManager"];
    if (!layoutManager) {
      layoutManager = [view valueForKey:@"textLayoutManager"];
    }
    if (layoutManager) {
      if ([layoutManager respondsToSelector:@selector(setAttributedString:)]) {
        [layoutManager setValue:value forKey:@"attributedString"];
        return YES;
      }
    }
  } @catch (__unused NSException *exception) {}
  @try {
    id storage = [view valueForKey:@"textStorage"];
    if ([storage isKindOfClass:[NSTextStorage class]]) {
      [(NSTextStorage *)storage setAttributedString:value];
      return YES;
    }
  } @catch (__unused NSException *exception) {}
  return NO;
}

static void EXBloomInspectorForceRedraw(UIView *view)
{
  if (!view) {
    return;
  }
  [view setNeedsDisplay];
  [view setNeedsLayout];
  [view invalidateIntrinsicContentSize];
  CALayer *layer = view.layer;
  [layer setNeedsDisplay];
  if (layer.sublayers.count) {
    for (CALayer *sublayer in layer.sublayers) {
      [sublayer setNeedsDisplay];
    }
  }
  if (view.superview) {
    [view.superview setNeedsLayout];
    [view.superview layoutIfNeeded];
  }
}

static NSString *EXBloomInspectorGetPlainTextFromView(UIView *view)
{
  if (!view) {
    return nil;
  }
  if ([view isKindOfClass:[UILabel class]]) {
    return ((UILabel *)view).text;
  }
  if ([view isKindOfClass:[UITextView class]]) {
    return ((UITextView *)view).text;
  }
  if ([view isKindOfClass:[UITextField class]]) {
    return ((UITextField *)view).text;
  }
  if ([view isKindOfClass:[UIButton class]]) {
    return [(UIButton *)view titleForState:UIControlStateNormal];
  }
  NSAttributedString *attr = EXBloomInspectorCopyAttributedText(view);
  if (attr.string.length) {
    return attr.string;
  }
  @try {
    id value = [view valueForKey:@"text"];
    if ([value isKindOfClass:[NSString class]]) {
      return (NSString *)value;
    }
  } @catch (__unused NSException *exception) {}
  return nil;
}

static NSDictionary *EXBloomInspectorRectInfo(CGRect rect)
{
  return @{
    @"x": @(rect.origin.x),
    @"y": @(rect.origin.y),
    @"width": @(rect.size.width),
    @"height": @(rect.size.height),
  };
}

static UIView *EXBloomInspectorFindTextView(UIView *view)
{
  if (!view) {
    return nil;
  }
  if ([view isKindOfClass:[UILabel class]] ||
      [view isKindOfClass:[UITextView class]] ||
      [view isKindOfClass:[UITextField class]]) {
    return view;
  }
  for (UIView *subview in view.subviews) {
    UIView *match = EXBloomInspectorFindTextView(subview);
    if (match) {
      return match;
    }
  }
  return nil;
}

static NSString *EXBloomInspectorExtractTextOverride(NSDictionary *props)
{
  if (!props || ![props isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  id value = props[@"children"];
  if (!value) {
    value = props[@"text"];
  }
  if (!value) {
    value = props[@"value"];
  }
  if ([value isKindOfClass:[NSString class]]) {
    return (NSString *)value;
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    return [(NSNumber *)value stringValue];
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableString *joined = [NSMutableString string];
    for (id entry in (NSArray *)value) {
      if ([entry isKindOfClass:[NSString class]]) {
        [joined appendString:entry];
      } else if ([entry isKindOfClass:[NSNumber class]]) {
        [joined appendString:[(NSNumber *)entry stringValue]];
      }
    }
    return joined.length ? [joined copy] : nil;
  }
  return nil;
}

static BOOL EXBloomInspectorApplyParagraphTextStyle(UIView *view, NSDictionary *style)
{
  if (!view || ![style isKindOfClass:[NSDictionary class]]) {
    return NO;
  }
  NSString *className = NSStringFromClass([view class]);
  if (![className containsString:@"Paragraph"] && ![className containsString:@"Text"]) {
    return NO;
  }

  NSAttributedString *existing = EXBloomInspectorCopyAttributedText(view);
  NSString *baseText = existing ? existing.string : EXBloomInspectorGetPlainTextFromView(view);
  if (!baseText || !baseText.length) {
    id fallbackValue = style[@"__bloomInspectorFallbackText"];
    if ([fallbackValue isKindOfClass:[NSString class]]) {
      baseText = (NSString *)fallbackValue;
    } else if ([fallbackValue isKindOfClass:[NSNumber class]]) {
      baseText = [(NSNumber *)fallbackValue stringValue];
    }
  }
  if (!baseText) {
    baseText = @"";
  }

  NSMutableAttributedString *mutableText = existing
    ? [existing mutableCopy]
    : [[NSMutableAttributedString alloc] initWithString:baseText];

  NSRange range = NSMakeRange(0, mutableText.length);
  if (range.length == 0) {
    return NO;
  }

  UIColor *textColor = nil;
  id colorValue = style[@"color"];
  if ([colorValue isKindOfClass:[NSString class]]) {
    textColor = EXBloomInspectorColorFromString(colorValue);
  } else if ([colorValue isKindOfClass:[NSNumber class]]) {
    textColor = EXBloomInspectorColorFromNumber(colorValue);
  }
  if (textColor) {
    [mutableText addAttribute:NSForegroundColorAttributeName value:textColor range:range];
  }

  NSNumber *fontSize = [style[@"fontSize"] isKindOfClass:[NSNumber class]] ? style[@"fontSize"] : nil;
  if (fontSize) {
    UIFont *font = [mutableText attribute:NSFontAttributeName atIndex:0 effectiveRange:nil];
    CGFloat size = [fontSize floatValue];
    if (size > 0) {
      UIFont *nextFont = font ? [font fontWithSize:size] : [UIFont systemFontOfSize:size];
      [mutableText addAttribute:NSFontAttributeName value:nextFont range:range];
    }
  }

  NSString *textAlign = [style[@"textAlign"] isKindOfClass:[NSString class]] ? style[@"textAlign"] : nil;
  if (textAlign) {
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = EXBloomInspectorTextAlignmentFromString(textAlign);
    [mutableText addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:range];
  }

  NSString *decoration = [style[@"textDecorationLine"] isKindOfClass:[NSString class]]
                             ? style[@"textDecorationLine"]
                             : nil;
  if (decoration && [decoration containsString:@"underline"]) {
    UIColor *underlineColor = nil;
    id underlineValue = style[@"textDecorationColor"];
    if ([underlineValue isKindOfClass:[NSString class]]) {
      underlineColor = EXBloomInspectorColorFromString(underlineValue);
    } else if ([underlineValue isKindOfClass:[NSNumber class]]) {
      underlineColor = EXBloomInspectorColorFromNumber(underlineValue);
    }
    [mutableText addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
    if (underlineColor) {
      [mutableText addAttribute:NSUnderlineColorAttributeName value:underlineColor range:range];
    }
  }
  if (!EXBloomInspectorApplyAttributedText(view, mutableText)) {
    return NO;
  }
  EXBloomInspectorForceRedraw(view);
  return YES;
}

static BOOL EXBloomInspectorApplyTextOverrideToView(UIView *view, NSString *textValue)
{
  if (!view || ![textValue isKindOfClass:[NSString class]]) {
    return NO;
  }

  if ([view isKindOfClass:[UILabel class]]) {
    ((UILabel *)view).text = textValue;
    return YES;
  }
  if ([view isKindOfClass:[UITextView class]]) {
    ((UITextView *)view).text = textValue;
    return YES;
  }
  if ([view isKindOfClass:[UITextField class]]) {
    ((UITextField *)view).text = textValue;
    return YES;
  }
  if ([view isKindOfClass:[UIButton class]]) {
    [(UIButton *)view setTitle:textValue forState:UIControlStateNormal];
    return YES;
  }

  NSString *className = NSStringFromClass([view class]);
  if ([className containsString:@"Paragraph"] || [className containsString:@"Text"]) {
    NSAttributedString *existing = EXBloomInspectorCopyAttributedText(view);
    NSDictionary *attributes = nil;
    if (existing.length > 0) {
      attributes = [existing attributesAtIndex:0 effectiveRange:nil];
    }
    NSMutableAttributedString *mutableText = attributes
      ? [[NSMutableAttributedString alloc] initWithString:textValue attributes:attributes]
      : [[NSMutableAttributedString alloc] initWithString:textValue];
    if (!EXBloomInspectorApplyAttributedText(view, mutableText)) {
      return NO;
    }
    EXBloomInspectorForceRedraw(view);
    return YES;
  }

  UIView *textView = EXBloomInspectorFindTextView(view);
  if (textView && textView != view) {
    return EXBloomInspectorApplyTextOverrideToView(textView, textValue);
  }
  return NO;
}

static void EXBloomInspectorApplyTextStyleToView(UIView *view, NSDictionary *style)
{
  if (!view || ![style isKindOfClass:[NSDictionary class]]) {
    return;
  }
  if (EXBloomInspectorApplyParagraphTextStyle(view, style)) {
    return;
  }
  UIView *textView = EXBloomInspectorFindTextView(view);
  if (!textView) {
    return;
  }
  UIColor *textColor = nil;
  id colorValue = style[@"color"];
  if ([colorValue isKindOfClass:[NSString class]]) {
    textColor = EXBloomInspectorColorFromString(colorValue);
  } else if ([colorValue isKindOfClass:[NSNumber class]]) {
    textColor = EXBloomInspectorColorFromNumber(colorValue);
  }
  if (textColor && [textView respondsToSelector:@selector(setTextColor:)]) {
    [(id)textView setTextColor:textColor];
  }
  NSString *textAlign = [style[@"textAlign"] isKindOfClass:[NSString class]] ? style[@"textAlign"] : nil;
  if (textAlign && [textView respondsToSelector:@selector(setTextAlignment:)]) {
    [(id)textView setTextAlignment:EXBloomInspectorTextAlignmentFromString(textAlign)];
  }
  NSNumber *fontSize = [style[@"fontSize"] isKindOfClass:[NSNumber class]] ? style[@"fontSize"] : nil;
  if (fontSize) {
    UIFont *font = nil;
    id fontValue = nil;
    @try {
      fontValue = [textView valueForKey:@"font"];
    } @catch (__unused NSException *exception) {
      fontValue = nil;
    }
    if ([fontValue isKindOfClass:[UIFont class]]) {
      font = (UIFont *)fontValue;
    }
    CGFloat size = [fontSize floatValue];
    if (size > 0) {
      UIFont *nextFont = font ? [font fontWithSize:size] : [UIFont systemFontOfSize:size];
      if ([textView respondsToSelector:@selector(setFont:)]) {
        [(id)textView setFont:nextFont];
      }
    }
  }
  NSString *decoration = [style[@"textDecorationLine"] isKindOfClass:[NSString class]]
                             ? style[@"textDecorationLine"]
                             : nil;
  if (decoration && [decoration containsString:@"underline"]) {
    UIColor *underlineColor = nil;
    id underlineValue = style[@"textDecorationColor"];
    if ([underlineValue isKindOfClass:[NSString class]]) {
      underlineColor = EXBloomInspectorColorFromString(underlineValue);
    } else if ([underlineValue isKindOfClass:[NSNumber class]]) {
      underlineColor = EXBloomInspectorColorFromNumber(underlineValue);
    }
    NSAttributedString *existing = EXBloomInspectorCopyAttributedText(textView);
    NSString *text = nil;
    if (!existing && [textView respondsToSelector:@selector(text)]) {
      text = [(id)textView text];
    }
    if (!existing && !text) {
      return;
    }
    NSMutableAttributedString *mutableText =
        existing ? [existing mutableCopy] : [[NSMutableAttributedString alloc] initWithString:text ?: @""];
    NSRange range = NSMakeRange(0, mutableText.length);
    if (range.length > 0) {
      [mutableText addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
      if (underlineColor) {
        [mutableText addAttribute:NSUnderlineColorAttributeName value:underlineColor range:range];
      }
      if (textColor) {
        [mutableText addAttribute:NSForegroundColorAttributeName value:textColor range:range];
      }
    }
    if ([textView respondsToSelector:@selector(setAttributedText:)]) {
      [(id)textView setAttributedText:mutableText];
    }
  }
}

static void EXBloomInspectorApplyUIKitStyleToView(UIView *view, NSDictionary *props, RCTPromiseResolveBlock resolve)
{
  if (!view) {
    resolve(@{@"ok": @NO, @"reason": @"no-hitView", @"mode": @"uikit"});
    return;
  }

  NSDictionary *style = props[@"style"];
  if (![style isKindOfClass:[NSDictionary class]]) {
    style = props;
  }
  NSString *textOverride = EXBloomInspectorExtractTextOverride(props);
  BOOL hasStyle = [style isKindOfClass:[NSDictionary class]] && style.count > 0;
  if (!hasStyle && !textOverride) {
    resolve(@{@"ok": @NO, @"reason": @"empty-style", @"mode": @"uikit"});
    return;
  }
  if (!hasStyle) {
    style = @{};
  }

  id bg = style[@"backgroundColor"];
  if ([bg isKindOfClass:[NSString class]]) {
    UIColor *color = EXBloomInspectorColorFromString(bg);
    if (color) {
      view.backgroundColor = color;
      view.layer.backgroundColor = color.CGColor;
      view.opaque = YES;
      UIView *contentView = nil;
      if ([view respondsToSelector:@selector(contentView)]) {
        @try {
          contentView = [view valueForKey:@"contentView"];
        } @catch (__unused NSException *exception) {
          contentView = nil;
        }
      }
      if ([contentView isKindOfClass:[UIView class]]) {
        contentView.backgroundColor = color;
        contentView.layer.backgroundColor = color.CGColor;
        contentView.opaque = YES;
      } else if ([NSStringFromClass([view class]) containsString:@"Paragraph"]) {
        UIView *firstSubview = view.subviews.count ? view.subviews.firstObject : nil;
        if ([firstSubview isKindOfClass:[UIView class]]) {
          firstSubview.backgroundColor = color;
          firstSubview.layer.backgroundColor = color.CGColor;
          firstSubview.opaque = YES;
        }
      }
    }
  } else if ([bg isKindOfClass:[NSNumber class]]) {
    UIColor *color = EXBloomInspectorColorFromNumber(bg);
    if (color) {
      view.backgroundColor = color;
      view.layer.backgroundColor = color.CGColor;
      view.opaque = YES;
    }
  }
  id opacity = style[@"opacity"];
  if ([opacity isKindOfClass:[NSNumber class]]) {
    view.alpha = [(NSNumber *)opacity floatValue];
  }
  id hidden = style[@"display"];
  if ([hidden isKindOfClass:[NSString class]] && [hidden isEqualToString:@"none"]) {
    view.hidden = YES;
  }
  id borderColor = style[@"borderColor"];
  if ([borderColor isKindOfClass:[NSString class]]) {
    UIColor *color = EXBloomInspectorColorFromString(borderColor);
    if (color) {
      view.layer.borderColor = color.CGColor;
    }
  } else if ([borderColor isKindOfClass:[NSNumber class]]) {
    UIColor *color = EXBloomInspectorColorFromNumber(borderColor);
    if (color) {
      view.layer.borderColor = color.CGColor;
    }
  }
  id borderWidth = style[@"borderWidth"];
  if ([borderWidth isKindOfClass:[NSNumber class]]) {
    view.layer.borderWidth = [(NSNumber *)borderWidth floatValue];
  }
  id borderRadius = style[@"borderRadius"];
  if ([borderRadius isKindOfClass:[NSNumber class]]) {
    view.layer.cornerRadius = [(NSNumber *)borderRadius floatValue];
    view.layer.masksToBounds = YES;
  }
  EXBloomInspectorApplyTextStyleToView(view, style);
  if (textOverride) {
    EXBloomInspectorApplyTextOverrideToView(view, textOverride);
  }
  id tint = style[@"tintColor"];
  if ([tint isKindOfClass:[NSString class]]) {
    UIColor *color = EXBloomInspectorColorFromString(tint);
    if (color) {
      view.tintColor = color;
    }
  } else if ([tint isKindOfClass:[NSNumber class]]) {
    UIColor *color = EXBloomInspectorColorFromNumber(tint);
    if (color) {
      view.tintColor = color;
    }
  }
  id textColor = style[@"color"];
  if ([textColor isKindOfClass:[NSString class]] || [textColor isKindOfClass:[NSNumber class]]) {
    UIColor *color = [textColor isKindOfClass:[NSString class]]
      ? EXBloomInspectorColorFromString(textColor)
      : EXBloomInspectorColorFromNumber(textColor);
    if (color) {
      if ([view isKindOfClass:[UILabel class]]) {
        ((UILabel *)view).textColor = color;
      } else if ([view isKindOfClass:[UITextView class]]) {
        ((UITextView *)view).textColor = color;
      } else if ([view isKindOfClass:[UITextField class]]) {
        ((UITextField *)view).textColor = color;
      } else if ([view isKindOfClass:[UIButton class]]) {
        [(UIButton *)view setTitleColor:color forState:UIControlStateNormal];
      }
    }
  }

  resolve(@{
    @"ok": @YES,
    @"mode": @"uikit",
    @"componentViewClass": NSStringFromClass([view class]),
    @"componentViewFrame": EXBloomInspectorRectInfo(view.frame),
    @"componentViewBounds": EXBloomInspectorRectInfo(view.bounds),
    @"componentViewHidden": @(view.hidden),
    @"componentViewAlpha": @(view.alpha),
    @"componentViewBackgroundColor": EXBloomInspectorColorToString(view.backgroundColor) ?: [NSNull null],
  });
}

RCT_REMAP_METHOD(applyNativePropsAsync,
                 applyNativeProps:(NSDictionary *)props
                 withResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  if (!props || props.count == 0) {
    resolve(@{@"ok": @NO, @"reason": @"empty-props"});
    return;
  }

  EXKernelAppRecord *visibleApp = [EXKernel sharedInstance].visibleApp;
  id host = visibleApp.appManager.reactHost;
  if (!host || ![host respondsToSelector:@selector(moduleRegistry)]) {
    resolve(@{@"ok": @NO, @"reason": @"no-host"});
    return;
  }

  EXBloomInspectorOverlayView *overlayView =
      [[EXBloomInspectorOverlayManager sharedInstance] viewController].overlayView;
  NSArray<NSNumber *> *availableTags = overlayView.selectedViewTags ?: @[];
  NSNumber *reactTag = overlayView.selectedViewTag ?: (availableTags.count ? availableTags[0] : nil);
  if (!reactTag) {
    EXBloomInspectorApplyUIKitStyleToView(overlayView.selectedHitView, props, resolve);
    return;
  }

  EXBloomInspectorApplyNativePropsToReactTag(host, reactTag, props, resolve);
}

RCT_REMAP_METHOD(applyNativePropsToTagAsync,
                 applyNativePropsToTag:(NSNumber *)reactTag
                 props:(NSDictionary *)props
                 withResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  if (!props || props.count == 0) {
    resolve(@{@"ok": @NO, @"reason": @"empty-props"});
    return;
  }

  EXKernelAppRecord *visibleApp = [EXKernel sharedInstance].visibleApp;
  id host = visibleApp.appManager.reactHost;
  if (!host) {
    resolve(@{@"ok": @NO, @"reason": @"no-host"});
    return;
  }

  if (!reactTag) {
    EXBloomInspectorOverlayView *overlayView =
        [[EXBloomInspectorOverlayManager sharedInstance] viewController].overlayView;
    EXBloomInspectorApplyUIKitStyleToView(overlayView.selectedHitView, props, resolve);
    return;
  }

  EXBloomInspectorApplyNativePropsToReactTag(host, reactTag, props, resolve);
}

RCT_REMAP_METHOD(applyLiveEditToAppAsync,
                 applyLiveEditToApp:(NSNumber *)reactTag
                 props:(NSDictionary *)props
                 withResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  if (!reactTag) {
    resolve(@{@"ok": @NO, @"reason": @"no-tag"});
    return;
  }

  EXBloomInspector *inspectorModule = EXGetBloomInspectorModuleForVisibleApp();
  if (!inspectorModule) {
    resolve(@{@"ok": @NO, @"reason": @"no-inspector"});
    return;
  }

  NSDictionary *payload = @{
    @"reactTag": reactTag ?: [NSNull null],
    @"props": props ?: @{},
  };
  [inspectorModule emitLiveEdit:payload];
  resolve(@{@"ok": @YES});
}

RCT_EXPORT_METHOD(sendPick:(NSDictionary *)payload)
{
  EXBloomInspectorOverlay *module = EXGetBloomInspectorOverlayModule();
  if (!module) {
    BLOOM_LOG(@"Bloom Log: 95 sendPick missing overlay module");
    return;
  }
  kBloomInspectorLastJSPickTime = CFAbsoluteTimeGetCurrent();
  BLOOM_LOG(@"Bloom Log: 95 sendPick emitPick hasListeners=%@", module->_hasListeners ? @"YES" : @"NO");
  [module emitPick:payload];
}

RCT_EXPORT_METHOD(log:(NSString *)message)
{
  if (!kBloomInspectorDebugLogs || message.length == 0) {
    return;
  }
  BLOOM_LOG(@"Bloom Log: %@", message);
}

- (void)emitPick:(NSDictionary *)payload
{
  if (_hasListeners) {
    BLOOM_LOG(@"Bloom Log: 95 emitPick sending event");
    [self sendEventWithName:@"bloomInspectorOverlayPick" body:payload];
  } else {
    BLOOM_LOG(@"Bloom Log: 95 emitPick no listeners");
  }
}

- (void)emitToggle:(BOOL)enabled
{
  if (_hasListeners) {
    [self sendEventWithName:@"bloomInspectorOverlayToggle" body:@{@"enabled": @(enabled)}];
  }
}

- (void)emitPing:(NSDictionary *)payload
{
  if (_hasListeners) {
    [self sendEventWithName:@"bloomInspectorOverlayPing" body:payload];
  }
}

@end
