-- voicetel.resources.acl — operations under /v2.2/acl.
--
-- add takes a body of shape `{ acl = { { cidr = "..." }, ... } }`; remove
-- takes the CIDRs as a required comma-separated `cidrs` query parameter.

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

-- remove removes one or more CIDR entries. Returns 200 with body (NOT 204):
-- { removed = { { cidr = "..." }, ... } }. No request body — the entries to
-- remove go in the required `cidrs` query parameter as a comma-separated
-- list (or an array, which is joined for you).
-- DELETE /v2.2/acl   query: { cidrs = "203.0.113.0/24,203.0.113.1/32" }
function M:remove(cidrs)
    if type(cidrs) == "table" then cidrs = table.concat(cidrs, ",") end
    return self._t:request("DELETE", "/v2.2/acl", { cidrs = cidrs }, nil, true)
end

return M
