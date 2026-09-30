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
6. If the phone is absent, enter a numeric key number or one email address and
   select **Find by key** or **Find by email**. Several email matches require a choice.
7. After manual key lookup, **Link number to organization** offers a confirmation
   showing the phone and organization. This needs a token with append permission.

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

`company.phone` is the current raw organization phone field, used as an optimistic
concurrency snapshot. Old read-only gateways may omit it; lookup still works,
but linking is unavailable until a fresh response includes this field.

`company.phones` is the gateway's canonical, deduplicated phone array. It splits
the raw comma/semicolon/newline list, handles legacy local numbers using the
city code, and returns full `+`-prefixed numbers. Telephone uses this array for
association checks before considering raw text. It rejects noncanonical values
or duplicates. Old gateways may omit the array; the client then uses raw-field
normalization as a compatibility fallback. `phone` itself remains untouched as
the exact append concurrency snapshot.

The displayed `formattedCode` need not match the organization ID. Portal URLs
use **company.id**: convert it to decimal digits, prepend one zero if there are
fewer than eight digits, insert a hyphen after the first four digits, then after
the first two, and append the numeric key ID. The client checks the exact HTTPS
URL before showing a link. Browser portal sessions are independent; gateway
tokens are never added to portal URLs.

## Explicit phone association

Only a manual key result offers this operation. The actual caller phone must
be valid; the result must have a positive source key ID and a current raw phone
field. The confirmation shows the number and company. Preparing/dismissing it
sends nothing; accepting it sends one request:

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
    "phone":"+12025550100, +70005550101",
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

The gateway checks permission, key ownership and the complete current phone
field against `expectedPhone`. It preserves existing text, adds the canonical
number separated by a comma, avoids equivalent duplicates and verifies the
result. `added:false` means the number was already associated. Existing local
values can match through a city code even if the raw field lacks the full number.

`403` means missing append permission. `409` means the field changed. A network
failure or `PHONE_WRITE_UNCONFIRMED` can leave the write outcome unknown.
Every failed append blocks another attempt until **Refresh organization** reloads
the key result, including its actual current phone field.
Append is never retried automatically. Call/input/settings changes invalidate
the confirmation and UI result. A request accepted by the gateway can still
finish on the server after the window closes.

### From an existing call in history

History can also offer **Link number to organization** after a matched manual
key lookup and only when the existing call's stored peer `user` contains a full
phone number. A saved result does not authorize a write on its own. Telephone
re-reads the phone from that call and performs a fresh key lookup before showing
the confirmation; it verifies the same source key and owner. The gateway's
current raw `company.phone` is held only in memory as `expectedPhone` for this
one confirmation and is never saved in the SQLite snapshot. The dialog shows
the exact phone and organization; dismissing it sends no append request.

On confirmation, Telephone checks that the same call still exists, its phone
still matches, and the call, settings and lookup generations are current. It
then sends one append request. A second activation of the same confirmation
cannot send a second request. Email and phone lookup results, invalid internal
extensions, changed key ownership, or a deleted call cannot start this write.
After a confirmed success, the normalized organization inventory and updated
canonical phones replace that call's local snapshot. The raw CRM phone field is
removed. A local SQLite save error is reported separately from the completed
CRM write. If the append response cannot establish the write outcome, the UI
shows an unconfirmed result; the user must perform another fresh key lookup
before trying again. Closing the sheet after the request was sent cannot
guarantee that the server did not complete it.

## Errors and completeness

| Condition | Telephone behavior |
|---|---|
| Complete `200`, `data: null`, no matches | No organization found; manual key or email fallback |
| `401`, or lookup `403` | Token rejected; update local settings |
| Append `403` | Phone append permission missing |
| Append `409` | Refresh organization before another append |
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

### Explicit CRM checks from call history

