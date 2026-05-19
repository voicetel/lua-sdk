-- spec/helpers.lua — tiny test helpers used by every spec file.
--
-- The core helper is `mock_backend(t)`. It returns a function that satisfies
-- the same contract as the real HTTP backends but pulls its responses from
-- a queue. Each invocation records the request it received, so assertions
-- can verify URL/headers/body shape.

local M = {}

-- mock_backend builds a stub HTTP backend pre-seeded with a list of responses.
-- Each response can be:
--   { status = 200, body = "..." or table, headers = { ... } }
-- or a string (treated as a transport-level error message).
--
-- Returned object exposes:
--   backend(req)  -> the function to pass to voicetel.new{ http_backend = ... }
--   calls         -> list of recorded requests (mutated in place)
--   responses     -> the (mutable) list of pending responses
function M.mock_backend(responses)
    local state = {
        calls = {},
        responses = responses or {},
    }

    state.backend = function(req)
        table.insert(state.calls, {
            method  = req.method,
            url     = req.url,
            headers = req.headers,
            body    = req.body,
        })
        local r = table.remove(state.responses, 1)
        if r == nil then
            return nil, "mock_backend: no more responses queued"
        end
        if type(r) == "string" then
            return nil, r
        end
        local body = r.body
        if type(body) == "table" then
            local json = require("voicetel.json")
            body = json.encode(body)
        end
        return {
            status  = r.status or 200,
            headers = r.headers or {},
            body    = body or "",
        }, nil
    end

    return state
end

-- ok wraps a JSON payload in the standard `{ status, data }` envelope so
-- specs can write `helpers.ok({ number = "..." })` instead of repeating the
-- envelope every time.
function M.ok(data, status)
    return {
        status = status or 200,
        body   = { status = "success", data = data },
    }
end

-- err builds a non-2xx response with a JSON error body.
function M.err(status, message, code, extra)
    local body = { message = message }
    if code then body.code = code end
    if extra then
        for k, v in pairs(extra) do body[k] = v end
    end
    return { status = status, body = body }
end

-- new_client constructs a voicetel client wired to a mock backend. Returns
-- (client, mock) so tests can drive the queue and assert against calls.
function M.new_client(responses, opts)
    local voicetel = require("voicetel")
    local mock = M.mock_backend(responses)
    opts = opts or {}
    return voicetel.new({
        api_key      = opts.api_key or "test-key",
        base_url     = opts.base_url or "https://api.voicetel.com",
        http_backend = mock.backend,
        sleep        = function(_) end, -- never actually sleep in tests
        max_retries  = opts.max_retries,
    }), mock
end

-- decode_body returns the JSON-decoded body of the n-th recorded call (1-indexed).
function M.decode_body(mock, n)
    local json = require("voicetel.json")
    local raw = mock.calls[n].body
    if not raw or raw == "" then return nil end
    local v, e = json.decode(raw)
    assert(not e, e)
    return v
end

return M
