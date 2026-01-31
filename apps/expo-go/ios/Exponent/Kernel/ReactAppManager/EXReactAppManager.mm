#import "EXBuildConstants.h"
#import "EXEnvironment.h"
#import "EXErrorRecoveryManager.h"
#import "EXKernel.h"
#import "EXAbstractLoader.h"
#import "EXKernelLinkingManager.h"
#import "EXKernelServiceRegistry.h"
#import "EXLog.h"
#import "ExpoKit.h"
#import "EXReactAppManager.h"
#import "EXReactAppManager+Private.h"
#import "EXBloomInspectorManager.h"
#import "EXVersionManagerObjC.h"
#import "EXVersions.h"
#import "EXAppViewController.h"
#import <ExpoModulesCore/EXModuleRegistryProvider.h>
#import <EXConstants/EXConstantsService.h>
#import <ReactCommon/RCTTurboModuleManager.h>

// When `use_frameworks!` is used, the generated Swift header is inside modules.
// Otherwise, it's available only locally with double-quoted imports.
#if __has_include(<EXManifests/EXManifests-Swift.h>)
#import <EXManifests/EXManifests-Swift.h>
#else
#import "EXManifests-Swift.h"
#endif

#import <React/RCTBridge.h>
#import <React/RCTRootView.h>

#import "Expo_Go-Swift.h"

NSString *const RCTInstanceDidLoadBundle = @"RCTInstanceDidLoadBundle";

