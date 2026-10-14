-- voicetel.resources.authentication — operations under /v2.2/auth.

local M = {}
M.__index = M

-- AuthType constants — surfaced on the top-level module for convenience.
-- 0=Digest, 1=Lax (Digest | IP), 2=IP, 3=Strict (Digest + IP).
M.AUTH_TYPE_DIGEST = 0
M.AUTH_TYPE_LAX    = 1
M.AUTH_TYPE_IP     = 2
M.AUTH_TYPE_STRICT = 3

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
