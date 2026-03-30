#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreMedia/CoreMedia.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

#import "../common/CFXShared.h"
#import "CFXSwizzle.h"

@interface NSWindow (CornerFixSharpenerHooks)
- (void)cfx_makeKeyAndOrderFront:(id)sender;
- (void)cfx_orderFront:(id)sender;
- (void)cfx_orderFrontRegardless;
- (void)cfx_setFrame:(NSRect)frameRect display:(BOOL)displayFlag;
- (void)cfx_setStyleMask:(NSWindowStyleMask)styleMask;
- (void)cfx__updateCornerMask;
- (void)cfx__setCornerRadius:(CGFloat)radius;
- (void)cfx__setEffectiveCornerRadius:(CGFloat)radius;
- (CGFloat)cfx__effectiveCornerRadius;
- (CGFloat)cfx__cornerRadius;
- (CGFloat)cfx__topCornerRadius;
- (CGFloat)cfx__bottomCornerRadius;
- (id)cfx_cornerMask;
@end

@interface CornerFixSharpener : NSObject
+ (instancetype)shared;
- (void)start;
- (void)reloadPreferencesAndRefresh;
- (void)applyToWindow:(NSWindow *)window;
- (CGFloat)effectiveRadiusForWindow:(NSWindow *)window;
/// When YES, mirror apple-sharpener: skip system `_updateCornerMask` and use KVC `cornerRadius` instead.
- (BOOL)shouldReplaceSystemCornerMaskForWindow:(NSWindow *)window;
@end

@interface CFXCornerOverlayView : NSView
@property (nonatomic) CGFloat radius;
@end

@interface CFXExternalCornerOverlayView : NSView
@property (nonatomic) CGFloat capSize;
@property (nonatomic, strong, nullable) NSColor *topLeftColor;
@property (nonatomic, strong, nullable) NSColor *topRightColor;
@property (nonatomic, strong, nullable) NSColor *bottomLeftColor;
@property (nonatomic, strong, nullable) NSColor *bottomRightColor;
@property (nonatomic) CGFloat targetInset;
@end

@interface CFXExternalCornerOverlayWindow : NSWindow
@property (nonatomic, strong) CFXExternalCornerOverlayView *overlayView;
@end

static void CFXHandleDarwinNotification(CFNotificationCenterRef center,
                                        void *observer,
                                        CFNotificationName name,
                                        const void *object,
                                        CFDictionaryRef userInfo);

static const void *kCFXOriginalCornerRadiusKey = &kCFXOriginalCornerRadiusKey;
static const void *kCFXOriginalMasksToBoundsKey = &kCFXOriginalMasksToBoundsKey;
static const void *kCFXOverlayViewKey = &kCFXOverlayViewKey;
static const void *kCFXOriginalViewHiddenKey = &kCFXOriginalViewHiddenKey;
static const void *kCFXOriginalHasShadowKey = &kCFXOriginalHasShadowKey;
static const void *kCFXExternalOverlayWindowKey = &kCFXExternalOverlayWindowKey;

static BOOL CFXDebugLoggingEnabled(void) {
    return CFXReadDebugLoggingEnabled() || [NSProcessInfo.processInfo.environment[@"CFX_DEBUG"] boolValue];
}

static NSString *CFXDebugLogFilePath(void) {
    NSString *overridePath = NSProcessInfo.processInfo.environment[@"CFX_DEBUG_LOG_PATH"];
    if (overridePath.length > 0) {
        return overridePath;
    }
    return @"/tmp/CornerFix.debug.log";
}

static void CFXLog(NSString *format, ...) {
    if (!CFXDebugLoggingEnabled()) {
        return;
    }

    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSLog(@"[CornerFix] %@", message);

    NSString *line = [NSString stringWithFormat:@"%@ [CornerFix] %@\n", [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = CFXDebugLogFilePath();
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle == nil) {
        [data writeToFile:path atomically:YES];
        return;
    }

    @try {
        [handle seekToEndOfFile];
        [handle writeData:data];
    } @catch (NSException *exception) {
        (void)exception;
    } @finally {
        [handle closeFile];
    }
}

static uint32_t CFXScreenNumberForWindow(NSWindow *window) {
    NSNumber *number = window.screen.deviceDescription[@"NSScreenNumber"];
    return number != nil ? (uint32_t)number.unsignedIntValue : 0;
}

static NSColor *CFXColorFromCGImage1x1(CGImageRef image) {
    if (image == NULL) {
        return nil;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    if (rep == nil || rep.pixelsWide < 1 || rep.pixelsHigh < 1) {
        return nil;
    }
    return [rep colorAtX:0 y:0];
}

static void CFXSampleBackgroundColorsForWindow(NSWindow *window,
                                               NSArray<NSValue *> *samplePointsInScreenPoints,
                                               void (^completion)(NSArray<NSColor *> *colors)) {
    if (completion == nil) {
        return;
    }
    if (window == nil || samplePointsInScreenPoints.count == 0) {
        completion(@[]);
        return;
    }

    if (@available(macOS 12.3, *)) {
        uint32_t screenNumber = CFXScreenNumberForWindow(window);
        NSNumber *windowNumber = @(window.windowNumber);

        [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent * _Nullable content, NSError * _Nullable error) {
            if (content == nil || error != nil) {
                completion(@[]);
                return;
            }

            SCDisplay *display = nil;
            for (SCDisplay *candidate in content.displays) {
                if ((uint32_t)candidate.displayID == screenNumber) {
                    display = candidate;
                    break;
                }
            }
            if (display == nil) {
                display = content.displays.firstObject;
            }
            if (display == nil) {
                completion(@[]);
                return;
            }

            NSMutableArray<SCWindow *> *excluded = [NSMutableArray array];
            for (SCWindow *w in content.windows) {
                if (w.windowID == windowNumber.unsignedIntValue) {
                    [excluded addObject:w];
                    break;
                }
            }

            SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:excluded];
            SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
            config.width = 1;
            config.height = 1;
            config.queueDepth = 1;
            config.showsCursor = NO;

            dispatch_group_t group = dispatch_group_create();
            NSMutableArray<NSColor *> *results = [NSMutableArray arrayWithCapacity:samplePointsInScreenPoints.count];
            for (NSUInteger i = 0; i < samplePointsInScreenPoints.count; i++) {
                [results addObject:(NSColor *)[NSNull null]];
            }

            CGFloat scale = window.screen.backingScaleFactor > 0.0 ? window.screen.backingScaleFactor : 1.0;

            for (NSUInteger idx = 0; idx < samplePointsInScreenPoints.count; idx++) {
                CGPoint p = samplePointsInScreenPoints[idx].pointValue;
                CGRect rect = CGRectMake(floor(p.x), floor(p.y), 1.0 / scale, 1.0 / scale);
                config.sourceRect = rect;

                dispatch_group_enter(group);
                [SCScreenshotManager captureImageWithFilter:filter configuration:config completionHandler:^(CGImageRef  _Nullable image, NSError * _Nullable capError) {
                    (void)capError;
                    NSColor *c = CFXColorFromCGImage1x1(image);
                    if (c != nil) {
                        results[idx] = c;
                    }
                    dispatch_group_leave(group);
                }];
            }

            dispatch_group_notify(group, dispatch_get_main_queue(), ^{
                // Preserve order (one output per input point).
                NSMutableArray<NSColor *> *colors = [NSMutableArray arrayWithCapacity:results.count];
                for (id obj in results) {
                    if (obj != (id)[NSNull null]) {
                        [colors addObject:(NSColor *)obj];
                    } else {
                        [colors addObject:(NSColor *)[NSNull null]];
                    }
                }
                completion(colors);
            });
        }];
        return;
    }

    completion(@[]);
}

static NSArray<NSString *> *CFXCornerSelectors(void) {
    return @[
        @"setCornerRadius:",
        @"setContinuousCornerRadius:",
        @"_setCornerRadius:",
        @"_setContinuousCornerRadius:",
        @"setContentCornerRadius:",
        @"_setContentCornerRadius:",
        @"setMaskToCorners:",
        @"_setMaskToCorners:",
        // macOS 15+: KVC `cornerRadius` does not drive the compositor; this does (see _effectiveCornerRadius).
        @"_setEffectiveCornerRadius:"
    ];
}