static const char kBloomInspectorBundlePrelude[] = R"JS(
;(function () {
  try {
    function log(message) {
      var text = 'Bloom Log: ' + message;
      if (global.console && global.console.info) {
        global.console.info(text);
      }
      try {
        var module = null;
        if (global.__turboModuleProxy) {
          module = global.__turboModuleProxy('BloomInspectorOverlay');
        }
        if (!module && global.NativeModules && global.NativeModules.BloomInspectorOverlay) {
          module = global.NativeModules.BloomInspectorOverlay;
        }
        if (module && typeof module.log === 'function') {
          module.log(text);
        }
      } catch (e) {}
    }

    log('1 prelude start');
    log('2 bridge installed=' + String(global.__bloomInspectorBridgeInstalled));
    if (global.__bloomInspectorBridgeInstalled) {
      return;
    }
    global.__bloomInspectorBridgeInstalled = true;
    global.__bloomInspectorPreludeInstalled = true;
    function observeHook(targetHook, label) {
      if (!targetHook || targetHook.__bloomInspectorObserved) {
        return;
      }
      targetHook.__bloomInspectorObserved = true;
      log('34 devtools hook observed ' + label);
      if (targetHook.renderers && typeof targetHook.renderers.set === 'function') {
        var originalSet = targetHook.renderers.set.bind(targetHook.renderers);
        targetHook.renderers.set = function (id, renderer) {
          log('34 renderer injected id=' + id);
          return originalSet(id, renderer);
        };
      }
      if (typeof targetHook.inject === 'function') {
        var originalInject = targetHook.inject.bind(targetHook);
        targetHook.inject = function (renderer) {
          var id = originalInject(renderer);
          log('34 renderer injected id=' + id);
          return id;
        };
      }
    }

    var hook = global.__REACT_DEVTOOLS_GLOBAL_HOOK__;
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
      global.__REACT_DEVTOOLS_GLOBAL_HOOK__ = hook;
      log('3 devtools hook installed');
    }
    global.__bloomInspectorHookInstalled = true;
    observeHook(hook, 'initial');
    try {
      var hookValue = hook;
      Object.defineProperty(global, '__REACT_DEVTOOLS_GLOBAL_HOOK__', {
        configurable: true,
        get: function () {
          return hookValue;
        },
        set: function (value) {
          hookValue = value;
          observeHook(value, 'setter');
        },
      });
    } catch (e) {}

    function tryAttach(attempt) {
      var overlayModule = null;
      if (global.__turboModuleProxy) {
        overlayModule = global.__turboModuleProxy('BloomInspectorOverlay');
      }
      if (!overlayModule && global.NativeModules && global.NativeModules.BloomInspectorOverlay) {
        overlayModule = global.NativeModules.BloomInspectorOverlay;
      }
      var deviceEmitter = global.__RCTDeviceEventEmitter || global.RCTDeviceEventEmitter;
      if (!deviceEmitter || typeof deviceEmitter.addListener !== 'function') {
        if (attempt < 20) {
          log('4 device event emitter missing (retry=' + attempt + ')');
          setTimeout(function () {
            tryAttach(attempt + 1);
          }, 250);
        } else {
          log('4 device event emitter missing (final)');
        }
        return;
      }

      deviceEmitter.addListener('bloomInspectorOverlayPing', function (payload) {
        try {
          log('43 overlay ping received ' + JSON.stringify(payload || {}));
        } catch (e) {
          log('43 overlay ping received');
        }
      });

      var renderers = Array.from(hook.renderers.values());
      if (hook.on && typeof hook.on === 'function') {
        hook.on('renderer', function (payload) {
          if (payload && payload.renderer) {
            renderers.push(payload.renderer);
          }
        });
      }
      log('5 devtools hook attached, renderers=' + renderers.length);
      try {
        var lastRendererCount = renderers.length;
        var pollCount = 0;
        var pollTimer = setInterval(function () {
          pollCount++;
          var currentHook = global.__REACT_DEVTOOLS_GLOBAL_HOOK__;
          if (currentHook && currentHook.renderers && typeof currentHook.renderers.values === 'function') {
            var values = Array.from(currentHook.renderers.values());
            if (values.length !== lastRendererCount) {
              lastRendererCount = values.length;
              log('36 renderer count updated=' + lastRendererCount);
            }
          }
          if (pollCount >= 20) {
            clearInterval(pollTimer);
          }
        }, 500);
      } catch (e) {}
      deviceEmitter.addListener('bloomInspectorTap', function (payload) {
        if (!payload || payload.viewTag == null) {
          log('6 tap event missing viewTag');
          return;
        }
        var viewTag = payload.viewTag;
        var hasData = false;
        for (var i = 0; i < renderers.length; i++) {
          var renderer = renderers[i];
          var fn = renderer && renderer.rendererConfig && renderer.rendererConfig.getInspectorDataForViewTag;
          if (typeof fn !== 'function') {
            continue;
          }
          var data = fn(viewTag);
          if (!data || !data.hierarchy || !data.hierarchy.length) {
            continue;
          }
          hasData = true;

          var hierarchy = data.hierarchy || [];
          var selectedIndex =
            data.selectedIndex != null ? data.selectedIndex : Math.max(hierarchy.length - 1, 0);
          var selected = hierarchy[selectedIndex];
          var props = null;
          if (selected && typeof selected.getInspectorData === 'function') {
            try {
              var findNodeHandle = null;
              if (global.__bloomInspectorFindNodeHandle) {
                findNodeHandle = global.__bloomInspectorFindNodeHandle;
              }
              var inspectorData = selected.getInspectorData(findNodeHandle);
              if (inspectorData && inspectorData.props) {
                props = inspectorData.props;
              }
            } catch (e) {}
          }

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

          var payloadToSend = {
            frame: data.frame,
            hierarchy: hierarchy.map(function (item) {
              return { name: item && item.name ? item.name : 'Anonymous' };
            }),
            props: props ? sanitize(props, 0) : undefined,
            selectedIndex: selectedIndex,
            source: data.source,
            componentStack: data.componentStack,
          };

          if (overlayModule && overlayModule.sendPick) {
            overlayModule.sendPick(payloadToSend);
          }
          log('7 sent JS payload with ' + payloadToSend.hierarchy.length + ' items');
          break;
        }
        if (!hasData) {
          log('8 no inspector data for viewTag=' + viewTag);
        }
      });
    }
    tryAttach(0);
    try {
      var requireFn = global.__r || global.require;
      function findModuleIdByName(substr) {
        if (!requireFn || !requireFn.getModules) {
          return null;
        }
        var modules = requireFn.getModules();
        if (!modules) {
          return null;
        }
        var entries = Object.entries(modules);
        for (var i = 0; i < entries.length; i++) {
          var key = entries[i][0];
          var value = entries[i][1];
          var name = value && (value.verboseName || value.moduleId || value.id || value.name);
          if (typeof name === 'string' && name.indexOf(substr) !== -1) {
            return Number(key);
          }
        }
        return null;
      }

      function tryWrapAppRegistry(attempt) {
        if (global.__bloomInspectorWrappedRegisterComponent) {
          return;
        }
        if (!requireFn || !requireFn.getModules) {
          if (attempt < 30) {
            setTimeout(function () { tryWrapAppRegistry(attempt + 1); }, 200);
          }
          return;
        }
        var appRegistryId = findModuleIdByName('ReactNative/AppRegistry');
        var reactId = findModuleIdByName('/react/index.js');
        var viewId = findModuleIdByName('Libraries/Components/View/View');
        if (appRegistryId == null || reactId == null || viewId == null) {
          if (attempt < 30) {
            setTimeout(function () { tryWrapAppRegistry(attempt + 1); }, 200);
          } else {
            log('90 failed to wrap AppRegistry (modules missing)');
          }
          return;
        }
        var AppRegistry = requireFn(appRegistryId);
        var React = requireFn(reactId);
        var ViewModule = requireFn(viewId);
        var View = (ViewModule && (ViewModule.default || ViewModule.View || ViewModule)) || null;
        if (!AppRegistry || !React || !View || typeof AppRegistry.registerComponent !== 'function') {
          log('90 failed to wrap AppRegistry (resolve failed)');
          return;
        }
        global.__bloomInspectorWrappedRegisterComponent = true;
        var originalRegisterComponent = AppRegistry.registerComponent;
        AppRegistry.registerComponent = function (appKey, componentProvider) {
          return originalRegisterComponent(appKey, function () {
            var InnerComponent = componentProvider();
            function BloomInspectorRootWrapper(props) {
              return React.createElement(
                View,
                {
                  style: { flex: 1 },
                  ref: function (ref) {
                    if (ref && global.__bloomInspectorHostComponent !== ref) {
                      global.__bloomInspectorHostComponent = ref;
                      if (!global.__bloomInspectorHostLogged) {
                        global.__bloomInspectorHostLogged = true;
                        log('91 host component captured');
                      }
                    }
                  },
                },
                React.createElement(InnerComponent, props)
              );
            }
            BloomInspectorRootWrapper.displayName = 'BloomInspectorRootWrapper';
            return BloomInspectorRootWrapper;
          });
        };
        log('90 wrapped AppRegistry.registerComponent');
      }

      tryWrapAppRegistry(0);
    } catch (e) {
      log('90 failed to wrap AppRegistry error=' + (e && e.message ? e.message : 'unknown'));
    }
    try {
      setTimeout(function () {
        log('37 prelude alive hook=' + String(!!global.__REACT_DEVTOOLS_GLOBAL_HOOK__) +
          ' renderers=' + String(global.__REACT_DEVTOOLS_GLOBAL_HOOK__ &&
            global.__REACT_DEVTOOLS_GLOBAL_HOOK__.renderers &&
            global.__REACT_DEVTOOLS_GLOBAL_HOOK__.renderers.size));
      }, 1000);
    } catch (e) {}
  } catch (e) {}
})();
)JS";

