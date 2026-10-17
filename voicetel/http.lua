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

-- ------------------------------------------------------ CA store ---

-- TLS parameters shared by both LuaSec paths: verify the peer chain against a
-- real CA bundle and never allow SSLv2/SSLv3.
local TLS_OPTIONS = { "all", "no_sslv2", "no_sslv3" }

-- Known CA bundle locations, in probe order (Debian/Ubuntu, Fedora/RHEL,
-- OpenSUSE, OpenBSD/Alpine/macOS).
local CAFILE_CANDIDATES = {
    "/etc/ssl/certs/ca-certificates.crt",
    "/etc/pki/tls/certs/ca-bundle.crt",
    "/etc/ssl/ca-bundle.pem",
    "/etc/ssl/cert.pem",
}

-- find_cafile resolves the CA bundle to verify peers against: an explicit
-- `cafile` client option wins, otherwise the usual system paths are probed.
-- Returns nil when nothing usable is found — callers must fail loudly in
-- that case rather than fall back to an unverified connection.
local function find_cafile(override)
    if override then return override end
    for _, path in ipairs(CAFILE_CANDIDATES) do
        local f = io.open(path, "rb")
        if f then f:close(); return path end
    end
    return nil
end

local NO_CAFILE_ERR =
    "TLS: no CA bundle found for peer verification; install the system " ..
    "ca-certificates package or pass cafile = \"/path/to/ca-bundle.pem\" to voicetel.new"

-- --------------------------- hostname verification (pure Lua) ---

-- Released LuaSec (<= 1.3.x) verifies the certificate chain when
-- verify = "peer" but never matches the certificate against the expected
-- hostname (upstream only gains that via sethost() after 1.3.2). We verify
-- the host ourselves after the handshake: subjectAltName dNSName entries
-- first (RFC 6125), iPAddress entries for IP-literal hosts, and the subject
-- CN when no SAN is present at all. A wildcard covers exactly one left-most
-- label ("*.example.com" matches "api.example.com" but not "a.b.example.com").
local function dnsname_match(pattern, host)
    pattern = string.lower(tostring(pattern or ""))
    host = string.lower(tostring(host or ""))
    if string.sub(pattern, 1, 2) == "*." then
        local suffix = string.sub(pattern, 2) -- ".example.com"
        local label, rest = string.match(host, "^([^.]+)(%..+)$")
        return label ~= nil and rest == suffix
    end
    return pattern == host
end

