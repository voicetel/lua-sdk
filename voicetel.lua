-- voicetel — official Lua SDK for the VoiceTel REST API (v2.2.10).
--
-- Designed to run inside FreeSWITCH's mod_lua (Lua 5.2). HTTP transport is
-- pluggable: by default we use `freeswitch.Curl` when available and fall
-- back to LuaSocket otherwise.
--
-- Quickstart:
--
--     local voicetel = require("voicetel")
--
--     local client = voicetel.new({ api_key = "32hex..." })
--     local me, err = client.account:get()
--     if err then
--         if voicetel.is_rate_limit(err) then
--             freeswitch.consoleLog("WARNING", "rate-limited; backing off\n")
--         end
--         return
--     end
--     freeswitch.consoleLog("INFO", "balance: $" .. tostring(me.cash) .. "\n")
--
-- All methods return `(result, err)`. `err` is `nil` on success. Tests can
-- inject a deterministic `http_backend` via the constructor.

local version   = require("voicetel.version")
local errors    = require("voicetel.errors")
local json      = require("voicetel.json")
local transport = require("voicetel.transport")

local Account        = require("voicetel.resources.account")
local Acl            = require("voicetel.resources.acl")
local Authentication = require("voicetel.resources.authentication")
local E911           = require("voicetel.resources.e911")
local Gateways       = require("voicetel.resources.gateways")
local INumbering     = require("voicetel.resources.inumbering")
local Lookups        = require("voicetel.resources.lookups")
local Messaging      = require("voicetel.resources.messaging")
local Numbers        = require("voicetel.resources.numbers")
local Support        = require("voicetel.resources.support")

local M = {}

-- Public re-exports.
M.SDK_VERSION         = version.SDK_VERSION
M.API_VERSION         = version.API_VERSION
M.DEFAULT_BASE_URL    = version.DEFAULT_BASE_URL
M.DEFAULT_USER_AGENT  = version.DEFAULT_USER_AGENT

-- Error helpers (mirror the Go SDK's IsX / IsY style).
M.is_rate_limit         = errors.is_rate_limit
M.is_not_found          = errors.is_not_found
M.is_authentication     = errors.is_authentication
M.is_permission_denied  = errors.is_permission_denied
M.is_conflict           = errors.is_conflict
M.is_bad_request        = errors.is_bad_request
M.is_server             = errors.is_server

-- Error-kind constants, in case callers want to switch on err.kind themselves.
M.KIND_UNKNOWN           = errors.KIND_UNKNOWN
M.KIND_BAD_REQUEST       = errors.KIND_BAD_REQUEST
M.KIND_AUTHENTICATION    = errors.KIND_AUTHENTICATION
M.KIND_PERMISSION_DENIED = errors.KIND_PERMISSION_DENIED
M.KIND_NOT_FOUND         = errors.KIND_NOT_FOUND
M.KIND_CONFLICT          = errors.KIND_CONFLICT
M.KIND_RATE_LIMIT        = errors.KIND_RATE_LIMIT
M.KIND_SERVER            = errors.KIND_SERVER

-- Authentication mode constants for client.authentication:update.
M.AUTH_TYPE_DIGEST        = Authentication.AUTH_TYPE_DIGEST
M.AUTH_TYPE_IP_AUTH       = Authentication.AUTH_TYPE_IP_AUTH
M.AUTH_TYPE_DIGEST_OR_IP  = Authentication.AUTH_TYPE_DIGEST_OR_IP
M.AUTH_TYPE_DIGEST_AND_IP = Authentication.AUTH_TYPE_DIGEST_AND_IP

-- Expose for advanced use cases / tests.
M.errors    = errors
M.json      = json
M.transport = transport

local Client = {}
Client.__index = Client

-- new constructs a Client. opts table fields (all optional except api_key
-- when you skip login):
--
--   api_key       (string)   bearer token; omit to call client:login(...)
--   base_url      (string)   defaults to "https://api.voicetel.com"
--   user_agent    (string)   defaults to "voicetel-lua/<v>"
--   max_retries   (int)      defaults to 2 (total attempts = max_retries+1)
--   timeout       (number)   per-request timeout in seconds (default 30)
--   http_backend  (function) override the HTTP transport (for tests/instrumentation)
--   sleep         (function) override the inter-retry sleep (for tests)
function M.new(opts)
    opts = opts or {}
    local t = transport.new({
        base_url     = opts.base_url   or version.DEFAULT_BASE_URL,
        user_agent   = opts.user_agent or version.DEFAULT_USER_AGENT,
        api_key      = opts.api_key,
        max_retries  = opts.max_retries,
        timeout      = opts.timeout,
        http_backend = opts.http_backend,
        sleep        = opts.sleep,
    })

    local client = setmetatable({ _t = t }, Client)
    client.account        = Account.new(t)
    client.acl            = Acl.new(t)
    client.authentication = Authentication.new(t)
    client.e911           = E911.new(t)
    client.gateways       = Gateways.new(t)
    client.inumbering     = INumbering.new(t)
    client.lookups        = Lookups.new(t)
    client.messaging      = Messaging.new(t)
    client.numbers        = Numbers.new(t)
    client.support        = Support.new(t)
    return client
end

-- base_url returns the API endpoint this client is configured against.
function Client:base_url() return self._t.base_url end

-- api_key returns the currently-installed bearer token (or nil before login).
function Client:api_key() return self._t:get_bearer() end

-- set_api_key installs a bearer token after construction. Useful when the
-- key is fetched from a secret manager.
function Client:set_api_key(key) self._t:set_bearer(key) end

-- login exchanges username + password for a 32-hex bearer token and installs
-- it on this client. The exchange counts against the 6 req/hour/IP cap.
--
--   key, err = client:login(1000000001, "hunter2")
function Client:login(username, password)
    local body = { username = username, password = password }
    local data, err = self._t:request("POST", "/v2.2/account/api-key", nil, body, false)
    if err then return nil, err end
    if type(data) ~= "table" or type(data.apikey) ~= "string" or data.apikey == "" then
        return nil, errors.new(0, nil, "api-key response did not contain data.apikey", data)
    end
    self._t:set_bearer(data.apikey)
    return data.apikey, nil
end

M.Client = Client

return M