static NSData *EXInjectBloomInspectorPrelude(NSData *data)
{
  if (!data || data.length == 0) {
    return data;
  }
  NSString *source = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (!source) {
    NSLog(@"Bloom Log: 40 bundle not UTF-8 (size=%lu)", (unsigned long)data.length);
    return data;
  }
  NSUInteger previewLength = MIN((NSUInteger)120, source.length);
  NSString *preview = [source substringToIndex:previewLength];
  preview = [[preview stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"]
    stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
  NSLog(@"Bloom Log: 40 bundle UTF-8 size=%lu preview=%@", (unsigned long)data.length, preview);
  if ([source containsString:@"__bloomInspectorBridgeInstalled"]) {
    return data;
  }
  NSString *prelude = [NSString stringWithUTF8String:kBloomInspectorBundlePrelude];
  if (!prelude) {
    return data;
  }
  NSString *combined = [prelude stringByAppendingString:source];
  NSData *combinedData = [combined dataUsingEncoding:NSUTF8StringEncoding];
  return combinedData ?: data;
}

@implementation RCTSource (EXReactAppManager)

- (instancetype)initWithURL:(nonnull NSURL *)url data:(nonnull NSData *)data
{
  if (self = [super init]) {
    // Use KVO since RN publicly declares these properties as readonly and privately defines the
    // ivars
    [self setValue:url forKey:@"url"];
    [self setValue:data forKey:@"data"];
    [self setValue:@(data.length) forKey:@"length"];
    [self setValue:@(RCTSourceFilesChangedCountNotBuiltByBundler) forKey:@"filesChangedCount"];
  }
  return self;
}

@end

@interface EXReactAppManager ()

@property (nonatomic, strong) UIView * __nullable reactRootView;
@property (nonatomic, copy) RCTSourceLoadBlock loadCallback;
@property (nonatomic, strong) NSDictionary *initialProps;
@property (nonatomic, strong) NSTimer *viewTestTimer;

@end

@implementation EXReactAppManager

- (instancetype)initWithAppRecord:(EXKernelAppRecord *)record initialProps:(NSDictionary *)initialProps
{
  if (self = [super init]) {
    _appRecord = record;
    _initialProps = initialProps;
    _isHeadless = NO;
    _exceptionHandler = [[EXReactAppExceptionHandler alloc] initWithAppRecord:_appRecord];
    RCTRegisterReloadCommandListener(self);
  }
  return self;
}

- (id)reactHost {
  id host = _expoAppInstance.reactNativeFactory.rootViewFactory.reactHost;
  if (host && [host respondsToSelector:@selector(runtimeDelegate)]) {
    id runtimeDelegate = [host valueForKey:@"runtimeDelegate"];
    if (!runtimeDelegate) {
      [host setValue:EXGetBloomInspectorRuntimeDelegate() forKey:@"runtimeDelegate"];
      NSLog(@"Bloom Log: 48 runtime delegate attached in EXReactAppManager");
    }
  }
  return host;
}

- (void)setAppRecord:(EXKernelAppRecord *)appRecord
{
  _appRecord = appRecord;
  _exceptionHandler = [[EXReactAppExceptionHandler alloc] initWithAppRecord:appRecord];
}

- (EXReactAppManagerStatus)status
{
  if (!_appRecord) {
    return kEXReactAppManagerStatusError;
  }
  if (_loadCallback) {
    return kEXReactAppManagerStatusBridgeLoading;
  }
  if (_isReactHostRunning) {
    return kEXReactAppManagerStatusRunning;
  }
  return kEXReactAppManagerStatusNew;
}

- (UIView *)rootView
{
  return _reactRootView;
}

- (void)rebuildHost
{
  EXAssertMainThread();
  NSAssert((_delegate != nil), @"Cannot init react app without EXReactAppManagerDelegate");

  [self _invalidateAndClearDelegate:NO];

  // Assert early so we can catch the error before instantiating the RCTHost, otherwise we would be passing a
  // nullish scope key to the scoped modules.
  // Alternatively we could skip instantiating the scoped modules but then singletons like the one used in
  // expo-updates would be loaded as bare modules. In the case of expo-updates, this would throw a fatal error
  // because Expo.plist is not available in the Expo Go app.
  NSAssert(_appRecord.scopeKey, @"Experience scope key should be nonnull when getting initial properties for root view. This can occur when the manifest JSON, loaded from the server, is missing keys.");

  if ([self isReadyToLoad]) {
    _versionManager = [[EXVersionManager alloc] initWithParams:[self extraParams]
                                                      manifest:_appRecord.appLoader.manifest
                                                  fatalHandler:handleFatalReactError
                                                   logFunction:[self logFunction]
                                                  logThreshold:[self logLevel]];
    
    [self _createAppInstance];
    [self _startObservingNotificationsForHost];
    
    if (!_isHeadless) {
      id host = self.expoAppInstance.reactNativeFactory.rootViewFactory.reactHost;
      if (host && [host respondsToSelector:@selector(runtimeDelegate)]) {
        id runtimeDelegate = [host valueForKey:@"runtimeDelegate"];
        if (!runtimeDelegate) {
          [host setValue:EXGetBloomInspectorRuntimeDelegate() forKey:@"runtimeDelegate"];
          NSLog(@"Bloom Log: 48 runtime delegate attached before rootView creation");
        }
      }
      _reactRootView = [self.expoAppInstance.reactNativeFactory.rootViewFactory viewWithModuleName:[self applicationKeyForRootView] initialProperties:[self initialPropertiesForRootView]];
    }

    [self setupWebSocketControls];
    [_delegate reactAppManagerIsReadyForLoad:self];
  }
}

- (void)_createAppInstance
{
  __weak __typeof(self) weakSelf = self;
  ExpoAppInstance *appInstance = [[ExpoAppInstance alloc] initWithSourceURL:[self bundleUrl] manager:_versionManager onLoad:^(NSURL *sourceURL, RCTSourceLoadBlock loadCallback) {
    EXReactAppManager *strongSelf = weakSelf;
    [strongSelf loadSourceForHost:sourceURL onComplete:loadCallback];
  }];

  _expoAppInstance = appInstance;
}

- (NSDictionary *)extraParams
{
  // we allow the vanilla RN dev menu in some circumstances.
  BOOL isStandardDevMenuAllowed = false;
  return @{
    @"manifest": _appRecord.appLoader.manifest.rawManifestJSON,
    @"constants": @{
        @"linkingUri": RCTNullIfNil([EXKernelLinkingManager linkingUriForExperienceUri:_appRecord.appLoader.manifestUrl useLegacy:NO]),
        @"experienceUrl": RCTNullIfNil(_appRecord.appLoader.manifestUrl? _appRecord.appLoader.manifestUrl.absoluteString: nil),
        @"expoRuntimeVersion": [EXBuildConstants sharedInstance].expoRuntimeVersion,
        @"manifest": _appRecord.appLoader.manifest.rawManifestJSON,
        @"executionEnvironment": [self _executionEnvironment],
        @"appOwnership": @"expo",
        @"isHeadless": @(_isHeadless),
        @"supportedExpoSdks": @[[EXVersions sharedInstance].sdkVersion],
    },
    @"exceptionsManagerDelegate": _exceptionHandler,
    @"initialUri": RCTNullIfNil([EXKernelLinkingManager initialUriWithManifestUrl:_appRecord.appLoader.manifestUrl]),
    @"isDeveloper": @([self enablesDeveloperTools]),
    @"isStandardDevMenuAllowed": @(isStandardDevMenuAllowed),
    @"testEnvironment": @([EXEnvironment sharedEnvironment].testEnvironment),
    @"services": [EXKernel sharedInstance].serviceRegistry.allServices,
    @"singletonModules": [EXModuleRegistryProvider singletonModules],
    @"moduleRegistryDelegateClass": RCTNullIfNil([self moduleRegistryDelegateClass]),
    @"fileSystemDirectories": @{
        @"documentDirectory": [self scopedDocumentDirectory],
        @"cachesDirectory": [self scopedCachesDirectory]
    }
  };
}

- (void)invalidate
{
  [self _invalidateAndClearDelegate:YES];
}

- (void)_invalidateAndClearDelegate:(BOOL)clearDelegate
{
  [self _stopObservingNotifications];
  if (_viewTestTimer) {
    [_viewTestTimer invalidate];
    _viewTestTimer = nil;
  }
  if (_versionManager) {
    [_versionManager invalidate];
    _versionManager = nil;
  }
  if (_reactRootView) {
    [_reactRootView removeFromSuperview];
    _reactRootView = nil;
  }
  if (_expoAppInstance) {
    _expoAppInstance = nil;
    if (_delegate) {
      [_delegate reactAppManagerDidInvalidate:self];
      if (clearDelegate) {
        _delegate = nil;
      }
    }
  }
  _isReactHostRunning = NO;
}

- (BOOL)isReadyToLoad
{
  if (_appRecord) {
    return (_appRecord.appLoader.status == kEXAppLoaderStatusHasManifest || _appRecord.appLoader.status == kEXAppLoaderStatusHasManifestAndBundle);
  }
  return NO;
}

- (NSURL *)bundleUrl
{
  return [EXApiUtil bundleUrlFromManifest:_appRecord.appLoader.manifest];
}

#pragma mark - EXAppFetcherDataSource

- (NSString *)bundleResourceNameForAppFetcher:(EXAppFetcher *)appFetcher withManifest:(nonnull EXManifestsManifest *)manifest
{
  return manifest.legacyId;
}

- (BOOL)appFetcherShouldInvalidateBundleCache:(EXAppFetcher *)appFetcher
{
  return NO;
}

- (void)loadSourceForHost:(NSURL *)sourceURL onComplete:(RCTSourceLoadBlock)loadCallback {
  // clear any potentially old loading state
  if (_appRecord.scopeKey) {
    [[EXKernel sharedInstance].serviceRegistry.errorRecoveryManager setError:nil forScopeKey:_appRecord.scopeKey];
  }
  
  if ([self enablesDeveloperTools]) {
    if ([_appRecord.appLoader supportsBundleReload]) {
      [_appRecord.appLoader forceBundleReload];
    } else {
      NSAssert(_appRecord.scopeKey, @"EXKernelAppRecord.scopeKey should be nonnull if we have a manifest with developer tools enabled");
      [[EXKernel sharedInstance] reloadAppWithScopeKey:_appRecord.scopeKey];
    }
  }
  
  _loadCallback = loadCallback;
  if (_appRecord.appLoader.status == kEXAppLoaderStatusHasManifestAndBundle) {
    // finish loading immediately (app loader won't call this since it's already done)
    [self appLoaderFinished];
  } else {
    // wait for something else to call `appLoaderFinished` or `appLoaderFailed` later.
  }
}

- (void)appLoaderFinished
{
  __block NSData *data = _appRecord.appLoader.bundle;
  if ([self enablesDeveloperTools]) {
    NSString *utf8Probe = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!utf8Probe) {
      NSURL *bundleURL = [self bundleUrl];
      NSURLComponents *components = [NSURLComponents componentsWithURL:bundleURL resolvingAgainstBaseURL:NO];
      NSMutableArray<NSURLQueryItem *> *items = [components.queryItems mutableCopy] ?: [NSMutableArray array];
      BOOL didUpdate = NO;
      for (NSUInteger i = 0; i < items.count; i++) {
        NSURLQueryItem *item = items[i];
        if ([item.name isEqualToString:@"transform.bytecode"]) {
          items[i] = [NSURLQueryItem queryItemWithName:item.name value:@"0"];
          didUpdate = YES;
          break;
        }
      }
      if (!didUpdate) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"transform.bytecode" value:@"0"]];
      }
      components.queryItems = items;
      NSURL *fallbackURL = components.URL ?: bundleURL;
      NSLog(@"Bloom Log: 92 bundle not UTF-8; retrying with bytecode=0");
      __weak EXReactAppManager *weakSelf = self;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *fallbackData = [NSData dataWithContentsOfURL:fallbackURL];
        dispatch_async(dispatch_get_main_queue(), ^{
          __strong EXReactAppManager *strongSelf = weakSelf;
          if (!strongSelf) {
            return;
          }
          if (fallbackData && fallbackData.length > 0) {
            NSString *fallbackProbe = [[NSString alloc] initWithData:fallbackData encoding:NSUTF8StringEncoding];
            if (fallbackProbe) {
              data = fallbackData;
              NSLog(@"Bloom Log: 93 fetched bytecode=0 bundle size=%lu", (unsigned long)fallbackData.length);
            } else {
              NSLog(@"Bloom Log: 94 bytecode=0 bundle still not UTF-8");
            }
          } else {
            NSLog(@"Bloom Log: 94 failed to fetch bytecode=0 bundle");
          }
          NSData *injectedData = EXInjectBloomInspectorPrelude(data);
          NSLog(@"Bloom Log: 32 injected bundle prelude (pre-check)");
          if (injectedData != data) {
              data = injectedData;
            NSLog(@"Bloom Log: 33 injected bundle prelude (dev tools enabled)");
          }
          if (strongSelf->_loadCallback) {
            strongSelf->_loadCallback(nil, [[RCTSource alloc] initWithURL:[strongSelf bundleUrl] data:data]);
            strongSelf->_loadCallback = nil;
          }
        });
      });
      return;
    }
    NSData *injectedData = EXInjectBloomInspectorPrelude(data);
    NSLog(@"Bloom Log: 32 injected bundle prelude (pre-check)");
    if (injectedData != data) {
      data = injectedData;
      NSLog(@"Bloom Log: 33 injected bundle prelude (dev tools enabled)");
    }
  }
  if (_loadCallback) {
    _loadCallback(nil, [[RCTSource alloc] initWithURL:[self bundleUrl] data:data]);
    _loadCallback = nil;
  }
}

