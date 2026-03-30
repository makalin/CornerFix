#import <Foundation/Foundation.h>
#import "../common/CFXShared.h"

static double PresetRadius(NSString *presetName) {
    NSDictionary<NSString *, NSNumber *> *presets = @{
        @"sharp": @0.0,
        @"default": @6.0,
        @"soft": @10.0
    };
    NSNumber *value = presets[presetName.lowercaseString];
    return value != nil ? value.doubleValue : -1.0;
}

static NSString *BoolString(BOOL value) {
    return value ? @"true" : @"false";
}

static NSString *DebugString(void) {
    return BoolString(CFXReadDebugLoggingEnabled());
}

static void PrintJSONString(id object) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:&error];
    if (data == nil) {
        fprintf(stderr, "Failed to encode JSON: %s\n", error.localizedDescription.UTF8String);
        return;
    }
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
}

static void PrintUsage(void) {
    fprintf(stderr,
            "Usage: cornerfixctl [command] [options]\n"
            "Commands:\n"
            "  on/off/toggle          Enable or disable the sharpener\n"
            "  reload                 Broadcast a live reload notification\n"
            "  reset                  Reset all global and per-app settings\n"
            "  list                   Print global settings and app overrides\n"
            "  config-path            Print the active settings plist path\n"
            "  dump-config            Print raw config as JSON\n"
            "  effective-config       Print effective config for --app or global scope\n"
            "  doctor                 Run local diagnostics for support/troubleshooting\n"
            "  debug-on               Enable payload debug logging\n"
            "  debug-off              Disable payload debug logging\n"
            "Options:\n"
            "  -r, --radius VALUE     Set radius from 0 to 24\n"
            "  --preset NAME          Apply preset: sharp, default, soft\n"
            "  --app BUNDLE_ID        Apply command/options to one app override\n"
            "  --clear-app            Remove overrides for --app\n"
            "  -s, --status           Print current state\n");
}

static void PrintStatus(NSString *bundleIdentifier) {
    if (bundleIdentifier != nil) {
        printf("bundle=%s enabled=%s radius=%.1f debug=%s\n",
               bundleIdentifier.UTF8String,
               CFXReadEnabledForBundleIdentifier((__bridge CFStringRef)bundleIdentifier) ? "true" : "false",
               CFXReadRadiusForBundleIdentifier((__bridge CFStringRef)bundleIdentifier),
               DebugString().UTF8String);
        return;
    }

    printf("enabled=%s radius=%.1f debug=%s\n",
           CFXReadEnabled() ? "true" : "false",
           CFXReadRadius(),
           DebugString().UTF8String);
}

static void PrintList(void) {
    printf("global enabled=%s radius=%.1f debug=%s\n",
           CFXReadEnabled() ? "true" : "false",
           CFXReadRadius(),
           DebugString().UTF8String);
    NSDictionary<NSString *, NSDictionary *> *snapshot = CFXCopySettingsSnapshot();
    NSArray<NSString *> *bundleIdentifiers = [[snapshot allKeys] sortedArrayUsingSelector:@selector(compare:)];
    if (bundleIdentifiers.count == 0) {
        printf("overrides none\n");
        return;
    }

    printf("overrides %lu\n", (unsigned long)bundleIdentifiers.count);
    for (NSString *bundleIdentifier in bundleIdentifiers) {
        NSDictionary *entry = snapshot[bundleIdentifier];
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        NSNumber *enabled = entry[@"enabled"];
        NSNumber *radius = entry[@"radius"];
        if ([enabled isKindOfClass:[NSNumber class]]) {
            [parts addObject:[NSString stringWithFormat:@"enabled=%s", enabled.boolValue ? "true" : "false"]];
        }
        if ([radius isKindOfClass:[NSNumber class]]) {
            [parts addObject:[NSString stringWithFormat:@"radius=%.1f", radius.doubleValue]];
        }
        NSString *description = parts.count > 0 ? [parts componentsJoinedByString:@" "] : @"(empty)";
        printf("%s %s\n", bundleIdentifier.UTF8String, description.UTF8String);
    }
}

static void PrintConfigPath(void) {
    printf("%s\n", CFXCopySettingsFilePath().UTF8String);
}

static void PrintDumpConfig(void) {
    NSMutableDictionary *payload = [[CFXCopyRawDomainSnapshot() mutableCopy] ?: [NSMutableDictionary dictionary] mutableCopy];
    if (payload[@"appSettings"] == nil) {
        payload[@"appSettings"] = @{};
    }
    PrintJSONString(payload);
}

