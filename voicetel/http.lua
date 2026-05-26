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

-- ---------------------------------------------------- URL parsing ---

local function parse_url(url)
    local scheme, rest = url:match("^(https?)://(.+)")
    if not scheme then return nil end
    local host_port, path = rest:match("^([^/]*)(.*)")
    if not host_port or host_port == "" then return nil end
    if path == "" then path = "/" end
    local host, port = host_port:match("^([^:]+):?(%d*)")
    port = tonumber(port) or (scheme == "https" and 443 or 80)
    return { scheme = scheme, host = host, port = port, path = path }
end

-- --------------------------------- Persistent connection pool ---

-- Single-entry pool: keeps one TCP+TLS socket alive for reuse.
-- All SDK traffic targets one host (api.voicetel.com), so one slot suffices.
local function new_conn_pool()
    local entry = nil

    local function evict()
        if entry then
            pcall(function() entry.sock:close() end)
            entry = nil
        end
    end

    local function acquire(host, port, scheme, timeout)
        if entry and entry.host == host and entry.port == port then
            local sock = entry.sock
            entry = nil
            sock:settimeout(0)
            local data, err = sock:receive(1)
            sock:settimeout(timeout or 30)
            if data or err == "closed" then
                pcall(function() sock:close() end)
            else
                return sock, nil
            end
        elseif entry then
            evict()
        end

        local ok_socket, socket_mod = pcall(require, "socket")
        if not ok_socket then return nil, "socket library not available" end
        local tcp = socket_mod.tcp()
        tcp:settimeout(timeout or 30)
        local ok, cerr = tcp:connect(host, port)
        if not ok then
            tcp:close()
            return nil, "connect: " .. tostring(cerr)
        end

        if scheme == "https" then
            local ok_ssl, ssl = pcall(require, "ssl")
            if not ok_ssl then
                tcp:close()
                return nil, "LuaSec (ssl) required for HTTPS URLs"
            end
            local wrapped, werr = ssl.wrap(tcp, {
                mode = "client",
                protocol = "any",
                verify = "peer",
                options = {"all"},
            })
            if not wrapped then
                tcp:close()
                return nil, "TLS wrap failed: " .. tostring(werr)
            end
            wrapped:sni(host)
            local hok, herr = wrapped:dohandshake()
            if not hok then
                wrapped:close()
                return nil, "TLS handshake failed: " .. tostring(herr)
            end
            return wrapped, nil
        end

        return tcp, nil
    end

    local function release(sock, host, port)
        evict()
        entry = { sock = sock, host = host, port = port }
    end

    return { acquire = acquire, release = release, evict = evict }
end

-- --------------------------------- Raw HTTP/1.1 helpers ---

