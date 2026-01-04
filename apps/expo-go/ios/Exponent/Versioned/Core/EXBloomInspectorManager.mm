// Copyright 2015-present 650 Industries. All rights reserved.

#import "EXBloomInspectorManager.h"

#import <React/UIView+React.h>
#import "EXDevMenuManager.h"
#import "EXKernel.h"
#import "EXReactAppManager.h"

#import <Expo/RCTAppDelegateUmbrella.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import <ReactCommon/RCTHost.h>
#import <jsi/jsi.h>
#import <memory>
#import <objc/runtime.h>
#import <string>

static const char kBloomInspectorInjectionScript[] = R"JS(
(function () {
  var g = typeof globalThis !== 'undefined' ? globalThis : typeof global !== 'undefined' ? global : typeof window !== 'undefined' ? window : this;
  if (!g || g.__bloomInspectorRuntimeInstalled) {
    return;
  }
  g.__bloomInspectorRuntimeInstalled = true;

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
  try {
    if (typeof setTimeout === 'function') {
      setTimeout(function () {
        log('35 prelude installed (delayed)=' + String(g.__bloomInspectorPreludeInstalled));
      }, 1000);
      setTimeout(function () {
        log('36 prelude installed (delayed)=' + String(g.__bloomInspectorPreludeInstalled));
      }, 3000);
    } else {
      log('35 prelude installed (delayed)=no-timer');
    }
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
        log('71 renderer injected id=' + id);
        g.__bloomInspectorRenderers.push(renderer);
        try {
          if (renderer && renderer.rendererConfig) {
            var keys = Object.keys(renderer.rendererConfig);
            log('73 rendererConfig keys=' + keys.slice(0, 8).join(','));
            log('73 rendererConfig hasTag=' + String(typeof renderer.rendererConfig.getInspectorDataForViewTag === 'function') +
              ' hasPoint=' + String(typeof renderer.rendererConfig.getInspectorDataForViewAtPoint === 'function') +
              ' hasInstance=' + String(typeof renderer.rendererConfig.getInspectorDataForInstance === 'function'));
          }
          if (renderer) {
            log('73 renderer hasFindByNativeTag=' +
              String(typeof renderer.findHostInstanceByNativeTag === 'function'));
            try {
              var proto = Object.getPrototypeOf(renderer);
              var protoKeys = proto ? Object.getOwnPropertyNames(proto) : [];
              var fnKeys = protoKeys.filter(function (key) {
                try {
                  return typeof renderer[key] === 'function';
                } catch (e) {
                  return false;
                }
              });
              log('73 renderer protoFns=' + fnKeys.slice(0, 8).join(','));
            } catch (e) {}
          }
        } catch (e) {}
        return originalSet(id, renderer);
      };
    }
    if (typeof targetHook.inject === 'function') {
      var originalInject = targetHook.inject.bind(targetHook);
      targetHook.inject = function (renderer) {
        var id = originalInject(renderer);
        log('71 renderer injected id=' + id);
        g.__bloomInspectorRenderers.push(renderer);
        try {
          if (renderer && renderer.rendererConfig) {
            var keys = Object.keys(renderer.rendererConfig);
            log('73 rendererConfig keys=' + keys.slice(0, 8).join(','));
            log('73 rendererConfig hasTag=' + String(typeof renderer.rendererConfig.getInspectorDataForViewTag === 'function') +
              ' hasPoint=' + String(typeof renderer.rendererConfig.getInspectorDataForViewAtPoint === 'function') +
              ' hasInstance=' + String(typeof renderer.rendererConfig.getInspectorDataForInstance === 'function'));
          }
          if (renderer) {
            log('73 renderer hasFindByNativeTag=' +
              String(typeof renderer.findHostInstanceByNativeTag === 'function'));
            try {
              var proto = Object.getPrototypeOf(renderer);
              var protoKeys = proto ? Object.getOwnPropertyNames(proto) : [];
              var fnKeys = protoKeys.filter(function (key) {
                try {
                  return typeof renderer[key] === 'function';
                } catch (e) {
                  return false;
                }
              });
              log('73 renderer protoFns=' + fnKeys.slice(0, 8).join(','));
            } catch (e) {}
          }
        } catch (e) {}
        return id;
      };
    }
  }

  function ensureHook() {
    var hook = g.__REACT_DEVTOOLS_GLOBAL_HOOK__;
    if (!hook || !hook.renderers) {
      hook = (function () {
        var renderers = new Map();
        var listeners = {};
        var nextRendererId = 1;
        function emit(event, payload) {
          var handlers = listeners[event];
          if (!handlers) {
            return;
          }
          handlers.forEach(function (handler) {
            try {
              handler(payload);
            } catch (e) {}
          });
        }
        return {
          supportsFiber: true,
          renderers: renderers,
          inject: function (renderer) {
            var id = renderer && (renderer.id || renderer.rendererID) || nextRendererId++;
            renderers.set(id, renderer);
            emit('renderer', { id: id, renderer: renderer });
            return id;
          },
          on: function (event, handler) {
            if (!listeners[event]) {
              listeners[event] = [];
            }
            listeners[event].push(handler);
          },
          off: function (event, handler) {
            var handlers = listeners[event];
            if (!handlers) {
              return;
            }
            var index = handlers.indexOf(handler);
            if (index >= 0) {
              handlers.splice(index, 1);
            }
          },
          emit: emit,
        };
      })();
      g.__REACT_DEVTOOLS_GLOBAL_HOOK__ = hook;
      log('70 devtools hook installed');
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

  function sendPayload(data, touchID) {
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
      var payloadToSend = {
        frame: data.frame,
        hierarchy: hierarchy.map(function (item) {
          return { name: item && item.name ? item.name : 'Anonymous' };
        }),
        props: undefined,
        selectedIndex: selectedIndex,
        source: undefined,
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
      if (payloadToSend) {
        try {
          log('38-1 js payload keys=' + Object.keys(payloadToSend).join(','));
        } catch (e) {}
        try {
          var preview = {
            touchID: payloadToSend.touchID,
            payloadSource: payloadToSend.payloadSource,
            hasSource: !!payloadToSend.source,
            componentStack: payloadToSend.componentStack
              ? String(payloadToSend.componentStack).split('\n').slice(0, 3).join(' > ')
              : undefined,
            propsKeys: payloadToSend.props ? Object.keys(payloadToSend.props).slice(0, 5) : [],
          };
          log('38-2 js payload preview=' + JSON.stringify(preview));
        } catch (e) {}
        try {
          log('38-3 js payload full=' + JSON.stringify(payloadToSend));
        } catch (e) {
          log('38-3 js payload full=unserializable');
        }
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
    if (!g.__bloomInspectorModuleDumped) {
      try {
        var entries = [];
        if (typeof modules.forEach === 'function') {
          modules.forEach(function (value, key) {
            if (value && value.verboseName) {
              entries.push(key + ':' + value.verboseName);
            }
          });
        } else if (typeof modules === 'object') {
          for (var key in modules) {
            var value = modules[key];
            if (value && value.verboseName) {
              entries.push(key + ':' + value.verboseName);
            }
          }
        }
        entries.sort();
        var preview = entries.slice(0, 40).join(', ');
        log('62 module ids preview=' + preview);
        log('62 module ids count=' + entries.length);
        g.__bloomInspectorModuleDumped = true;
      } catch (e) {}
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
            handled = true;
            hadAnyData = true;
            sendPayload(dataByTag, payload.touchID);
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
                  var rawStack = viewData.componentStack;
                  var fiberFromViewData = getFiberFromViewData(viewData);
                  if (fiberFromViewData) {
                    var stackNames = buildComponentStackFromFiber(fiberFromViewData);
                    var nearestFiber = findNearestUserFiberWithSource(fiberFromViewData);
                    var fiberHierarchy = buildHierarchyFromFiber(fiberFromViewData);
                    var fiberStack = stackNames.length ? stackNames.join(' > ') : undefined;
                    var fiberSource = nearestFiber ? nearestFiber.codeInfo : getCodeInfoFromFiber(fiberFromViewData);
                    if (fiberStack) {
                      viewData.componentStack = fiberStack;
                    }
                    if (fiberSource) {
                      viewData.source = fiberSource;
                    }
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
                    sendPayload(viewData, payload.touchID);
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
                        sendPayload(pendingViewData, payload.touchID);
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
                sendPayload(dataByInstance, payload.touchID);
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
            var fiberData = {
              hierarchy: hierarchy,
              selectedIndex: hierarchy.length ? hierarchy.length - 1 : 0,
              props: fiber.memoizedProps,
              source: nearest ? nearest.codeInfo : (fiber._debugSource || null),
              componentStack: stackNames.length ? stackNames.join(' > ') : undefined,
              frame: payload.frame || null,
            };
            handled = true;
            fiberHandled = true;
            if (pendingTimer) {
              clearTimeout(pendingTimer);
            }
            hadAnyData = true;
            sendPayload(fiberData, payload.touchID);
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
    try {
      Object.defineProperty(g, '__REACT_DEVTOOLS_GLOBAL_HOOK__', {
        configurable: true,
        set: function (value) {
          Object.defineProperty(g, '__REACT_DEVTOOLS_GLOBAL_HOOK__', { value: value, writable: true });
          observeHook(value, 'setter');
          attach();
        },
        get: function () {
          return undefined;
        },
      });
    } catch (e) {}
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
static const NSTimeInterval kBloomInspectorFallbackDelaySeconds = 0.35;
static const NSTimeInterval kBloomInspectorSuppressWindowSeconds = 1.0;

// ------------------------------------------------------------
// Runtime delegate + RCTHost swizzle
// ------------------------------------------------------------

@interface EXBloomInspectorRuntimeDelegate : NSObject <RCTHostRuntimeDelegate>
@end

@implementation EXBloomInspectorRuntimeDelegate

- (void)host:(RCTHost *)host didInitializeRuntime:(facebook::jsi::Runtime &)runtime
{
  NSLog(@"Bloom Log: 39 injecting JS runtime for host: %@", host);
  try {
    auto script = std::make_shared<facebook::jsi::StringBuffer>(kBloomInspectorInjectionScript);
    runtime.evaluateJavaScript(script, "BloomInspectorRuntime.js");
    NSLog(@"Bloom Log: 44 runtime script evaluated");
    bool hasFlag = runtime.global().hasProperty(runtime, "__bloomInspectorRuntimeInstalled");
    NSLog(@"Bloom Log: 50 runtime flag=%@", hasFlag ? @"YES" : @"NO");
    bool preludeFlag = runtime.global().hasProperty(runtime, "__bloomInspectorPreludeInstalled");
    NSLog(@"Bloom Log: 52 prelude flag=%@", preludeFlag ? @"YES" : @"NO");
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
    NSLog(@"Bloom Log: 44 runtime script failed: %s", e.what());
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
    NSLog(@"Bloom Log: 48 runtime delegate attached via swizzle (delegate=%@)", delegateName);
  } else if (!self.runtimeDelegate) {
    NSLog(@"Bloom Log: 48 runtime delegate skipped (delegate=%@)", delegateName);
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
  NSLog(@"Bloom Log: 9 tap %.1f %.1f", point.x, point.y);
  [self _inspectAtPoint:point];
}

- (void)_handlePan:(UIPanGestureRecognizer *)gesture
{
  CGPoint point = [gesture locationInView:self];
  NSLog(@"Bloom Log: 10 pan %.1f %.1f", point.x, point.y);
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
    NSLog(@"Bloom Log: 11 missing rootView/window");
    _highlightView.hidden = YES;
    _label.hidden = YES;
    return;
  }

  CGPoint pointInRootWindow = [self.window convertPoint:point toWindow:rootWindow];
  CGPoint pointInRoot = [rootView convertPoint:pointInRootWindow fromView:rootWindow];

  UIView *hitView = [rootView hitTest:pointInRoot withEvent:nil];
  if (!hitView) {
    NSLog(@"Bloom Log: 12 hitTest returned nil");
    _highlightView.hidden = YES;
    _label.hidden = YES;
    return;
  }
  NSLog(@"Bloom Log: 13 hitView=%@", NSStringFromClass([hitView class]));

  EXBloomInspector *inspectorModule = EXGetBloomInspectorModuleForVisibleApp();
  if (inspectorModule) {
    NSNumber *viewTag = nil;
    UIView *taggedView = hitView;
    while (taggedView) {
      if ([taggedView respondsToSelector:@selector(reactTag)]) {
        viewTag = taggedView.reactTag;
        if (viewTag) {
          break;
        }
      }
      taggedView = taggedView.superview;
    }
    NSNumber *rootTag = nil;
    if ([rootView respondsToSelector:@selector(reactTag)]) {
      rootTag = rootView.reactTag;
    }
    if (viewTag) {
      NSLog(@"Bloom Log: 14 emitTap viewTag=%@", viewTag);
    } else {
      NSLog(@"Bloom Log: 14 emitTap viewTag=<nil>");
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
    NSLog(@"Bloom Log: 14 emitTap skipped (no module)");
  }

  // JS-side listener is attached via NativeEventEmitter on BloomInspector.

  BOOL inspectorAvailable = [self _emitReactInspectorDataForPoint:pointInRoot hitView:hitView touchID:touchID];
  NSLog(@"Bloom Log: 15 inspectorAvailable=%@", inspectorAvailable ? @"YES" : @"NO");

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

  if (!inspectorAvailable) {
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
    }

    NSDictionary *payload = @{
      @"payloadSource": @"native",
      @"touchID": touchID,
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

    NSLog(@"Bloom Log: 16 scheduling fallback native payload");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBloomInspectorFallbackDelaySeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      NSTimeInterval delta = CFAbsoluteTimeGetCurrent() - kBloomInspectorLastJSPickTime;
      if (delta < kBloomInspectorSuppressWindowSeconds) {
        NSLog(@"Bloom Log: 16 fallback native payload suppressed (recent JS pick)");
        return;
      }
      EXBloomInspectorOverlay *module = EXGetBloomInspectorOverlayModule();
      if (module) {
        [module emitPick:payload];
      } else {
        NSLog(@"Bloom Log: 16 fallback emitPick skipped (no module)");
      }
    });
  }
}

- (BOOL)_emitReactInspectorDataForPoint:(CGPoint)pointInRoot hitView:(UIView *)hitView touchID:(NSNumber *)touchID
{
  EXKernelAppRecord *visibleApp = [EXKernel sharedInstance].visibleApp;
  id host = visibleApp.appManager.reactHost;
  if (!host || ![host respondsToSelector:@selector(moduleRegistry)]) {
    NSLog(@"Bloom Log: 17 no react host/moduleRegistry");
    return NO;
  }
  id moduleRegistry = [host moduleRegistry];
  id uiManager = [moduleRegistry moduleForName:"UIManager"];
  if (!uiManager) {
    uiManager = [moduleRegistry moduleForName:"RCTUIManager"];
  }
  if (!uiManager) {
    NSLog(@"Bloom Log: 18 UIManager not found");
    return NO;
  }
  NSLog(@"Bloom Log: 19 UIManager=%@", NSStringFromClass([uiManager class]));

  SEL selector = NSSelectorFromString(@"getInspectorDataForViewAtPoint:callback:");
  if ([uiManager respondsToSelector:selector]) {
    NSLog(@"Bloom Log: 20 calling getInspectorDataForViewAtPoint");
    NSMethodSignature *signature = [uiManager methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments < 4) {
      NSLog(@"Bloom Log: 21 invalid signature for getInspectorDataForViewAtPoint");
      return NO;
    }

    void (^callback)(id) = ^(id result) {
      NSDictionary *payload = nil;
      NSLog(@"Bloom Log: 22 inspector raw=%@", result);
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
          NSLog(@"Bloom Log: 23 emitPick skipped (no overlay module)");
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
    NSLog(@"Bloom Log: 24 invoked getInspectorDataForViewAtPoint");
    return YES;
  }

  SEL tagSelector = NSSelectorFromString(@"getInspectorDataForViewTag:callback:");
  if ([uiManager respondsToSelector:tagSelector] && [hitView respondsToSelector:@selector(reactTag)]) {
    NSNumber *tag = hitView.reactTag;
    if (!tag) {
      NSLog(@"Bloom Log: 25 viewTag missing");
      return NO;
    }

    NSLog(@"Bloom Log: 26 calling getInspectorDataForViewTag tag=%@", tag);
    NSMethodSignature *signature = [uiManager methodSignatureForSelector:tagSelector];
    if (!signature || signature.numberOfArguments < 4) {
      NSLog(@"Bloom Log: 27 invalid signature for getInspectorDataForViewTag");
      return NO;
    }

    void (^callback)(id) = ^(id result) {
      NSDictionary *payload = nil;
      NSLog(@"Bloom Log: 28 inspector raw=%@", result);
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
          NSLog(@"Bloom Log: 29 emitPick skipped (no overlay module)");
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
    NSLog(@"Bloom Log: 30 invoked getInspectorDataForViewTag");
    return YES;
  }

  NSLog(@"Bloom Log: 31 UIManager missing inspector selectors");
  return NO;
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
  return @[@"bloomInspectorToggle", @"bloomInspectorTap"];
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

RCT_EXPORT_METHOD(sendPick:(NSDictionary *)payload)
{
  EXBloomInspectorOverlay *module = EXGetBloomInspectorOverlayModule();
  if (!module) {
    NSLog(@"Bloom Log: 95 sendPick forwarder missing overlay module");
    return;
  }
  NSLog(@"Bloom Log: 95 sendPick forwarder emitPick");
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

RCT_EXPORT_METHOD(sendPick:(NSDictionary *)payload)
{
  EXBloomInspectorOverlay *module = EXGetBloomInspectorOverlayModule();
  if (!module) {
    NSLog(@"Bloom Log: 95 sendPick missing overlay module");
    return;
  }
  kBloomInspectorLastJSPickTime = CFAbsoluteTimeGetCurrent();
  NSLog(@"Bloom Log: 95 sendPick emitPick hasListeners=%@", module->_hasListeners ? @"YES" : @"NO");
  [module emitPick:payload];
}

RCT_EXPORT_METHOD(log:(NSString *)message)
{
  if (message.length == 0) {
    return;
  }
  NSLog(@"Bloom Log: %@", message);
}

- (void)emitPick:(NSDictionary *)payload
{
  if (_hasListeners) {
    NSLog(@"Bloom Log: 95 emitPick sending event");
    [self sendEventWithName:@"bloomInspectorOverlayPick" body:payload];
  } else {
    NSLog(@"Bloom Log: 95 emitPick no listeners");
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
