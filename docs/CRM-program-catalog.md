# Program catalogue

Open **CRM → Program Catalog…** (Cmd+Shift+P). This is a separate window that
uses the existing gateway settings and saved device token. It does not require
a SIP call. The private gateway must support `POST /v1/programs/filter` with an
empty JSON request and the ordinary complete-response metadata.

Search by name, catalogue ID, version, release or distribution directory.
The availability filter initially shows records available for new supply;
turn it off to see inactive historical entries. Sign/Stealth selects which
version, release and distribution directory are displayed. Same-named records
remain separate by ID, and release zeroes are preserved. No catalogue edits,
licence changes, distribution execution or downloads are performed.

Availability describes new supply. It is independent of the manufactured
programmes in a customer's inventory, which continue to include older versions.
The window keeps results in memory, clears them when access settings change,
and offers explicit refresh. Catalogue records are not added to call history.
