-- Tests that exercise the FreeSWITCH-mode path of voicetel.http by stubbing
-- the `freeswitch` global. Also covers backend selection logic.

local http = require("voicetel.http")

describe("voicetel.http", function()
    after_each(function()
        rawset(_G, "freeswitch", nil)
    end)

    it("get_header is case-insensitive", function()
        local resp = { headers = { ["Retry-After"] = "5", Content_Type = "x" } }
        assert.are.equal("5", http.get_header(resp, "retry-after"))
        assert.is_nil(http.get_header(resp, "missing"))
        assert.is_nil(http.get_header(nil, "x"))
    end)

    describe("FreeSWITCH backend", function()
        it("dispatches GET to freeswitch.Curl:get", function()
            local seen = {}
            local stub_curl = {
                timeout = function(self, t) seen.timeout = t end,
                get = function(self, url, hdrs)
                    seen.url = url; seen.hdrs = hdrs
                    return '{"status":"success","data":{"ok":1}}', 200, { ["Content-Type"] = "application/json" }
                end,
            }
            rawset(_G, "freeswitch", { Curl = function() return stub_curl end })
            local backend = http.new_freeswitch_backend()
            local resp, err = backend({ method = "GET", url = "https://x/y", headers = { A = "B" }, timeout = 15 })
            assert.is_nil(err)
            assert.are.equal(200, resp.status)
            assert.are.equal(15, seen.timeout)
            assert.are.equal("https://x/y", seen.url)
            assert.are.same({ "A: B" }, seen.hdrs)
            assert.matches('"ok":1', resp.body)
        end)

        it("dispatches POST/PUT to dedicated methods", function()
            local got_method
            local stub = {
                post = function(self, url, body, hdrs)
                    got_method = "POST"; return '{"data":{}}', 201, {}
                end,
                put = function(self, url, body, hdrs)
                    got_method = "PUT"; return '{"data":{}}', 200, {}
                end,
            }
            rawset(_G, "freeswitch", { Curl = function() return stub end })
            local backend = http.new_freeswitch_backend()
            backend({ method = "POST", url = "u", headers = {}, body = "{}" })
            assert.are.equal("POST", got_method)
            backend({ method = "PUT", url = "u", headers = {}, body = "{}" })
            assert.are.equal("PUT", got_method)
        end)

        it("dispatches DELETE/PATCH via curl:request when present", function()
            local saw = {}
            local stub = {
                request = function(self, method, url, body, hdrs)
                    saw[#saw+1] = method
                    return "", 204, {}
                end,
            }
            rawset(_G, "freeswitch", { Curl = function() return stub end })
            local backend = http.new_freeswitch_backend()
            backend({ method = "DELETE", url = "u", headers = {} })
            backend({ method = "PATCH",  url = "u", headers = {}, body = "{}" })
            assert.are.same({ "DELETE", "PATCH" }, saw)
        end)

        it("returns an error when freeswitch.Curl is unavailable", function()
            rawset(_G, "freeswitch", nil)
            local backend = http.new_freeswitch_backend()
            local resp, err = backend({ method = "GET", url = "u", headers = {} })
            assert.is_nil(resp)
            assert.matches("freeswitch.Curl not available", err)
        end)

        it("rejects unsupported methods", function()
            rawset(_G, "freeswitch", { Curl = function() return { get = function() return "", 200, {} end } end })
            local backend = http.new_freeswitch_backend()
            local _, err = backend({ method = "OPTIONS", url = "u", headers = {} })
            assert.matches("unsupported method", err)
        end)
    end)

    describe("default_backend", function()
        it("picks FreeSWITCH when freeswitch.Curl is available", function()
            local called
            rawset(_G, "freeswitch", { Curl = function()
                return { get = function() called = true; return '{"data":{}}', 200, {} end }
            end })
            local backend = http.default_backend()
            local resp = backend({ method = "GET", url = "u", headers = {} })
            assert.is_true(called)
            assert.are.equal(200, resp.status)
        end)
    end)

    describe("TLS hostname verification", function()
        -- Mimics the subset of LuaSec's certificate object used by
        -- http._verify_hostname: extensions() + subject().
        local function fake_cert(san_dns, san_ips, cn)
            return {
                extensions = function()
                    if not san_dns and not san_ips then return {} end
                    local san = { name = "X509v3 Subject Alternative Name" }
                    if san_dns then san.dNSName = san_dns end
                    if san_ips then san.iPAddress = san_ips end
                    return { ["2.5.29.17"] = san }
                end,
                subject = function()
                    if not cn then return {} end
                    return { { oid = "2.5.4.3", name = "commonName", value = cn } }
                end,
            }
        end

        it("matches an exact SAN dNSName", function()
            assert.is_true(http._verify_hostname(
                fake_cert({ "api.voicetel.com" }, nil, nil), "api.voicetel.com"))
        end)

        it("is case-insensitive", function()
            assert.is_true(http._verify_hostname(
                fake_cert({ "API.VoiceTel.COM" }, nil, nil), "api.voicetel.com"))
        end)

        it("matches a one-label wildcard", function()
            assert.is_true(http._verify_hostname(
                fake_cert({ "*.voicetel.com" }, nil, nil), "api.voicetel.com"))
        end)

        it("wildcard does not span multiple labels", function()
            local ok = http._verify_hostname(
                fake_cert({ "*.voicetel.com" }, nil, nil), "a.b.voicetel.com")
            assert.is_nil(ok)
        end)

        it("wildcard does not match the bare apex", function()
            local ok = http._verify_hostname(
                fake_cert({ "*.voicetel.com" }, nil, nil), "voicetel.com")
            assert.is_nil(ok)
        end)

        it("rejects a mismatched SAN", function()
            local ok, err = http._verify_hostname(
                fake_cert({ "evil.example.com" }, nil, nil), "api.voicetel.com")
            assert.is_nil(ok)
            assert.matches("hostname mismatch", err)
        end)

        it("falls back to the subject CN when no SAN is present", function()
            assert.is_true(http._verify_hostname(
                fake_cert(nil, nil, "api.voicetel.com"), "api.voicetel.com"))
        end)

        it("matches an iPAddress SAN for IP-literal hosts", function()
            assert.is_true(http._verify_hostname(
                fake_cert(nil, { "192.0.2.10" }, nil), "192.0.2.10"))
        end)
    end)
end)