- (void)appLoaderFailedWithError:(NSError *)error
{
  // RN is going to call RCTFatal() on this error, so keep a reference to it for later
  // so we can distinguish this non-fatal error from actual fatal cases.
  if (_appRecord.scopeKey) {
    [[EXKernel sharedInstance].serviceRegistry.errorRecoveryManager setError:error forScopeKey:_appRecord.scopeKey];
  }

  // react won't post this for us
  [[NSNotificationCenter defaultCenter] postNotificationName:RCTJavaScriptDidFailToLoadNotification object:error];

  if (_loadCallback) {
    _loadCallback(error, nil);
    _loadCallback = nil;
  }
}

#pragma mark - JavaScript loading

- (void)_startObservingNotificationsForHost
{
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_handleJavaScriptLoadEvent:)
                                               name:RCTInstanceDidLoadBundle
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_handleJavaScriptLoadEvent:)
                                               name:RCTJavaScriptDidFailToLoadNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_handleReactContentEvent:)
                                               name:RCTContentDidAppearNotification
                                             object:nil];
}

- (void)_stopObservingNotifications
{
  [[NSNotificationCenter defaultCenter] removeObserver:self name:RCTInstanceDidLoadBundle object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:RCTJavaScriptDidFailToLoadNotification object:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:RCTContentDidAppearNotification object:nil];
}

