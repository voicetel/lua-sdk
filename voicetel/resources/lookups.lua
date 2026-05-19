-- voicetel.resources.lookups — CNAM + LRN dips.
--
-- Both endpoints cost money per call; rate them deliberately.

local M = {}
M.__index = M

function M.new(transport) return setmetatable({ _t = transport }, M) end

-- cnam performs a CNAM dip on `number` (10-digit TN).
-- GET /v2.2/cnam/{number}
function M:cnam(number)
    return self._t:request("GET", "/v2.2/cnam/" .. tostring(number), nil, nil, true)
end

-- lrn performs an LRN dip. `ani` is the presented ANI used for billing/auth.
-- GET /v2.2/lrn/{number}/{ani}
function M:lrn(number, ani)
    return self._t:request("GET",
        "/v2.2/lrn/" .. tostring(number) .. "/" .. tostring(ani), nil, nil, true)
end

return M
