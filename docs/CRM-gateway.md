# CRM gateway integration

Telephone uses an independently deployed gateway for optional CRM lookups and
one explicit phone association operation. This repository contains the generic
macOS client. Gateway deployment, upstream authentication and private
infrastructure settings are managed separately.

## User setup

1. Obtain your gateway address and a device access token from its operator.
   The operator opens the gateway setup shortcut on the Windows gateway
   computer, signs in to CRM once and creates a device token for this Mac there.
   The installed `Open-Setup.ps1` launcher opens the authorized local setup page;
   a bare API address is not a browser login page. CRM email/password stay on
   that computer; the gateway maintains its CRM session automatically.
2. Open **Settings → CRM** in Telephone.
3. Enter the HTTPS origin, for example `https://gateway.example`. Do not append
   a path, query or credentials. A non-default HTTPS port is allowed. If your
   operator supplies a Tailscale IPv4 address, **Allow HTTP over Tailscale**
   permits plain HTTP only for `100.64.0.0/10` with an explicit port. Use this
   only while Tailscale is connected; the IP address alone does not verify the
   peer. HTTPS remains the default.
4. Paste the device token into **Gateway token**, enable CRM lookup and select
   **Apply**. This token is separate from the CRM password and Tailscale login.
5. During a call, Telephone looks up the actual peer's phone number. One exact
   match shows its organization. Multiple matches require an explicit choice.
6. If the phone is absent, use **Search organization…**. Enter a numeric key
   ID directly in **Key number** and click **Find** (or press Return). Separate
   fields also allow email address and registration number searches, such as
   `98-76-5432`. Several email matches require an explicit choice.
7. During an eligible call, a verified phone lookup or manual key lookup may
   offer **Link number to organization**. A confirmation shows the phone and
   organization, and the token needs append permission.

The feature is disabled by default. **How to connect to the gateway** in CRM
settings explains the local setup, token creation and Telephone connection.
Tailscale Serve only exposes the gateway over the tailnet; it does not perform
gateway or CRM authentication. The local administration page must remain local
to the gateway computer and must not be published through Serve.

The token is stored in macOS Keychain under service
`com.tlphn.Telephone.crm-gateway`, with the canonical origin as its account.
Settings show the exact address for which a token is saved. An empty token
field preserves the token for that same address. Changing the address does not
automatically copy or send a credential saved for another address.

When switching between two addresses of the **same gateway**, for example its
HTTPS hostname and Tailscale IP, **Use saved token for this address** offers a
confirmation showing the saved and new addresses. Confirming stores the same
token for the new address and applies the settings. Use this only when both
addresses lead to the same trusted gateway. Dismissing the confirmation leaves
credentials unchanged; no token is shown or copied to the clipboard. A new
gateway requires its own device token. **Remove saved token** removes the token
for the explicitly displayed saved address and disables lookup. Other origins
retain their separate credentials until removed.

The gateway and its network/VPN must be available. HTTPS uses normal system
certificate validation. The optional HTTP connection uses Tailscale's protected
network path and is restricted to its shared IPv4 range, with an explicit
settings switch and port. The address and token remain local settings. CRM
email/password stay on the gateway computer.
The gateway token is a separate credential, not an upstream CRM JWT.

## Fixed request routes

All requests use `POST`, `Content-Type: application/json`,
`Accept: application/json` and `Authorization: Bearer <gateway-token>`.
There is no configurable route, general proxy, arbitrary query or CRM editor.
The application never calls upstream CRM endpoints directly.

### Gateway status (no CRM session)

```http
POST /v1/status
```

```json
{}
```

The authenticated **Settings → CRM → Check connection** action verifies
gateway access without contacting upstream CRM. Example HTTP 200 response:

```json
{
  "runtime": {
    "build": {
      "version": "1.4.0",
      "commit": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "builtAt": "2026-10-08T00:00:00.000Z",
      "integrity": "verified"
    },
    "startedAt": "2026-10-08T01:00:00.000Z",
    "processId": 123
  }
}
```

For `integrity: "verified"`, the gateway supplies a nonblank version,
a lowercase 40-hex commit and valid build timestamp. For
`integrity: "unknown"`, version, commit and build time are all explicitly
`null`. `startedAt` must be ISO 8601 and `processId` positive.
The status probe times out after 10 seconds; HTTP 404 means this optional
route is unsupported.