- (void)_handleJavaScriptStartLoadingEvent:(NSNotification *)notification
{
  __weak __typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    __strong __typeof(self) strongSelf = weakSelf;
    if (strongSelf) {
      [strongSelf.delegate reactAppManagerStartedLoadingJavaScript:strongSelf];
    }
  });
}

- (void)_handleJavaScriptLoadEvent:(NSNotification *)notification
{
  if ([notification.name isEqualToString:RCTInstanceDidLoadBundle]) {
    _isReactHostRunning = YES;
    _hasHostEverLoaded = YES;
    [_versionManager hostFinishedLoading:self.reactHost];
    NSDictionary *payload = @{@"message": @"overlay ping after bundle load"};
    if (EXBloomInspectorEmitPing(payload)) {
      NSLog(@"Bloom Log: 41 emitted overlay ping after bundle load");
    } else {
      NSLog(@"Bloom Log: 41 failed to emit overlay ping after bundle load");
    }

    // TODO: temporary solution for hiding LoadingProgressWindow
    if (_appRecord.viewController) {
      EX_WEAKIFY(self);
      dispatch_async(dispatch_get_main_queue(), ^{
        EX_ENSURE_STRONGIFY(self);
        [self->_appRecord.viewController hideLoadingProgressWindow];
      });
    }
  } else if ([notification.name isEqualToString:RCTJavaScriptDidFailToLoadNotification]) {
    NSError *error = (notification.userInfo) ? notification.userInfo[@"error"] : nil;
    if (_appRecord.scopeKey) {
      [[EXKernel sharedInstance].serviceRegistry.errorRecoveryManager setError:error forScopeKey:_appRecord.scopeKey];
    }

    EX_WEAKIFY(self);
    dispatch_async(dispatch_get_main_queue(), ^{
      EX_ENSURE_STRONGIFY(self);
      [self.delegate reactAppManager:self failedToLoadJavaScriptWithError:error];
    });
  }
}