local function send_raw_request(sock, method, path, host_header, headers, body)
    local lines = {
        method .. " " .. path .. " HTTP/1.1",
        "Host: " .. host_header,
        "Connection: keep-alive",
    }
    for k, v in pairs(headers) do
        local lk = string.lower(k)
        if lk ~= "host" and lk ~= "connection" then
            lines[#lines + 1] = tostring(k) .. ": " .. tostring(v)
        end
    end
    if body and #body > 0 then
        lines[#lines + 1] = "Content-Length: " .. tostring(#body)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = ""
    local head = table.concat(lines, "\r\n")
    local _, err = sock:send(head)
    if err then return err end
    if body and #body > 0 then
        _, err = sock:send(body)
        if err then return err end
    end
    return nil
end

local function read_raw_response(sock)
    local line, err = sock:receive("*l")
    if not line then return nil, "status read: " .. tostring(err), false end
    local status = tonumber(line:match("HTTP/%d%.%d (%d+)"))
    if not status then return nil, "malformed status line: " .. line, false end

    local headers = {}
    while true do
        line, err = sock:receive("*l")
        if not line or line == "" then break end
        if err then return nil, "header read: " .. tostring(err), false end
        local k, v = line:match("^([^:]+):%s*(.*)")
        if k then headers[string.lower(k)] = v end
    end

    local body
    local cl = tonumber(headers["content-length"])
    local te = headers["transfer-encoding"]

    if te and te:find("chunked") then
        local chunks = {}
        while true do
            local size_line
            size_line, err = sock:receive("*l")
            if not size_line then break end
            local size = tonumber(size_line, 16)
            if not size or size == 0 then
                sock:receive("*l")
                break
            end
            local chunk
            chunk, err = sock:receive(size)
            if not chunk then break end
            chunks[#chunks + 1] = chunk
            sock:receive("*l")
        end
        body = table.concat(chunks)
    elseif cl then
        if cl > 0 then
            body, err = sock:receive(cl)
            if not body then return nil, "body read: " .. tostring(err), false end
        else
            body = ""
        end
    elseif status == 204 or status == 304 then
        body = ""
    else
        body = sock:receive("*a") or ""
        return { status = status, headers = headers, body = body }, nil, false
    end

    local conn_hdr = headers["connection"]
    local keep_alive = not (conn_hdr and string.lower(conn_hdr) == "close")

    return { status = status, headers = headers, body = body or "" }, nil, keep_alive
end

-- ------------------------------------------ FreeSWITCH (freeswitch.Curl) ---

-- new_freeswitch_backend builds a backend that talks to FreeSWITCH's built-in
-- HTTP client. The curl handle is cached across requests so that cURL's
-- internal TLS session cache is retained between calls.
function M.new_freeswitch_backend()
    local cached_curl = nil
    return function(req)
        if not cached_curl then
            local fs = rawget(_G, "freeswitch")
            if not fs or not fs.Curl then
                return nil, "freeswitch.Curl not available"
            end
            cached_curl = fs.Curl()
            if not cached_curl then return nil, "could not construct freeswitch.Curl" end
        end
        local curl = cached_curl
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
            cached_curl = nil
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
    local ltn12 = require("ltn12")

    local pool = new_conn_pool()

    return function(req)
        local parsed = parse_url(req.url)

        -- Persistent-connection path for HTTPS: reuses the TCP+TLS socket
        -- so that TLS session state is retained across requests.
        if parsed and parsed.scheme == "https" then
            local sock, serr = pool.acquire(parsed.host, parsed.port, "https", req.timeout or 30)
            if not sock then return nil, serr end

            local headers = {}
            for k, v in pairs(req.headers or {}) do headers[k] = v end

            local host_header = parsed.host
            if parsed.port ~= 443 then
                host_header = parsed.host .. ":" .. tostring(parsed.port)
            end

            local send_err = send_raw_request(
                sock,
                string.upper(req.method or "GET"),
                parsed.path,
                host_header,
                headers,
                req.body
            )
            if send_err then
                pcall(function() sock:close() end)
                return nil, "send: " .. tostring(send_err)
            end

            local resp, rerr, keep_alive = read_raw_response(sock)
            if not resp then
                pcall(function() sock:close() end)
                return nil, rerr
            end

            if keep_alive then
                pool.release(sock, parsed.host, parsed.port)
            else
                pcall(function() sock:close() end)
            end

            return resp, nil
        end

        -- Plain HTTP (or unparseable URL): delegate to LuaSocket's http.request.
        local is_https = string.sub(req.url, 1, 5) == "https"
        if is_https then
            local ok_s, https = pcall(require, "ssl.https")
            if not ok_s then return nil, "LuaSec (ssl.https) required for HTTPS URLs" end
            local body_chunks = {}
            local source = nil
            local hdr = {}
            for k, v in pairs(req.headers or {}) do hdr[k] = v end
            if req.body and #req.body > 0 then
                source = ltn12.source.string(req.body)
                hdr["Content-Length"] = tostring(#req.body)
            end
            local one, code, resp_headers = https.request{
                url     = req.url,
                method  = string.upper(req.method or "GET"),
                headers = hdr,
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

        local body_chunks = {}
        local source = nil
        local headers = {}
        for k, v in pairs(req.headers or {}) do headers[k] = v end
        if req.body and #req.body > 0 then
            source = ltn12.source.string(req.body)
            headers["Content-Length"] = tostring(#req.body)
        end
        local one, code, resp_headers = http_mod.request{
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
