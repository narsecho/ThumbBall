#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
ROOT="$PWD"
STAGE="$(mktemp -d /private/tmp/thumbball-build.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/ThumbBall.app"
echo "ea51dd5d774def2a441dbbf8892c34055027ba0c768eaf8ed36691ce50c21a6c  Vendor/Rime/librime.1.dylib" | shasum -a 256 -c -
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$ROOT/.module-cache" "$STAGE/rime-user"
cp Vendor/Rime/librime.1.dylib "$APP/Contents/Frameworks/"
cp -RX Resources/Rime "$APP/Contents/Resources/Rime"
cp -RX Resources/Licenses "$APP/Contents/Resources/Licenses"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -I Vendor/Rime/include -I Sources -c Sources/RimeBridge.c -o "$STAGE/RimeBridge.o"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -I Sources Sources/RimeDeploy.c "$STAGE/RimeBridge.o" -L Vendor/Rime -lrime.1 -Wl,-rpath,"$ROOT/Vendor/Rime" -o "$STAGE/deploy"
"$STAGE/deploy" "$APP/Contents/Resources/Rime" "$STAGE/rime-user"
cp -RX "$STAGE/rime-user/build" "$APP/Contents/Resources/Rime/build"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos13.0 -module-cache-path "$ROOT/.module-cache" Sources/main.swift Sources/RimeEngine.swift -import-objc-header Sources/RimeBridge.h "$STAGE/RimeBridge.o" -L Vendor/Rime -lrime.1 -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$APP/Contents/MacOS/ThumbBall" -framework AppKit -framework ApplicationServices -framework Carbon
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/ThumbBall.icns "$APP/Contents/Resources/ThumbBall.icns"
/usr/bin/xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/Frameworks/librime.1.dylib"
codesign --force --sign - --identifier local.thumbball.app "$APP"
"$APP/Contents/MacOS/ThumbBall" --self-test
"$APP/Contents/MacOS/ThumbBall" --rime-self-test
codesign --verify --deep --strict "$APP"
# Sign on a local temporary volume; cloud file providers may add FinderInfo to Documents bundles.
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl -c -k --keepParent "$APP" "$ROOT/ThumbBall.zip"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl "$APP" "$ROOT/ThumbBall.app"
/usr/bin/xattr -cr "$ROOT/ThumbBall.app"
if [[ "${1:-}" != "--no-install" ]]; then
  mkdir -p "$HOME/Applications"
  COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noacl "$APP" "$HOME/Applications/ThumbBall.app"
  /usr/bin/xattr -cr "$HOME/Applications/ThumbBall.app"
  codesign --verify --deep --strict "$HOME/Applications/ThumbBall.app"
  echo "Installed and verified: $HOME/Applications/ThumbBall.app"
fi