# pragma mark app loading & splash screen

- (void)_handleReactContentEvent:(NSNotification *)notification
{
  if ([notification.name isEqualToString:RCTContentDidAppearNotification]) {
    EX_WEAKIFY(self);
    dispatch_async(dispatch_get_main_queue(), ^{
      EX_ENSURE_STRONGIFY(self);
      [self.delegate reactAppManagerAppContentDidAppear:self];
      [self _appLoadingFinished];
    });
  }
}

- (void)_appLoadingFinished
{
  EX_WEAKIFY(self);
  dispatch_async(dispatch_get_main_queue(), ^{
    EX_ENSURE_STRONGIFY(self);
    if (self.appRecord.scopeKey) {
      [[EXKernel sharedInstance].serviceRegistry.errorRecoveryManager experienceFinishedLoadingWithScopeKey:self.appRecord.scopeKey];
    }
    [self.delegate reactAppManagerFinishedLoadingJavaScript:self];
  });
}

- (void)didReceiveReloadCommand {
  EX_WEAKIFY(self);
  dispatch_async(dispatch_get_main_queue(), ^{
    EX_ENSURE_STRONGIFY(self);
    [self.delegate reactAppManagerAppContentWillReload:self];
  });
}

#pragma mark - dev tools

- (RCTLogFunction)logFunction
{
  return (([self enablesDeveloperTools]) ? EXDeveloperRCTLogFunction : EXDefaultRCTLogFunction);
}

