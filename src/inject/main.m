#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <spawn.h>
#import <sys/wait.h>

extern char **environ;

static void PrintUsage(void) {
    fprintf(stderr,
            "Usage: cornerfix-inject (--app PATH | --bundle-id ID) [--dylib PATH] [--cwd PATH] [--check] [--wait] [-- args...]\n"
            "  --app PATH        Path to an .app bundle or executable\n"
            "  --bundle-id ID    Resolve an installed app by bundle identifier\n"
            "  --dylib PATH      Dylib to inject (default: installed path, then local build path)\n"
            "  --cwd PATH        Working directory for the launched process\n"
            "  --check           Resolve paths and print launch plan without starting the app\n"
            "  --wait            Wait for the launched process to exit\n"
            "  --                Pass remaining arguments to the target executable\n");
}

static NSString *DefaultDylibPath(void) {
    NSArray<NSString *> *candidates = @[
        @"/usr/local/lib/cornerfix/libcornerfix.dylib",
        [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"build/libcornerfix.dylib"]
    ];

    for (NSString *candidate in candidates) {
        if ([[NSFileManager defaultManager] isReadableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return candidates.firstObject;
}

static NSString *ResolveExecutablePath(NSString *appPath, NSString *bundleIdentifier) {
    if (bundleIdentifier.length > 0) {
        NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleIdentifier];
        if (appURL == nil) {
            return nil;
        }
        appPath = appURL.path;
    }

    if (appPath.length == 0) {
        return nil;
    }

    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:appPath isDirectory:&isDirectory] && isDirectory) {
        NSBundle *bundle = [NSBundle bundleWithPath:appPath];
        return bundle.executablePath;
    }
    return appPath;
}

