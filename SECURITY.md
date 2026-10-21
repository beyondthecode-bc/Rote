# Security policy

## Supported versions

Only the latest release on the [Releases](https://github.com/beyondthecode-bc/Rote/releases/latest) page is supported. Older versions get no fixes; update through Rote's About window or with `brew upgrade --cask rote`.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately through GitHub's
[private vulnerability reporting](https://github.com/beyondthecode-bc/Rote/security/advisories/new) for this repository.
Include the Rote version, macOS version, steps to reproduce and what an attacker gains.

What to expect:

- An acknowledgement within 7 days.
- A fix, or a decision explained to you, within 90 days of the report. Fixes ship as a new release; the advisory is published with it.
- Credit in the advisory and the release notes, unless you prefer to stay anonymous.

## Disclosure window

Please keep the report private for 90 days from the day you send it, or until a fix is released, whichever comes first. If a fix needs longer, we will tell you before the 90 days are up and agree on a date.

## What is in scope

- The Rote app and its in-app updater (`Rote/Engine/GitHubUpdateChecker.swift`).
- The release pipeline (`release.sh`, `.github/workflows`) and the Homebrew cask in `beyondthecode-bc/homebrew-tap`.

Every release is Developer ID signed, notarized by Apple and listed with its SHA-256 and VirusTotal result. The updater installs only a bundle whose signature matches Rote's Team ID and whose download matches the published checksum.
