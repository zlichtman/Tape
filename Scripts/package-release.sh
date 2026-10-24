#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
staging="$(mktemp -d "${TMPDIR:-/tmp}/tape-release.XXXXXX")"
profile="${TAPE_NOTARY_PROFILE:-MacSpaces}"
identity="${TAPE_SIGNING_IDENTITY:-Developer ID Application: Zach Lichtman (28LJG7MXT3)}"
notarize="${TAPE_NOTARIZE:-1}"
cleanup() {
  hdiutil detach "$staging/verify" >/dev/null 2>&1 || true
  rm -rf "$staging"
}
trap cleanup EXIT
cd "$project_root"
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit the final source before packaging a release.' >&2; exit 1; }
revision="$(git rev-parse HEAD)"
# Use the existing owner-authorized profile, just as MacSpaces does. Check it
# before building or signing so inaccessible credentials fail without wasted work.
if [[ "$notarize" == 1 ]]; then
  xcrun notarytool history --keychain-profile "$profile" --output-format json >/dev/null
fi
xcodegen generate
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
/usr/bin/grep -Fxq "**Tape $version**" RELEASE_NOTES.md || { echo 'Release notes and build version must match.' >&2; exit 1; }
if [[ -z "${TAPE_PREBUILT_APP:-}" ]]; then
  xcodebuild -quiet -project Tape.xcodeproj -scheme Tape -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$staging/build" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO TAPE_SOURCE_REVISION="$revision" build
  built_app="$staging/build/Build/Products/Release/Tape.app"
else
  # The CI artifact is from the same canonical Xcode build and exact source commit.
  # Never sign a prebuilt bundle with a mismatched identity, version or revision.
  built_app="$TAPE_PREBUILT_APP"
fi
app="$staging/Tape.app"
dmg="$staging/Tape.dmg"
ditto --noextattr --norsrc "$built_app" "$app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == dev.opensource.Tape ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :TapeSourceRevision' "$app/Contents/Info.plist")" == "$revision" ]]
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
codesign -dv --verbose=4 "$app" 2> "$staging/signature"
/usr/bin/grep -qx 'TeamIdentifier=28LJG7MXT3' "$staging/signature"
architectures="$(lipo -archs "$app/Contents/MacOS/Tape")"
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]
if [[ "$notarize" == 1 ]]; then
  ditto -c -k --keepParent "$app" "$staging/Tape.zip"
  xcrun notarytool submit "$staging/Tape.zip" --keychain-profile "$profile" --wait --timeout 60m
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
fi
mkdir "$staging/image"
ditto --noextattr --norsrc "$app" "$staging/image/Tape.app"
ln -s /Applications "$staging/image/Applications"
hdiutil create -quiet -volname 'Tape' -srcfolder "$staging/image" -format UDZO "$dmg"
codesign --force --timestamp --sign "$identity" "$dmg"
codesign --verify --strict "$dmg"
if [[ "$notarize" == 1 ]]; then
  xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait --timeout 60m
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
fi
mkdir "$staging/verify"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$staging/verify" "$dmg"
codesign --verify --deep --strict "$staging/verify/Tape.app"
if [[ "$notarize" == 1 ]]; then
  xcrun stapler validate "$staging/verify/Tape.app"
  spctl --assess --type execute --verbose=2 "$staging/verify/Tape.app"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
fi
hdiutil detach -quiet "$staging/verify"
mkdir -p Releases
ditto --noextattr --norsrc "$dmg" Releases/Tape.dmg
shasum -a 256 Releases/Tape.dmg