static BOOL CFXInvokeCGFloatSetter(id target, NSString *selectorName, CGFloat value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (target == nil || ![target respondsToSelector:selector]) {
        return NO;
    }

    ((void (*)(id, SEL, CGFloat))objc_msgSend)(target, selector, value);
    return YES;
}

static BOOL CFXInvokeUnsignedSetter(id target, NSString *selectorName, NSUInteger value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (target == nil || ![target respondsToSelector:selector]) {
        return NO;
    }

    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(target, selector, value);
    return YES;
}

static inline BOOL CFXIsStandardAppWindow(NSWindow *window) {
    if (window == nil) { return NO; }
    NSWindowStyleMask mask = window.styleMask;
    if ((mask & NSWindowStyleMaskTitled) == 0) { return NO; }
    if (mask & (NSWindowStyleMaskHUDWindow | NSWindowStyleMaskUtilityWindow)) { return NO; }
    if (window.level != NSNormalWindowLevel) { return NO; }
    NSRect frame = window.frame;
    if (frame.size.width < 100.0 || frame.size.height < 50.0) { return NO; }
    return YES;
}

static void CFXApplyAppleSharpenerStyleCornerRadius(NSWindow *window, CGFloat radius) {
    if (window == nil) { return; }
    if (!CFXIsStandardAppWindow(window)) { return; }
    CGFloat r = MAX(0.0, radius);
    @try {
        [(id)window setValue:@(r) forKey:@"cornerRadius"];
    } @catch (NSException *exception) {
        (void)exception;
    }
    // Confirmed on macOS 15: `cornerRadius` KVC leaves _effectiveCornerRadius at ~16; the private setter does not.
    (void)CFXInvokeCGFloatSetter(window, @"_setEffectiveCornerRadius:", r);
    [window invalidateShadow];
}

/// When CornerFix is disabled for this window, returns -1 (passthrough to original getters).
static CGFloat CFXConfiguredCornerRadiusForHookedGetter(NSWindow *window) {
    return [[CornerFixSharpener shared] effectiveRadiusForWindow:window];
}

/// Resizable corner mask tile used by AppKit for the window silhouette (see public gists / Firefox).
/// Radius 0 yields a square mask so the compositor draws straight edges against the desktop.

static NSImage *CFXCornerMaskImageForRadius(CGFloat cornerRadius) {
    CGFloat r = MAX(0.0, cornerRadius);
    CGFloat dimension = 2.0 * r + 1.0;
    if (dimension < 1.0) {
        dimension = 1.0;
    }
    NSSize size = NSMakeSize(dimension, dimension);
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        NSBezierPath *path = (r <= 0.0)
            ? [NSBezierPath bezierPathWithRect:dstRect]
            : [NSBezierPath bezierPathWithRoundedRect:dstRect xRadius:r yRadius:r];
        [[NSColor blackColor] set];
        [path fill];
        return YES;
    }];
    image.capInsets = NSEdgeInsetsMake(r, r, r, r);
    image.resizingMode = NSImageResizingModeStretch;
    return image;
}

@implementation CornerFixSharpener {
    NSMutableSet<NSWindow *> *_trackedWindows;
    NSString *_bundleIdentifier;
}

+ (instancetype)shared {
    static CornerFixSharpener *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _trackedWindows = [NSMutableSet set];
        _bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: NSProcessInfo.processInfo.processName;
        CFXLog(@"init bundle=%@", _bundleIdentifier);
    }
    return self;
}

- (void)start {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFXLog(@"start bundle=%@", _bundleIdentifier);
        [self installWindowHooks];
        [self installNotifications];
        [self refreshAllWindows];
    });
}

- (void)installWindowHooks {
    CFXLog(@"installWindowHooks");
    CFXSwizzleInstanceMethod([NSWindow class], @selector(makeKeyAndOrderFront:), @selector(cfx_makeKeyAndOrderFront:));
    CFXSwizzleInstanceMethod([NSWindow class], @selector(orderFront:), @selector(cfx_orderFront:));
    CFXSwizzleInstanceMethod([NSWindow class], @selector(orderFrontRegardless), @selector(cfx_orderFrontRegardless));
    CFXSwizzleInstanceMethod([NSWindow class], @selector(setFrame:display:), @selector(cfx_setFrame:display:));
    CFXSwizzleInstanceMethod([NSWindow class], @selector(setStyleMask:), @selector(cfx_setStyleMask:));
    // Mirror apple-sharpener: keep the window's internal corner mask in sync.
    CFXSwizzleInstanceMethod([NSWindow class], NSSelectorFromString(@"_updateCornerMask"), @selector(cfx__updateCornerMask));
    CFXSwizzleInstanceMethod([NSWindow class], NSSelectorFromString(@"_setCornerRadius:"), @selector(cfx__setCornerRadius:));
    CFXSwizzleInstanceMethod([NSWindow class], NSSelectorFromString(@"_setEffectiveCornerRadius:"), @selector(cfx__setEffectiveCornerRadius:));
    if (class_getInstanceMethod([NSWindow class], NSSelectorFromString(@"_effectiveCornerRadius")) != NULL) {
        (void)CFXSwizzleInstanceMethod([NSWindow class], NSSelectorFromString(@"_effectiveCornerRadius"), @selector(cfx__effectiveCornerRadius));
    }
    // Compositor still reads these; they can stay 16 while _effectiveCornerRadius is 0.
    if (class_getInstanceMethod([NSWindow class], NSSelectorFromString(@"_cornerRadius")) != NULL) {
        (void)CFXSwizzleInstanceMethod([NSWindow class], NSSelectorFromString(@"_cornerRadius"), @selector(cfx__cornerRadius));
    }
    if (class_getInstanceMethod([NSWindow class], NSSelectorFromString(@"_topCornerRadius")) != NULL) {
        (void)CFXSwizzleInstanceMethod([NSWindow class], NSSelectorFromString(@"_topCornerRadius"), @selector(cfx__topCornerRadius));
    }
    if (class_getInstanceMethod([NSWindow class], NSSelectorFromString(@"_bottomCornerRadius")) != NULL) {
        (void)CFXSwizzleInstanceMethod([NSWindow class], NSSelectorFromString(@"_bottomCornerRadius"), @selector(cfx__bottomCornerRadius));
    }
    // Compositor uses this mask image for the window outline; KVC alone often leaves rounded desktop edges.
    if (class_getInstanceMethod([NSWindow class], NSSelectorFromString(@"_cornerMask")) != NULL) {
        (void)CFXSwizzleInstanceMethod([NSWindow class], NSSelectorFromString(@"_cornerMask"), @selector(cfx_cornerMask));
    }

    // Mirror apple-sharpener: suppress titlebar decoration drawing when using a custom radius.
    Class titlebarDecorationView = NSClassFromString(@"_NSTitlebarDecorationView");
    if (titlebarDecorationView != Nil) {
        CFXSwizzleInstanceMethod(titlebarDecorationView, @selector(drawRect:), @selector(cfx_cornerfix_drawRect:));
    }
}

- (void)installNotifications {
    CFXLog(@"installNotifications");
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSArray<NSNotificationName> *notifications = @[
        NSWindowDidBecomeKeyNotification,
        NSWindowDidBecomeMainNotification,
        NSWindowDidResizeNotification,
        NSWindowDidMoveNotification,
        NSWindowDidChangeScreenNotification,
        NSWindowDidEnterFullScreenNotification,
        NSWindowDidExitFullScreenNotification,
        NSApplicationDidFinishLaunchingNotification
    ];

    for (NSNotificationName name in notifications) {
        [center addObserver:self selector:@selector(handleWindowNotification:) name:name object:nil];
    }

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)self,
                                    CFXHandleDarwinNotification,
                                    kCFXReloadNotification,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)handleWindowNotification:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        CFXLog(@"notification name=%@ object=%@", notification.name, notification.object);
        if (notification.object != nil && [notification.object isKindOfClass:[NSWindow class]]) {
            [self applyToWindow:(NSWindow *)notification.object];
        } else {
            [self refreshAllWindows];
        }
    });
}

