-- voicetel.resources.lookups — CNAM, carrier & LRN dips.
--
-- All three endpoints cost money per call; rate them deliberately.

local url_encode = require("voicetel.transport")._url_encode

local M = {}
M.__index = M

function M.new(transport) return setmetatable({ _t = transport }, M) end

-- cnam performs a CNAM dip on `number` (10-digit TN).
-- GET /v2.2/cnam/{number}
function M:cnam(number)
    return self._t:request("GET", "/v2.2/cnam/" .. url_encode(number), nil, nil, true)
end

-- carrier performs a carrier & line-type lookup on `number` (10-digit TN).
-- Billed per lookup at the account's CNAM rate. Field names inside `carrier`
-- are the upstream carrier's (snake_case):
--   { name = "EXAMPLE CARRIER"|nil, type = "voip"|"landline"|"mobile"|nil,
--     mobile_country_code = "310"|nil, mobile_network_code = "456"|nil,
--     error_code = <int>|nil }
-- GET /v2.2/carrier/{number}
function M:carrier(number)
    return self._t:request("GET", "/v2.2/carrier/" .. url_encode(number), nil, nil, true)
end

-- lrn performs an LRN dip. `ani` is the presented ANI used for billing/auth.
-- GET /v2.2/lrn/{number}/{ani}
function M:lrn(number, ani)
    return self._t:request("GET",
        "/v2.2/lrn/" .. url_encode(number) .. "/" .. url_encode(ani), nil, nil, true)
end

return M
