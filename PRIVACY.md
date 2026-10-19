# Rote Privacy

Rote keeps everything on your Mac. There is no account, no analytics, no crash reporting and no telemetry of any kind.

## What it reads

- **Menus:** through the macOS Accessibility API, the titles, keyboard shortcuts and enabled state of the frontmost app's menu items, and which menu item you pick. It never reads window contents, passwords or clipboard data.
- **Keys and clicks:** a key monitor sees key presses, modifier keys and clicks while Rote runs, so it can tell when you used a menu's shortcut and when to open or close the shortcut sheet. A key press is only counted when it is the shortcut (with ⌘, ⌃ or ⌥, or an F-key) of a menu item Rote is coaching or has taught you; every other press is discarded at once. Rote never records or logs what you type.

## What it stores

- **`~/Library/Application Support/Rote/state.json`:** for each menu item with a shortcut that you picked with the mouse, the app's bundle identifier, the menu titles down to the item (for example Edit › Find › Find Next), its shortcut, and the times you used the menu item or its shortcut; the item's coaching state (coaching, learned, snoozed, stopped); a log of those uses kept for 30 days; and how many nudges were shown each day. If the file cannot be read, Rote starts fresh and keeps the old one next to it as `state.corrupt-<date>.json`.
- **Preferences** (`~/Library/Preferences/com.beyondthecode.rote.plist`): your settings (`coach.nudgeAfter`, `coach.itemSpacingHours`, `coach.dailyCap`, `coach.hudDuration`, `coach.soundEnabled`, `overlay.trigger`, `overlay.holdDelayMs`, `overlay.showItemsWithoutShortcuts`, `overlay.showAppleMenu`, `apps.excluded`, `apps.paused`, `updates.checkOnLaunch`, `rote.language`), whether onboarding is done (`onboarding.completed`), the last Settings tab (`settings.selectedTab`), and the end of a pause (`coach.pauseUntil`), so a pause survives quitting and relaunching. macOS may add the window and menu bar positions it saves for every app.
- **Launch at login** is registered with macOS (System Settings › General › Login Items), not stored by Rote.
- **Diagnostics:** short messages, such as an app's bundle identifier or the title of a menu item Rote nudged about, go to the macOS unified log on this Mac.

Settings › Data exports the state file as JSON and resets the statistics (items you stopped coaching are kept). To remove everything, quit Rote and delete `~/Library/Application Support/Rote` and `~/Library/Preferences/com.beyondthecode.rote.plist`.

## Network

Rote makes one kind of request: it asks the GitHub Releases API (`https://api.github.com/repos/beyondthecode-bc/Rote/releases/latest`) whether a newer version exists, when the app launches and when you click Check Now in Settings › About. Turn off "Check for updates on launch" in Settings › General to stop the launch check. Only when you click Download does Rote fetch the release's zip from GitHub. These requests carry no account, identifier or usage data; as with any website, GitHub sees your IP address and the standard user agent macOS adds (the app's name and build number and the system's networking version). The About tab's GitHub, GitHub Sponsors and Buy Me a Coffee links open in your browser only when you click them.

## Permissions

Accessibility only. Rote is not sandboxed, because the Accessibility API is unavailable to sandboxed apps.

## Contact

apps@beyondthecode.app