static NSArray<NSString *> *MergedEnvironment(NSString *dylibPath) {
    NSMutableDictionary<NSString *, NSString *> *environment = [NSMutableDictionary dictionaryWithDictionary:NSProcessInfo.processInfo.environment];
    NSString *existing = environment[@"DYLD_INSERT_LIBRARIES"];
    if (existing.length > 0) {
        environment[@"DYLD_INSERT_LIBRARIES"] = [NSString stringWithFormat:@"%@:%@", dylibPath, existing];
    } else {
        environment[@"DYLD_INSERT_LIBRARIES"] = dylibPath;
    }

    NSMutableArray<NSString *> *flat = [NSMutableArray arrayWithCapacity:environment.count];
    for (NSString *key in environment) {
        [flat addObject:[NSString stringWithFormat:@"%@=%@", key, environment[key]]];
    }
    return flat;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *appPath = nil;
        NSString *bundleIdentifier = nil;
        NSString *dylibPath = DefaultDylibPath();
        NSString *workingDirectory = nil;
        BOOL checkOnly = NO;
        BOOL waitForExit = NO;
        NSMutableArray<NSString *> *targetArguments = [NSMutableArray array];

        for (int index = 1; index < argc; index++) {
            const char *argument = argv[index];
            if (strcmp(argument, "--app") == 0) {
                if (index + 1 >= argc) {
                    PrintUsage();
                    return 1;
                }
                appPath = [NSString stringWithUTF8String:argv[++index]];
            } else if (strcmp(argument, "--bundle-id") == 0) {
                if (index + 1 >= argc) {
                    PrintUsage();
                    return 1;
                }
                bundleIdentifier = [NSString stringWithUTF8String:argv[++index]];
            } else if (strcmp(argument, "--dylib") == 0) {
                if (index + 1 >= argc) {
                    PrintUsage();
                    return 1;
                }
                dylibPath = [NSString stringWithUTF8String:argv[++index]];
            } else if (strcmp(argument, "--cwd") == 0) {
                if (index + 1 >= argc) {
                    PrintUsage();
                    return 1;
                }
                workingDirectory = [NSString stringWithUTF8String:argv[++index]];
            } else if (strcmp(argument, "--check") == 0) {
                checkOnly = YES;
            } else if (strcmp(argument, "--wait") == 0) {
                waitForExit = YES;
            } else if (strcmp(argument, "--") == 0) {
                for (int argIndex = index + 1; argIndex < argc; argIndex++) {
                    [targetArguments addObject:[NSString stringWithUTF8String:argv[argIndex]]];
                }
                break;
            } else if (strcmp(argument, "-h") == 0 || strcmp(argument, "--help") == 0) {
                PrintUsage();
                return 0;
            } else {
                fprintf(stderr, "Unknown argument: %s\n", argument);
                PrintUsage();
                return 1;
            }
        }

        if ((appPath.length == 0 && bundleIdentifier.length == 0) || (appPath.length > 0 && bundleIdentifier.length > 0)) {
            fprintf(stderr, "Specify exactly one of --app or --bundle-id.\n");
            return 1;
        }
        if (![[NSFileManager defaultManager] isReadableFileAtPath:dylibPath]) {
            fprintf(stderr, "Dylib not found or unreadable: %s\n", dylibPath.UTF8String);
            return 1;
        }

        NSString *executablePath = ResolveExecutablePath(appPath, bundleIdentifier);
        if (executablePath.length == 0 || ![[NSFileManager defaultManager] isExecutableFileAtPath:executablePath]) {
            fprintf(stderr, "Could not resolve an executable to launch.\n");
            return 1;
        }
        if (workingDirectory.length == 0) {
            workingDirectory = [executablePath stringByDeletingLastPathComponent];
        }
        if (![[NSFileManager defaultManager] fileExistsAtPath:workingDirectory]) {
            fprintf(stderr, "Working directory does not exist: %s\n", workingDirectory.UTF8String);
            return 1;
        }

        printf("plan executable=%s dylib=%s cwd=%s\n",
               executablePath.UTF8String,
               dylibPath.UTF8String,
               workingDirectory.UTF8String);
        if (bundleIdentifier.length > 0) {
            printf("plan bundle_id=%s\n", bundleIdentifier.UTF8String);
        }
        if (checkOnly) {
            printf("note=launch plan only; no process started.\n");
            return 0;
        }

        NSMutableArray<NSString *> *argvStrings = [NSMutableArray arrayWithObject:executablePath];
        [argvStrings addObjectsFromArray:targetArguments];
        NSMutableArray<NSData *> *argvData = [NSMutableArray arrayWithCapacity:argvStrings.count];
        NSMutableArray<NSData *> *envData = [NSMutableArray array];

        for (NSString *string in argvStrings) {
            [argvData addObject:[string dataUsingEncoding:NSUTF8StringEncoding]];
        }
        for (NSString *string in MergedEnvironment(dylibPath)) {
            [envData addObject:[string dataUsingEncoding:NSUTF8StringEncoding]];
        }

        char *spawnArgv[argvData.count + 1];
        for (NSUInteger idx = 0; idx < argvData.count; idx++) {
            spawnArgv[idx] = (char *)argvData[idx].bytes;
        }
        spawnArgv[argvData.count] = NULL;

        char *spawnEnv[envData.count + 1];
        for (NSUInteger idx = 0; idx < envData.count; idx++) {
            spawnEnv[idx] = (char *)envData[idx].bytes;
        }
        spawnEnv[envData.count] = NULL;

        posix_spawn_file_actions_t fileActions;
        posix_spawn_file_actions_init(&fileActions);
        posix_spawnattr_t attributes;
        posix_spawnattr_init(&attributes);

        pid_t pid = 0;
        int spawnStatus = posix_spawn(&pid, executablePath.fileSystemRepresentation, &fileActions, &attributes, spawnArgv, spawnEnv);
        posix_spawn_file_actions_destroy(&fileActions);
        posix_spawnattr_destroy(&attributes);
        if (spawnStatus != 0) {
            fprintf(stderr, "posix_spawn failed with status %d\n", spawnStatus);
            return spawnStatus;
        }

        printf("launched pid=%d executable=%s dylib=%s\n", pid, executablePath.UTF8String, dylibPath.UTF8String);
        printf("note=DYLD_INSERT_LIBRARIES launch injection may be blocked for Apple-protected or hardened apps.\n");
        printf("tip=Use vmmap %d | grep -i cornerfix to verify the dylib actually loaded.\n", pid);

        if (waitForExit) {
            int waitStatus = 0;
            if (waitpid(pid, &waitStatus, 0) < 0) {
                perror("waitpid");
                return 1;
            }
            if (WIFEXITED(waitStatus)) {
                printf("exit_status=%d\n", WEXITSTATUS(waitStatus));
                return WEXITSTATUS(waitStatus);
            }
            if (WIFSIGNALED(waitStatus)) {
                printf("signal=%d\n", WTERMSIG(waitStatus));
                if (WTERMSIG(waitStatus) == SIGKILL) {
                    printf("note=SIGKILL often indicates code-signing or hardened-runtime rejection of DYLD_INSERT_LIBRARIES.\n");
                }
                return 1;
            }
        }
    }
    return 0;
}
