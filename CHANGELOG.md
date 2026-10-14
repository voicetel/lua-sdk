# Changelog

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
