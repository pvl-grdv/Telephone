# Changelog

## 2.0
- Minimum deployment target macOS 26 on Apple silicon.
- Migrated Telephone application code to Swift 6.4 with strict concurrency.
- Moved call, transfer, account, settings, and call-history presentation to
  SwiftUI while retaining focused AppKit integration where macOS requires it.
- Moved the SIP runtime and PJSIP callback handling to Swift, leaving a narrow
  C boundary for the external PJSIP library.
- Added SQLite-backed call history and local customer context.
- Added App Intents and Shortcuts for calling, settings, and account status.
- Hardened account credentials, Contacts integration, CoreAudio selection,
  SIP lifecycle handling, and database migration behavior.
- Added reproducible pinned builds for PJSIP, Opus, and LibreSSL.
- StoreKit 2.
- Liquid Glass app icon.

## 1.6 - 2022-06-29
- macOS Big Sur.
- Apple silicon.
- Minimum deployment target 10.13.
- Fixed an issue where matching contact for an incoming call could not
  be found when the incoming phone number was exactly the same length
  as the significant phone number setting and the contact's phone
  number was longer than that.
- Remove user notification when incoming call is answered or declined.
- Allow the app settings to be copied to clipboard as text.
- LibreSSL 3.1.5.
