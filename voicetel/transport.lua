-- voicetel.transport — low-level HTTP request helper.
--
-- Responsibilities:
--   * Build the URL (base + path + query string).
--   * Inject Authorization, Accept, Content-Type, User-Agent headers.
--   * JSON-encode the request body when present.
--   * Retry 429 / 5xx responses up to `max_retries` times, honoring
--     `Retry-After` (integer seconds form).
--   * Strip the `{ status = "success", data = ... }` envelope on success.
--   * Convert non-2xx responses into a structured error table.
--
-- The transport is created indirectly via `voicetel.new(opts)` and never
-- exposed in the public API surface.

local errors = require("voicetel.errors")
local json   = require("voicetel.json")
local http   = require("voicetel.http")

local M = {}
M.__index = M

local DEFAULT_MAX_RETRIES = 2
local DEFAULT_TIMEOUT     = 30
local BACKOFF_BASE_SEC    = 0.5
local BACKOFF_CAP_SEC     = 8

local function url_encode(s)
    s = tostring(s)
    return (string.gsub(s, "([^A-Za-z0-9_.~%-])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- build_query encodes a Lua table as a sorted query string. nil/false values
-- are skipped. Numeric and boolean values are stringified.
local function build_query(q)
    if not q then return "" end
    local keys = {}
    for k, v in pairs(q) do
        if v ~= nil and v ~= false then keys[#keys + 1] = k end
    end
    if #keys == 0 then return "" end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = url_encode(k) .. "=" .. url_encode(q[k])
    end
    return "?" .. table.concat(parts, "&")
end

local RETRYABLE_STATUSES = { [429] = true, [500] = true, [502] = true, [503] = true, [504] = true }

local function parse_retry_after(header_val)
    if not header_val then return nil end
    local secs = tonumber(tostring(header_val))
    if secs and secs >= 0 then return secs end
    return nil
end

-- backoff_delay computes the wait before retry `attempt+1`, in seconds.
-- attempt is 0-indexed (so the first retry sleeps base, second 2*base, ...).
local function backoff_delay(attempt, resp)
    if resp then
        local retry_after = parse_retry_after(http.get_header(resp, "Retry-After"))
        if retry_after then return retry_after end
    end
    local d = BACKOFF_BASE_SEC * (2 ^ attempt)
    if d > BACKOFF_CAP_SEC then d = BACKOFF_CAP_SEC end
    return d
end

-- sleep blocks for `seconds` (fractional ok). Uses `voicetel.sleep` from opts
-- when provided (tests use this to fast-forward time).
local function sleep(seconds, sleep_fn)
    if seconds <= 0 then return end
    if sleep_fn then return sleep_fn(seconds) end
    local fs = rawget(_G, "freeswitch")
    if fs and fs.msleep then
        fs.msleep(math.floor(seconds * 1000))
        return
    end
    local ok_socket, socket = pcall(require, "socket")
    if ok_socket and socket.sleep then
        socket.sleep(seconds)
        return
    end
    -- Last-ditch busy wait — never reached on FreeSWITCH or with LuaSocket
    -- installed, but keeps the transport functional on pure-Lua hosts.
    local stop = os.time() + math.ceil(seconds)
    while os.time() < stop do end
end

-- unwrap strips the standard envelope `{ status = "success", data = <T> }`
-- when present. Returns the inner data; otherwise returns the original value.
local function unwrap(decoded)
    if type(decoded) == "table"
        and decoded.status ~= nil
        and decoded.data ~= nil
    then
        return decoded.data
    end
    return decoded
end

-- decode_response converts a raw HTTP response into either (result, nil) on
-- success or (nil, err) on failure. status>=200<300 is treated as success.
local function decode_response(resp)
    local status = resp.status or 0
    local raw = resp.body or ""
    local decoded, derr
    if #raw > 0 then
        decoded, derr = json.decode(raw)
        if derr then
            decoded = raw -- fall back to the raw string for error.body
        end
    end

    if status >= 200 and status < 300 then
        if derr then
            return nil, errors.new(status, nil, "failed to decode JSON response: " .. derr, raw)
        end
        if decoded == nil then return true end -- 204 No Content
        return unwrap(decoded)
    end

    local code, message
    if type(decoded) == "table" then
        code = decoded.code or decoded.error
        message = decoded.message or decoded.error
    end
    if type(code) ~= "string" then code = nil end
    if type(message) ~= "string" or message == "" then
        message = "HTTP " .. tostring(status)
    end
    return nil, errors.new(status, code, message, decoded or raw)
end

-- new constructs a transport. opts:
--   base_url    (string, required)
--   user_agent  (string, required)
--   api_key     (string or nil)
--   max_retries (int)
--   timeout     (number, seconds)
--   http_backend (function: req -> resp, err)
--   sleep        (function: seconds -> nil) — test hook
function M.new(opts)
    opts = opts or {}
    local self = {
        base_url     = (opts.base_url or ""):gsub("/+$", ""),
        user_agent   = opts.user_agent or "voicetel-lua",
        api_key      = opts.api_key,
        max_retries  = opts.max_retries or DEFAULT_MAX_RETRIES,
        timeout      = opts.timeout or DEFAULT_TIMEOUT,
        http_backend = opts.http_backend or http.default_backend(),
        sleep_fn     = opts.sleep,
    }
    return setmetatable(self, M)
end

function M:set_bearer(api_key)
    self.api_key = api_key
end

function M:get_bearer()
    return self.api_key
end

-- request performs an HTTP call.
--
-- args:
--   method        - "GET" / "POST" / "PUT" / "PATCH" / "DELETE"
--   path          - "/v2.2/numbers"
--   query         - table or nil
--   body          - table (will be JSON-encoded), already-encoded string, or nil
--   require_auth  - boolean; when true, Authorization header is set/required
--
-- returns (result, err) — result is the unwrapped `data` payload; for 204
-- responses result is `true`. On any failure, result is nil and err is a
-- structured error table.
function M:request(method, path, query, body, require_auth)
    if require_auth and not self.api_key then
        return nil, errors.new(0, nil,
            "no api key set; call client:login(username, password) or pass api_key to voicetel.new",
            nil)
    end
    -- Override kind to authentication when the key is missing — the call
    -- above defaulted to "unknown" because status is 0.
    -- (Done inline so we don't allocate two error tables.)

    local url = self.base_url .. path .. build_query(query)
    local raw_body = nil
    if body ~= nil then
        if type(body) == "string" then
            raw_body = body
        else
            local ok, encoded = pcall(json.encode, body)
            if not ok then
                return nil, errors.new_transport("failed to encode request body: " .. tostring(encoded))
            end
            raw_body = encoded
        end
    end

    local last_err
    for attempt = 0, self.max_retries do
        local headers = {
            ["Accept"]     = "application/json",
            ["User-Agent"] = self.user_agent,
        }
        if raw_body then headers["Content-Type"] = "application/json" end
        if require_auth then headers["Authorization"] = "Bearer " .. self.api_key end

        local req = {
            method  = method,
            url     = url,
            headers = headers,
            body    = raw_body,
            timeout = self.timeout,
        }
        local resp, err = self.http_backend(req)
        if not resp then
            last_err = err or "transport failure"
            if attempt >= self.max_retries then
                return nil, errors.new_transport("transport error after "
                    .. tostring(attempt + 1) .. " attempt(s): " .. tostring(last_err))
            end
            sleep(backoff_delay(attempt, nil), self.sleep_fn)
        else
            if RETRYABLE_STATUSES[resp.status] and attempt < self.max_retries then
                sleep(backoff_delay(attempt, resp), self.sleep_fn)
            else
                return decode_response(resp)
            end
        end
    end
    return nil, errors.new_transport("retry loop exhausted: " .. tostring(last_err or ""))
end

-- ------------------------------------------------------ exposed helpers ---

M._build_query   = build_query
M._unwrap        = unwrap
M._backoff_delay = backoff_delay
M._url_encode    = url_encode

return M
