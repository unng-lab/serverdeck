#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || { echo 'Build on Linux x86_64' >&2; exit 1; }
version=$(python3 tools/release_manifest.py --version)
debversion=${version/+/-}
flutter pub get
flutter build linux --release
bundle=build/linux/x64/release/bundle
(cd packages/serverdeck_locald && dart pub get && dart compile exe bin/locald.dart -o "../../$bundle/serverdeck_locald")
test -f "$bundle/lib/libisar.so"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/opt/serverdeck" "$stage/usr/bin" "$stage/usr/share/applications" "$stage/usr/share/icons/hicolor/256x256/apps" "$stage/DEBIAN"
cp -a "$bundle/." "$stage/opt/serverdeck/"
chmod 755 "$stage/opt/serverdeck/serverdeck" "$stage/opt/serverdeck/serverdeck_locald"
ln -s /opt/serverdeck/serverdeck "$stage/usr/bin/serverdeck"
cp packaging/icons/serverdeck.png "$stage/usr/share/icons/hicolor/256x256/apps/serverdeck.png"
cat > "$stage/usr/share/applications/serverdeck.desktop" <<'EOF'
[Desktop Entry]
Name=ServerDeck
Comment=Local server management
Exec=/opt/serverdeck/serverdeck
Icon=serverdeck
Terminal=false
Type=Application
Categories=System;Utility;
StartupWMClass=dev.unng.serverdeck
EOF
# Resolve shared-library requirements from all ELF binaries, excluding the
# bundled libraries themselves (dpkg-shlibdeps may need their search path).
dependency_args=()
while IFS= read -r -d '' binary; do
  if file "$binary" | grep -q ELF; then dependency_args+=(-e"$binary"); fi
done < <(find "$stage/opt/serverdeck" -type f -print0)
metadata=$(mktemp -d)
mkdir -p "$metadata/debian"
printf 'Source: serverdeck\nSection: utils\nPriority: optional\nMaintainer: unng-lab <noreply@github.com>\n\nPackage: serverdeck\nArchitecture: amd64\nDescription: ServerDeck client\n' > "$metadata/debian/control"
deps=$(cd "$metadata" && dpkg-shlibdeps --ignore-missing-info -O -l"$stage/opt/serverdeck/lib" "${dependency_args[@]}" | sed -n 's/^shlibs:Depends=//p')
rm -rf "$metadata"
test -n "$deps"
cat > "$stage/DEBIAN/control" <<EOF
Package: serverdeck
Version: $debversion
Section: utils
Priority: optional
Architecture: amd64
Maintainer: unng-lab <noreply@github.com>
Depends: $deps, xdg-utils
Description: Local-first ServerDeck server management client
EOF
mkdir -p output/dist
dpkg-deb --root-owner-group --build "$stage" "output/dist/ServerDeck-$version-linux-x64.deb"
