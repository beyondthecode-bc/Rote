# Contributing to Rote

## Translations

Rote ships with 8 languages: English (source), French, German, Spanish, Japanese, Korean, Portuguese (Brazilian), and Chinese (Simplified). Native-speaker refinements via PR are welcome.

### How to contribute translations

1. Fork this repository
2. Edit an existing file in the `languages/` folder, or create a new one by copying `English.xml`
3. Translate the string values (the text between `<string>` tags) -- **do not** change the `key` attributes
4. Keep any `%1`, `%2`, `%@`, `%d` placeholders in place -- the app needs them
5. Run `python3 scripts/check-languages.py` and fix anything it reports -- it checks keys, placeholders, the ⌘ ⌥ ⌃ ⇧ symbols, "Esc" and "Rote" against `English.xml`
6. Submit a pull request with a brief description of changes

### Adding a new language

1. Copy `languages/English.xml` to `languages/YourLanguage.xml`
2. Translate all string values
3. Open a PR with your additions

### Translation guidelines

- **Technical terms** stay in English in all locales (e.g., CPU, GPU, RPM, app-specific identifiers)
- **App name** "Rote" is never translated
- **French**: follow Apple French Glossary (e.g., "Reglages" for Settings, "Quitter" for Quit)
- **German**: use formal `Sie` register, follow Apple macOS system terminology
- **Spanish**: use formal `usted` register, follow Apple Spanish Glossary
- **Japanese**: follow Apple Japanese Glossary conventions
- **Korean**: follow Apple Korean Glossary conventions
- **Portuguese (BR)**: use Brazilian Portuguese conventions
- **Chinese (Simplified)**: follow Apple Simplified Chinese Glossary
- **Plurals**: keys ending in `.one` and `.other` are the singular and plural forms of one phrase. Rote uses `.one` for 1 in English, German and Spanish, for 0 and 1 in French and Portuguese, and never in Japanese, Korean and Chinese (give both keys the same text there)
- **Spoken key names** (`spoken.*`): what VoiceOver reads for a shortcut's keys; use the names Apple's "Mac keyboard shortcuts" page uses in your language
- **Inserted times and names**: a phrase around `%1` must read correctly for any value, for example for both 1:00 and 13:00

## Code

Rote is Swift 6 with strict concurrency, SwiftUI, and two local packages. Keep `RoteCore` free of AppKit so its tests stay fast and deterministic.

1. Install Xcode 27.1 or later and `brew install xcodegen`, then run `xcodegen generate` (the `.xcodeproj` is not committed).
2. Run the language check and all three test suites before opening a pull request:

   ```bash
   python3 scripts/check-languages.py
   swift test --package-path Packages/RoteCore
   swift test --package-path Packages/RoteAX
   xcodebuild test -project Rote.xcodeproj -scheme Rote -destination 'platform=macOS' \
     -derivedDataPath build/derived CODE_SIGN_IDENTITY="-"
   ```

   `RoteCore` covers the shortcut model, the coaching rules, the weekly statistics and the state file; `RoteAX` covers the Accessibility wrappers against recorded menu fixtures; `RoteTests`, run by `xcodebuild test`, covers the app target (settings, the engine, the HUD, the shortcut sheet, onboarding and the localized strings).
3. CI runs the same checks on every pull request and on `main`, with the app built unsigned (`CODE_SIGNING_ALLOWED=NO`), and also builds the Release configuration, which fails when code outside `#if DEBUG` uses a Debug-only symbol.
4. Coaching rules live in `Packages/RoteCore/Sources/RoteCore/Coaching/Coach.swift`; every rule has a test in `CoachTests.swift` or `CoachRulesTests.swift`. Change the test first.
5. Text the app shows goes through `l("key")`, and the key goes into every file in `languages/`, translated where you can; `python3 scripts/check-languages.py` catches a key missing from a language file, and `LocalizedSourceTests` catches a key missing from `English.xml`, a plural phrase called without `count:` or without its `.one` and `.other` forms, and a shortcut spoken without `spokenShortcut`, which reads the `spoken.*` names.
6. Debug builds are signed ad hoc, so every rebuild looks like a new app to macOS and loses Accessibility access even while System Settings still shows Rote switched on. After a rebuild, remove Rote from System Settings › Privacy & Security › Accessibility and add the new build, or run `tccutil reset Accessibility com.beyondthecode.rote` and grant access again.
7. Debug builds have a **Debug** menu in the popover: simulate a nudge, simulate the shortcut sheet with a fixture Safari menu bar for screenshots (this needs Accessibility, which an ad-hoc Debug build loses on every rebuild; the item reads "Simulate overlay (needs Accessibility)" until access is granted), or export the frontmost app's menu snapshot as JSON for a new test fixture.
