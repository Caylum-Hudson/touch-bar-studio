#import "TouchBarPrivateApi.h"
#import <objc/message.h>
#import <objc/runtime.h>

// A separate instance/class for Studio's compact bar. Never replace methods on
// AppKit's class: native Control Strip overlays retain their own close behavior.
static Class studioOverlayClass;
static IMP nativeCloseImplementation;
static NSUInteger suppressedCloseUpdates;
static id activeOverlay;
static NSTouchBar *activeBar;

static void StudioSkipCloseUpdate(id self, SEL command) {
    suppressedCloseUpdates++;
}

static BOOL HasSignature(Class type, const char *selector, const char *encoding) {
    Method method = class_getInstanceMethod(type, sel_registerName(selector));
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0;
}

static Class StudioOverlayClass(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class native = NSClassFromString(@"NSSystemModalTouchBarOverlay");
        if (!native || class_getSuperclass(native) != NSObject.class ||
            !HasSignature(native, "showTouchBar:placement:systemTrayIdentifier:", "v40@0:8@16q24@32") ||
            !HasSignature(native, "_updateCloseButton", "v16@0:8") ||
            !HasSignature(native, "minimize", "v16@0:8") ||
            !HasSignature(native, "dismiss", "v16@0:8")) return;
        nativeCloseImplementation = class_getMethodImplementation(native, sel_registerName("_updateCloseButton"));
        Class subclass = objc_allocateClassPair(native, "StudioCompactTouchBarOverlay", 0);
        if (!subclass) return;
        if (!class_addMethod(subclass, sel_registerName("_updateCloseButton"), (IMP)StudioSkipCloseUpdate, "v16@0:8")) {
            objc_disposeClassPair(subclass);
            return;
        }
        objc_registerClassPair(subclass);
        studioOverlayClass = subclass;
    });
    return studioOverlayClass;
}

BOOL StudioPresentCompactOverlay(NSTouchBar *bar, NSTouchBarItemIdentifier identifier) {
    NSCAssert(NSThread.isMainThread, @"Touch Bar presentation must run on the main thread");
    Class type = StudioOverlayClass();
    // _updateCloseButton also places an escape-key replacement. Keep AppKit's
    // normal presenter for bars that request one; never suppress that content.
    if (!type || !bar || bar.escapeKeyReplacementItemIdentifier != nil) return NO;
    if (activeBar != bar) {
        if (activeOverlay) ((void (*)(id, SEL))objc_msgSend)(activeOverlay, sel_registerName("dismiss"));
        activeOverlay = [[type alloc] init];
        activeBar = bar;
    }
    ((void (*)(id, SEL, id, long long, id))objc_msgSend)(activeOverlay,
        sel_registerName("showTouchBar:placement:systemTrayIdentifier:"), bar, 0, identifier);
    return YES;
}

BOOL StudioMinimizeCompactOverlay(NSTouchBar *bar) {
    if (!activeOverlay || activeBar != bar) return NO;
    ((void (*)(id, SEL))objc_msgSend)(activeOverlay, sel_registerName("minimize"));
    return YES;
}

BOOL StudioDismissCompactOverlay(NSTouchBar *bar) {
    if (!activeOverlay || activeBar != bar) return NO;
    ((void (*)(id, SEL))objc_msgSend)(activeOverlay, sel_registerName("dismiss"));
    activeOverlay = nil;
    activeBar = nil;
    return YES;
}

BOOL StudioCompactOverlaySelfTest(void) {
    Class type = StudioOverlayClass();
    if (!type) return NO;
    Class native = class_getSuperclass(type);
    SEL update = sel_registerName("_updateCloseButton");
    NSUInteger previous = suppressedCloseUpdates;
    id probe = [[type alloc] init];
    ((void (*)(id, SEL))objc_msgSend)(probe, update);
    return suppressedCloseUpdates == previous + 1 &&
        class_getMethodImplementation(type, update) == (IMP)StudioSkipCloseUpdate &&
        class_getMethodImplementation(native, update) == nativeCloseImplementation;
}