### Automatic phone lookup

```http
POST /v1/customer-by-phone/filter
```

```json
{"phoneNumber":"+12025550100"}
```

The result contains `matches: [{id,name,formattedCode}]`, `data` and `meta`.
Zero matches returns `data: null` and an empty array. Exactly one exact match
returns its complete inventory. Several matches return `data: null` and choices;
the client does not select one automatically.

Choosing a company repeats phone lookup with its ID:

```json
{"phoneNumber":"+12025550100","companyId":1200456}
```

The gateway revalidates the exact phone match. The client checks the returned
company against the selection. Phone inventory has `sourceKeyId: null`.

Normalization accepts ASCII digits and ordinary phone punctuation. Without an
explicit leading `+`, a Russian 10-digit national number receives prefix `7`,
and an 11-digit number starting with `8` changes that prefix to `7`. Explicit
international numbers retain their country code. Canonical requests contain
`+` followed by 8–15 digits. Letters, extensions, short SIP users and multiple
numbers are rejected. The gateway additionally handles existing CRM local
phones using the organization's city code; Telephone does not guess a city for
a short caller number.

Only the actual peer URI user is eligible. SIP display names, diagnostic headers
and arbitrary SIP usernames are not treated as phone identities.

### Manual key lookup

```http
POST /v1/customer-by-key/filter
```

```json
{"keyNumber":76543}
```

`keyNumber` is a positive integer no greater than `9007199254740991`, preserving
exact representation in JavaScript and Swift. The app sends no other key fields.

### Manual email lookup

```http
POST /v1/customer-by-email/filter
```

```json
{"email":"person@example.test"}
```

This is an exact, case-insensitive lookup of one plain ASCII email address.
Telephone and the gateway trim outer spaces and lowercase both parts. The local
part permits letters, digits, `.`, `_`, `+` and `-`, with no leading, trailing or
consecutive dots. Domain labels contain letters, digits and internal hyphens;
at least two labels are required. Local parts are at most 64 characters, labels
at most 63, and the whole address at most 254. Controls, whitespace within the
address, wildcards, percent signs, quoted mailboxes and recipient lists fail
validation before a request is sent.

The response uses the same `data`, `matches` and `meta` structure as phone lookup.
No match returns `data:null` and an empty matches array. Multiple exact matches
require an explicit choice, repeated as:

```json
{"email":"person@example.test","companyId":1200456}
```

The gateway rechecks that this organization still owns the email. An email
inventory has `sourceKeyId:null` and a required `company.emails` canonical,
unique array containing the searched address. Other lookup responses may omit
`emails`. Email lookup never automatically adds the caller's number to CRM and
does not offer the phone-append operation.

### Manual organization registration number lookup

The generic macOS client supports this **optional gateway capability**.
A gateway must implement the route below before Telephone can use it.
Until then, HTTP 404 produces an explicit update-gateway message rather than
silently falling back to searching by key or internal organization ID.

```http
POST /v1/customer-by-organization-code/filter
```

```json
{"organizationCode":"98-76-5432"}
```

Telephone accepts a displayed `NN-NN-NNNN` registration number or eight ASCII
digits, and transmits only the canonical **string** (including leading zeroes).
It never derives an internal `company.id`, key number or portal URL from it.
The gateway is responsible for authorization and an exact, unambiguous match
against its authoritative organization registration number. A unique match
returns the existing `CRMKeyLookupResponse` shape with the **complete**
`data` inventory, `sourceKeyId: null`, and `meta`. No match returns
`data: null`. Ambiguous values must fail rather than returning an arbitrary
organization. Telephone checks that `data.company.formattedCode` matches the
requested registration number and validates the usual inventory/URL invariants.
The endpoint is read-only and does not grant phone-append permissions.

### Incoming-call answer lookup (ATS)

This read-only route provides answering-employee attribution for local
call history. It is **not** the removed post-call CRM verification feature.

```http
POST /v1/incoming-call/answers
```

