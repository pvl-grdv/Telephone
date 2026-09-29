# CRM gateway integration

Telephone uses an independently deployed gateway for optional, read-only CRM
lookups. This repository contains the generic macOS client. Gateway deployment,
upstream CRM authentication, and private infrastructure settings are managed
separately.

## User setup

1. Obtain your HTTPS gateway origin and gateway access token from its operator.
2. Open **Settings → CRM** in Telephone.
3. Enter the HTTPS origin, for example `https://gateway.example`. Do not append
   a path, query, or credentials. A non-default HTTPS port is allowed.
4. Enter the gateway token, enable CRM lookup, and select **Apply**.
5. During a call, expand the client details area, enter a numeric key number,
   and select **Search**.

The token is stored in macOS Keychain under service
`com.tlphn.Telephone.crm-gateway`, with the canonical HTTPS origin as its
account. An empty token field preserves the saved token for that origin.
Changing the origin never sends another origin's token. **Remove token**
removes the credential for the currently saved origin and disables CRM lookup.
Previously configured origins retain their own credentials until removed.

The gateway and its network/VPN must be available. HTTPS uses normal system
certificate validation; the client does not trust arbitrary certificates or
disable App Transport Security. CRM email/password are never entered on the
Mac. The gateway token is a separate credential, not an upstream CRM JWT.

## Request

```http
POST /v1/customer-by-key/filter
Authorization: Bearer <gateway-token>
Content-Type: application/json
Accept: application/json
```

```json
{"keyNumber":76543}
```

`keyNumber` is a positive integer no greater than `9007199254740991`, preserving
exact representation in JavaScript as well as Swift. Phone/SIP/email caller
addresses are not valid key numbers. The app sends no other lookup fields and
does not call upstream CRM endpoints.

## Successful response

All example identifiers and names below are fictional.

```json
{
  "data": {
    "sourceKeyId": 76543,
    "company": {
      "id": 1200456,
      "name": "Example Company",
      "formattedCode": "98-76-5432"
    },
    "keys": [
      {
        "id": 76543,
        "name": "Sample76543",
        "url": "https://integral.ru/personal/keys/01-20-0456/76543/",
        "programs": [
          {
            "recordId": 7000101,
            "programId": 1000,
            "name": "Sample Program",
            "version": "4.0",
            "release": "0006",
            "keyUrl": "https://integral.ru/personal/keys/01-20-0456/76543/"
          }
        ]
      }
    ]
  },
  "meta": {
    "requestId": "fictional-request",
    "fetchedAt": "2026-01-01T12:00:00.000Z",
    "complete": true,
    "fromCache": false
  }
}
```

HTTP status is **200**. A missing key returns `"data": null` with the same
metadata structure. This is distinct from an authorization or service failure.
`programId`, `version`, and `release` may be null. Releases are strings, so
leading zeroes survive. Each `recordId` identifies a separate license/program
record; repeated program IDs and older version records must be preserved.
Additional upstream fields are ignored by the macOS decoder.

The displayed `formattedCode` need not match the organization ID. Portal URLs
use **company.id**, independently of the displayed code: convert the ID to
decimal digits, prepend one zero if there are fewer than eight digits, insert
a hyphen after the first four digits, then after the first two. Append the
numeric key ID. The client verifies the exact resulting HTTPS URL before
showing a link. Portal pages may require their own browser session; the
gateway token is never added to a portal link.

## Failure and completeness rules

| Condition | Telephone behavior |
|---|---|
| `200`, `data: null`, valid complete metadata | No owner found |
| `401` or `403` | Token rejected; update local settings |
| `429` | Ask the user to retry shortly |
| `500`–`599`, network/TLS failure | Gateway/CRM unavailable; explicit retry |
| `300`–`399` | Redirect refused; token is not forwarded |
| Other status, malformed JSON, `complete: false` | Invalid/incomplete response |

The gateway must finish all pages before returning `complete: true`. Partial
lists must fail rather than silently omit keys or programs. For a found owner,
the requested source key must appear in the returned key list. Key IDs and
program record IDs within each key are unique. Program portal URLs must match
their containing key. `meta.fetchedAt` is ISO 8601, with or without fractional
seconds; `meta.requestId` is a non-empty string.

The gateway's total lookup budget is 60 seconds. The app uses a 65-second
request timeout and a 70-second resource timeout so a gateway timeout response
can arrive. The user can cancel immediately. There is no automatic search
retry or authentication against the upstream CRM on macOS.

## Architecture and privacy

- `CompositionRoot` creates one gateway provider and one shared settings store;
  they reach each call window through its account controller.
- `CRMGatewayClient` is an actor with one permitted request shape and an
  ephemeral `URLSession`. Cookie storage, credential storage, and HTTP caching
  are disabled; every redirect is rejected.
- A dedicated lookup model tracks request, call context, and saved settings
  generations. Late responses from cancelled/previous searches are ignored.
- The result is transient call-window presentation. It does not replace SIP
  caller identity and is not written to local customer context automatically.
- Non-secret settings are local UserDefaults. Tokens are Keychain entries;
  neither tokens nor responses are logged by the gateway client.
- Production origins, tokens, upstream CRM credentials, real customers and
  captured responses must remain outside this public repository. Public tests
  use invented fixture data only.

The legacy address-based `CRMProvider` interface remains compatible and
disabled by default. Manual key lookup uses `CRMKeyLookupProvider` rather than
pretending that a key number is a phone address.

## Validation

Run the repository's standard commands on a Mac:

```sh
./script/test.sh
./script/build.sh Debug
```

Unit tests cover the endpoint and JSON allowlist, HTTPS origin validation,
redirect refusal, response decoding and completeness, safe portal links,
preservation of old records and releases, not-found versus errors, token origin
scoping, and cancellation/settings/context races. Localization smoke tests
include the CRM views and verify English, German and Russian strings. An
actual gateway connection requires a separately configured deployment and
local credentials.
