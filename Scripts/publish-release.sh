#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
repo=zlichtman/Tape
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
tag="v$version"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
/usr/bin/grep -Fxq "**Tape $version**" RELEASE_NOTES.md || { echo 'Release notes and build version must match.' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit the final source before publishing.' >&2; exit 1; }
staging="$(mktemp -d "${TMPDIR:-/tmp}/tape-publish.XXXXXX")"
trap 'hdiutil detach "$staging/mount" >/dev/null 2>&1 || true; rm -rf "$staging"' EXIT
mkdir "$staging/mount"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$staging/mount" Releases/Tape.dmg
app="$staging/mount/Tape.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == dev.opensource.Tape ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$build" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :TapeSourceRevision' "$app/Contents/Info.plist")" == "$(git rev-parse HEAD)" ]] || { echo 'Installer source revision differs from the current commit.' >&2; exit 1; }
codesign --verify --deep --strict "$app"
codesign -dv --verbose=4 "$app" 2> "$staging/signature"
/usr/bin/grep -qx 'TeamIdentifier=28LJG7MXT3' "$staging/signature"
architectures="$(lipo -archs "$app/Contents/MacOS/Tape")"
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]
xcrun stapler validate "$app"
xcrun stapler validate Releases/Tape.dmg
spctl --assess --type execute "$app"
spctl --assess --type open --context context:primary-signature Releases/Tape.dmg
hdiutil detach -quiet "$staging/mount"
commit="$(git rev-parse HEAD)"
remote_commit="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
[[ "$remote_commit" == "$commit" ]] || { echo 'Push the source to main before publishing.' >&2; exit 1; }
gh run list --repo "$repo" --workflow ci.yml --commit "$commit" --limit 10 --json conclusion --jq '.[].conclusion' > "$staging/ci"
/usr/bin/grep -qx 'success' "$staging/ci" || { echo 'CI must pass on the exact source commit.' >&2; exit 1; }
cat RELEASE_NOTES.md > "$staging/notes.md"
printf '\n<!-- tape-build:%s -->\n<!-- tape-source:%s -->\n' "$build" "$commit" >> "$staging/notes.md"
if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
  [[ "$(git rev-parse "$tag^{commit}")" == "$commit" ]] || { echo "Existing $tag points to a different source commit." >&2; exit 1; }
else
  git tag "$tag"
fi
git push origin "$tag"
gh release create "$tag" Releases/Tape.dmg --repo "$repo" --title "Tape $version" --notes-file "$staging/notes.md" --verify-tag --latest
expected="sha256:$(shasum -a 256 Releases/Tape.dmg | awk '{print $1}')"
actual="$(gh api "repos/$repo/releases/tags/$tag" --jq '.assets[] | select(.name == "Tape.dmg") | .digest')"
[[ "$actual" == "$expected" ]] || { echo 'Published checksum differs.' >&2; exit 1; }
./Scripts/prepare-homebrew.sh
echo "Published Tape $version. The matching cask is Homebrew/tape.rb."
