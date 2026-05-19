-- voicetel.resources.messaging — SMS/MMS sending + 10DLC brand/campaign mgmt.
--
-- Note on wire field names: messageSend uses `fromNumber` / `toNumber`. The
-- send() method accepts both `from`/`to` and `from_number`/`to_number` and
-- translates them to the wire spelling so callers don't have to remember.

local M = {}
M.__index = M

function M.new(transport) return setmetatable({ _t = transport }, M) end

-- history fetches message history.
-- GET /v2.2/messages   query: { number, start, end (`["end"]`), type }
function M:history(opts)
    local q = {}
    if opts then
        if opts.number then q.number = opts.number end
        if opts.start  then q.start  = opts.start  end
        if opts["end"] then q["end"] = opts["end"] end
        if opts.type   then q.type   = opts.type   end
    end
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
-- GET /v2.2/messaging/campaigns
function M:campaign_status()
    return self._t:request("GET", "/v2.2/messaging/campaigns", nil, nil, true)
end

-- create_campaign registers a 10DLC campaign with the carrier.
-- POST /v2.2/messaging/campaigns
function M:create_campaign(body)
    return self._t:request("POST", "/v2.2/messaging/campaigns", nil, body or {}, true)
end

-- numbers_state returns the messaging state for many numbers at once.
-- GET /v2.2/numbers/messaging   query: { numbers = "2015551234,2015555678" }
function M:numbers_state(numbers)
    local q = {}
    if numbers and #numbers > 0 then
        q.numbers = table.concat(numbers, ",")
    end
    return self._t:request("GET", "/v2.2/numbers/messaging", q, nil, true)
end

return M