- (void)reloadPreferencesAndRefresh {
    CFXLog(@"reloadPreferencesAndRefresh enabled=%d radius=%.1f debug=%d",
           CFXReadEnabledForBundleIdentifier((__bridge CFStringRef)_bundleIdentifier),
           CFXReadRadiusForBundleIdentifier((__bridge CFStringRef)_bundleIdentifier),
           CFXReadDebugLoggingEnabled());
    [self refreshAllWindows];
}

- (void)refreshAllWindows {
    CFXLog(@"refreshAllWindows count=%lu", (unsigned long)NSApp.windows.count);
    for (NSWindow *window in NSApp.windows) {
        [self applyToWindow:window];
    }
}

- (void)applyToWindow:(NSWindow *)window {
    NSString *skipReason = nil;
    if (![self shouldManageWindow:window reason:&skipReason]) {
        CFXLog(@"skip window=%@ class=%@ reason=%@ frame=%@ level=%ld styleMask=%llu",
               window.title,
               NSStringFromClass(window.class),
               skipReason,
               NSStringFromRect(window.frame),
               (long)window.level,
               (unsigned long long)window.styleMask);
        [self restoreWindowIfNeeded:window];
        return;
    }

    [_trackedWindows addObject:window];

    CGFloat radius = [self effectiveRadiusForWindow:window];
    [self updateShadowForWindow:window radius:radius];
    CFXApplyAppleSharpenerStyleCornerRadius(window, radius < 0.0 ? 0.0 : radius);
    [self applyPrivateCornerControlsToWindow:window radius:radius];
    NSArray<NSView *> *candidateViews = [self candidateViewsForWindow:window];
    CFXLog(@"apply window=%@ class=%@ frame=%@ radius=%.1f candidateViews=%lu",
           window.title,
           NSStringFromClass(window.class),
           NSStringFromRect(window.frame),
           radius,
           (unsigned long)candidateViews.count);

    for (NSView *view in candidateViews) {
        if ([self shouldApplyToView:view forWindow:window]) {
            [self applyRadius:radius toView:view];
        } else if (CFXDebugLoggingEnabled()) {
            CFXLog(@"skipView view=%@ frame=%@",
                   NSStringFromClass(view.class),
                   NSStringFromRect(view.frame));
        }
    }
    [self updateOverlayForWindow:window radius:radius];
    [self updateExternalOverlayForWindow:window radius:radius];
}