```json
{
  "calls": [{
    "id": "synthetic-call-1",
    "phoneNumber": "+12025550100",
    "startedAt": "2026-10-14T09:00:00.000Z"
  }]
}
```

Each request contains 1–25 entries with distinct local call IDs, canonical
phone numbers and ISO 8601 SIP start times. The app batches by UTC date
and never asks for a locally answered incoming call with positive duration.
A declined incoming call with zero connected seconds remains eligible.
Example HTTP 200 response:

```json
{
  "data": [{
    "id": "synthetic-call-1",
    "phoneNumber": "+12025550100",
    "startedAt": "2026-10-14T09:00:00.000Z",
    "status": "answered",
    "reason": null,
    "answeredBy": {"displayName": "Example Employee", "source": "ats"},
    "match": {
      "method": "phone-and-time",
      "confidence": "correlated",
      "startedAt": "2026-10-14T09:00:05.000Z"
    }
  }],
  "meta": {
    "requestId": "synthetic-answer",
    "fetchedAt": "2026-10-14T09:00:06.000Z",
    "complete": true,
    "fromCache": false
  }
}
```

The response must contain exactly one entry per submitted ID, with identical
`phoneNumber` and `startedAt`, valid complete metadata and `fromCache: false`.
The client validates three mutually exclusive outcomes:

- `answered`: `reason: null`, a nonblank employee name with
  `source: "ats"`, and a `match` with `method: "phone-and-time"`,
  `confidence: "correlated"` and a start time within **±10 seconds** of SIP.
- `unanswered`: `reason: null` and `answeredBy: null`, with the same
  verified time correlation in `match`.
- `unknown`: both `answeredBy` and `match` are `null`, with `reason`
  equal to `not-found`, `time-mismatch`, `ambiguous`, `transferred`,
  `not-confirmed` or `identity-unavailable`.

An unknown result must not become evidence that nobody answered.
HTTP 404 indicates an older gateway without the route. Authorization,
network and validation errors remain explicit rather than being presented
as missed calls. Telephone does not store ATS or employee data. Successful
answers for unchanged history records can be reused while scrolling;
the refresh control requests them again. A changed SIP record or gateway
settings invalidates the applicable cached answer.

## Inventory response

HTTP status is **200**. All names, phones and IDs in these examples are fictional.

```json
{
  "data": {
    "sourceKeyId": 76543,
    "company": {
      "id": 1200456,
      "name": "Example Company",
      "formattedCode": "98-76-5432",
      "phone": "+12025550100",
      "phones": ["+12025550100"]
    },
    "keys": [{
      "id": 76543,
      "name": "Sample76543",
      "url": "https://integral.ru/personal/keys/01-20-0456/76543/",
      "programs": [{
        "recordId": 7000101,
        "programId": 1000,
        "name": "Sample Program",
        "version": "4.0",
        "release": "0006",
        "keyUrl": "https://integral.ru/personal/keys/01-20-0456/76543/"
      }]
    }]
  },
  "meta": {
    "requestId": "fictional-request",
    "fetchedAt": "2026-01-01T12:00:00Z",
    "complete": true,
    "fromCache": false
  }
}
```

A missing key returns `data: null` with valid metadata. This differs from
authorization/service failure. `programId`, `version` and `release` may be null.
Releases are strings, so leading zeroes survive. Each `recordId` is a separate
record; repeated program IDs and older versions are preserved. The decoder
ignores additional upstream fields.

`company.phone` is a compatibility/concurrency snapshot supplied by the gateway.
Telephone passes it back as `expectedPhone` without interpreting CRM storage.
Old read-only gateways may omit it; lookup still works, but linking is unavailable
until a fresh response includes this field. It is not the destination for a new
phone number; CRM data is not saved in local call history.

`company.phones` is the gateway's canonical, deduplicated phone array, combining
all supported phone sources. Parsing existing phone lists, interpreting local
numbers and merging separate records belong to the gateway. It returns full
`+`-prefixed numbers. Telephone uses this array for
association checks before considering raw text. It rejects noncanonical values
or duplicates. Old gateways may omit the array; the client then uses raw-field
normalization as a compatibility fallback. `phone` itself remains untouched as
the exact append concurrency snapshot.

