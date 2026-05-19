local helpers = require("spec.helpers")

describe("messaging", function()
    it("history with all options", function()
        local c, m = helpers.new_client({ helpers.ok({ messages = {} }) })
        c.messaging:history({ number = "2015551234", start = 1, ["end"] = 2, type = "sms" })
        local url = m.calls[1].url
        assert.matches("number=2015551234", url)
        assert.matches("start=1", url)
        assert.matches("end=2", url)
        assert.matches("type=sms", url)
    end)

    -- Spec quirk: wire body uses fromNumber/toNumber; we accept the
    -- snake-case aliases as a convenience.
    it("send remaps from_number/to_number to wire field names", function()
        local c, m = helpers.new_client({ helpers.ok({ id = "x", type = "sms" }) })
        c.messaging:send({ from_number = "2015551234", to_number = "2125551234", text = "hi" })
        local body = helpers.decode_body(m, 1)
        assert.are.equal("2015551234", body.fromNumber)
        assert.are.equal("2125551234", body.toNumber)
        assert.is_nil(body.from_number)
        assert.is_nil(body.to_number)
    end)

    it("send accepts wire spelling unchanged", function()
        local c, m = helpers.new_client({ helpers.ok({ id = "x" }) })
        c.messaging:send({ fromNumber = "a", toNumber = "b", text = "hi" })
        local body = helpers.decode_body(m, 1)
        assert.are.equal("a", body.fromNumber)
        assert.are.equal("b", body.toNumber)
    end)

    it("create_brand + campaign_status + create_campaign", function()
        local c, m = helpers.new_client({
            helpers.ok({ result = { status = "Success" } }),
            helpers.ok({ campaigns = {} }),
            helpers.ok({ result = { status = "Success" } }),
        })
        c.messaging:create_brand({ messagingBrandId = "B1", messagingBrandName = "x" })
        c.messaging:campaign_status()
        c.messaging:create_campaign({ messagingBrandId = "B1", externalCampaignId = "C1",
                                       campaignDescription = "x" })
        assert.matches("/v2.2/messaging/brands$",    m.calls[1].url)
        assert.matches("/v2.2/messaging/campaigns$", m.calls[2].url)
        assert.matches("/v2.2/messaging/campaigns$", m.calls[3].url)
    end)

    it("numbers_state encodes the numbers list", function()
        local c, m = helpers.new_client({ helpers.ok({ numbers = {} }) })
        c.messaging:numbers_state({ "2015551234", "2015555678" })
        assert.matches("numbers=2015551234%%2C2015555678", m.calls[1].url)
    end)

    it("numbers_state with empty list omits the query", function()
        local c, m = helpers.new_client({ helpers.ok({ numbers = {} }) })
        c.messaging:numbers_state({})
        assert.are.equal("https://api.voicetel.com/v2.2/numbers/messaging", m.calls[1].url)
    end)

    it("error path on send", function()
        local c = helpers.new_client({ helpers.err(403, "not allowed") })
        local _, err = c.messaging:send({ fromNumber = "a", toNumber = "b", text = "hi" })
        assert.are.equal("permission_denied", err.kind)
    end)
end)
