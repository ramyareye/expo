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