The gateway resolves ownership and constructs portal URLs. Telephone treats
`formattedCode` as display text and never derives a portal code from the
organization ID. Its navigation allowlist accepts only canonical HTTPS URLs on
`integral.ru`, with path `/personal/keys/<decimal-hyphen-segment>/<key-id>/` and
no port, credentials, query, fragment or encoded path. The organization segment
is opaque to the Mac and must match across all keys in an inventory; the numeric
key segment must match its record. Program links must equal their containing
key's URL. Gateway URLs are validated before presentation. The gateway is responsible for the semantic link
between the organization ID and that URL segment. Browser portal sessions are
independent; gateway tokens are never added to portal URLs.

### Keys and programs in the app

The gateway fetches every page of keys and program records, in ascending record
ID order. This transport order does not identify the latest version. Each
`recordId` remains a separate record, including repeated program IDs and older
versions; the response does not establish which record is active or licensed.

`CRMInventoryPresentation` prepares a display-only view of that complete
inventory for both live-call Client details and the standalone CRM window:

- The manually searched key appears first; other keys use ascending key number.
- Programs are grouped by `programId`. Records without that ID use their
  case-insensitive name; unnamed records stay separate.
- Program groups use name order. Within a group, version then release use
  descending numeric text comparison, so `10.0` precedes `9.0`. Missing values
  follow known values, and record ID breaks ties. This is display ordering, not
  semantic version parsing or an active-license decision.
- Search matches key number/name or program name/version/release. A matching
  program keeps its complete version history visible. Clearing search restores
  the full inventory. Filtering sends no additional gateway request.

The SwiftUI browser uses one native `Table` with a key `Picker` and a
search `TextField` beside it. Expensive filtering runs
off the main actor after a short debounce. There is no sidebar or alternate
compact rendering path; no records are removed to simplify the view.

Displayed totals distinguish keys, program groups and individual records. The gateway response retains all original records and their order;
presentation sorting does not discard or rewrite them.

## Explicit phone association

A manual key lookup or a confirmed incoming-phone lookup may offer this
operation. For a phone result, no manual key entry is needed: Telephone takes
a key already included in the organization's complete inventory. The gateway
still verifies the chosen key belongs to that company. If the organization has
no keys, the existing protected append route is unavailable.

The gateway additionally returns `company.atsPhones`, containing only the
separate ATS numbers. This is distinct from the merged `company.phones` list,
which also includes legacy numbers. A number found in the legacy field but
absent from `atsPhones` can be explicitly copied into ATS. Older gateways
without `atsPhones` cannot offer the phone-lookup shortcut. The actual caller
phone must be valid and the raw phone snapshot current. The confirmation
shows the number and company. Preparing or dismissing it sends nothing;
accepting it sends one request:

```http
POST /v1/customer-phone/append
```

```json
{
  "companyId":1200456,
  "sourceKeyId":76543,
  "phoneNumber":"+70005550101",
  "expectedPhone":"+12025550100"
}
```

```json
{
  "data": {
    "companyId":1200456,
    "phone":"+12025550100",
    "phones":["+12025550100", "+70005550101"],
    "added":true
  },
  "meta": {
    "requestId":"fictional-append",
    "fetchedAt":"2026-01-01T12:00:00Z",
    "complete":true,
    "fromCache":false
  }
}
```

The gateway checks permission, key ownership, the current compatibility snapshot
against `expectedPhone` and existing ATS phone associations. It adds the canonical
number to its configured phone storage, avoids equivalent duplicates and verifies
the result. Separate phone storage can leave `phone` unchanged while extending
`phones`; Telephone does not require the legacy text to change. `added:false`
means the number was already associated. The client does not know the upstream
write route, storage schema or regional rules.

`403` means missing append permission. `409` means the field changed. A network
failure or `PHONE_WRITE_UNCONFIRMED` can leave the write outcome unknown.
Every failed append blocks another attempt until **Refresh organization** reloads
the key result, including its actual current phone field.
Append is never retried automatically. Call/input/settings changes invalidate
the confirmation and UI result. A request accepted by the gateway can still
finish on the server after the window closes.

## Errors and completeness