- (RCTLogLevel)logLevel
{
  return ([self enablesDeveloperTools]) ? RCTLogLevelInfo : RCTLogLevelWarning;
}

- (BOOL)enablesDeveloperTools
{
  EXManifestsManifest *manifest = _appRecord.appLoader.manifest;
  if (manifest) {
    return manifest.isUsingDeveloperTool;
  }
  return false;
}

- (BOOL)requiresValidManifests
{
  return YES;
}

- (void)showDevMenu
{
  if ([self enablesDeveloperTools]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.versionManager showDevMenuForHost:self.reactHost];
    });
  }
}

- (void)reloadApp
{
  if ([self enablesDeveloperTools]) {
    RCTTriggerReloadCommandListeners(@"Dev menu - reload");
  }
}

- (void)togglePerformanceMonitor
{
  if ([self enablesDeveloperTools]) {
    [self.versionManager togglePerformanceMonitorForHost:self.reactHost];
  }
}

- (void)toggleElementInspector
{
  if ([self enablesDeveloperTools]) {
    [self.versionManager toggleElementInspectorForHost:self.reactHost];
  }
}

- (void)toggleBloomElementInspector
{
  if ([self enablesDeveloperTools]) {
    [self.versionManager toggleBloomElementInspectorForHost:self.reactHost];
  }
}


- (void)toggleDevMenu
{
  [[EXKernel sharedInstance] switchTasks];
}

- (void)setupWebSocketControls
{
  if ([self enablesDeveloperTools]) {
    if ([_versionManager respondsToSelector:@selector(addWebSocketNotificationHandler:queue:forMethod:)]) {
      __weak __typeof(self) weakSelf = self;

      // Attach listeners to the bundler's dev server web socket connection.
      // This enables tools to automatically reload the client remotely (i.e. in expo-cli).

      // Enable a lot of tools under the same command namespace
      [_versionManager addWebSocketNotificationHandler:^(id params) {
        if (params != [NSNull null] && (NSDictionary *)params) {
          NSDictionary *_params = (NSDictionary *)params;
          if (_params[@"name"] != nil && (NSString *)_params[@"name"]) {
            NSString *name = _params[@"name"];
            if ([name isEqualToString:@"reload"]) {
              [[EXKernel sharedInstance] reloadVisibleApp];
            } else if ([name isEqualToString:@"toggleDevMenu"]) {
              [weakSelf toggleDevMenu];
            } else if ([name isEqualToString:@"toggleElementInspector"]) {
              [weakSelf toggleElementInspector];
            } else if ([name isEqualToString:@"toggleBloomElementInspector"]) {
              [weakSelf toggleBloomElementInspector];
            } else if ([name isEqualToString:@"togglePerformanceMonitor"]) {
              [weakSelf togglePerformanceMonitor];
            }
          }
        }
      }
                                                 queue:dispatch_get_main_queue()
                                             forMethod:@"sendDevCommand"];

      // These (reload and devMenu) are here to match RN dev tooling.

      // Reload the app on "reload"
      [_versionManager addWebSocketNotificationHandler:^(id params) {
        [[EXKernel sharedInstance] reloadVisibleApp];
      }
                                                 queue:dispatch_get_main_queue()
                                             forMethod:@"reload"];

      // Open the dev menu on "devMenu"
      [_versionManager addWebSocketNotificationHandler:^(id params) {
        [weakSelf toggleDevMenu];
      }
                                                 queue:dispatch_get_main_queue()
                                             forMethod:@"devMenu"];
    }
  }
}

