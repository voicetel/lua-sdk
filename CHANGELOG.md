# Changelog

## 2.2.17 — 2026-10-17

Spec v2.2.17 sync.

### Fixed
- DID `route` fields are documented as the global route enum (1 USER, 2 T30, 3 VOICE_BRIDGE, 4 DID (default), 5 T38, 6 VOICEML, 8 SDN, 9 MOBILE); examples that showed invalid values (0, 1000) corrected.
- Example data sanitized suite-wide (fiction-reserved 555-01xx phone numbers; no real names/addresses/campaign IDs); no API behavior change.

## 2.2.16 — 2026-10-17

Spec-conformance release tracking VoiceTel API spec v2.2.16. **Contains breaking changes** — request shapes now match the documented wire format.

### Breaking
- `login` / API-key exchange and sub-account create: `username` (and `masterAccount`) are now **strings** per spec.
- `GET /v2.2/inventory` search: parameters are `tnMask` (required), `quantity`, `province`, `rateCenter`, `lata`; the old `npa`/`nxx`/`state`/`ratecenter`/`contains`/`endswith`/`limit` params were removed.
- `GET /v2.2/inventory/coverage`: `countBy` (required; `state`/`city`/`rateCenter`/`npanxx`/`block`) plus `locState`/`city`/`rcAbbre`/`npa`/`lata`; the old `state`/`ratecenter` params were removed.
- `GET /v2.2/messages` history: parameters are `number` (required), `from`, `to`, `type`; `start`/`end` were removed.
- `GET /v2.2/messaging/campaigns`: the `ids` query parameter is now required.
- `DELETE /v2.2/numbers/{number}/messaging-campaign`: the `campaignId` query parameter is now required.
- `DELETE /v2.2/numbers/messaging-campaign` (bulk unassign): sends required `numbers` + `campaignId` **query** parameters; no request body.
- `DELETE /v2.2/acl`: sends the required `cidrs` query parameter; no request body.
- `GET /v2.2/numbers/messaging`: the `numbers` parameter is now required.
- `GET /v2.2/ports/{id}`: `id` is the 5-character pid **string**.
- `lata` filter parameters are strings, matching the response schemas.
- Message-history `value.number` is now a string (spec fix).

### Fixed
- API error envelope `{"status":"error","error":{"code":N,"message":"..."}}` is parsed correctly — `code` and `message` are populated instead of degrading to `HTTP <status>`.
- `POST /v2.2/accounts` (signup) no longer requires an API key, per spec.
- Honored `Retry-After` values are capped at 8 seconds (previously unbounded).
- Path parameters are URL-encoded.
- `GET /v2.2/account/credits` exposes the optional `status` filter; the tickets list includes `totalCount`; removed the nonexistent `expires` field from registration data.
- Docs: corrected the rate-limit list (GET `/v2.2/account`, `/account/cdr`, `/account/recurring-charges`, POST `/account/api-key` at 6/hr/IP; POST `/v2.2/messaging/health/check` at 30/hr/account) and the operation count (79).
- HTTPS now loads a CA store and verifies hostnames on both LuaSec paths; the rockspec declares `luasocket`/`luasec`; empty API keys are rejected; truncated chunked responses now raise a transport error.

## 2.2.15 — 2026-10-15

Sync with VoiceTel API spec v2.2.15.

### Messaging

- New **messaging health** surface (the same view as the portal Messaging tab).
  The spec defines no response schema for these endpoints, so each method returns
  the decoded JSON table verbatim; only the request body/query is shaped.
  - `GET /v2.2/messaging/health` → `messaging:health()` — account-wide overview:
    summary counts, campaigns with carrier-review progress, numbers needing
    attention (with fix-it actions), 14 days of delivery counts, and the
    alert-email setting. Updated hourly.
  - `GET /v2.2/messaging/health/alerts` → `messaging:health_alerts()` — whether
    new messaging problems are emailed to the account.
  - `PUT /v2.2/messaging/health/alerts` → `messaging:set_health_alerts(enabled)`
    — turn alert emails on or off (at most one digest about every 20 hours).
  - `POST /v2.2/messaging/health/check` → `messaging:health_check(number)` — live
    check of one number (in service, messaging enabled, campaign approved,
    assigned by the provider, delivery failures in the last 24h, enablement in
    progress). Limited to 30 checks per hour per account.
  - `GET /v2.2/messaging/health/samples` → `messaging:health_samples(number)` — up
    to 3 recent outbound messages from the number that carriers blocked as spam.

## 2.2.14 — 2026-10-14

Sync with VoiceTel API spec v2.2.14.

### Messaging

- `GET /v2.2/messaging/campaigns` — campaign status items now carry `dca`,
  the carrier (DCA) review progress: `electionComplete` (every carrier has a
  DCA assigned), `electedCarriers` (DCAs assigned so far, null when
  unavailable), and `carriers[]` — the latest per-carrier decision
  (`carrier`, `status` of ACTIVE / REJECTED / SUSPENDED / UNSUSPENDED /
  TERMINATED, `detail`, `updatedAt`). `dca` is null for
  `CAMPAIGN_INVALID_ID`.
- Campaign `status` values documented: `CAMPAIGN_DCA_COMPLETE` (ready:
  carrier review finished, numbers assigned),
  `CAMPAIGN_DCA_COMPLETE_NO_NUMBERS_ASSIGNED`, `CAMPAIGN_PENDING_DCA`
  (registry-active but carrier review unfinished — numbers cannot be enabled
  yet), `CAMPAIGN_DCA_REJECTED` (see `dca.carriers`),
  `CAMPAIGN_<registry status>`, `CAMPAIGN_INVALID_ID`.
- `POST /v2.2/messaging/campaigns` — clarified that `campaignClassName` is
  auto-populated from the campaign registry and `campaignStartDate` defaults
  to today.

## 2.2.11 — 2026-10-14 (backfilled)

Sync with VoiceTel API spec v2.2.11, which this SDK had not yet absorbed.

### Messaging / Numbers

- Async (path C) campaign enablement: new enablement-job model
  (`campaignId`, `state` of queued -> hosting -> assigning -> routing ->
  done | failed, `message`, `createdAt`, `updatedAt`).
- `GET /v2.2/numbers/{number}/messaging` — the state may now report network
  "C" and carries `pending` (the enablement job) while provisioning runs.
- `POST /v2.2/numbers/{number}/messaging/campaign` — the result now reports
  `status` ("enabled" | "already" | "pending"), `alreadyAssigned`,
  `orderId` (path B only; null for path C), `message`, `warning`, and `job`
  (path C). Assign-network is now B/C; `previousNetwork` no longer reports
  "unknown". Path A campaigns are being migrated and take no new numbers.
- `PUT` assign now returns 202 with status "pending" for path C — poll the
  number's messaging state until the job is done or failed.

### Account / iNumbering

- `services.rcid` removed from account responses.
- `supportUrl` removed from port summaries.
- Port-out PIN update now reports `changed` — an existing PIN is locked for
  30 days once set and is returned unchanged.

### Authentication

- Auth-mode wording clarified: 0 = Digest, 1 = Lax (Digest | IP), 2 = IP,
  3 = Strict (Digest + IP).
