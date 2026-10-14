**Tape 1.29**

- A lone window fills the screen automatically. Opening an app tab or receiving another focus notification keeps the same layout; explicitly chosen widths remain yours.
- Drag a title bar to reorder columns without Tape correcting it mid-drag. Hold near a display edge to browse the strip while dragging.
- Resize a native window by its edge. Enable Resize Windows Together to share width changes across its display, or use All Window Widths for a single group resize.
- Lock Tape to selected open windows. Unchecking a window restores its original size and position; future windows stay unmanaged while locked.
- Join neighboring columns as stacks or tabs, select and reorder their windows, adjust stack heights, and separate a window again. Tape’s native tab strip supports drag reordering.
- Closing a window immediately retargets the remaining layout, including during motion. Preserve column widths and groups across temporary window disappearance, and separate stacks that exceed an app’s minimum height.
- Pause and Quit retain restoration frames for previously managed windows missing from a later scan. Restoration follows in-flight animation writes in each app’s queue, so an old off-screen frame cannot overwrite it.
- Keep known windows through transient Accessibility read failures only when public window geometry corroborates them. Frame work remains display-paced and coalesced per app.

**Tape 1.28**

- Jump to the first or last window with Control–Option–[ / ] on compact keyboards; Home/End still work.
- Bind signed installers to their exact source commit and reject stale release artifacts.
- Give each enabled display its own window strip, widths, focus and scroll position.
- Control–Option scrolling browses the display under your pointer without switching apps or changing keyboard focus on another display.
- Move the selected window to another display from the native menu, or use Control–Option–D for the next enabled display. Width presets are preserved.
- Enable or disable individual displays in General settings. Disabling restores their windows; Pause leaves those windows alone.
- Preserve local restoration positions when displays are rearranged, and recover reachable layouts when a display is disconnected. Mirrored displays share one strip.
- Discard obsolete queued motion on display/desktop changes. Closing tail windows no longer leaves the viewport beyond the strip.

**Tape 1.27**

- Include normal windows from menu-bar apps in discovery and the app picker.
- Recognize movable, resizable custom windows with missing or unknown subroles. Keep dialogs, sheets, fixed-size panels and Tape’s own windows outside the strip.
- Retry incomplete Accessibility discovery up to twice instead of caching failed capability reads. Allow small drift between independent frame reads.
- Preserve centered edge margins when browsing, and learn app-enforced minimum widths after a scroll.
- Log discovery counts without window titles. Keep simulated controller tests out of the real app’s log.

**Tape 1.26**

- Hold Control–Option and scroll horizontally with two fingers to browse the strip without activating apps. Natural-scroll direction and macOS momentum are preserved; ordinary scrolling stays with your apps.
- Pace animation and scrolling with the display, without a second filter skipping refreshes. Retargeting uses the remaining animation time rather than restarting the full easing duration.
- Use independent frame-write queues per app, coalescing each window’s waiting frames. A slow app no longer blocks movement in other apps.
- Wait for queued frame writes to settle before the reconciliation scan, and cancel pending scrolling on pause, quit and desktop changes.
- Explain trackpad browsing in the first-run guide, searchable Settings and README.

**Tape 1.25**

- Reverse an in-progress layout animation from its current position, without ignoring the new command.
- Correct manually displaced managed windows even when the strip layout has not changed.
- Avoid repeated correction animations when an app refuses the same frame.
- Keep stale scan callbacks from interfering with a new pause/resume session.
- Write the last animation step once.

**Tape 1.24**

- Keep window-creation listeners for managed apps before their first window opens.
- Preserve the 1.23 reductions in excluded-app scanning and stale focus reads.

**Tape 1.23**

- Skip Accessibility scans of excluded apps and apps with no visible windows.
- Coalesce focus notifications and discard reads superseded by newer keyboard commands.
- Preserve window handles until deselected apps have received their restoration frames.

**Tape 1.22**

- Replace the custom black menu with a native macOS menu. Remove theme controls and the sidebar version footer.
- Add menu commands for choosing windows, moving columns, and setting an explicit width.
- Keep deselected apps untouched when pausing or quitting; stop retaining ownership of their frames.
- Choose managed apps with checkboxes, an app picker, and an option to manage only selected apps. Unchecking an app restores its windows.
- Keep focus independent of animation writes and scans; protect rapid navigation from stale focus events.
- Resize windows once, then animate only their positions. Skip unchanged Accessibility writes and batch window reads.
- Preserve initial left-to-right order and reconcile desktop changes without continuing stale animation.
- Replace the multi-page setup with a short guide available from the menu. Show the icon and version with the updater. Match the MacSpaces updater’s layout, small native button, checkbox rows, and restart wording.
- Use the MacSpaces version convention: 1.22 is build 22, displayed without a separate build suffix.

Universal macOS 13+ build. Accessibility only. Trackpad swiping, multi-display strips, and stacks are not included.