| Condition | Telephone behavior |
|---|---|
| Complete `200`, `data: null`, no matches | No organization found; manual key or email fallback |
| `401`, or lookup `403` | Token rejected; update local settings |
| Append `403` | Phone append permission missing |
| Append `409` | Refresh organization before another append |
| `404` on status, registration-number or ATS answer lookup | Optional gateway capability unsupported |
| `429` | Retry shortly |
| `500`–`599`, network/TLS failure | Gateway/CRM unavailable; explicit retry |
| `300`–`399` | Redirect refused; token is not forwarded |
| Other status, malformed/incomplete response | Contract failure |

The gateway must finish all pages before `complete:true`. Partial lists fail
instead of omitting keys/programs silently. A manual key result must include its
source key. Key IDs and program record IDs within each key are unique. Program
URLs match their containing key. Metadata requires a non-empty request ID and
an ISO 8601 timestamp, with or without fractional seconds.

The gateway's total lookup budget is 60 seconds. App request/resource timeouts
are 65/70 seconds so gateway timeout responses can arrive. Lookup can be
cancelled. There is no automatic retry or upstream authentication on macOS.

## Architecture and privacy

### Retired history lookup and SQLite cleanup

Live-call **Client details** and the separate CRM window initiate CRM lookup.
The standalone window always shows distinct key-number, email and
registration-number fields without an active call. Each field searches
independently. Neither path stores CRM customer data locally.
The separate CRM verification window for old calls, manual history lookup,
post-call phone association and local CRM result snapshots have been removed.
Telephone does not run automatic CRM checks when calls end.

Schema v6 removes the old CRM snapshots and Telephone-only customer profiles,
key references, email addresses, and notes. It rebuilds `calls` without the
obsolete `party_id` foreign key, while preserving call history and import
markers. Old local details are permanently discarded on upgrade; archive
`Telephone.sqlite3` (including WAL/SHM) before launching if needed.
The Mac no longer persists any CRM inventory or local client-card data.

### Shared gateway behavior

- `CRMIntegrationRecords` contains the typed gateway results and provider
  interface used by live lookup and CRM inventory views.
  `CRMGatewayClient` owns transport and response validation. Presentation does
  not parse upstream CRM responses or choose upstream endpoints.
- `CompositionRoot` creates one provider/settings store and passes them through
  account controllers to each call window.
- `CRMGatewayClient` is an actor with fixed typed gateway routes and an ephemeral
  URLSession. Cookies, URL credential storage and HTTP caching are disabled.
  Every redirect is refused.
- Lookup state tracks request, call context and settings generations. Late
  responses are ignored. Phone confirmation carries the same scope and snapshot.
- Live-call and standalone CRM results are transient UI data, not persisted
  CRM snapshots. They do not replace SIP caller identity. The only CRM change
  is the explicitly confirmed phone append through the gateway.
- Call-history ATS attribution is read-only and does not store employee
  records or restore retired post-call CRM verification.
- Non-secret settings use local UserDefaults; gateway tokens use Keychain.
  Requests, tokens and customer responses are not logged by the client.
- Production origins/tokens, upstream credentials, real customers and captured
  responses stay outside the public repository. Tests use invented data.

CRM login/session recovery, upstream pagination, owner resolution, legacy and
separate phone storage, duplicate detection and phone writes belong to the
gateway. The Mac keeps caller input validation, token/origin security, safe link
validation and explicit choices/confirmations. Local call history remains
separate; the app does not receive CRM credentials or expose a general editor.

The legacy address-based `CRMProvider` remains compatible and disabled by
default. Key, email and phone lookup use explicit typed gateway methods instead of
pretending that a key is a phone address.

## Validation

Run the standard commands on a Mac:

```sh
./script/test.sh
./script/build.sh Debug
```

Tests cover status and ATS answer routes, route/body restrictions, HTTPS and
redirects, decoding/completeness, safe links, old records and release strings,
not-found/error distinctions,
token origin scoping, phone normalization, ambiguous choices, confirmation,
append permission/conflict handling and context/settings/cancellation races.
SQLite migration tests verify obsolete customer/CRM tables and notes are
removed while calls and prior legacy-import markers remain intact.
Localization smoke tests verify English, German and Russian UI strings.
Real integration checks require a separately configured gateway and credentials.
