# Tape instructions

Tape is a Swift menu-bar window manager for macOS 13+, universal Intel and Apple
silicon. `project.yml` is canonical; generated projects and Info.plist are ignored.
Keep the native menu, system appearance, searchable Settings and existing updater
conventions. Do not add an Appearance page or a version footer. Public versions
are `1.N`, with build `N`. Keep the owner’s artwork and wording original.

## Scope and privacy

Read BRIEF.md, README.md and CHECKS.md. Later user decisions override the brief:
leave ordinary snapping to macOS; preserve the accepted illustrated site demo;
use Control–Option horizontal precision scrolling without activating apps. The
owner has declined Computer Use. Do not automate or capture native Mac windows,
and do not claim physical runtime checks from simulated tests or the site film.
Keep tests isolated from production preferences, logs and Accessibility calls.
No accounts, telemetry, Screen Recording permission or private gesture APIs.
Preserve local owner changes and iCloud duplicate files while investigating them.

## Verification

Use `swift test --scratch-path /tmp/Tape-tests` for the engine/runtime suite.
Use fake window servers and clocks to exercise race conditions and failures.
Run the universal Xcode build for app/UI changes. Keep idle behavior notification
based. AX reads/writes stay off the main thread, with deadlines and latest-frame
coalescing. Never expand discovery by admitting arbitrary overlapping windows or
by blindly moving dialogs. CHECKS.md distinguishes proof from missing evidence.

## Release

Update release notes and version together. Commit and push the exact tested
source; CI must pass on that commit. Use the owner-authorized MacSpaces keychain
profile for the existing release script. Sign, notarize and staple the app and
DMG, verify Gatekeeper and both architectures, then publish with
Scripts/publish-release.sh. Update only Tape’s cask in zlichtman/tap, install
through Homebrew, and verify the installed bundle. Keep zlichtman.com’s download
link current in the owner’s Portfolio project without changing the demo.