- (void)updateShadowForWindow:(NSWindow *)window radius:(CGFloat)radius {
    if (window == nil) {
        return;
    }

    if (objc_getAssociatedObject(window, kCFXOriginalHasShadowKey) == nil) {
        objc_setAssociatedObject(window,
                                 kCFXOriginalHasShadowKey,
                                 @(window.hasShadow),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (radius < 0.0) {
        NSNumber *original = objc_getAssociatedObject(window, kCFXOriginalHasShadowKey);
        if (original != nil) {
            window.hasShadow = original.boolValue;
        }
        return;
    }

    // On newer macOS builds, the shadow can be the last visible "curve" even when the
    // frame is capped to a hard edge. Disable it for radius==0.
    window.hasShadow = (radius > 0.0);
}

- (CGFloat)hardEdgeCapSize {
    NSString *override = NSProcessInfo.processInfo.environment[@"CFX_HARD_EDGE_CAP"];
    CGFloat value = override != nil ? (CGFloat)override.doubleValue : 12.0;
    return value > 1.0 ? value : 12.0;
}

- (void)updateExternalOverlayForWindow:(NSWindow *)window radius:(CGFloat)radius {
    if (window == nil) {
        return;
    }

    // External overlays draw *outside* the real window silhouette. This is the only
    // way to visually square the compositor-level rounding on newer macOS builds,
    // but it looks like "boxes outside" the window. Keep it opt-in.
    BOOL externalEnabled = [NSProcessInfo.processInfo.environment[@"CFX_EXTERNAL_OVERLAY"] boolValue];

    CFXExternalCornerOverlayWindow *overlayWindow = objc_getAssociatedObject(window, kCFXExternalOverlayWindowKey);

    if (!externalEnabled) {
        if (overlayWindow != nil) {
            [overlayWindow orderOut:nil];
            objc_setAssociatedObject(window, kCFXExternalOverlayWindowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            CFXLog(@"externalOverlay removed (disabled) window=%@", window.title);
        }
        return;
    }

    // Only show external overlay for radius==0; it draws outside the window silhouette.
    if (radius != 0.0) {
        if (overlayWindow != nil) {
            [overlayWindow orderOut:nil];
            objc_setAssociatedObject(window, kCFXExternalOverlayWindowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            CFXLog(@"externalOverlay removed window=%@", window.title);
        }
        return;
    }

    CGFloat (^Snap)(CGFloat, CGFloat) = ^CGFloat(CGFloat value, CGFloat scale) {
        if (scale <= 0.0) {
            return value;
        }
        return round(value * scale) / scale;
    };
    NSRect (^SnapRect)(NSRect, CGFloat) = ^NSRect(NSRect rect, CGFloat scale) {
        return NSMakeRect(Snap(rect.origin.x, scale),
                          Snap(rect.origin.y, scale),
                          Snap(rect.size.width, scale),
                          Snap(rect.size.height, scale));
    };

    CGFloat cap = ceil([self hardEdgeCapSize]) + 2.0;
    // Anchor to the theme frame (chrome) rather than window.frame, which can
    // include shadow/margins and cause the external caps to "float" away.
    NSView *themeFrame = window.contentView.superview;
    NSRect targetFrame = window.frame;
    if (themeFrame != nil) {
        NSRect themeInWindow = [themeFrame convertRect:themeFrame.bounds toView:nil];
        targetFrame = [window convertRectToScreen:themeInWindow];
    }

    CGFloat scale = window.screen.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor;
    targetFrame = SnapRect(targetFrame, scale);
    cap = Snap(cap, scale);

    NSRect expandedFrame = NSInsetRect(targetFrame, -cap, -cap);
    expandedFrame = SnapRect(expandedFrame, scale);

    if (CFXDebugLoggingEnabled()) {
        CFXLog(@"externalOverlay frames title=%@ windowFrame=%@ themeFrame=%@ expanded=%@ scale=%.2f cap=%.2f",
               window.title,
               NSStringFromRect(window.frame),
               NSStringFromRect(targetFrame),
               NSStringFromRect(expandedFrame),
               scale,
               cap);
    }

    if (overlayWindow == nil) {
        overlayWindow = [[CFXExternalCornerOverlayWindow alloc] initWithContentRect:expandedFrame
                                                                         styleMask:NSWindowStyleMaskBorderless
                                                                           backing:NSBackingStoreBuffered
                                                                             defer:NO];
        overlayWindow.opaque = NO;
        overlayWindow.backgroundColor = NSColor.clearColor;
        overlayWindow.hasShadow = NO;
        overlayWindow.ignoresMouseEvents = YES;
        overlayWindow.releasedWhenClosed = NO;
        overlayWindow.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                                            NSWindowCollectionBehaviorStationary |
                                            NSWindowCollectionBehaviorIgnoresCycle |
                                            NSWindowCollectionBehaviorFullScreenAuxiliary);

        CFXExternalCornerOverlayView *view = [[CFXExternalCornerOverlayView alloc] initWithFrame:NSMakeRect(0, 0, expandedFrame.size.width, expandedFrame.size.height)];
        view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        view.capSize = cap;
        view.targetInset = cap;
        overlayWindow.contentView = view;
        overlayWindow.overlayView = view;

        objc_setAssociatedObject(window, kCFXExternalOverlayWindowKey, overlayWindow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CFXLog(@"externalOverlay added window=%@", window.title);
    }

    overlayWindow.level = window.level + 1;
    [overlayWindow setFrame:expandedFrame display:YES];
    overlayWindow.overlayView.capSize = cap;
    overlayWindow.overlayView.targetInset = cap;
    [overlayWindow orderFront:nil];

    // ScreenCaptureKit sampling (opt-in) to match pixels behind the window.
    BOOL samplingEnabled = [NSProcessInfo.processInfo.environment[@"CFX_EXTERNAL_SAMPLE"] boolValue];
    if (samplingEnabled) {
        // Sample *just outside* the visible frame we anchored to (`targetFrame`), not window.frame.
        CGFloat sampleOffset = 2.0;
        NSArray<NSValue *> *points = @[
            [NSValue valueWithPoint:NSMakePoint(NSMinX(targetFrame) - sampleOffset, NSMaxY(targetFrame) + sampleOffset)], // TL
            [NSValue valueWithPoint:NSMakePoint(NSMaxX(targetFrame) + sampleOffset, NSMaxY(targetFrame) + sampleOffset)], // TR
            [NSValue valueWithPoint:NSMakePoint(NSMinX(targetFrame) - sampleOffset, NSMinY(targetFrame) - sampleOffset)], // BL
            [NSValue valueWithPoint:NSMakePoint(NSMaxX(targetFrame) + sampleOffset, NSMinY(targetFrame) - sampleOffset)]  // BR
        ];
        CFXSampleBackgroundColorsForWindow(window, points, ^(NSArray<NSColor *> *colors) {
            if (colors.count >= 4) {
                overlayWindow.overlayView.topLeftColor = (colors[0] != (id)[NSNull null]) ? colors[0] : nil;
                overlayWindow.overlayView.topRightColor = (colors[1] != (id)[NSNull null]) ? colors[1] : nil;
                overlayWindow.overlayView.bottomLeftColor = (colors[2] != (id)[NSNull null]) ? colors[2] : nil;
                overlayWindow.overlayView.bottomRightColor = (colors[3] != (id)[NSNull null]) ? colors[3] : nil;
            }
        });
    }
}

- (void)applyPrivateCornerControlsToWindow:(NSWindow *)window radius:(CGFloat)radius {
    if (window == nil) {
        return;
    }

    NSMutableArray<NSString *> *hits = [NSMutableArray array];
    for (NSString *selectorName in CFXCornerSelectors()) {
        @try {
            if (CFXInvokeCGFloatSetter(window, selectorName, radius)) {
                [hits addObject:selectorName];
            } else if (CFXInvokeUnsignedSetter(window, selectorName, radius <= 0.0 ? 0 : NSUIntegerMax)) {
                [hits addObject:selectorName];
            }
        } @catch (NSException *exception) {
            CFXLog(@"privateWindowSelector failed windowClass=%@ selector=%@ exception=%@",
                   NSStringFromClass(window.class),
                   selectorName,
                   exception.reason);
        }
    }

    if (hits.count > 0) {
        CFXLog(@"privateWindowSelectors applied windowClass=%@ selectors=%@ radius=%.1f",
               NSStringFromClass(window.class),
               hits,
               radius);
    }

    [self applyPrivateCornerControlsToWindowInternals:window radius:radius];
    [self applyRadiusToThemeLayersForWindow:window radius:radius];
}

- (id)tryPerformObjectSelector:(NSString *)selectorName onTarget:(id)target {
    if (target == nil || selectorName.length == 0) {
        return nil;
    }

    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) {
        return nil;
    }

    @try {
        return ((id (*)(id, SEL))objc_msgSend)(target, selector);
    } @catch (NSException *exception) {
        CFXLog(@"performObjectSelector failed target=%@ selector=%@ exception=%@",
               NSStringFromClass([target class]),
               selectorName,
               exception.reason);
        return nil;
    }
}

- (void)applyPrivateCornerControlsToWindowInternals:(NSWindow *)window radius:(CGFloat)radius {
    NSArray<NSString *> *internalSelectors = @[
        @"_platformWindow",
        @"platformWindow",
        @"_window",
        @"_nsWindow",
        @"_bridge",
        @"_visualProvider",
        @"_windowBackdropView"
    ];

    for (NSString *selectorName in internalSelectors) {
        id internal = [self tryPerformObjectSelector:selectorName onTarget:window];
        if (internal == nil) {
            continue;
        }

        NSMutableArray<NSString *> *hits = [NSMutableArray array];
        for (NSString *cornerSelector in CFXCornerSelectors()) {
            @try {
                if (CFXInvokeCGFloatSetter(internal, cornerSelector, radius)) {
                    [hits addObject:cornerSelector];
                } else if (CFXInvokeUnsignedSetter(internal, cornerSelector, radius <= 0.0 ? 0 : NSUIntegerMax)) {
                    [hits addObject:cornerSelector];
                }
            } @catch (NSException *exception) {
                CFXLog(@"privateInternalSelector failed internalClass=%@ via=%@ selector=%@ exception=%@",
                       NSStringFromClass([internal class]),
                       selectorName,
                       cornerSelector,
                       exception.reason);
            }
        }

        if (hits.count > 0) {
            CFXLog(@"privateInternalSelectors applied internalClass=%@ via=%@ selectors=%@ radius=%.1f",
                   NSStringFromClass([internal class]),
                   selectorName,
                   hits,
                   radius);
        } else if (CFXDebugLoggingEnabled()) {
            CFXLog(@"internalFound internalClass=%@ via=%@ (no corner selectors)",
                   NSStringFromClass([internal class]),
                   selectorName);
        }
    }
}

- (void)applyRadiusToThemeLayersForWindow:(NSWindow *)window radius:(CGFloat)radius {
    NSView *themeFrame = window.contentView.superview;
    if (themeFrame == nil) {
        return;
    }

    themeFrame.wantsLayer = YES;
    CALayer *root = themeFrame.layer;
    if (root == nil) {
        return;
    }

    NSMutableArray<CALayer *> *stack = [NSMutableArray arrayWithObject:root];
    NSUInteger visited = 0;
    while (stack.count > 0 && visited < 64) {
        CALayer *layer = stack.lastObject;
        [stack removeLastObject];
        visited += 1;

        CGRect bounds = layer.bounds;
        NSString *layerClassName = NSStringFromClass(layer.class);
        BOOL bigEnough = bounds.size.width >= 120.0 && bounds.size.height >= 20.0;
        BOOL chromeSized = bounds.size.height <= 90.0 || layer == root;
        BOOL chromeClass = ([layerClassName containsString:@"WindowFrame"] ||
                            [layerClassName containsString:@"Backdrop"] ||
                            [layerClassName containsString:@"Chameleon"] ||
                            [layerClassName containsString:@"Portal"] ||
                            [layerClassName containsString:@"VisualEffect"] ||
                            [layerClassName containsString:@"Titlebar"] ||
                            layer == root);

        if (bigEnough && chromeSized && chromeClass) {
            layer.cornerCurve = kCACornerCurveCircular;
            layer.cornerRadius = radius < 0.0 ? 0.0 : radius;
            layer.masksToBounds = (radius > 0.0);
            [self applyPrivateCornerControlsToLayer:layer radius:radius];
            if (CFXDebugLoggingEnabled()) {
                CFXLog(@"applyLayerRadius layer=%@ cornerRadius=%.1f masksToBounds=%d bounds=%@",
                       layerClassName,
                       layer.cornerRadius,
                       layer.masksToBounds,
                       NSStringFromRect(NSRectFromCGRect(bounds)));
            }
        }

        for (CALayer *sublayer in layer.sublayers) {
            if (sublayer != nil) {
                [stack addObject:sublayer];
            }
        }
    }
}

- (BOOL)shouldManageWindow:(NSWindow *)window reason:(NSString **)reason {
    if (window == nil) {
        if (reason != NULL) { *reason = @"nil-window"; }
        return NO;
    }
    if (window.styleMask == NSWindowStyleMaskBorderless) {
        if (reason != NULL) { *reason = @"borderless"; }
        return NO;
    }
    if ((window.styleMask & NSWindowStyleMaskTitled) == 0) {
        if (reason != NULL) { *reason = @"not-titled"; }
        return NO;
    }
    if (window.level != NSNormalWindowLevel) {
        if (reason != NULL) { *reason = [NSString stringWithFormat:@"window-level-%ld", (long)window.level]; }
        return NO;
    }
    if (window.sheetParent != nil) {
        if (reason != NULL) { *reason = @"sheet-child"; }
        return NO;
    }
    if (window.frame.size.width < 120.0 || window.frame.size.height < 120.0) {
        if (reason != NULL) { *reason = @"too-small"; }
        return NO;
    }

    NSString *className = NSStringFromClass(window.class);
    NSArray<NSString *> *excludedClassFragments = @[
        @"NSStatusBarWindow",
        @"NSCarbonMenuWindow",
        @"NSPopover",
        @"NSMenu",
        @"_NSFullScreenUnbufferedWindow",
        @"NSDock",
        @"NSPanel"
    ];
    for (NSString *fragment in excludedClassFragments) {
        if ([className containsString:fragment]) {
            if (reason != NULL) { *reason = [NSString stringWithFormat:@"excluded-class-%@", fragment]; }
            return NO;
        }
    }

    if (reason != NULL) { *reason = @"accepted"; }
    return YES;
}

- (CGFloat)effectiveRadiusForWindow:(NSWindow *)window {
    if (!CFXReadEnabledForBundleIdentifier((__bridge CFStringRef)_bundleIdentifier)) {
        return -1.0;
    }
    if ((window.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen) {
        return 0.0;
    }
    return (CGFloat)CFXReadRadiusForBundleIdentifier((__bridge CFStringRef)_bundleIdentifier);
}

- (BOOL)shouldReplaceSystemCornerMaskForWindow:(NSWindow *)window {
    if ([self effectiveRadiusForWindow:window] < 0.0) {
        return NO;
    }
    NSString *reason = nil;
    if (![self shouldManageWindow:window reason:&reason]) {
        return NO;
    }
    // Same window shape filter as KVC path (apple-sharpener’s `isStandardAppWindow`).
    return CFXIsStandardAppWindow(window);
}

- (NSArray<NSView *> *)candidateViewsForWindow:(NSWindow *)window {
    NSMutableOrderedSet<NSView *> *views = [NSMutableOrderedSet orderedSet];
    NSView *contentView = window.contentView;
    if (contentView != nil) {
        // Avoid rounding arbitrary app content (controls, labels, etc). We only want to
        // influence the system-managed window chrome.
        [views addObject:contentView];
        NSView *ancestor = contentView.superview;
        NSUInteger depth = 0;
        while (ancestor != nil && depth < 8) {
            [views addObject:ancestor];
            ancestor = ancestor.superview;
            depth += 1;
        }
    }

    NSView *container = window.contentView.superview;
    if (container != nil) {
        for (NSView *view in container.subviews) {
            NSString *name = NSStringFromClass(view.class);
            if ([name containsString:@"Theme"] || [name containsString:@"Title"] || [name containsString:@"Frame"] || [name containsString:@"Container"]) {
                [views addObject:view];
            }
        }
    }
    if (CFXDebugLoggingEnabled()) {
        NSMutableArray<NSString *> *viewDescriptions = [NSMutableArray array];
        for (NSView *view in views.array) {
            [viewDescriptions addObject:[NSString stringWithFormat:@"%@ frame=%@ wantsLayer=%d",
                                         NSStringFromClass(view.class),
                                         NSStringFromRect(view.frame),
                                         view.wantsLayer]];
        }
        CFXLog(@"candidateViews bundle=%@ views=%@", _bundleIdentifier, viewDescriptions);
    }
    return views.array;
}

- (BOOL)shouldApplyToView:(NSView *)view forWindow:(NSWindow *)window {
    if (view == nil || window == nil) {
        return NO;
    }

    NSString *className = NSStringFromClass(view.class);

    // Never touch the window control widgets / titlebar buttons.
    NSArray<NSString *> *excludedFragments = @[
        @"Widget",
        @"Button",
        @"TextField",
        @"Segment",
        @"Toolbar",
        @"TouchBar"
    ];
    for (NSString *fragment in excludedFragments) {
        if ([className containsString:fragment]) {
            return NO;
        }
    }
    if ([className hasPrefix:@"_NSTheme"] && ![className containsString:@"Frame"]) {
        return NO;
    }

    // Prefer large, chrome-like containers.
    NSSize size = view.bounds.size;
    if (size.width < 120.0 || size.height < 32.0) {
        return NO;
    }

    NSView *themeFrame = window.contentView.superview;
    if (view == themeFrame) {
        return YES;
    }
    if ([className containsString:@"ThemeFrame"] ||
        [className containsString:@"Titlebar"] ||
        [className containsString:@"VisualEffect"] ||
        [className containsString:@"Backdrop"]) {
        return YES;
    }

    return NO;
}

- (void)collectViewSubtree:(NSView *)view intoOrderedSet:(NSMutableOrderedSet<NSView *> *)views depth:(NSUInteger)depth maxDepth:(NSUInteger)maxDepth {
    if (view == nil || depth > maxDepth) {
        return;
    }
    [views addObject:view];
    for (NSView *subview in view.subviews) {
        [self collectViewSubtree:subview intoOrderedSet:views depth:depth + 1 maxDepth:maxDepth];
    }
}

- (void)logViewTreeForWindow:(NSWindow *)window {
    if (!CFXDebugLoggingEnabled()) {
        return;
    }
    NSView *root = window.contentView.superview ?: window.contentView;
    if (root == nil) {
        return;
    }
    CFXLog(@"viewTree window=%@ begin", window.title);
    [self logView:root depth:0];
    CFXLog(@"viewTree window=%@ end", window.title);
}

- (void)logView:(NSView *)view depth:(NSUInteger)depth {
    NSMutableString *indent = [NSMutableString string];
    for (NSUInteger i = 0; i < depth; i++) {
        [indent appendString:@"  "];
    }
    CFXLog(@"%@view=%@ frame=%@ wantsLayer=%d subviews=%lu",
           indent,
           NSStringFromClass(view.class),
           NSStringFromRect(view.frame),
           view.wantsLayer,
           (unsigned long)view.subviews.count);
    if (view.layer != nil) {
        CFXLog(@"%@layer=%@ cornerRadius=%.1f masksToBounds=%d bounds=%@",
               indent,
               NSStringFromClass(view.layer.class),
               view.layer.cornerRadius,
               view.layer.masksToBounds,
               NSStringFromRect(NSRectFromCGRect(view.layer.bounds)));
    }
    for (NSView *subview in view.subviews) {
        [self logView:subview depth:depth + 1];
    }
}

- (void)applyRadius:(CGFloat)radius toView:(NSView *)view {
    view.wantsLayer = YES;
    CALayer *layer = view.layer;
    if (layer == nil) {
        CFXLog(@"applyRadius skipped view=%@ no-layer", NSStringFromClass(view.class));
        return;
    }

    if (objc_getAssociatedObject(layer, kCFXOriginalCornerRadiusKey) == nil) {
        objc_setAssociatedObject(layer,
                                 kCFXOriginalCornerRadiusKey,
                                 @(layer.cornerRadius),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(layer,
                                 kCFXOriginalMasksToBoundsKey,
                                 @(layer.masksToBounds),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (radius < 0.0) {
        NSNumber *originalRadius = objc_getAssociatedObject(layer, kCFXOriginalCornerRadiusKey);
        NSNumber *originalMasksToBounds = objc_getAssociatedObject(layer, kCFXOriginalMasksToBoundsKey);
        layer.cornerRadius = originalRadius != nil ? originalRadius.doubleValue : 0.0;
        layer.masksToBounds = originalMasksToBounds != nil ? originalMasksToBounds.boolValue : NO;
        CFXLog(@"restore view=%@ cornerRadius=%.1f masksToBounds=%d",
               NSStringFromClass(view.class),
               layer.cornerRadius,
               layer.masksToBounds);
        return;
    }

    layer.cornerCurve = kCACornerCurveCircular;
    layer.cornerRadius = radius;
    layer.masksToBounds = YES;
    CFXLog(@"applyRadius view=%@ frame=%@ cornerRadius=%.1f masksToBounds=%d",
           NSStringFromClass(view.class),
           NSStringFromRect(view.frame),
           layer.cornerRadius,
           layer.masksToBounds);

    [self applyPrivateCornerControlsToView:view radius:radius];
    [self applyPrivateCornerControlsToLayer:layer radius:radius];
    [self tweakRenderChainForView:view radius:radius];
}

- (void)applyPrivateCornerControlsToView:(NSView *)view radius:(CGFloat)radius {
    NSMutableArray<NSString *> *hits = [NSMutableArray array];
    for (NSString *selectorName in CFXCornerSelectors()) {
        @try {
            if (CFXInvokeCGFloatSetter(view, selectorName, radius)) {
                [hits addObject:selectorName];
            } else if (CFXInvokeUnsignedSetter(view, selectorName, radius <= 0.0 ? 0 : NSUIntegerMax)) {
                [hits addObject:selectorName];
            }
        } @catch (NSException *exception) {
            CFXLog(@"privateViewSelector failed view=%@ selector=%@ exception=%@",
                   NSStringFromClass(view.class),
                   selectorName,
                   exception.reason);
        }
    }
    if (hits.count > 0) {
        CFXLog(@"privateViewSelectors applied view=%@ selectors=%@ radius=%.1f",
               NSStringFromClass(view.class),
               hits,
               radius);
    }
}

- (void)applyPrivateCornerControlsToLayer:(CALayer *)layer radius:(CGFloat)radius {
    NSMutableArray<NSString *> *hits = [NSMutableArray array];
    for (NSString *selectorName in CFXCornerSelectors()) {
        @try {
            if (CFXInvokeCGFloatSetter(layer, selectorName, radius)) {
                [hits addObject:selectorName];
            } else if (CFXInvokeUnsignedSetter(layer, selectorName, radius <= 0.0 ? 0 : NSUIntegerMax)) {
                [hits addObject:selectorName];
            }
        } @catch (NSException *exception) {
            CFXLog(@"privateLayerSelector failed layer=%@ selector=%@ exception=%@",
                   NSStringFromClass(layer.class),
                   selectorName,
                   exception.reason);
        }
    }
    if (hits.count > 0) {
        CFXLog(@"privateLayerSelectors applied layer=%@ selectors=%@ radius=%.1f",
               NSStringFromClass(layer.class),
               hits,
               radius);
    }
}

- (void)tweakRenderChainForView:(NSView *)view radius:(CGFloat)radius {
    if (radius > 0.0) {
        if (objc_getAssociatedObject(view, kCFXOriginalViewHiddenKey) == nil) {
            objc_setAssociatedObject(view, kCFXOriginalViewHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSString *className = NSStringFromClass(view.class);
        if ([className containsString:@"VisualEffect"] || [className containsString:@"Titlebar"]) {
            view.layer.masksToBounds = YES;
        }
        return;
    }

    NSNumber *originalHidden = objc_getAssociatedObject(view, kCFXOriginalViewHiddenKey);
    if (originalHidden != nil) {
        view.hidden = originalHidden.boolValue;
    }
}

- (void)updateOverlayForWindow:(NSWindow *)window radius:(CGFloat)radius {
    NSView *themeFrame = window.contentView.superview;
    if (themeFrame == nil) {
        return;
    }

    CFXCornerOverlayView *overlay = objc_getAssociatedObject(window, kCFXOverlayViewKey);
    // Even at radius==0, newer macOS builds may keep a small minimum rounding.
    // Use an overlay to "cap" the corners into a hard edge when requested.
    BOOL shouldShow = (radius >= 0.0);
    if (!shouldShow) {
        if (overlay != nil) {
            [overlay removeFromSuperview];
            objc_setAssociatedObject(window, kCFXOverlayViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            CFXLog(@"overlay removed window=%@", window.title);
        }
        return;
    }

    if (overlay == nil) {
        overlay = [[CFXCornerOverlayView alloc] initWithFrame:themeFrame.bounds];
        overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        overlay.translatesAutoresizingMaskIntoConstraints = YES;
        [themeFrame addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
        objc_setAssociatedObject(window, kCFXOverlayViewKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CFXLog(@"overlay added window=%@", window.title);
    }

    overlay.frame = themeFrame.bounds;
    // If radius==0, draw a small cap to eliminate any residual system rounding.
    // Tunable via env var for different macOS builds.
    CGFloat cap = radius;
    if (cap <= 0.0) {
        NSString *override = NSProcessInfo.processInfo.environment[@"CFX_HARD_EDGE_CAP"];
        CGFloat value = override != nil ? (CGFloat)override.doubleValue : 12.0;
        cap = value > 1.0 ? value : 12.0;
    }
    overlay.radius = cap;
    overlay.hidden = NO;
    overlay.needsDisplay = YES;
    CFXLog(@"overlay updated window=%@ capRadius=%.1f requestedRadius=%.1f frame=%@", window.title, cap, radius, NSStringFromRect(overlay.frame));
}

- (void)restoreWindowIfNeeded:(NSWindow *)window {
    if (![_trackedWindows containsObject:window]) {
        return;
    }

    CFXLog(@"restoreWindow window=%@", window.title);
    [self updateShadowForWindow:window radius:-1.0];
    for (NSView *view in [self candidateViewsForWindow:window]) {
        [self applyRadius:-1.0 toView:view];
    }
    [self updateOverlayForWindow:window radius:-1.0];
    [self updateExternalOverlayForWindow:window radius:-1.0];
    [_trackedWindows removeObject:window];
}

@end

static void CFXHandleDarwinNotification(CFNotificationCenterRef center,
                                        void *observer,
                                        CFNotificationName name,
                                        const void *object,
                                        CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    CFXLog(@"received Darwin reload notification");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CornerFixSharpener shared] reloadPreferencesAndRefresh];
    });
}

@implementation NSWindow (CornerFixSharpenerHooks)

- (void)cfx_makeKeyAndOrderFront:(id)sender {
    [self cfx_makeKeyAndOrderFront:sender];
    [[CornerFixSharpener shared] logViewTreeForWindow:self];
    [[CornerFixSharpener shared] applyToWindow:self];
}

- (void)cfx_orderFront:(id)sender {
    [self cfx_orderFront:sender];
    [[CornerFixSharpener shared] logViewTreeForWindow:self];
    [[CornerFixSharpener shared] applyToWindow:self];
}

- (void)cfx_orderFrontRegardless {
    [self cfx_orderFrontRegardless];
    [[CornerFixSharpener shared] logViewTreeForWindow:self];
    [[CornerFixSharpener shared] applyToWindow:self];
}

- (void)cfx_setFrame:(NSRect)frameRect display:(BOOL)displayFlag {
    [self cfx_setFrame:frameRect display:displayFlag];
    [[CornerFixSharpener shared] applyToWindow:self];
}

- (void)cfx_setStyleMask:(NSWindowStyleMask)styleMask {
    [self cfx_setStyleMask:styleMask];
    [[CornerFixSharpener shared] applyToWindow:self];
}

- (void)cfx__updateCornerMask {
    CornerFixSharpener *sharpener = [CornerFixSharpener shared];
    // apple-sharpener: when active, do *not* call the original `_updateCornerMask` — it reapplies
    // the default rounded compositor mask and undoes KVC `cornerRadius`. Only push our radius.
    if ([sharpener shouldReplaceSystemCornerMaskForWindow:self]) {
        CGFloat r = [sharpener effectiveRadiusForWindow:self];
        CFXApplyAppleSharpenerStyleCornerRadius(self, r);
        return;
    }
    [self cfx__updateCornerMask];
}

- (void)cfx__setCornerRadius:(CGFloat)radius {
    CGFloat effective = [[CornerFixSharpener shared] effectiveRadiusForWindow:self];
    if (effective < 0.0) {
        [self cfx__setCornerRadius:radius];
        return;
    }
    if ((self.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen) {
        [self cfx__setCornerRadius:0.0];
        return;
    }
    [self cfx__setCornerRadius:effective];
}

- (void)cfx__setEffectiveCornerRadius:(CGFloat)radius {
    CGFloat effective = [[CornerFixSharpener shared] effectiveRadiusForWindow:self];
    if (effective < 0.0) {
        [self cfx__setEffectiveCornerRadius:radius];
        return;
    }
    if ((self.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen) {
        [self cfx__setEffectiveCornerRadius:0.0];
        return;
    }
    [self cfx__setEffectiveCornerRadius:effective];
}

- (CGFloat)cfx__effectiveCornerRadius {
    CGFloat configured = CFXConfiguredCornerRadiusForHookedGetter(self);
    if (configured < 0.0) {
        return [self cfx__effectiveCornerRadius];
    }
    return configured;
}

- (CGFloat)cfx__cornerRadius {
    CGFloat configured = CFXConfiguredCornerRadiusForHookedGetter(self);
    if (configured < 0.0) {
        return [self cfx__cornerRadius];
    }
    return configured;
}

- (CGFloat)cfx__topCornerRadius {
    CGFloat configured = CFXConfiguredCornerRadiusForHookedGetter(self);
    if (configured < 0.0) {
        return [self cfx__topCornerRadius];
    }
    return configured;
}

- (CGFloat)cfx__bottomCornerRadius {
    CGFloat configured = CFXConfiguredCornerRadiusForHookedGetter(self);
    if (configured < 0.0) {
        return [self cfx__bottomCornerRadius];
    }
    return configured;
}

- (id)cfx_cornerMask {
    if ((self.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen) {
        return [self cfx_cornerMask];
    }
    CornerFixSharpener *sharpener = [CornerFixSharpener shared];
    if ([sharpener shouldReplaceSystemCornerMaskForWindow:self]) {
        CGFloat r = [sharpener effectiveRadiusForWindow:self];
        return CFXCornerMaskImageForRadius(r < 0.0 ? 0.0 : r);
    }
    return [self cfx_cornerMask];
}

@end

@implementation NSView (CornerFixTitlebarDecorationHook)

- (void)cfx_cornerfix_drawRect:(NSRect)dirtyRect {
    // Mirror apple-sharpener: suppress decoration drawing when using a non-zero custom radius.
    NSWindow *window = self.window;
    CGFloat radius = window != nil ? [[CornerFixSharpener shared] effectiveRadiusForWindow:window] : -1.0;
    if (window != nil && radius > 0.0 && CFXIsStandardAppWindow(window)) {
        return;
    }
    [self cfx_cornerfix_drawRect:dirtyRect];
}

@end

__attribute__((constructor))
static void CornerFixSharpenerInitialize(void) {
    CFXLog(@"constructor loaded process=%@ bundle=%@",
           NSProcessInfo.processInfo.processName,
           NSBundle.mainBundle.bundleIdentifier ?: @"(none)");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CornerFixSharpener shared] start];
    });
}

@implementation CFXCornerOverlayView

- (BOOL)isOpaque {
    return NO;
}

- (NSRect)trafficLightsExclusionRectInLocalCoordsWithPadding:(CGFloat)padding {
    NSWindow *window = self.window;
    if (window == nil) {
        return NSZeroRect;
    }

    NSButton *close = [window standardWindowButton:NSWindowCloseButton];
    NSButton *mini = [window standardWindowButton:NSWindowMiniaturizeButton];
    NSButton *zoom = [window standardWindowButton:NSWindowZoomButton];
    if (close == nil || mini == nil || zoom == nil) {
        return NSZeroRect;
    }

    NSRect unionRect = NSUnionRect(close.frame, NSUnionRect(mini.frame, zoom.frame));
    // These frames are in the standard button container's coordinate space.
    // Convert directly into our overlay (themeFrame) coordinate space.
    NSView *container = close.superview;
    if (container == nil) {
        return NSZeroRect;
    }

    NSRect inLocal = [self convertRect:unionRect fromView:container];
    return NSInsetRect(inLocal, -padding, -padding);
}

- (void)setRadius:(CGFloat)radius {
    _radius = radius;
    self.needsDisplay = YES;
}

- (NSArray<NSValue *> *)rectsBySubtractingRect:(NSRect)cutout fromRect:(NSRect)rect {
    if (NSIsEmptyRect(cutout) || !NSIntersectsRect(rect, cutout)) {
        return @[[NSValue valueWithRect:rect]];
    }

    NSRect intersection = NSIntersectionRect(rect, cutout);
    if (NSIsEmptyRect(intersection)) {
        return @[[NSValue valueWithRect:rect]];
    }

    NSMutableArray<NSValue *> *pieces = [NSMutableArray array];

    // Above intersection
    if (NSMaxY(intersection) < NSMaxY(rect)) {
        [pieces addObject:[NSValue valueWithRect:NSMakeRect(NSMinX(rect),
                                                           NSMaxY(intersection),
                                                           NSWidth(rect),
                                                           NSMaxY(rect) - NSMaxY(intersection))]];
    }
    // Below intersection
    if (NSMinY(intersection) > NSMinY(rect)) {
        [pieces addObject:[NSValue valueWithRect:NSMakeRect(NSMinX(rect),
                                                           NSMinY(rect),
                                                           NSWidth(rect),
                                                           NSMinY(intersection) - NSMinY(rect))]];
    }
    // Left of intersection
    if (NSMinX(intersection) > NSMinX(rect)) {
        [pieces addObject:[NSValue valueWithRect:NSMakeRect(NSMinX(rect),
                                                           NSMinY(intersection),
                                                           NSMinX(intersection) - NSMinX(rect),
                                                           NSHeight(intersection))]];
    }
    // Right of intersection
    if (NSMaxX(intersection) < NSMaxX(rect)) {
        [pieces addObject:[NSValue valueWithRect:NSMakeRect(NSMaxX(intersection),
                                                           NSMinY(intersection),
                                                           NSMaxX(rect) - NSMaxX(intersection),
                                                           NSHeight(intersection))]];
    }

    // Filter any degenerate rects.
    NSIndexSet *bad = [pieces indexesOfObjectsPassingTest:^BOOL(NSValue * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)idx; (void)stop;
        NSRect r = obj.rectValue;
        return (NSWidth(r) <= 0.5 || NSHeight(r) <= 0.5);
    }];
    if (bad.count > 0) {
        [pieces removeObjectsAtIndexes:bad];
    }

    return pieces;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (self.radius <= 0.0) {
        return;
    }

    NSGraphicsContext *context = NSGraphicsContext.currentContext;
    BOOL oldAA = context.shouldAntialias;
    context.shouldAntialias = NO;

    // Match the system frame fill as closely as possible.
    NSColor *fill = [NSColor windowBackgroundColor];
    [fill setFill];

    // Slightly overdraw to avoid a 1px anti-aliased fringe.
    CGFloat r = ceil(self.radius) + 2.0;
    NSRect bounds = self.bounds;

    // Avoid clipping the traffic-light buttons by punching out their area.
    NSRect exclude = [self trafficLightsExclusionRectInLocalCoordsWithPadding:6.0];

    void (^FillCapRectWithExclusion)(NSRect) = ^(NSRect capRect) {
        for (NSValue *value in [self rectsBySubtractingRect:exclude fromRect:capRect]) {
            NSRectFill(value.rectValue);
        }
    };

    // System titlebar draws a 1px hairline across the top; corner caps only paint the corners, so the
    // line looks "broken" near the top-right (cap covers the end, rest of edge still shows the line).
    CGFloat scale = self.window.backingScaleFactor > 0.0 ? self.window.backingScaleFactor : 1.0;
    CGFloat topBand = MAX(2.0, 2.0 / scale + 1.0);
    NSRect topEdgeBand = NSMakeRect(0.0, NSMaxY(bounds) - topBand, NSWidth(bounds), topBand);
    FillCapRectWithExclusion(topEdgeBand);

    // Top-left, top-right, bottom-left, bottom-right
    FillCapRectWithExclusion(NSMakeRect(0, NSMaxY(bounds) - r, r, r));
    FillCapRectWithExclusion(NSMakeRect(NSMaxX(bounds) - r, NSMaxY(bounds) - r, r, r));
    FillCapRectWithExclusion(NSMakeRect(0, 0, r, r));
    FillCapRectWithExclusion(NSMakeRect(NSMaxX(bounds) - r, 0, r, r));

    context.shouldAntialias = oldAA;
}

@end

@implementation CFXExternalCornerOverlayWindow
@end

@implementation CFXExternalCornerOverlayView

- (BOOL)isOpaque {
    return NO;
}

- (void)layout {
    [super layout];
    [self cfx_updateMask];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;

        NSVisualEffectView *effectView = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
        effectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        effectView.state = NSVisualEffectStateActive;
        if (@available(macOS 10.14, *)) {
            NSString *materialOverride = NSProcessInfo.processInfo.environment[@"CFX_EXTERNAL_MATERIAL"];
            if ([materialOverride isEqualToString:@"sidebar"]) {
                effectView.material = NSVisualEffectMaterialSidebar;
            } else if ([materialOverride isEqualToString:@"hud"]) {
                effectView.material = NSVisualEffectMaterialHUDWindow;
            } else if ([materialOverride isEqualToString:@"menu"]) {
                effectView.material = NSVisualEffectMaterialMenu;
            } else {
                effectView.material = NSVisualEffectMaterialUnderWindowBackground;
            }
        }
        [self addSubview:effectView];

        // Store as layer name lookup to avoid adding ivars.
        effectView.layer.name = @"CFXEffectLayer";
        [self cfx_updateMask];
    }
    return self;
}

- (void)setCapSize:(CGFloat)capSize {
    _capSize = capSize;
    self.needsDisplay = YES;
    [self cfx_updateMask];
}

- (void)setTopLeftColor:(NSColor *)topLeftColor { _topLeftColor = topLeftColor; self.needsDisplay = YES; }
- (void)setTopRightColor:(NSColor *)topRightColor { _topRightColor = topRightColor; self.needsDisplay = YES; }
- (void)setBottomLeftColor:(NSColor *)bottomLeftColor { _bottomLeftColor = bottomLeftColor; self.needsDisplay = YES; }
- (void)setBottomRightColor:(NSColor *)bottomRightColor { _bottomRightColor = bottomRightColor; self.needsDisplay = YES; }

- (void)setTargetInset:(CGFloat)targetInset {
    _targetInset = targetInset;
    self.needsDisplay = YES;
    [self cfx_updateMask];
}

- (NSVisualEffectView *)cfx_effectView {
    for (NSView *subview in self.subviews) {
        if ([subview isKindOfClass:[NSVisualEffectView class]]) {
            return (NSVisualEffectView *)subview;
        }
    }
    return nil;
}

- (void)cfx_updateMask {
    NSVisualEffectView *effectView = [self cfx_effectView];
    if (effectView == nil) {
        return;
    }

    effectView.wantsLayer = YES;

    CGFloat c = ceil(self.capSize);
    if (c <= 1.0) {
        effectView.layer.mask = nil;
        return;
    }

    // Keep the visible blur area minimal so it doesn't look like big boxes.
    CGFloat strip = 3.0;
    NSString *stripOverride = NSProcessInfo.processInfo.environment[@"CFX_EXTERNAL_STRIP"];
    if (stripOverride.length > 0) {
        strip = MAX(1.0, (CGFloat)stripOverride.doubleValue);
    }

    CGFloat inset = MAX(0.0, self.targetInset);
    NSRect b = self.bounds;
    NSRect target = NSInsetRect(b, inset, inset);
    CGFloat tx0 = NSMinX(target);
    CGFloat ty0 = NSMinY(target);
    CGFloat tx1 = NSMaxX(target);
    CGFloat ty1 = NSMaxY(target);

    // Build a path containing the 4 L-shaped cap regions.
    CGMutablePathRef path = CGPathCreateMutable();

    // Helper to add a rect.
    void (^AddRect)(CGRect) = ^(CGRect r) {
        if (r.size.width <= 0.0 || r.size.height <= 0.0) { return; }
        CGPathAddRect(path, NULL, r);
    };

    // Top-left: square + top strip + left strip
    AddRect(CGRectMake(tx0 - c, ty1, c, c));
    AddRect(CGRectMake(tx0, ty1, c, strip));
    AddRect(CGRectMake(tx0 - strip, ty1 - c, strip, c));

    // Top-right
    AddRect(CGRectMake(tx1, ty1, c, c));
    AddRect(CGRectMake(tx1 - c, ty1, c, strip));
    AddRect(CGRectMake(tx1, ty1 - c, strip, c));

    // Bottom-left
    AddRect(CGRectMake(tx0 - c, ty0 - c, c, c));
    AddRect(CGRectMake(tx0, ty0 - strip, c, strip));
    AddRect(CGRectMake(tx0 - strip, ty0, strip, c));

    // Bottom-right
    AddRect(CGRectMake(tx1, ty0 - c, c, c));
    AddRect(CGRectMake(tx1 - c, ty0 - strip, c, strip));
    AddRect(CGRectMake(tx1, ty0, strip, c));

    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.frame = effectView.bounds;
    mask.path = path;
    mask.fillColor = NSColor.blackColor.CGColor;
    CGPathRelease(path);

    effectView.layer.mask = mask;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    // If sampling provided colors, paint solid caps (one per corner) to match background.
    // Otherwise, leave it to the NSVisualEffectView blur.
    if (self.topLeftColor == nil && self.topRightColor == nil && self.bottomLeftColor == nil && self.bottomRightColor == nil) {
        return;
    }

    NSVisualEffectView *effectView = [self cfx_effectView];
    effectView.hidden = YES;

    NSGraphicsContext *context = NSGraphicsContext.currentContext;
    BOOL oldAA = context.shouldAntialias;
    context.shouldAntialias = NO;

    CGFloat c = ceil(self.capSize);
    CGFloat strip = 3.0;
    NSString *stripOverride = NSProcessInfo.processInfo.environment[@"CFX_EXTERNAL_STRIP"];
    if (stripOverride.length > 0) {
        strip = MAX(1.0, (CGFloat)stripOverride.doubleValue);
    }

    CGFloat inset = MAX(0.0, self.targetInset);
    NSRect b = self.bounds;
    NSRect target = NSInsetRect(b, inset, inset);
    CGFloat tx0 = NSMinX(target);
    CGFloat ty0 = NSMinY(target);
    CGFloat tx1 = NSMaxX(target);
    CGFloat ty1 = NSMaxY(target);

    // Top-left
    [(self.topLeftColor ?: self.topRightColor ?: self.bottomLeftColor ?: NSColor.windowBackgroundColor) setFill];
    NSRectFill(NSMakeRect(tx0 - c, ty1, c, c));
    NSRectFill(NSMakeRect(tx0, ty1, c, strip));
    NSRectFill(NSMakeRect(tx0 - strip, ty1 - c, strip, c));

    // Top-right
    [(self.topRightColor ?: self.topLeftColor ?: self.bottomRightColor ?: NSColor.windowBackgroundColor) setFill];
    NSRectFill(NSMakeRect(tx1, ty1, c, c));
    NSRectFill(NSMakeRect(tx1 - c, ty1, c, strip));
    NSRectFill(NSMakeRect(tx1, ty1 - c, strip, c));

    // Bottom-left
    [(self.bottomLeftColor ?: self.topLeftColor ?: self.bottomRightColor ?: NSColor.windowBackgroundColor) setFill];
    NSRectFill(NSMakeRect(tx0 - c, ty0 - c, c, c));
    NSRectFill(NSMakeRect(tx0, ty0 - strip, c, strip));
    NSRectFill(NSMakeRect(tx0 - strip, ty0, strip, c));

    // Bottom-right
    [(self.bottomRightColor ?: self.topRightColor ?: self.bottomLeftColor ?: NSColor.windowBackgroundColor) setFill];
    NSRectFill(NSMakeRect(tx1, ty0 - c, c, c));
    NSRectFill(NSMakeRect(tx1 - c, ty0 - strip, c, strip));
    NSRectFill(NSMakeRect(tx1, ty0, strip, c));

    context.shouldAntialias = oldAA;
}

@end
