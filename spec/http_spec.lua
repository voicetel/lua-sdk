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
end)
