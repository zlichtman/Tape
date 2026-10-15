# Production validation

This file records the scope of evidence. Tests and an illustrated film do not
prove live window behavior, physical gesture feel or competitive product quality.

## Automated gates

Run `swift test --scratch-path /tmp/Tape-tests` and the universal Xcode build.
The 1.29 suite covers geometry, parking, restoration, mixed window traits,
foreground/background insertion, app rules, focus/scan races, search, update
selection, gesture ownership and momentum, write isolation/coalescing, animation
pacing, accessory apps, custom subroles, post-scroll minimum widths, independent display
strips, pointer routing, transfers, per-display exclusion, mirroring, disconnected
display recovery and restoration after display rearrangement.
Additional 1.29 regression coverage includes lone-window sizing across app-tab/focus notifications, immediate close during motion, native drag ownership and edge browsing, shared resizing without writes to the dragged source, selected-window restoration and future-window exclusion, tab selection/order and temporary disappearance, and oversized-stack separation.
Controller tests use fake window servers, clocks and logging. They do not touch
real windows or create lifecycle entries in the production log.

For each release, CI must pass on its exact source commit; the mounted installer’s source revision must match that
commit. Signing, notarization,
stapling, mounted installer checks, both architectures and Gatekeeper are
separate required gates. Record the installed version after the Homebrew upgrade.

## Current runtime scope

Independent enabled-display strips, normal columns, keyboard focus and reordering, native drag reordering, shared widths, selected-window locking, stacks/tabs and height controls,
floating, Control–Option precision browsing, app selection, native menu and
Settings, and the verified updater are implemented. Tape excludes its own
windows, explicit dialogs/sheets, fixed-size panels, minimized and full-screen
windows. Accessory apps with normal windows are eligible. Application rules can
exclude any app. Discovery logs contain counts, never window titles.

## Required live acceptance — not yet proved

- Ten mixed apps, including normal custom windows, a menu-bar app’s Settings,
  dialogs, sheets, fixed-size panels and native full screen.
- All eligible on-screen windows discovered. A failed or late AX response must
  not permanently omit a normal window. Re-check the reported overlapping-window
  case; code coverage alone does not prove the screenshot is resolved.
- New foreground/background windows, long-strip keys, physical two-finger
  gestures and momentum, and transitions between browsing and keyboard focus.
- Native title-bar and edge drags, edge browsing during a drag, stacked-window minimum sizes, tab-strip click/drag behavior and focus across groups. Shared resizing under rapid input with mixed apps.
- Lock to one or several windows, restore exceptions and verify future windows stay unmanaged; selections reset only when Tape quits.
- Minimize, close, hide, reveal, restart apps and switch desktops; no lost windows.
- Permission loss and an unresponsive app; menu and Settings remain responsive.
- Pause and Quit restore sensible frames, including after gesture interruption.
- Side-by-side/stacked displays, unplug/reconnect and no cross-display parking.
- Idle CPU, actual input latency and AX write throughput with mixed apps.
- Intel/macOS 13 and Apple silicon on current macOS: physical runtime, fallback
  display links, appearance, permission flow, app selection and updater paths.
- Signed updater: newer/equal/older releases, wrong identity/build, incompatible
  platform, offline behavior, canceled and accepted installation.

Leave these unverified until trusted runtime evidence is available; never imply
that compilation substitutes for them.

## Remaining brief requirements

Production superiority remains unproved. The original brief also calls for
navigation overview; optional focus aids;
per-Space layout retention with an isolated fallback; persisted order/widths;
per-app placement rules; shortcut recording; login item; Mac Setup checks; URL,
CLI and Shortcuts integrations. These are incomplete in the current app. Preserve
this scope rather than redefining the goal around today’s passing release.
Independent display strips and sending windows between displays are implemented
and covered by model/controller tests; physical multi-display validation is still
required above. The requested two-finger public-scroll approach supersedes the earlier private
three/four-finger gesture proposal. Ordinary edge snapping belongs to macOS.
