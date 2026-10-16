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

If you are learning Swift, start with the [Russian-language code tour](docs/START-HERE.ru.md).
It explains the main files, useful boundaries, and the KISS approach to maintenance.

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
- SQLite-backed call history (no duplicate local customer database);
- App Intents and Shortcuts for calling, settings, and account status;
- hardened CoreAudio selection, account credentials, and SIP network
  validation;
- reproducible builds of pinned Opus, LibreSSL, and PJSIP dependencies.

The fork intentionally keeps the Telephone name and its upstream history, while
clearly identifying itself as independently maintained in the README and About
window. Product behavior and documentation in this repository should be treated
as authoritative for this fork when they differ from upstream.

The 2.0.1 update reviews the native presentation against
[WWDC25 concurrency guidance](https://developer.apple.com/videos/play/wwdc2025/266/)
and [WWDC26 SwiftUI guidance](https://developer.apple.com/videos/play/wwdc2026/269/).
It retains the existing Observation models and native scenes, checks cancellation
after asynchronous token reads, and adopts `ContentBuilder` and the current
button menu style in call history. Its native tests cover actual row visibility,
refreshing, and the separate answered, unanswered and unknown outcomes.

ATS answering-employee lookup is read-only and covers visible incoming
calls, including those declined locally with zero connected seconds. A
confirmed ATS outcome may show who accepted the call; an unverified result
shows why it cannot be attributed (missing caller match, time mismatch,
ambiguity or unconfirmed event). An older or unauthorized gateway displays
an explicit error rather than silently showing a local missed status as the
global outcome. Telephone does not persist ATS call or employee records.

This fork may continue to diverge from upstream as its maintenance needs evolve.

## Platform

The personal fork currently targets:

- Apple silicon
- macOS 26 or newer

## Installing a local update

This fork is still in development. GitHub Releases are paused; use test builds
from [macOS CI in Actions](https://github.com/pvl-grdv/Telephone/actions/workflows/ci.yml).
Open a successful run for `master`, check its source commit, and download the
`Telephone-<run number>-<commit>` artifact at the bottom of the run page. Sign
in to GitHub to download artifacts. The artifact contains the app ZIP, its
SHA-256 checksum and the package verification report. Artifacts expire after
7 days; run macOS CI manually to rebuild the selected commit when needed.

Download the packaged ZIP for the exact tested commit, unpack it on your Mac,
quit Telephone, and replace `Telephone.app` in Applications. Do not run the app
from inside the download archive. Check the new version and build in About
Telephone after launching it.

Before replacing an existing installation, keep a copy of the old app and its
data while Telephone is closed. In Finder, use Go → Go to Folder to locate
`~/Library/Containers/com.tlphn.Telephone` and copy the complete folder to a
private backup. If present, also copy
`~/Library/Application Support/com.tlphn.Telephone` and
`~/Library/Preferences/com.tlphn.Telephone.plist`. This retains the SQLite
database together with its accompanying files. Schema v6 preserves the call log and prior legacy-history import markers but
**deletes Telephone-only customer profiles, keys, email addresses, and notes**.
Back up the database together with its WAL/SHM files before starting the new
version if any of those local records are valuable. Only live CRM data remains
available in the client; CRM credentials and tokens are unaffected.

The bundle identifier and settings/Keychain services stay the same. Existing
SIP accounts and the saved gateway configuration are retained; the app does not
create a new gateway token during installation. Because local packages are ad-hoc
signed and are not notarized, macOS may ask you to confirm opening the app and
approve Keychain, microphone or Contacts access again. Follow
[Apple's app-opening instructions](https://support.apple.com/102445) for this
particular app if needed.

CI checks the checksum, bundle metadata, all embedded binary architectures,
signature and sandbox entitlements of the actual ZIP, then launches its
extracted Release app with SIP accounts and CRM disabled through launch
arguments. The accompanying verification report records the exact source
commit and package checksum. Native history UI tests use separate Debug-only
synthetic data; the distributed app contains no test scenario or gateway token.

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

The CRM interface uses the separately deployed gateway. If CRM is disabled,
Telephone still makes and receives calls and records history; it does not show
a separate local client-card editor.

### Optional CRM lookup through a gateway

Settings → CRM enables automatic lookup by the actual caller's phone number,
with a **numeric key number or email address** as a manual fallback in the call
window's client details section. One exact match shows its organization; multiple matches
require an explicit choice. Arbitrary SIP usernames are not treated as phones.
The result shows the owning organization, its code, all keys and all program
records, including older versions. Key and program links open the key's
personal account page.

The feature is disabled by default. Configure an HTTPS gateway origin and an
independent gateway token locally. The token is stored in macOS Keychain,
scoped to that origin; CRM credentials stay on the gateway computer. No
deployment addresses, customer data, or credentials are bundled with the app.

Telephone calls the gateway's fixed phone/key/email lookup routes. Email lookup
is case-insensitive and requires a plain, exact address; it never appends the
caller number to CRM. After manual key
lookup, **Link number to organization** can append the caller's phone to that
organization, with a confirmation showing the phone and organization. Existing
phone values are preserved and duplicates are avoided. The gateway token must
have separate permission for this operation; no general CRM editing is exposed.

The client rejects redirects, incomplete responses, and unexpected portal links. Searches
are asynchronous and can be cancelled; changing the call, input, or saved CRM
settings invalidates pending results. Existing SIP/audio behavior is unchanged.

See [the public gateway contract and setup guide](docs/CRM-gateway.md).

**Client details** is now a CRM-only, single-pane macOS browser using a native
`Table`, a key filter, and a single searchable toolbar. Manual lookup by key
or email lives in a compact popover. Search projection runs off the main actor
and is cancelled when superseded; it does not contact CRM again.

The old post-call CRM window and all local customer details/notes were
removed. SQLite schema v6 retains calls and the legacy import marker while
deleting obsolete customer/CRM tables. An archive requires a data backup made
before launching the upgraded app.

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
