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

## What this fork includes

Telephone 2 currently includes:

- a Swift 6.4 application layer with complete strict-concurrency checking;
- native SwiftUI scenes for calls, accounts, settings, transfer, and call
  history;
- a Swift SIP runtime and Swift PJSIP callbacks, with one narrow C callback
  header at the library boundary;
- SQLite-backed call history (no duplicate local customer database);
- optional gateway-backed CRM lookup during live calls and in a separate window;
- an explicit, permission-checked way to associate a caller's number with ATS;
- App Intents and Shortcuts for calling, settings, and account status;
- hardened CoreAudio selection, account credentials, and SIP network
  validation;
- reproducible builds of pinned Opus, LibreSSL, and PJSIP dependencies.

The fork intentionally keeps the Telephone name and its upstream history, while
clearly identifying itself as independently maintained in the README and About
window. Product behavior and documentation in this repository should be treated
as authoritative for this fork when they differ from upstream.

Recent incremental changes focus on simpler state transitions, reusable CRM
validation, independently cancellable call-window tasks, and serialized SIP
Keychain updates. The goal is to make behavior easier to follow without
rewriting the underlying SIP and audio integrations.

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

## First launch and everyday use

Telephone needs a SIP account to make and receive calls; a CRM gateway is
optional. On first launch, add an account when prompted. Later, use
**Settings → Accounts** to manage SIP accounts. Each enabled account has a
window with a dialer and its call history. The dialer accepts telephone
numbers and SIP addresses, and can suggest macOS Contacts after permission is
granted.

Call windows behave like normal macOS windows by default. If you want them
to stay above other windows, turn on **Call → Keep on Top**. This is an
optional, saved setting; Telephone does not force floating windows.

To inspect CRM keys and programs without placing a call, use
**CRM → Search organization…** (`Shift-Command-K`) after configuring
**Settings → CRM**. See [CRM lookup](#optional-crm-lookup-through-a-gateway)
for the difference between read-only searches and explicit phone linking.

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
**deletes obsolete Telephone-only customer profiles, keys, email addresses,
and notes**.
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

Run the unit and presentation tests:

    $ ./script/test.sh

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
4. when CRM is enabled, a separate customer summary and details view can
   display the matching company, its keys, programs, and email addresses.
   CRM lookup does not replace the SIP caller identity.

The CRM interface uses the separately deployed gateway. If CRM is disabled,
Telephone still makes and receives calls and records history; it does not show
a separate local client-card editor.

### Optional CRM lookup through a gateway

CRM is **off by default** and is not needed for SIP calling or call history.
In **Settings → CRM**, configure a separately deployed gateway with an HTTPS
origin and a device token. Telephone stores that token in macOS Keychain,
scoped to the gateway origin; upstream CRM passwords stay on the gateway
computer. An opt-in Tailscale HTTP connection is supported only under the
restrictions described in [gateway setup](docs/CRM-gateway.md).

#### Lookup during a call

Telephone can look up the actual caller's eligible phone number automatically.
One exact company match loads its inventory; several matches require you to
choose the company. Arbitrary SIP usernames and display names are not treated
as phone numbers.

Open **Client details → Search organization…** to search manually by
**key number, email address, or organization registration number**
(for example, `98-76-5432`). Registration-number lookup requires a gateway
that supports that route; older gateways report an explicit unsupported
feature instead of guessing an organization.

#### CRM without an active call

Use **CRM → Search organization…** (`Shift-Command-K`) for a separate
window with the same manual key, email, and registration-number searches.
This window is independent of SIP calls and allows you to browse keys and
programs without calling anyone. It has no caller phone to associate and
does not offer phone linking.

#### Keys, programs, and search

The result is a read-only, single-pane table of all returned keys and
program records, including older versions. Filter by key and search keys,
programs, versions, or releases. **Searching or clearing the text preserves
your selected key**; searching the inventory does not make another CRM
network request. Version order is for display and does not establish whether
a license is active. Links to the personal key portal come from the gateway
and are checked before they can be opened.

#### Explicitly linking a caller phone to ATS

During a live call, **Link number to organization** may be available after
a verified caller-phone or manual key lookup. If the caller's phone exists
only in the organization's legacy phone field and is absent from the separate
ATS list (`company.atsPhones`), the button can offer to add it to ATS.
The legacy field remains unchanged. Telephone uses a verified key belonging
to that company; **no manual key search is required for a verified phone
lookup**, but an organization with no keys cannot use the protected append
route. Older gateways without `company.atsPhones` cannot offer that
phone-lookup shortcut.

Linking requires a gateway token with append permission **and an explicit
confirmation** identifying the phone and organization. Nothing is written
when you search, open the confirmation, or dismiss it. The gateway
rechecks key ownership and the current phone value before accepting the
single write. Email and registration-number lookups do not grant phone
linking. After an uncertain or failed write, refresh the organization
before another attempt; the app never retries a write automatically.

The app rejects redirects, unsafe key links, and incomplete responses.
Changing a call, search input, or CRM settings invalidates stale lookup
results. CRM inventories and phone associations are not stored in the
local call-history database. The retired **post-call history verification**
window is gone; it is distinct from the current standalone CRM search window.

For complete route, permission, and privacy details, see the
[CRM gateway contract and setup guide](docs/CRM-gateway.md).

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