static void PrintEffectiveConfig(NSString *bundleIdentifier) {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"settingsPath"] = CFXCopySettingsFilePath();
    if (bundleIdentifier != nil) {
        payload[@"bundleIdentifier"] = bundleIdentifier;
        payload[@"enabled"] = @(CFXReadEnabledForBundleIdentifier((__bridge CFStringRef)bundleIdentifier));
        payload[@"radius"] = @(CFXReadRadiusForBundleIdentifier((__bridge CFStringRef)bundleIdentifier));
        NSDictionary *rawOverride = CFXCopySettingsSnapshot()[bundleIdentifier];
        payload[@"hasOverride"] = @([rawOverride isKindOfClass:[NSDictionary class]]);
        payload[@"override"] = rawOverride ?: @{};
    } else {
        payload[@"enabled"] = @(CFXReadEnabled());
        payload[@"radius"] = @(CFXReadRadius());
        payload[@"debugLogging"] = @(CFXReadDebugLoggingEnabled());
        payload[@"overrideCount"] = @([CFXCopySettingsSnapshot() count]);
    }
    PrintJSONString(payload);
}

static void RunDoctor(void) {
    NSString *cwd = NSFileManager.defaultManager.currentDirectoryPath;
    NSString *buildDylib = [cwd stringByAppendingPathComponent:@"build/libcornerfix.dylib"];
    NSString *buildCLI = [cwd stringByAppendingPathComponent:@"build/cornerfixctl"];
    NSString *blacklist = [cwd stringByAppendingPathComponent:@"libcornerfix.dylib.blacklist"];
    NSString *settingsPath = CFXCopySettingsFilePath();

    BOOL dylibExists = [NSFileManager.defaultManager fileExistsAtPath:buildDylib];
    BOOL cliExists = [NSFileManager.defaultManager fileExistsAtPath:buildCLI];
    BOOL blacklistExists = [NSFileManager.defaultManager fileExistsAtPath:blacklist];
    BOOL settingsExists = [NSFileManager.defaultManager fileExistsAtPath:settingsPath];
    BOOL usingOverridePath = NSProcessInfo.processInfo.environment[@"CFX_SETTINGS_PATH"].length > 0;

    printf("doctor build_dylib_exists=%s path=%s\n", BoolString(dylibExists).UTF8String, buildDylib.UTF8String);
    printf("doctor build_cli_exists=%s path=%s\n", BoolString(cliExists).UTF8String, buildCLI.UTF8String);
    printf("doctor blacklist_exists=%s path=%s\n", BoolString(blacklistExists).UTF8String, blacklist.UTF8String);
    printf("doctor settings_exists=%s path=%s\n", BoolString(settingsExists).UTF8String, settingsPath.UTF8String);
    printf("doctor using_override_settings_path=%s\n", BoolString(usingOverridePath).UTF8String);
    printf("doctor global_enabled=%s global_radius=%.1f debug=%s override_count=%lu\n",
           BoolString(CFXReadEnabled()).UTF8String,
           CFXReadRadius(),
           DebugString().UTF8String,
           (unsigned long)CFXCopySettingsSnapshot().count);
    printf("doctor note=This command cannot verify live injection into target app processes by itself.\n");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL printStatus = NO;
        BOOL printList = NO;
        BOOL printConfigPath = NO;
        BOOL dumpConfig = NO;
        BOOL printEffectiveConfig = NO;
        BOOL runDoctor = NO;
        BOOL updateEnabled = NO;
        BOOL updateDebug = NO;
        BOOL debugLogging = CFXReadDebugLoggingEnabled();
        BOOL enabled = CFXReadEnabled();
        BOOL updateRadius = NO;
        double radius = CFXReadRadius();
        BOOL triggerReloadOnly = NO;
        BOOL resetPreferences = NO;
        BOOL clearAppOverride = NO;
        NSString *bundleIdentifier = nil;

        for (int index = 1; index < argc; index++) {
            const char *argument = argv[index];
            if (strcmp(argument, "on") == 0) {
                updateEnabled = YES;
                enabled = YES;
            } else if (strcmp(argument, "off") == 0) {
                updateEnabled = YES;
                enabled = NO;
            } else if (strcmp(argument, "toggle") == 0) {
                updateEnabled = YES;
                enabled = !enabled;
            } else if (strcmp(argument, "reload") == 0) {
                triggerReloadOnly = YES;
            } else if (strcmp(argument, "reset") == 0) {
                resetPreferences = YES;
            } else if (strcmp(argument, "list") == 0) {
                printList = YES;
            } else if (strcmp(argument, "config-path") == 0) {
                printConfigPath = YES;
            } else if (strcmp(argument, "dump-config") == 0) {
                dumpConfig = YES;
            } else if (strcmp(argument, "effective-config") == 0) {
                printEffectiveConfig = YES;
            } else if (strcmp(argument, "doctor") == 0) {
                runDoctor = YES;
            } else if (strcmp(argument, "debug-on") == 0) {
                updateDebug = YES;
                debugLogging = YES;
            } else if (strcmp(argument, "debug-off") == 0) {
                updateDebug = YES;
                debugLogging = NO;
            } else if (strcmp(argument, "-s") == 0 || strcmp(argument, "--status") == 0) {
                printStatus = YES;
            } else if (strcmp(argument, "-r") == 0 || strcmp(argument, "--radius") == 0) {
                if (index + 1 >= argc) {
                    PrintUsage();
                    return 1;
                }
                index += 1;
                radius = strtod(argv[index], NULL);
                updateRadius = YES;
            } else if (strcmp(argument, "--preset") == 0) {
                if (index + 1 >= argc) {
                    PrintUsage();
                    return 1;
                }
                index += 1;
                NSString *preset = [NSString stringWithUTF8String:argv[index]];
                double presetRadius = PresetRadius(preset);
                if (presetRadius < 0.0) {
                    fprintf(stderr, "Unknown preset: %s\n", argv[index]);
                    return 1;
                }
                radius = presetRadius;
                updateRadius = YES;
            } else if (strcmp(argument, "--app") == 0) {
                if (index + 1 >= argc) {
                    PrintUsage();
                    return 1;
                }
                index += 1;
                bundleIdentifier = [NSString stringWithUTF8String:argv[index]];
                enabled = CFXReadEnabledForBundleIdentifier((__bridge CFStringRef)bundleIdentifier);
                radius = CFXReadRadiusForBundleIdentifier((__bridge CFStringRef)bundleIdentifier);
            } else if (strcmp(argument, "--clear-app") == 0) {
                clearAppOverride = YES;
            } else if (strcmp(argument, "-h") == 0 || strcmp(argument, "--help") == 0) {
                PrintUsage();
                return 0;
            } else {
                fprintf(stderr, "Unknown argument: %s\n", argument);
                PrintUsage();
                return 1;
            }
        }

        if (clearAppOverride && bundleIdentifier == nil) {
            fprintf(stderr, "--clear-app requires --app BUNDLE_ID\n");
            return 1;
        }
        if (resetPreferences && bundleIdentifier != nil) {
            fprintf(stderr, "reset cannot be combined with --app\n");
            return 1;
        }

        if (resetPreferences) {
            CFXResetPreferences();
        } else if (clearAppOverride) {
            CFXClearBundleIdentifierOverrides((__bridge CFStringRef)bundleIdentifier);
        } else {
            if (updateEnabled) {
                if (bundleIdentifier != nil) {
                    CFXWriteEnabledForBundleIdentifier((__bridge CFStringRef)bundleIdentifier, enabled);
                } else {
                    CFXWriteEnabled(enabled);
                }
            }
            if (updateRadius) {
                if (bundleIdentifier != nil) {
                    CFXWriteRadiusForBundleIdentifier((__bridge CFStringRef)bundleIdentifier, radius);
                } else {
                    CFXWriteRadius(radius);
                }
            }
            if (updateDebug) {
                CFXWriteDebugLoggingEnabled(debugLogging);
            }
        }

        if (resetPreferences || clearAppOverride || updateEnabled || updateRadius || updateDebug) {
            CFXSynchronizePreferences();
            CFXPostReloadNotification();
        }
        if (triggerReloadOnly) {
            CFXPostReloadNotification();
        }
        if (printConfigPath) {
            PrintConfigPath();
        }
        if (dumpConfig) {
            PrintDumpConfig();
        }
        if (printEffectiveConfig) {
            PrintEffectiveConfig(bundleIdentifier);
        }
        if (printList) {
            PrintList();
        }
        if (runDoctor) {
            RunDoctor();
        }
        if (printStatus || (!triggerReloadOnly && !resetPreferences && !clearAppOverride && !updateEnabled && !updateRadius && !updateDebug && !printList && !printConfigPath && !dumpConfig && !printEffectiveConfig && !runDoctor)) {
            PrintStatus(bundleIdentifier);
        }
    }
    return 0;
}
