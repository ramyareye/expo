#import <Foundation/Foundation.h>
#import <React/RCTEventEmitter.h>
#import <ReactCommon/RCTHost.h>
#import <UIKit/UIKit.h>

@class EXBloomInspectorOverlayViewController;

@interface EXBloomInspectorOverlayManager : NSObject
@property (nonatomic, strong, nullable) UIWindow *window;
@property (nonatomic, strong, nullable) EXBloomInspectorOverlayViewController *viewController;
@property (nonatomic, weak, nullable) UIWindow *previousKeyWindow;
@property (nonatomic, assign, getter=isVisible) BOOL visible;
@property (nonatomic, assign) CGRect panelFrame;
@property (nonatomic, assign) BOOL hasPanelFrame;
+ (instancetype)sharedInstance;
- (void)toggle;
- (void)show;
- (void)hide;
@end

@interface EXBloomInspector : RCTEventEmitter <RCTBridgeModule>
- (void)emitToggle;
- (void)emitTap:(NSDictionary *)payload;
@end

@interface EXBloomInspectorOverlay : RCTEventEmitter <RCTBridgeModule>
- (void)emitPick:(NSDictionary *)payload;
- (void)emitToggle:(BOOL)enabled;
- (void)emitPing:(NSDictionary *)payload;
@end

FOUNDATION_EXTERN id<RCTHostRuntimeDelegate> EXGetBloomInspectorRuntimeDelegate(void);
FOUNDATION_EXTERN BOOL EXBloomInspectorEmitPing(NSDictionary *payload);
