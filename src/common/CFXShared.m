#import "CFXShared.h"

CFStringRef const kCFXPreferencesDomain = CFSTR("com.makalin.cornerfix");
CFStringRef const kCFXEnabledKey = CFSTR("enabled");
CFStringRef const kCFXRadiusKey = CFSTR("radius");
CFStringRef const kCFXAppSettingsKey = CFSTR("appSettings");
CFStringRef const kCFXDebugKey = CFSTR("debugLogging");
CFStringRef const kCFXReloadNotification = CFSTR("com.makalin.cornerfix.reload");

static NSString *const kCFXEntryEnabledKey = @"enabled";
static NSString *const kCFXEntryRadiusKey = @"radius";

static NSString *CFXSettingsDirectoryPath(void) {
    NSString *overridePath = NSProcessInfo.processInfo.environment[@"CFX_SETTINGS_PATH"];
    if (overridePath.length > 0) {
        return [overridePath stringByDeletingLastPathComponent];
    }
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    return [base stringByAppendingPathComponent:@"CornerFix"];
}

static NSString *CFXSettingsFilePath(void) {
    NSString *overridePath = NSProcessInfo.processInfo.environment[@"CFX_SETTINGS_PATH"];
    if (overridePath.length > 0) {
        return overridePath;
    }
    return [CFXSettingsDirectoryPath() stringByAppendingPathComponent:@"settings.plist"];
}

static NSMutableDictionary *CFXMutableDomain(void) {
    NSDictionary *domain = [NSDictionary dictionaryWithContentsOfFile:CFXSettingsFilePath()];
    return domain != nil ? [domain mutableCopy] : [NSMutableDictionary dictionary];
}

static void CFXWriteDomain(NSDictionary *domain) {
    NSString *directory = CFXSettingsDirectoryPath();
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:domain
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&error];
    if (data == nil) {
        NSLog(@"[CornerFix] Failed to serialize settings domain: %@", error.localizedDescription);
        return;
    }
    if (![data writeToFile:CFXSettingsFilePath() options:NSDataWritingAtomic error:&error]) {
        NSLog(@"[CornerFix] Failed to write settings domain: %@", error.localizedDescription);
    }
}

static double CFXClampRadius(double radius) {
    if (radius < 0.0) {
        return 0.0;
    }
    if (radius > 24.0) {
        return 24.0;
    }
    return radius;
}

static NSMutableDictionary<NSString *, NSMutableDictionary *> *CFXMutableAppSettings(void) {
    NSDictionary *domain = CFXMutableDomain();
    id value = domain[(__bridge NSString *)kCFXAppSettingsKey];
    NSMutableDictionary<NSString *, NSMutableDictionary *> *result = [NSMutableDictionary dictionary];
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)value;
        for (id key in dictionary) {
            if ([key isKindOfClass:[NSString class]]) {
                id entry = dictionary[key];
                if ([entry isKindOfClass:[NSDictionary class]]) {
                    result[(NSString *)key] = [entry mutableCopy];
                }
            }
        }
    }
    return result;
}

static NSDictionary *CFXAppEntryForBundleIdentifier(CFStringRef bundleIdentifier) {
    if (bundleIdentifier == NULL) {
        return nil;
    }
    NSDictionary *settings = CFXCopySettingsSnapshot();
    return settings[(__bridge NSString *)bundleIdentifier];
}

bool CFXReadEnabled(void) {
    id value = CFXMutableDomain()[(__bridge NSString *)kCFXEnabledKey];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : true;
}

double CFXReadRadius(void) {
    id value = CFXMutableDomain()[(__bridge NSString *)kCFXRadiusKey];
    return [value isKindOfClass:[NSNumber class]] ? CFXClampRadius([value doubleValue]) : 0.0;
}

bool CFXReadDebugLoggingEnabled(void) {
    id value = CFXMutableDomain()[(__bridge NSString *)kCFXDebugKey];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : false;
}

void CFXWriteEnabled(bool enabled) {
    NSMutableDictionary *domain = CFXMutableDomain();
    domain[(__bridge NSString *)kCFXEnabledKey] = @(enabled);
    CFXWriteDomain(domain);
}

