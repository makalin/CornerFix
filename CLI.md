# `cornerfixctl`

The controller updates shared preferences and posts a Darwin notification so injected processes refresh without restarting.

## Global Commands

```bash
./build/cornerfixctl on
./build/cornerfixctl off
./build/cornerfixctl toggle
./build/cornerfixctl --radius 0
./build/cornerfixctl --preset default
./build/cornerfixctl reload
./build/cornerfixctl reset
./build/cornerfixctl list
./build/cornerfixctl config-path
./build/cornerfixctl dump-config
./build/cornerfixctl doctor
./build/cornerfixctl debug-on
./build/cornerfixctl debug-off
./build/cornerfixctl --status
```

## Per-App Overrides

```bash
./build/cornerfixctl --app com.apple.Safari on
./build/cornerfixctl --app com.apple.Safari --radius 0
./build/cornerfixctl --app com.apple.dt.Xcode --preset soft
./build/cornerfixctl --app com.apple.Safari --clear-app
./build/cornerfixctl --app com.apple.Safari --status
./build/cornerfixctl --app com.apple.Safari effective-config
```

## Presets

- `sharp` -> `0`
- `default` -> `6`
- `soft` -> `10`

## Notes

- Radius is clamped to `0...24`.
- `0` gives sharp corners.
- `--app` scopes state changes to one bundle identifier.
- `effective-config` prints resolved values for global or per-app scope.
- `dump-config` prints the raw on-disk config as JSON.
- `doctor` reports local build/config paths and basic support diagnostics.
- `debug-on` and `debug-off` control payload logging through the shared config.
- payload debug logs are also appended to `/tmp/CornerFix.debug.log` by default.
- For testing, you can override the settings file path with `CFX_SETTINGS_PATH=/tmp/cornerfix-settings.plist`.
- The CLI does nothing by itself unless `libcornerfix.dylib` is already injected into app processes.
