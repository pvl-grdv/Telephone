# Telephone

Telephone is a VoIP SIP softphone for macOS. It lets you make phone calls over
the Internet or a company network using a SIP account.

> **Fork notice**
>
> This repository is a personal, independently maintained fork of
> [64characters/Telephone](https://github.com/64characters/Telephone). It is not
> the upstream project. The original repository remains the reference for the
> project's history and upstream work.

## Goals of this fork

Telephone 2 is a small, native macOS evolution of the original app. The
application layer is Swift, with SwiftUI owning user-facing presentation and
AppKit used only where macOS-specific integration needs it.

In particular, this fork aims to:

- keep Telephone working on current macOS releases and Apple silicon;
- keep application code readable, explicit, and approachable to Swift
  developers;
- preserve proven SIP and audio behavior while exposing it through a narrow
  Swift-to-C boundary;
- keep third-party dependencies pinned and reproducible;
- prefer small, reviewable migrations over a big-bang rewrite.

PJSIP, Opus, and LibreSSL remain external C dependencies. Telephone does not
rewrite those libraries; it keeps their unsafe/C details at the lowest practical
boundary of the application.

## Current direction

Telephone 2 now includes:

- a Swift 6.4 application layer with complete strict-concurrency checking;
- native SwiftUI scenes for calls, accounts, settings, transfer, and call
  history;
- a Swift SIP runtime and Swift PJSIP callbacks, with one narrow C callback
  header at the library boundary;
- SQLite-backed call history and local customer context;
- App Intents and Shortcuts for calling, settings, and account status;
- hardened CoreAudio selection, account credentials, and SIP network
  validation;
- reproducible builds of pinned Opus, LibreSSL, and PJSIP dependencies.

The fork intentionally keeps the Telephone name and its upstream history, while
clearly identifying itself as independently maintained in the README and About
window. Product behavior and documentation in this repository should be treated
as authoritative for this fork when they differ from upstream.

This fork may continue to diverge from upstream as its maintenance needs evolve.

## Platform

The personal fork currently targets:

- Apple silicon
- macOS 26 or newer

## Building

Third-party dependencies are pinned and built by the repository bootstrap
script:

- Opus 1.5.2
- LibreSSL 4.3.2
- PJSIP 2.17

Build the dependencies:

    $ ./script/bootstrap_third_party.sh

Build Telephone:

    $ ./script/build.sh Debug

Build and run the local app:

    $ ./script/build_and_run.sh

CI stamps packaged builds with the GitHub Actions run number as
`CFBundleVersion` and embeds the source commit shown in the About window.
Local builds made through `script/build.sh` use the Git commit count and the
current short commit SHA.

Only builds from `master` (or manually dispatched workflows) are retained as
downloadable Actions artifacts. These artifacts expire after 7 days; work
branches still build and test, but do not retain app ZIPs.

CI uses ad-hoc signing. For repeated local development, create a stable
self-signed code-signing identity once so macOS Keychain/TCC can recognize
subsequent builds:

    $ bash ./script/create_local_signing_identity.sh
    $ export TELEPHONE_CODE_SIGN_IDENTITY="Telephone Local Development"
    $ ./script/build_and_run.sh

This identity is local to your Mac and does not require an Apple Developer
Program membership. If `TELEPHONE_CODE_SIGN_IDENTITY` is unset, the build
scripts fall back to ad-hoc signing.

The bootstrap script records dependency versions in each installation prefix,
so an existing checkout is rebuilt automatically when a pinned version changes.
Telephone-specific PJSIP patches live in `ThirdParty/PJSIP/patches`.

## Automation on macOS 27

Telephone exposes normal App Intents for the Shortcuts app:

- **Dial with Telephone** accepts a phone number or SIP address;
- **Open Telephone Settings** opens the SwiftUI settings scene;
- **Set Telephone Account Status** changes an enabled SIP account between
  Available, Unavailable, and Offline.

On macOS 27, Telephone also adopts the Phone `startCall` App Schema. This lets
Siri understand Telephone as an app that can place an audio call to a person,
instead of treating calling as an app-specific text command. Telephone supports
one destination per call and audio calls only.

After installing or rebuilding Telephone, launch the app once so the system can
refresh its App Intents metadata. The app-specific actions can then be found in
Shortcuts by searching for `Telephone`.

## Caller identity and customer context

Incoming-call presentation keeps SIP transport details out of the window title
and shows one primary identity. Telephone enriches that identity asynchronously
without delaying ringing:

1. the formatted SIP caller address is available immediately;
2. a meaningful SIP display name can replace the raw number;
3. macOS Contacts can add a person's name, organization, and phone label;
4. a configured CRM provider can promote the company name and return reference
   keys, programs associated with those keys, and email addresses.

The CRM interface is present, but this repository does not ship an Avantel CRM
adapter or credentials. With no CRM provider configured, the provider is
disabled and local customer context remains local to Telephone.

For diagnosing a PBX integration, Telephone captures a small allowlist of
identity and routing headers from the original incoming SIP INVITE, including
`P-Asserted-Identity`, `Remote-Party-ID`, `Diversion`, `History-Info`,
and selected `X-*` identity headers. They are retained on the call object and
logged only at the more verbose PJSIP log level used for diagnostics. They are
not treated as trusted CRM fields automatically.

## Profiling active calls

Telephone marks connected calls with the `CallPerformance / ActiveCall`
signpost interval. With Telephone already running, record a SwiftUI Instruments
trace with:

    $ TRACE_DURATION=60s ./script/profile_active_call.sh

The trace is written under `build/` by default and can be opened directly in
Instruments. A real SIP call is required for representative call-window data.

## Development workflow

Development for this fork happens in `pvl-grdv/Telephone`. The original
`64characters/Telephone` repository is treated as upstream reference material;
this fork does not automatically send its changes back upstream.

Changes normally use short-lived `work/<topic>` branches. CI runs unit tests and
the app build, and validated work is integrated into `master` as a clean logical
commit.

Detailed repository rules are in [AGENTS.md](AGENTS.md).

## Attribution and license

This project is based on
[64characters/Telephone](https://github.com/64characters/Telephone) and retains
the original repository history.

The source code in this repository is distributed under the GNU General Public
License v3.0. See [LICENSE](LICENSE) for the full license text.
