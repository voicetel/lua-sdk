-- voicetel.resources.messaging — SMS/MMS sending + 10DLC brand/campaign mgmt.
--
-- Note on wire field names: messageSend uses `fromNumber` / `toNumber`. The
-- send() method accepts both `from`/`to` and `from_number`/`to_number` and
-- translates them to the wire spelling so callers don't have to remember.

local M = {}
M.__index = M

function M.new(transport) return setmetatable({ _t = transport }, M) end

-- csv normalizes a comma-separated string (or an array of strings) into the
-- comma-separated string form the API expects on the wire.
local function csv(v)
    if type(v) == "table" then return table.concat(v, ",") end
    return v
end

-- history fetches message history for one number.
-- GET /v2.2/messages   query: { number (required 10-digit TN), from (Unix
--   seconds, range start — defaults to now), to (range end — defaults to
--   24h ago), type = "sms" (default) | "mms" | "dlr" }
-- Response: { number, type, fromTs, toTs, messages = { { key, value, id } } }.
-- Each record's value.number is the far-end number as a STRING
-- (e.g. "2015550123"); for type="dlr" the records carry
-- destinationNumber/sourceNumber instead of a message body.
function M:history(opts)
    opts = opts or {}
    local q = {}
    if opts.number then q.number = opts.number end
    if opts.from   then q.from   = opts.from   end
    if opts.to     then q.to     = opts.to     end
    if opts.type   then q.type   = opts.type   end
    return self._t:request("GET", "/v2.2/messages", q, nil, true)
end

-- send sends an SMS or MMS. Body must include fromNumber/toNumber/text; the
-- helper here remaps from/to and from_number/to_number for convenience.
-- POST /v2.2/messages
function M:send(body)
    body = body or {}
    local wire = {}
    for k, v in pairs(body) do wire[k] = v end
    if wire.from_number then wire.fromNumber = wire.from_number; wire.from_number = nil end
    if wire.to_number   then wire.toNumber   = wire.to_number;   wire.to_number   = nil end
    if wire.from        then wire.fromNumber = wire.fromNumber or wire.from; wire.from = nil end
    if wire.to          then wire.toNumber   = wire.toNumber   or wire.to;   wire.to   = nil end
    if wire.media_urls  then wire.mediaUrls  = wire.media_urls;  wire.media_urls = nil end
    return self._t:request("POST", "/v2.2/messages", nil, wire, true)
end

-- create_brand registers a 10DLC brand.
-- POST /v2.2/messaging/brands
function M:create_brand(body)
    return self._t:request("POST", "/v2.2/messaging/brands", nil, body or {}, true)
end

-- campaign_status returns the current 10DLC campaign statuses.
--   ids (required): comma-separated string (or array) of up to 100
--     alphanumeric campaign ids, e.g. campaign_status("CAMP002,ABC1234").
-- Each item is { id, status, numbers, dca }. `status` is one of:
--   CAMPAIGN_DCA_COMPLETE (ready: carrier review finished, numbers assigned),
--   CAMPAIGN_DCA_COMPLETE_NO_NUMBERS_ASSIGNED,
--   CAMPAIGN_PENDING_DCA (active at the campaign registry, but carrier (DCA)
--     review is not finished yet; numbers cannot be enabled until it is),
--   CAMPAIGN_DCA_REJECTED (a carrier's DCA rejected or suspended the
--     campaign; see dca.carriers),
--   CAMPAIGN_<registry status>, or CAMPAIGN_INVALID_ID.
-- `dca` is the carrier (DCA) review progress, nil for CAMPAIGN_INVALID_ID:
--   { electionComplete = every carrier has a DCA assigned to review the
--       campaign,
--     electedCarriers  = carriers with a DCA assigned so far (nil when
--       unavailable),
--     carriers         = { { carrier, status, detail, updatedAt } } — each
--       carrier DCA decision received, latest per carrier. status is ACTIVE,
--       REJECTED, SUSPENDED, UNSUSPENDED or TERMINATED; detail is the
--       reviewer's note, as given. }
-- GET /v2.2/messaging/campaigns   query: { ids (required) }
function M:campaign_status(ids)
    return self._t:request("GET", "/v2.2/messaging/campaigns", { ids = csv(ids) }, nil, true)
end

-- create_campaign registers a 10DLC campaign with the carrier. The body is
-- passed through to the campaign registration service; campaignClassName
-- (from the campaign registry) and campaignStartDate (today) are
-- auto-populated if omitted.
-- POST /v2.2/messaging/campaigns
function M:create_campaign(body)
    return self._t:request("POST", "/v2.2/messaging/campaigns", nil, body or {}, true)
end

-- numbers_state returns the messaging state for many numbers at once.
--   numbers (required): comma-separated string (or array) of up to 1000
--     10-digit numbers.
-- The per-number shape matches numbers:get_messaging — including
-- network ("A"/"B"/"C") and the optional `pending` asynchronous (path C)
-- enablement job.
-- GET /v2.2/numbers/messaging   query: { numbers = "2015550123,2015555678" }
function M:numbers_state(numbers)
    return self._t:request("GET", "/v2.2/numbers/messaging", { numbers = csv(numbers) }, nil, true)
end

-- health returns the account-wide messaging health overview — the same view as
-- the portal Messaging tab: summary counts (numbers, messaging on, healthy,
-- needing attention, in progress), campaigns with carrier-review progress,
-- numbers needing attention (each with a plain-language title, detail and the
-- actions that fix it: assign, disable, samples), 14 days of delivery counts
-- (delivered, failed, blocked as spam, refused because the number is not
-- enabled), and the alert-email setting. Updated hourly. Fix a number with
-- numbers:assign_campaign / numbers:unassign_campaign.
-- The spec defines no response schema, so the decoded JSON is returned as-is.
-- GET /v2.2/messaging/health
function M:health()
    return self._t:request("GET", "/v2.2/messaging/health", nil, nil, true)
end

-- health_alerts returns the alert-email setting: whether new messaging problems
-- are emailed to the account. The spec defines no response schema, so the
-- decoded JSON is returned as-is.
-- GET /v2.2/messaging/health/alerts
function M:health_alerts()
    return self._t:request("GET", "/v2.2/messaging/health/alerts", nil, nil, true)
end

-- set_health_alerts turns alert emails on or off. When enabled, the account is
-- emailed as new messaging problems are found (at most one digest about every
-- 20 hours). The spec defines no response schema, so the decoded JSON is
-- returned as-is.
-- PUT /v2.2/messaging/health/alerts   body: { enabled = true|false }
function M:set_health_alerts(enabled)
    return self._t:request("PUT", "/v2.2/messaging/health/alerts", nil, { enabled = enabled }, true)
end

-- health_check performs a live check of one number: in service, messaging
-- enabled, campaign approved, assigned to the campaign by the messaging
-- provider, delivery failures in the last 24 hours, enablement in progress.
-- Limited to 30 checks per hour per account. The spec defines no response
-- schema, so the decoded JSON is returned as-is.
-- POST /v2.2/messaging/health/check   body: { number = "2125550123" }
function M:health_check(number)
    return self._t:request("POST", "/v2.2/messaging/health/check", nil, { number = number }, true)
end

-- health_samples returns up to 3 recent outbound messages from the number that
-- carriers blocked as spam (time, masked recipient, text, reason), to help
-- review content. The spec defines no response schema, so the decoded JSON is
-- returned as-is.
-- GET /v2.2/messaging/health/samples   query: { number = "2125550123" }
function M:health_samples(number)
    return self._t:request("GET", "/v2.2/messaging/health/samples", { number = number }, nil, true)
end

return M
