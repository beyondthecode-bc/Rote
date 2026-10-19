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
