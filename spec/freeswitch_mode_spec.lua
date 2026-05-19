-- End-to-end test of the FreeSWITCH-mode path: build a client without
-- supplying an http_backend, stub `freeswitch.Curl`, and verify that the
-- default_backend dispatches through it.

local voicetel = require("voicetel")
local json     = require("voicetel.json")

describe("FreeSWITCH integration", function()
    after_each(function()
        rawset(_G, "freeswitch", nil)
    end)

    it("uses freeswitch.Curl when available", function()
        local seen = { calls = {} }
        local stub_curl = {
            timeout = function(self, t) end,
            get = function(self, url, hdrs)
                seen.calls[#seen.calls+1] = { method = "GET", url = url, hdrs = hdrs }
                local body = json.encode({ status = "success", data = { cnam = "ACME INC", number = "2015551234" } })
                return body, 200, { ["Content-Type"] = "application/json" }
            end,
        }
        rawset(_G, "freeswitch", { Curl = function() return stub_curl end })

        local client = voicetel.new({ api_key = "test-key" })
        local r, err = client.lookups:cnam("2015551234")
        assert.is_nil(err)
        assert.are.equal("ACME INC", r.cnam)
        assert.are.equal(1, #seen.calls)
        assert.matches("/v2.2/cnam/2015551234$", seen.calls[1].url)

        -- Authorization header was set on the freeswitch curl call.
        local saw_auth = false
        for _, h in ipairs(seen.calls[1].hdrs) do
            if h:find("Authorization: Bearer test%-key") then saw_auth = true end
        end
        assert.is_true(saw_auth)
    end)

    it("works without freeswitch.Curl (falls back to LuaSocket if installed)", function()
        -- We don't require LuaSocket to actually be installed; just verify
        -- that the backend selector reports a sensible error when no backend
        -- is available rather than crashing.
        rawset(_G, "freeswitch", nil)
        local client = voicetel.new({ api_key = "k" })
        local r, err = client.lookups:cnam("2015551234")
        assert.is_nil(r)
        -- Either LuaSocket is installed (any HTTP error) or it isn't (the
        -- "no HTTP backend available" message). Both are acceptable here —
        -- we're proving offline-mode doesn't blow up before yielding an err.
        assert.is_not_nil(err)
    end)
end)
