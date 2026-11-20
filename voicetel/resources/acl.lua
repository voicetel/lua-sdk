-- voicetel.resources.acl — operations under /v2.2/acl.
--
-- add and remove both take a body of shape `{ acl = { { cidr = "..." }, ... } }`
-- (remove accepts the same body as add; the old `cidrs` query parameter is
-- not read by the live handler).

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

-- remove removes one or more CIDR entries. Takes the SAME body shape as add:
--   { acl = { { cidr = "203.0.113.0/24" }, ... } }
-- A plain array of CIDR strings ({ "203.0.113.0/24", ... }) is accepted for
-- convenience and wrapped for you.
-- Returns 200 with body (NOT 204): { removed = { { cidr = "..." }, ... } }.
-- On 409 the error envelope carries a `data` object with the entries that
-- were removed and the ones that failed (`err.body.data`).
-- DELETE /v2.2/acl   body: { acl = { { cidr = "203.0.113.0/24" }, ... } }
function M:remove(body)
    if type(body) == "table" and body.acl == nil and type(body[1]) == "string" then
        local acl = {}
        for _, cidr in ipairs(body) do
            acl[#acl + 1] = { cidr = cidr }
        end
        body = { acl = acl }
    end
    return self._t:request("DELETE", "/v2.2/acl", nil, body or {}, true)
end

return M
