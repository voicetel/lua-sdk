-- voicetel.errors — structured error type + helper predicates.
--
-- Every public method on the SDK returns `result, err`. On failure `result` is
-- `nil` and `err` is a table with the shape documented below. Callers can
-- inspect `err.kind` to switch on the error category, or use the
-- `is_<kind>(err)` helpers exported from the top-level `voicetel` module.
--
--   err = {
--     kind        = "rate_limit", -- "bad_request" | "authentication" | ...
--     status_code = 429,           -- HTTP status; 0 when the transport failed
--     code        = nil,           -- server-supplied error code (string), if any
--     message     = "HTTP 429: ...",
--     body        = { ... },       -- decoded JSON body or the raw string
--   }
local M = {}

M.KIND_UNKNOWN          = "unknown"
M.KIND_BAD_REQUEST      = "bad_request"
M.KIND_AUTHENTICATION   = "authentication"
M.KIND_PERMISSION_DENIED = "permission_denied"
M.KIND_NOT_FOUND        = "not_found"
M.KIND_CONFLICT         = "conflict"
M.KIND_RATE_LIMIT       = "rate_limit"
M.KIND_SERVER           = "server"

local kind_from_status = {
    [400] = M.KIND_BAD_REQUEST,
    [401] = M.KIND_AUTHENTICATION,
    [403] = M.KIND_PERMISSION_DENIED,
    [404] = M.KIND_NOT_FOUND,
    [409] = M.KIND_CONFLICT,
    [429] = M.KIND_RATE_LIMIT,
}

function M.kind_for_status(status)
    local k = kind_from_status[status]
    if k then return k end
    if status and status >= 500 and status < 600 then
        return M.KIND_SERVER
    end
    return M.KIND_UNKNOWN
end

-- new creates a structured error table. status may be 0/nil for transport
-- failures (DNS, TLS, JSON-decode, etc).
function M.new(status, code, message, body)
    return {
        kind        = M.kind_for_status(status or 0),
        status_code = status or 0,
        code        = code,
        message     = message or (status and ("HTTP " .. status) or "unknown error"),
        body        = body,
    }
end

-- new_transport creates an error for a non-HTTP failure (timeout, DNS,
-- malformed JSON, etc). kind defaults to "unknown".
function M.new_transport(message, kind)
    return {
        kind        = kind or M.KIND_UNKNOWN,
        status_code = 0,
        code        = nil,
        message     = message,
        body        = nil,
    }
end

local function kind_of(err)
    if type(err) == "table" and err.kind then return err.kind end
    return nil
end

function M.is_rate_limit(err)         return kind_of(err) == M.KIND_RATE_LIMIT end
function M.is_not_found(err)          return kind_of(err) == M.KIND_NOT_FOUND end
function M.is_authentication(err)     return kind_of(err) == M.KIND_AUTHENTICATION end
function M.is_permission_denied(err)  return kind_of(err) == M.KIND_PERMISSION_DENIED end
function M.is_conflict(err)           return kind_of(err) == M.KIND_CONFLICT end
function M.is_bad_request(err)        return kind_of(err) == M.KIND_BAD_REQUEST end
function M.is_server(err)             return kind_of(err) == M.KIND_SERVER end

return M