-- verify_hostname(cert, host) -> true | nil, err
local function verify_hostname(cert, host)
    local names, ips = {}, {}
    local ok_ext, exts = pcall(function() return cert:extensions() end)
    if ok_ext and type(exts) == "table" then
        -- subjectAltName lives under its OID (2.5.29.17) as
        -- { name = "X509v3 Subject Alternative Name", dNSName = { ... }, ... }
        local san = exts["2.5.29.17"]
        if type(san) == "table" then
            if type(san.dNSName) == "table" then
                for _, n in ipairs(san.dNSName) do names[#names + 1] = n end
            end
            if type(san.iPAddress) == "table" then
                for _, n in ipairs(san.iPAddress) do ips[#ips + 1] = n end
            end
        end
    end
    if #names == 0 and #ips == 0 then
        local ok_s, subj = pcall(function() return cert:subject() end)
        if ok_s and type(subj) == "table" then
            for _, entry in ipairs(subj) do
                if type(entry) == "table"
                    and (entry.name == "commonName" or entry.oid == "2.5.4.3")
                    and entry.value
                then
                    names[#names + 1] = entry.value
                end
            end
        end
    end
    for _, n in ipairs(names) do
        if dnsname_match(n, host) then return true end
    end
    for _, n in ipairs(ips) do
        if tostring(n) == tostring(host) then return true end
    end
    return nil, "TLS: certificate hostname mismatch (expected " .. tostring(host) .. ")"
end

-- check_peer_hostname(conn, host) -> true | nil, err
-- Verifies the presented certificate against `host` on a handshaked LuaSec
-- connection. Callers that already passed sethost() before the handshake
-- (where OpenSSL enforces the match itself) skip this call.
local function check_peer_hostname(conn, host)
    if type(conn.getpeercertificate) ~= "function" then
        return nil, "TLS: cannot verify the peer hostname on this LuaSec version"
    end
    local cert = conn:getpeercertificate()
    if not cert then
        return nil, "TLS: peer did not present a certificate"
    end
    return verify_hostname(cert, host)
end

-- --------------------------------- Persistent connection pool ---

-- Single-entry pool: keeps one TCP+TLS socket alive for reuse.
-- All SDK traffic targets one host (api.voicetel.com), so one slot suffices.
-- tls_cfg = { cafile = "/path/to/ca-bundle.pem" or nil }.
local function new_conn_pool(tls_cfg)
    tls_cfg = tls_cfg or {}
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
            if not tls_cfg.cafile then
                tcp:close()
                return nil, NO_CAFILE_ERR
            end
            local wrapped, werr = ssl.wrap(tcp, {
                mode = "client",
                protocol = "any",
                verify = "peer",
                options = TLS_OPTIONS,
                cafile = tls_cfg.cafile,
            })
            if not wrapped then
                tcp:close()
                return nil, "TLS wrap failed: " .. tostring(werr)
            end
            wrapped:sni(host)
            -- LuaSec > 1.3.2 can enforce the hostname during the handshake
            -- itself; enable that when available.
            local host_checked = false
            if type(wrapped.sethost) == "function" then
                local shok, sherr = wrapped:sethost(host)
                if not shok then
                    wrapped:close()
                    return nil, "TLS sethost failed: " .. tostring(sherr)
                end
                host_checked = true
            end
            local hok, herr = wrapped:dohandshake()
            if not hok then
                wrapped:close()
                return nil, "TLS handshake failed: " .. tostring(herr)
            end
            -- Released LuaSec verified the chain but not the hostname — do
            -- it now (skipped when sethost above already covered it).
            if not host_checked then
                local vok, verr = check_peer_hostname(wrapped, host)
                if not vok then
                    wrapped:close()
                    return nil, verr
                end
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
            if not size_line then return nil, "body read: " .. tostring(err), false end
            local size = tonumber(size_line, 16)
            if not size or size == 0 then
                sock:receive("*l")
                break
            end
            local chunk
            chunk, err = sock:receive(size)
            if not chunk then return nil, "body read: " .. tostring(err), false end
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

-- new_luasocket_backend builds the non-FreeSWITCH backend. opts:
--   cafile (string) — CA bundle path for TLS peer verification; when omitted
--   the usual system locations are probed (see CAFILE_CANDIDATES).
function M.new_luasocket_backend(opts)
    opts = opts or {}
    local ok_http, http_mod = pcall(require, "socket.http")
    if not ok_http then
        return nil, "socket.http not installed"
    end
    local ltn12 = require("ltn12")

    local cafile = find_cafile(opts.cafile)

    -- LuaSec's ssl.https is the preferred HTTPS path. It is fed
    -- verify="peer" + the CA bundle for chain verification; hostname
    -- verification is hooked into the connection's connect() below, since
    -- released LuaSec performs none on its own. The raw pooled path further
    -- down remains as the fallback for partial installs that ship ssl
    -- without ssl.https.
    local ok_https, https_mod = pcall(require, "ssl.https")
    if ok_https then
        -- LuaSec 0.x is too old to trust (no cert:extensions()/subject());
        -- drop to the raw path, which fails loudly if it cannot verify.
        local v = tostring(https_mod._VERSION or "")
        if v:match("^0%.") or type(https_mod.tcp) ~= "function" then
            ok_https = false
        end
    end

    local pool = new_conn_pool({ cafile = cafile })

    return function(req)
        local parsed = parse_url(req.url)

        if parsed and parsed.scheme == "https" and ok_https then
            if not cafile then return nil, NO_CAFILE_ERR end
            local body_chunks = {}
            local source = nil
            local hdr = {}
            for k, v in pairs(req.headers or {}) do hdr[k] = v end
            if req.body and #req.body > 0 then
                source = ltn12.source.string(req.body)
                hdr["Content-Length"] = tostring(#req.body)
            end
            local make_conn = https_mod.tcp({
                protocol = "any",
                verify   = "peer",
                options  = TLS_OPTIONS,
                cafile   = cafile,
            })
            local function create()
                local conn = make_conn()
                local orig_connect = conn.connect
                -- connect() establishes TCP, wraps TLS and runs the
                -- handshake (raising on failure); the certificate hostname
                -- check rides along before the request is sent.
                conn.connect = function(self, host, port)
                    orig_connect(self, host, port)
                    local vok, verr = check_peer_hostname(self, host)
                    if not vok then error(verr) end
                    return 1
                end
                return conn
            end
            local one, code, resp_headers = http_mod.request{
                url     = req.url,
                method  = string.upper(req.method or "GET"),
                headers = hdr,
                source  = source,
                sink    = ltn12.sink.table(body_chunks),
                create  = create,
            }
            if not one then return nil, tostring(code) end
            return {
                status  = tonumber(code) or 0,
                headers = resp_headers or {},
                body    = table.concat(body_chunks),
            }, nil
        end

        -- Raw persistent-connection path for HTTPS: reuses the TCP+TLS socket
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
-- opts is forwarded to new_luasocket_backend (e.g. { cafile = "..." }).
function M.default_backend(opts)
    local fs_backend = M.new_freeswitch_backend()
    local ls_backend, ls_err
    return function(req)
        local fs = rawget(_G, "freeswitch")
        if fs and fs.Curl then
            return fs_backend(req)
        end
        if not ls_backend then
            ls_backend, ls_err = M.new_luasocket_backend(opts)
            if not ls_backend then
                return nil, "no HTTP backend available (" .. tostring(ls_err) .. ")"
            end
        end
        return ls_backend(req)
    end
end

-- ------------------------------------------------------ exposed helpers ---

-- Exposed for tests.
M._find_cafile     = find_cafile
M._dnsname_match   = dnsname_match
M._verify_hostname = verify_hostname

return M