Select an existing history row and use the **CRM** toolbar action or
**Check in CRM** context-menu action to check its phone now. The source number
comes from the existing SQLite call's peer `user` field, not a Contacts name or
the displayed history title. A first check uses phone lookup; later checks
refresh the last saved phone, key or email query.
History verification never places a call or edits CRM by itself. The separate,
explicitly confirmed key-based phone append described above is the only write.
The sheet also supports manual key and email searches, including calls whose
stored peer is an internal extension. A found organization is associated with
that selected call by saving its local verification result; it does not change
the call's phone identity or append that number to CRM.

**View saved CRM check** loads the saved local result without a network request.
The sheet's **Check CRM now** performs another explicit read. A fresh toolbar or
context-menu check also repeats the latest saved lookup identity; the first
check uses the stored peer phone. Manual key/email fields are restored when a
saved check is reopened. The sheet's **Find by phone** explicitly returns to
the original peer number. An old saved result
and its timestamp remain visible while the fresh request runs. Ambiguous matches
require a choice, revalidated by the same phone or email lookup with the company
ID. Refreshing a matched saved selection revalidates that chosen organization.

The newest verification outcome is saved against that existing call and account
in local SQLite: matched organization/inventory, no match, ambiguous candidates,
or a safe typed failure code. `checkedAt` is the local time this verification
finished; it does not assert what the CRM contained at the original call time.
The lookup provenance records the normalized phone, numeric key or email that
was actually checked; the original call phone remains separate. This makes a
manual association visible and refreshable without claiming a phone match.
The validated gateway request ID, fetched-at time, completeness and cache flag
are retained as evidence. One latest outcome replaces the previous check; this
is not an audit timeline of CRM changes.

Only an approved, normalized snapshot is stored: canonical phones/emails, lookup
provenance, company
name/code/ID, all key/program records and checked portal links. Raw company
phone text, credentials, origins, authorization/network headers and unfiltered
response bodies are excluded. Saved snapshots are validated again before their
links are displayed; invalid or oversized snapshots are rejected. The save and
restore limit is the same 16 MiB.

Closing the sheet, changing accounts/calls, or changing CRM settings cancels
pending checks and invalidates late results. Snapshots cannot create a call row;
if the original row was deleted, saving reports that it no longer exists.
Database read/save failures are shown separately from CRM errors. This feature
does not automatically backfill old calls or run CRM checks when a call ends.

### Shared gateway behavior

- `CompositionRoot` creates one provider/settings store and passes them through
  account controllers to each call window.
- `CRMGatewayClient` is an actor with four fixed typed requests and an ephemeral
  URLSession. Cookies, URL credential storage and HTTP caching are disabled.
  Every redirect is refused.
- Lookup state tracks request, call context and settings generations. Late
  responses are ignored. Phone confirmation carries the same scope and snapshot.
- Live-call results are transient UI data. Explicit history checks are saved
  locally with their verification time. Neither replaces SIP caller identity
  nor automatically updates local customer notes. The only CRM change is the
  explicitly confirmed phone append through the gateway.
- Non-secret settings use local UserDefaults; gateway tokens use Keychain.
  Requests, tokens and customer responses are not logged by the client.
- Production origins/tokens, upstream credentials, real customers and captured
  responses stay outside the public repository. Tests use invented data.

The legacy address-based `CRMProvider` remains compatible and disabled by
default. Key, email and phone lookup use explicit typed gateway methods instead of
pretending that a key is a phone address.

## Validation

Run the standard commands on a Mac:

```sh
./script/test.sh
./script/build.sh Debug
```

Tests cover route/body restrictions, HTTPS and redirects, decoding/completeness,
safe links, old records and release strings, not-found/error distinctions,
token origin scoping, phone normalization, ambiguous choices, confirmation,
append permission/conflict handling and context/settings/cancellation races.
History tests additionally cover normalized snapshot encoding, safe metadata,
saved-result reopening without network, current-time checks, ambiguous choices,
stale call/account/settings replies, deleted rows, visible local save errors,
manual key/email provenance and restoring/refreshing their saved associations.
Localization smoke tests verify English, German and Russian UI strings.
Real integration checks require a separately configured gateway and credentials.
