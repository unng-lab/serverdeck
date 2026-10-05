#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'Build on macOS' >&2; exit 1; }
version=$(python3 tools/release_manifest.py --version)
case "$(uname -m)" in arm64) arch=arm64;; x86_64) arch=x64;; *) exit 1;; esac
flutter pub get
flutter build macos --release
app=build/macos/Build/Products/Release/ServerDeck.app
(cd packages/serverdeck_locald && dart pub get && dart compile exe bin/locald.dart -o "../../$app/Contents/MacOS/serverdeck_locald")
isar=$(python3 tools/release_manifest.py --isar-library macos)
cp "$isar" "$app/Contents/Frameworks/libisar.dylib"
chmod +x "$app/Contents/MacOS/serverdeck_locald"
# The helper's precompiled Dart runtime needs no JIT entitlement.
identity=${MACOS_SIGN_IDENTITY:--}
if [[ "$identity" != - ]]; then
  while IFS= read -r -d '' item; do
    codesign --force --options runtime --timestamp --sign "$identity" "$item"
  done < <(find "$app/Contents" -depth \( -name '*.dylib' -o -name '*.framework' -o -name serverdeck_locald \) -print0)
  codesign --force --options runtime --timestamp --entitlements macos/Runner/Release.entitlements --sign "$identity" "$app"
else
  codesign --force --deep --sign - "$app"
fi
codesign --verify --deep --strict "$app"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/ServerDeck.app"
ln -s /Applications "$stage/Applications"
mkdir -p output/dist
package="output/dist/ServerDeck-$version-macos-$arch.dmg"
hdiutil create -volname ServerDeck -srcfolder "$stage" -ov -format UDZO "$package"
if [[ -n "${MACOS_NOTARY_PROFILE:-}" ]]; then
  [[ "$identity" != - ]] || { echo 'Notarization requires Developer ID' >&2; exit 1; }
  codesign --timestamp --sign "$identity" "$package"
  xcrun notarytool submit "$package" --keychain-profile "$MACOS_NOTARY_PROFILE" --wait
  xcrun stapler staple "$package"
  xcrun stapler validate "$package"
fi
echo "$package"
