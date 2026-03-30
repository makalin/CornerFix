#import "CFXSwizzle.h"
#import <objc/runtime.h>

BOOL CFXSwizzleInstanceMethod(Class cls, SEL originalSelector, SEL replacementSelector) {
    Method originalMethod = class_getInstanceMethod(cls, originalSelector);
    Method replacementMethod = class_getInstanceMethod(cls, replacementSelector);
    if (originalMethod == NULL || replacementMethod == NULL) {
        return NO;
    }

    BOOL didAddMethod = class_addMethod(cls,
                                        originalSelector,
                                        method_getImplementation(replacementMethod),
                                        method_getTypeEncoding(replacementMethod));
    if (didAddMethod) {
        class_replaceMethod(cls,
                            replacementSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, replacementMethod);
    }
    return YES;
}
