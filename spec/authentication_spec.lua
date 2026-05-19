local helpers  = require("spec.helpers")
local voicetel = require("voicetel")

describe("authentication", function()
    it("get", function()
        local c, m = helpers.new_client({
            helpers.ok({ authType = 1, authTypeDescription = "IP Auth", acl = {} }),
        })
        local r = c.authentication:get()
        assert.are.equal(1, r.authType)
        assert.matches("/v2.2/auth$", m.calls[1].url)
    end)

    it("update with auth type constant", function()
        local c, m = helpers.new_client({
            helpers.ok({ updated = { { field = "authType", value = voicetel.AUTH_TYPE_IP_AUTH } } }),
        })
        c.authentication:update({ authType = voicetel.AUTH_TYPE_IP_AUTH })
        assert.are.equal("PUT", m.calls[1].method)
        assert.are.same({ authType = 1 }, helpers.decode_body(m, 1))
    end)

    it("error path", function()
        local c = helpers.new_client({ helpers.err(400, "bad password") })
        local _, err = c.authentication:update({ password = "x" })
        assert.are.equal("bad_request", err.kind)
    end)
end)
