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

// Outline:
// - Runtime injection script + host delegate
// - Overlay window + hit-testing + native fallback payloads
// - Live edit helpers (native apply + text styling)
// - Bridge modules (BloomInspector / BloomInspectorOverlay)

#pragma mark - Configuration

static const BOOL kBloomInspectorDebugLogs = NO;
static const BOOL kBloomInspectorEnableNativeFallback = YES;
#define BLOOM_LOG(...)         \
  do {                         \
    if (kBloomInspectorDebugLogs) { \
      NSLog(__VA_ARGS__);      \
    }                          \
  } while (0)

#pragma mark - Forward declarations

static void EXBloomInspectorApplyNativePropsToReactTag(id host,
                                                       NSNumber *reactTag,
                                                       NSDictionary *props,
                                                       RCTPromiseResolveBlock resolve);
static UIColor *EXBloomInspectorColorFromString(NSString *value);
static UIColor *EXBloomInspectorColorFromNumber(id value);
static NSTextAlignment EXBloomInspectorTextAlignmentFromString(NSString *value);
static NSString *EXBloomInspectorColorToString(UIColor *color);
static NSAttributedString *EXBloomInspectorCopyAttributedText(UIView *view);
static BOOL EXBloomInspectorApplyAttributedText(UIView *view, NSAttributedString *value);
static void EXBloomInspectorForceRedraw(UIView *view);
static NSString *EXBloomInspectorGetPlainTextFromView(UIView *view);
static NSDictionary *EXBloomInspectorRectInfo(CGRect rect);
static UIView *EXBloomInspectorFindTextView(UIView *view);
static NSString *EXBloomInspectorExtractTextOverride(NSDictionary *props);
static BOOL EXBloomInspectorApplyParagraphTextStyle(UIView *view, NSDictionary *style);
static BOOL EXBloomInspectorApplyTextOverrideToView(UIView *view, NSString *textValue);
static void EXBloomInspectorApplyTextStyleToView(UIView *view, NSDictionary *style);
static void EXBloomInspectorApplyUIKitStyleToView(UIView *view, NSDictionary *props, RCTPromiseResolveBlock resolve);

#pragma mark - Runtime script

#include "EXBloomInspectorRuntimeScript.inc"

#pragma mark - Shared state

static NSTimeInterval kBloomInspectorLastJSPickTime = 0;
static const NSTimeInterval kBloomInspectorFallbackDelaySeconds = 0.05;
static const NSTimeInterval kBloomInspectorSuppressWindowSeconds = 1.0;

#pragma mark - Runtime delegate + RCTHost swizzle

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

#pragma mark - Overlay view (hit-testing + selection)

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

#pragma mark - Overlay view controller (React panel + overlay view)

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

#pragma mark - Overlay manager (window lifecycle)

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

#pragma mark - BloomInspector module (tap events)

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

#pragma mark - BloomInspectorOverlay module (panel events + commands)

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

#pragma mark - Live edit helpers

#include "EXBloomInspectorHelpers.inc"

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
