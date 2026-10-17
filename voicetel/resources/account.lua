-- voicetel.resources.account — operations under the /v2.2/account* paths.
--
-- Rate limits: get, cdr, recurring_charges and the login api-key exchange
-- (client:login) are each limited to 6 requests per hour per IP.

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

-- signup is the public sign-up flow (no Authorization header required).
-- POST /v2.2/accounts
function M:signup(body)
    return self._t:request("POST", "/v2.2/accounts", nil, body or {}, false)
end

-- cdr fetches call detail records in the [start, end] Unix-seconds range.
-- GET /v2.2/account/cdr (rate-limited)
function M:cdr(start_ts, end_ts)
    local q = {}
    if start_ts then q.start = start_ts end
    if end_ts then q["end"] = end_ts end
    return self._t:request("GET", "/v2.2/account/cdr", q, nil, true)
end

-- credits returns the credit history. Pass { status = "paid" | "unpaid" } to
-- filter by payment state.
-- GET /v2.2/account/credits   query: { status } (optional)
function M:credits(opts)
    local q
    if opts and opts.status then q = { status = opts.status } end
    return self._t:request("GET", "/v2.2/account/credits", q, nil, true)
end

-- recurring_charges returns active MRCs (rate-limited: 6 req/hour/IP).
-- GET /v2.2/account/recurring-charges
function M:recurring_charges()
    return self._t:request("GET", "/v2.2/account/recurring-charges", nil, nil, true)
end

-- payments returns the full payment history.
-- GET /v2.2/account/payments
function M:payments()
    return self._t:request("GET", "/v2.2/account/payments", nil, nil, true)
end

-- registration returns the current SIP registration.
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