- (NSDictionary<NSString *, NSString *> *)devMenuItems
{
  return [self.versionManager devMenuItemsForHost:self.reactHost];
}

- (void)selectDevMenuItemWithKey:(NSString *)key
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.versionManager selectDevMenuItemWithKey:key host:self.reactHost bundleURL:[self bundleUrl]];
  });
}

#pragma mark - RN configuration

- (NSDictionary *)launchOptionsForHost
{
  return @{};
}

- (Class)moduleRegistryDelegateClass
{
  return nil;
}

- (NSString *)applicationKeyForRootView
{
  EXManifestsManifest *manifest = _appRecord.appLoader.manifest;
  if (manifest && manifest.appKey) {
    return manifest.appKey;
  }

  NSURL *bundleUrl = [self bundleUrl];
  if (bundleUrl) {
    NSURLComponents *components = [NSURLComponents componentsWithURL:bundleUrl resolvingAgainstBaseURL:YES];
    NSArray<NSURLQueryItem *> *queryItems = components.queryItems;
    for (NSURLQueryItem *item in queryItems) {
      if ([item.name isEqualToString:@"app"]) {
        return item.value;
      }
    }
  }

  return @"main";
}

- (NSDictionary * _Nullable)initialPropertiesForRootView
{
  NSMutableDictionary *props = [NSMutableDictionary dictionary];
  NSMutableDictionary *expProps = [NSMutableDictionary dictionary];

  NSAssert(_appRecord.scopeKey, @"Experience scope key should be nonnull when getting initial properties for root view");

  NSDictionary *errorRecoveryProps = [[EXKernel sharedInstance].serviceRegistry.errorRecoveryManager developerInfoForScopeKey:_appRecord.scopeKey];
  if ([[EXKernel sharedInstance].serviceRegistry.errorRecoveryManager scopeKeyIsRecoveringFromError:_appRecord.scopeKey]) {
    [[EXKernel sharedInstance].serviceRegistry.errorRecoveryManager increaseAutoReloadBuffer];
    if (errorRecoveryProps) {
      expProps[@"errorRecovery"] = errorRecoveryProps;
    }
  }

  expProps[@"shell"] = @(_appRecord == nil);
  expProps[@"appOwnership"] = @"expo";
  if (_initialProps) {
    [expProps addEntriesFromDictionary:_initialProps];
  }

  NSString *manifestString = nil;
  EXManifestsManifest *manifest = _appRecord.appLoader.manifest;
  if (manifest && [NSJSONSerialization isValidJSONObject:manifest.rawManifestJSON]) {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:manifest.rawManifestJSON options:0 error:&error];
    if (jsonData) {
      manifestString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    } else {
      DDLogWarn(@"Failed to serialize JSON manifest: %@", error);
    }
  }

  expProps[@"manifestString"] = manifestString;
  if (_appRecord.appLoader.manifestUrl) {
    expProps[@"initialUri"] = [_appRecord.appLoader.manifestUrl absoluteString];
  }
  props[@"exp"] = expProps;
  return props;
}

- (NSString *)_executionEnvironment
{
  return EXConstantsExecutionEnvironmentStoreClient;
}

- (NSString *)scopedDocumentDirectory
{
  NSString *scopeKey = _appRecord.scopeKey;
  NSString *mainDocumentDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  NSString *exponentDocumentDirectory = [mainDocumentDirectory stringByAppendingPathComponent:@"ExponentExperienceData"];
  return [[exponentDocumentDirectory stringByAppendingPathComponent:scopeKey] stringByStandardizingPath];
}

- (NSString *)scopedCachesDirectory
{
  NSString *scopeKey = _appRecord.scopeKey;
  NSString *mainCachesDirectory = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
  NSString *exponentCachesDirectory = [mainCachesDirectory stringByAppendingPathComponent:@"ExponentExperienceData"];
  return [[exponentCachesDirectory stringByAppendingPathComponent:scopeKey] stringByStandardizingPath];
}

@end
