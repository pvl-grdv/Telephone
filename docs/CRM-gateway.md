# CRM gateway integration

Telephone uses an independently deployed gateway for optional CRM lookups and
one explicit phone association operation. This repository contains the generic
macOS client. Gateway deployment, upstream authentication and private
infrastructure settings are managed separately.

## User setup

1. Obtain your HTTPS gateway origin and gateway access token from its operator.
2. Open **Settings → CRM** in Telephone.
3. Enter the HTTPS origin, for example `https://gateway.example`. Do not append
   a path, query or credentials. A non-default HTTPS port is allowed.
4. Enter the gateway token, enable CRM lookup and select **Apply**.
5. During a call, Telephone looks up the actual peer's phone number. One exact
   match shows its organization. Multiple matches require an explicit choice.
6. If the phone is absent, enter a numeric key number and select **Search**.
7. After manual key lookup, **Link number to organization** offers a confirmation
   showing the phone and organization. This needs a token with append permission.

The feature is disabled by default. The token is stored in macOS Keychain under
service `com.tlphn.Telephone.crm-gateway`, with the canonical HTTPS origin as its
account. An empty token field preserves that origin's saved token. Changing the
origin never sends another origin's credential. **Remove token** removes the
credential for the saved origin and disables lookup. Previous origins retain
their separate credentials until removed.

The gateway and its network/VPN must be available. HTTPS uses normal system
certificate validation; the client does not trust arbitrary certificates or
disable App Transport Security. CRM email/password stay on the gateway computer.
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

## Errors and completeness

| Condition | Telephone behavior |
|---|---|
| Complete `200`, `data: null`, no phone matches | No organization found; manual key fallback |
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

- `CompositionRoot` creates one provider/settings store and passes them through
  account controllers to each call window.
- `CRMGatewayClient` is an actor with three fixed typed requests and an ephemeral
  URLSession. Cookies, URL credential storage and HTTP caching are disabled.
  Every redirect is refused.
- Lookup state tracks request, call context and settings generations. Late
  responses are ignored. Phone confirmation carries the same scope and snapshot.
- Results are transient UI data. They do not replace SIP caller identity or
  automatically update local customer context. The only CRM change is the
  explicitly confirmed phone append through the gateway.
- Non-secret settings use local UserDefaults; gateway tokens use Keychain.
  Requests, tokens and customer responses are not logged by the client.
- Production origins/tokens, upstream credentials, real customers and captured
  responses stay outside the public repository. Tests use invented data.

The legacy address-based `CRMProvider` remains compatible and disabled by
default. Key and phone lookup use explicit typed gateway methods instead of
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
Localization smoke tests verify English, German and Russian UI strings.
Real integration checks require a separately configured gateway and credentials.
