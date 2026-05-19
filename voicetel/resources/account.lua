-- voicetel.resources.account — operations under the /v2.2/account* paths.
--
-- Note: cdr, recurring_charges, payments, registration, info, and the
-- login api-key exchange all share a 6 req/hour/IP rate limit.

local M = {}
M.__index = M

function M.new(transport)
    return setmetatable({ _t = transport }, M)
end

-- get returns the authenticated account's profile.
-- GET /v2.2/account
function M:get()
    return self._t:request("GET", "/v2.2/account", nil, nil, true)
end

-- update partial-updates account settings.
-- PUT /v2.2/account
function M:update(body)
    return self._t:request("PUT", "/v2.2/account", nil, body or {}, true)
end

-- add creates a sub-account (admin-only).
-- POST /v2.2/account
function M:add(body)
    return self._t:request("POST", "/v2.2/account", nil, body or {}, true)
end

-- signup is the public sign-up flow.
-- POST /v2.2/accounts
function M:signup(body)
    return self._t:request("POST", "/v2.2/accounts", nil, body or {}, true)
end

-- cdr fetches call detail records in the [start, end] Unix-seconds range.
-- GET /v2.2/account/cdr (rate-limited)
function M:cdr(start_ts, end_ts)
    local q = {}
    if start_ts then q.start = start_ts end
    if end_ts then q["end"] = end_ts end
    return self._t:request("GET", "/v2.2/account/cdr", q, nil, true)
end

-- credits returns the full credit history.
-- GET /v2.2/account/credits
function M:credits()
    return self._t:request("GET", "/v2.2/account/credits", nil, nil, true)
end

-- recurring_charges returns active MRCs (rate-limited).
-- GET /v2.2/account/recurring-charges
function M:recurring_charges()
    return self._t:request("GET", "/v2.2/account/recurring-charges", nil, nil, true)
end

-- payments returns the full payment history (rate-limited).
-- GET /v2.2/account/payments
function M:payments()
    return self._t:request("GET", "/v2.2/account/payments", nil, nil, true)
end

-- registration returns the current SIP registration (rate-limited).
-- GET /v2.2/account/registration
function M:registration()
    return self._t:request("GET", "/v2.2/account/registration", nil, nil, true)
end

-- recover kicks off the password recovery flow (no auth required).
-- POST /v2.2/account/recovery
function M:recover(body)
    return self._t:request("POST", "/v2.2/account/recovery", nil, body or {}, false)
end

return M