void CFXWriteRadius(double radius) {
    NSMutableDictionary *domain = CFXMutableDomain();
    domain[(__bridge NSString *)kCFXRadiusKey] = @(CFXClampRadius(radius));
    CFXWriteDomain(domain);
}

void CFXWriteDebugLoggingEnabled(bool enabled) {
    NSMutableDictionary *domain = CFXMutableDomain();
    domain[(__bridge NSString *)kCFXDebugKey] = @(enabled);
    CFXWriteDomain(domain);
}

bool CFXReadEnabledForBundleIdentifier(CFStringRef bundleIdentifier) {
    NSDictionary *entry = CFXAppEntryForBundleIdentifier(bundleIdentifier);
    NSNumber *value = entry[kCFXEntryEnabledKey];
    if ([value isKindOfClass:[NSNumber class]]) {
        return value.boolValue;
    }
    return CFXReadEnabled();
}

double CFXReadRadiusForBundleIdentifier(CFStringRef bundleIdentifier) {
    NSDictionary *entry = CFXAppEntryForBundleIdentifier(bundleIdentifier);
    NSNumber *value = entry[kCFXEntryRadiusKey];
    if ([value isKindOfClass:[NSNumber class]]) {
        return CFXClampRadius(value.doubleValue);
    }
    return CFXReadRadius();
}

void CFXWriteEnabledForBundleIdentifier(CFStringRef bundleIdentifier, bool enabled) {
    if (bundleIdentifier == NULL) {
        return;
    }
    NSMutableDictionary *settings = CFXMutableAppSettings();
    NSString *key = (__bridge NSString *)bundleIdentifier;
    NSMutableDictionary *entry = [settings[key] mutableCopy] ?: [NSMutableDictionary dictionary];
    entry[kCFXEntryEnabledKey] = @(enabled);
    settings[key] = entry;
    NSMutableDictionary *domain = CFXMutableDomain();
    domain[(__bridge NSString *)kCFXAppSettingsKey] = settings;
    CFXWriteDomain(domain);
}

void CFXWriteRadiusForBundleIdentifier(CFStringRef bundleIdentifier, double radius) {
    if (bundleIdentifier == NULL) {
        return;
    }
    NSMutableDictionary *settings = CFXMutableAppSettings();
    NSString *key = (__bridge NSString *)bundleIdentifier;
    NSMutableDictionary *entry = [settings[key] mutableCopy] ?: [NSMutableDictionary dictionary];
    entry[kCFXEntryRadiusKey] = @(CFXClampRadius(radius));
    settings[key] = entry;
    NSMutableDictionary *domain = CFXMutableDomain();
    domain[(__bridge NSString *)kCFXAppSettingsKey] = settings;
    CFXWriteDomain(domain);
}

void CFXClearBundleIdentifierOverrides(CFStringRef bundleIdentifier) {
    if (bundleIdentifier == NULL) {
        return;
    }
    NSMutableDictionary *settings = CFXMutableAppSettings();
    [settings removeObjectForKey:(__bridge NSString *)bundleIdentifier];
    NSMutableDictionary *domain = CFXMutableDomain();
    if (settings.count > 0) {
        domain[(__bridge NSString *)kCFXAppSettingsKey] = settings;
    } else {
        [domain removeObjectForKey:(__bridge NSString *)kCFXAppSettingsKey];
    }
    CFXWriteDomain(domain);
}

void CFXResetPreferences(void) {
    [[NSFileManager defaultManager] removeItemAtPath:CFXSettingsFilePath() error:nil];
}

NSDictionary<NSString *, NSDictionary *> *CFXCopySettingsSnapshot(void) {
    return [CFXMutableAppSettings() copy];
}

NSDictionary *CFXCopyRawDomainSnapshot(void) {
    return [CFXMutableDomain() copy];
}

NSString *CFXCopySettingsFilePath(void) {
    return [CFXSettingsFilePath() copy];
}

void CFXSynchronizePreferences(void) {
}

void CFXPostReloadNotification(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         kCFXReloadNotification,
                                         NULL,
                                         NULL,
                                         true);
}
