-- voicetel.http — backend selection + tiny normalization for HTTP responses.
--
-- The SDK targets FreeSWITCH's mod_lua first and a plain LuaSocket runtime
-- second. We pick whichever is available at require-time, but allow callers
-- to override via `voicetel.new({ http_backend = fn })`.
--
-- A backend is a function with the signature:
--
--   function(req) -> response, err
--
-- where req is:
--   { method = "GET", url = "...", headers = { ... }, body = "..." or nil,
--     timeout = 30 }
-- and response is:
--   { status = 200, headers = { ... }, body = "..." }
-- and err is either nil or a string describing a transport-level failure
-- (DNS, TLS, timeout). For non-2xx HTTP responses, err is nil; the status
-- code is the source of truth.

local M = {}

-- ---------------------------------------------------------------- helpers ---

local function lower_header_table(h)
    local out = {}
    for k, v in pairs(h or {}) do
        out[string.lower(k)] = v
    end
    return out
end

-- get_header looks up a header case-insensitively from a response.
function M.get_header(resp, name)
    if not resp or not resp.headers then return nil end
    local lower = lower_header_table(resp.headers)
    return lower[string.lower(name)]
end

-- ------------------------------------------ FreeSWITCH (freeswitch.Curl) ---

-- new_freeswitch_backend builds a backend that talks to FreeSWITCH's built-in
-- HTTP client. The function looks up the global at call time so that tests
-- can install a stub `freeswitch` global before the first request.
function M.new_freeswitch_backend()
    return function(req)
        local fs = rawget(_G, "freeswitch")
        if not fs or not fs.Curl then
            return nil, "freeswitch.Curl not available"
        end
        local curl = fs.Curl()
        if not curl then return nil, "could not construct freeswitch.Curl" end

        -- freeswitch.Curl exposes a small high-level API. Different FS builds
        -- spell the methods slightly differently, so we check before calling.
        if curl.timeout then curl:timeout(req.timeout or 30) end

        local hdrs = {}
        for k, v in pairs(req.headers or {}) do
            table.insert(hdrs, tostring(k) .. ": " .. tostring(v))
        end

        local body, status, resp_headers
        local method = string.upper(req.method or "GET")
        if method == "GET" then
            body, status, resp_headers = curl:get(req.url, hdrs)
        elseif method == "POST" then
            body, status, resp_headers = curl:post(req.url, req.body or "", hdrs)
        elseif method == "PUT" then
            body, status, resp_headers = curl:put(req.url, req.body or "", hdrs)
        elseif method == "DELETE" then
            -- freeswitch.Curl historically lacks a DELETE shortcut; fall back
            -- to the lower-level `request` method when present.
            if curl.request then
                body, status, resp_headers = curl:request("DELETE", req.url, req.body or "", hdrs)
            elseif curl.delete then
                body, status, resp_headers = curl:delete(req.url, hdrs)
            else
                return nil, "freeswitch.Curl: DELETE not supported by this build"
            end
        elseif method == "PATCH" then
            if curl.request then
                body, status, resp_headers = curl:request("PATCH", req.url, req.body or "", hdrs)
            elseif curl.patch then
                body, status, resp_headers = curl:patch(req.url, req.body or "", hdrs)
            else
                return nil, "freeswitch.Curl: PATCH not supported by this build"
            end
        else
            return nil, "voicetel.http: unsupported method " .. tostring(method)
        end

        if not status then
            return nil, "freeswitch.Curl request failed"
        end
        return {
            status  = tonumber(status) or 0,
            headers = resp_headers or {},
            body    = body or "",
        }, nil
    end
end

-- --------------------------------------------------- LuaSocket fallback ---

function M.new_luasocket_backend()
    local ok_http, http_mod = pcall(require, "socket.http")
    if not ok_http then
        return nil, "socket.http not installed"
    end
    -- HTTPS support requires LuaSec; load lazily.
    local function pick(url)
        if string.sub(url, 1, 5) == "https" then
            local ok_s, https = pcall(require, "ssl.https")
            if ok_s then return https end
            return nil, "LuaSec (ssl.https) required for HTTPS URLs"
        end
        return http_mod
    end
    local ltn12 = require("ltn12")
    return function(req)
        local backend, perr = pick(req.url)
        if not backend then return nil, perr end
        local body_chunks = {}
        local source = nil
        local headers = {}
        for k, v in pairs(req.headers or {}) do headers[k] = v end
        if req.body and #req.body > 0 then
            source = ltn12.source.string(req.body)
            headers["Content-Length"] = tostring(#req.body)
        end
        local one, code, resp_headers = backend.request{
            url     = req.url,
            method  = string.upper(req.method or "GET"),
            headers = headers,
            source  = source,
            sink    = ltn12.sink.table(body_chunks),
        }
        if not one then return nil, tostring(code) end
        return {
            status  = tonumber(code) or 0,
            headers = resp_headers or {},
            body    = table.concat(body_chunks),
        }, nil
    end
end

-- default_backend picks the FreeSWITCH backend if `freeswitch.Curl` exists at
-- the moment of the first request; otherwise LuaSocket. The selection is
-- deferred per-call so unit tests can install a stub freeswitch global.
function M.default_backend()
    local fs_backend = M.new_freeswitch_backend()
    local ls_backend, ls_err
    return function(req)
        local fs = rawget(_G, "freeswitch")
        if fs and fs.Curl then
            return fs_backend(req)
        end
        if not ls_backend then
            ls_backend, ls_err = M.new_luasocket_backend()
            if not ls_backend then
                return nil, "no HTTP backend available (" .. tostring(ls_err) .. ")"
            end
        end
        return ls_backend(req)
    end
end

return M
