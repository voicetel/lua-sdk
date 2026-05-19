-- voicetel.resources.acl — operations under /v2.2/acl.
--
-- All three endpoints take/return a body of shape `{ acl = { { cidr = "..." }, ... } }`.

local M = {}
M.__index = M

function M.new(transport) return setmetatable({ _t = transport }, M) end

-- list returns the current IP allowlist.
-- GET /v2.2/acl
function M:list()
    return self._t:request("GET", "/v2.2/acl", nil, nil, true)
end

-- add appends one or more CIDR entries.
-- POST /v2.2/acl   body: { acl = { { cidr = "203.0.113.0/24" }, ... } }
function M:add(body)
    return self._t:request("POST", "/v2.2/acl", nil, body or {}, true)
end

-- remove removes one or more CIDR entries. Returns 200 with body (NOT 204).
-- DELETE /v2.2/acl
function M:remove(body)
    return self._t:request("DELETE", "/v2.2/acl", nil, body or {}, true)
end

return M
