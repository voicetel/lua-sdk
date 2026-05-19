-- voicetel.resources.authentication — operations under /v2.2/auth.

local M = {}
M.__index = M

-- AuthType constants — surfaced on the top-level module for convenience.
M.AUTH_TYPE_DIGEST        = 0
M.AUTH_TYPE_IP_AUTH       = 1
M.AUTH_TYPE_DIGEST_OR_IP  = 2
M.AUTH_TYPE_DIGEST_AND_IP = 3

function M.new(transport) return setmetatable({ _t = transport }, M) end

-- get returns the current auth mode + IP allowlist.
-- GET /v2.2/auth
function M:get()
    return self._t:request("GET", "/v2.2/auth", nil, nil, true)
end

-- update sets the auth mode and/or password.
-- PUT /v2.2/auth   body: { authType = 1, password = "..." }
function M:update(body)
    return self._t:request("PUT", "/v2.2/auth", nil, body or {}, true)
end

return M
