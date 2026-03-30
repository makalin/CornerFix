# Testing

## Recommended First Target

Use the unsigned local test app bundled with this repo before trying Safari or other protected apps.

Build everything:

```bash
make
```

Launch the test app with injection:

```bash
./build/cornerfix-inject --app ./build/CornerFixTestApp.app
```

Then verify:

```bash
ps aux | grep CornerFixTestApp
vmmap <PID> | grep -i cornerfix
./build/cornerfixctl debug-on
rm -f /tmp/CornerFix.debug.log
./build/cornerfixctl --radius 0
./build/cornerfixctl --radius 10
./build/cornerfixctl reload
cat /tmp/CornerFix.debug.log
```

Expected result:

- the test app launches
- `vmmap` shows `libcornerfix.dylib`
- changing radius affects the outer app window corners live
- with debug enabled, `/tmp/CornerFix.debug.log` shows whether windows were skipped or modified

## Why This Matters

If the test app works but Safari fails, the issue is not the payload. It is the injection method being blocked by code signing, hardened runtime, or SIP-related protections.
