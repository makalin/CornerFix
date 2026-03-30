# Loader Integration

`CornerFix` now includes a small launcher-style injector, `cornerfix-inject`, and can also be used with an external loader. `cornerfix-inject` launches a target app with `DYLD_INSERT_LIBRARIES`; it is useful for non-hardened apps and testing, but it is not equivalent to a full system-wide injector.

## Built-In Injector

Preflight without launching:

```bash
./build/cornerfix-inject --app ./build/CornerFixTestApp.app --check
```

Launch by app path:

```bash
./build/cornerfix-inject --app ./build/CornerFixTestApp.app
```

Launch by bundle identifier:

```bash
./build/cornerfix-inject --bundle-id com.apple.TextEdit
```

Use the installed tool:

```bash
/usr/local/bin/cornerfix-inject --bundle-id com.apple.TextEdit
```

Important limits:

- launch-only, not attach-to-PID injection
- may be blocked by SIP, hardened runtime, or Apple-protected apps
- Safari and other system apps may ignore this method even when the command succeeds
- the included `CornerFixTestApp.app` is the recommended first validation target

## Ammonia-Style Flow

1. Build CornerFix:

```bash
make
```

2. Install the library and controller somewhere stable:

```bash
make install PREFIX=/usr/local
```

3. Configure your loader to inject:

- library: `/usr/local/lib/cornerfix/libcornerfix.dylib`
- blacklist: `/usr/local/share/cornerfix/libcornerfix.dylib.blacklist`

4. Use the controller after injection is active:

```bash
cornerfixctl --preset sharp
cornerfixctl --app com.apple.Safari --radius 4
cornerfixctl reload
```

## What To Verify

- the loader only targets GUI apps you actually want to modify
- the loader respects the blacklist
- the controller path is on `PATH`
- changing `cornerfixctl` settings affects already-running injected apps
- if using `cornerfix-inject`, verify the launched process actually loaded `libcornerfix.dylib` with `vmmap <pid> | grep -i cornerfix`

## Support Notes

- If config changes seem ignored, run `cornerfixctl doctor`
- If you are testing in a constrained environment, use `CFX_SETTINGS_PATH=/tmp/cornerfix-settings.plist`
- If one app behaves badly, add it to the loader blacklist first
