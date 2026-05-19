-- voicetel.resources.e911 — operations under /v2.2/e911.

local M = {}
M.__index = M

function M.new(transport) return setmetatable({ _t = transport }, M) end

-- list returns every e911 record on the account.
-- GET /v2.2/e911
function M:list()
    return self._t:request("GET", "/v2.2/e911", nil, nil, true)
end

-- create validates + provisions in one call.
-- POST /v2.2/e911
function M:create(body)
    return self._t:request("POST", "/v2.2/e911", nil, body or {}, true)
end

-- validate validates an address and returns an addressid for use with provision.
-- POST /v2.2/e911/validations
function M:validate(body)
    return self._t:request("POST", "/v2.2/e911/validations", nil, body or {}, true)
end

-- get fetches the e911 record for `dn` (10-digit TN).
-- GET /v2.2/e911/{dn}
function M:get(dn)
    return self._t:request("GET", "/v2.2/e911/" .. tostring(dn), nil, nil, true)
end

-- provision uses a validated addressid to provision e911 on `dn`.
-- PUT /v2.2/e911/{dn}   body: { callername = "...", addressid = 123 }
function M:provision(dn, body)
    return self._t:request("PUT", "/v2.2/e911/" .. tostring(dn), nil, body or {}, true)
end

-- remove deletes the e911 record for `dn`. Returns `true` on 204.
-- DELETE /v2.2/e911/{dn}
function M:remove(dn)
    return self._t:request("DELETE", "/v2.2/e911/" .. tostring(dn), nil, nil, true)
end

return M
