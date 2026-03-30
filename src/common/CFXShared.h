#import <Foundation/Foundation.h>
#import <stdbool.h>

extern CFStringRef _Nonnull const kCFXPreferencesDomain;
extern CFStringRef _Nonnull const kCFXEnabledKey;
extern CFStringRef _Nonnull const kCFXRadiusKey;
extern CFStringRef _Nonnull const kCFXAppSettingsKey;
extern CFStringRef _Nonnull const kCFXDebugKey;
extern CFStringRef _Nonnull const kCFXReloadNotification;

bool CFXReadEnabled(void);
double CFXReadRadius(void);
void CFXWriteEnabled(bool enabled);
void CFXWriteRadius(double radius);
bool CFXReadDebugLoggingEnabled(void);
void CFXWriteDebugLoggingEnabled(bool enabled);
bool CFXReadEnabledForBundleIdentifier(CFStringRef _Nullable bundleIdentifier);
double CFXReadRadiusForBundleIdentifier(CFStringRef _Nullable bundleIdentifier);
void CFXWriteEnabledForBundleIdentifier(CFStringRef _Nonnull bundleIdentifier, bool enabled);
void CFXWriteRadiusForBundleIdentifier(CFStringRef _Nonnull bundleIdentifier, double radius);
void CFXClearBundleIdentifierOverrides(CFStringRef _Nonnull bundleIdentifier);
void CFXResetPreferences(void);
NSDictionary<NSString *, NSDictionary *> * _Nonnull CFXCopySettingsSnapshot(void);
NSDictionary * _Nonnull CFXCopyRawDomainSnapshot(void);
NSString * _Nonnull CFXCopySettingsFilePath(void);
void CFXSynchronizePreferences(void);
void CFXPostReloadNotification(void);
