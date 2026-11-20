local helpers = require("spec.helpers")

describe("messaging", function()
    it("history with all options", function()
        local c, m = helpers.new_client({ helpers.ok({ messages = {} }) })
        c.messaging:history({ number = "2015550123", from = 1, to = 2, type = "sms" })
        local url = m.calls[1].url
        assert.matches("number=2015550123", url)
        assert.matches("from=1", url)
        assert.matches("to=2", url)
        assert.matches("type=sms", url)
    end)

    -- Spec quirk: wire body uses fromNumber/toNumber; we accept the
    -- snake-case aliases as a convenience.
    it("send remaps from_number/to_number to wire field names", function()
        local c, m = helpers.new_client({ helpers.ok({ id = "x", type = "sms" }) })
        c.messaging:send({ from_number = "2015550123", to_number = "2125550123", text = "hi" })
        local body = helpers.decode_body(m, 1)
        assert.are.equal("2015550123", body.fromNumber)
        assert.are.equal("2125550123", body.toNumber)
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

    -- v2.2.20 truth fix: text is optional for MMS — a media-only send is
    -- valid and must not inject a text field onto the wire.
    it("send allows media-only MMS (no text)", function()
        local c, m = helpers.new_client({ helpers.ok({ id = "m1", type = "mms", parts = 1 }) })
        local r, err = c.messaging:send({
            from_number = "2015550123",
            to_number   = "2125550123",
            media_urls  = { "https://example.com/cat.png" },
        })
        assert.is_nil(err)
        assert.are.equal("mms", r.type)
        local body = helpers.decode_body(m, 1)
        assert.are.equal("2015550123", body.fromNumber)
        assert.are.equal("2125550123", body.toNumber)
        assert.is_nil(body.text)
        assert.are.same({ "https://example.com/cat.png" }, body.mediaUrls)
    end)

    it("send remaps media_urls to the wire mediaUrls", function()
        local c, m = helpers.new_client({ helpers.ok({ id = "x" }) })
        c.messaging:send({ fromNumber = "a", toNumber = "b", text = "hi",
                           media_urls = { "https://example.com/x.jpg" } })
        local body = helpers.decode_body(m, 1)
        assert.are.same({ "https://example.com/x.jpg" }, body.mediaUrls)
        assert.is_nil(body.media_urls)
    end)

    -- v2.2.20: history records carry the full per-type field set in `value`.
    it("history records surface dlr and mms value fields", function()
        local c = helpers.new_client({
            helpers.ok({
                number = "2015550123", type = "dlr", fromTs = 1, toTs = 2,
                messages = {
                    {
                        id = "d1", key = { "2015550123", 1700000000 },
                        value = {
                            destinationNumber = "2125550000",
                            sourceNumber      = "2015550123",
                            messageText       = "DELIV",
                            transactionGUID   = "abc-123",
                            concatenatedMessage = nil,
                        },
                    },
                    {
                        id = "m2", key = { "2125550000", 1700000100 },
                        value = {
                            number      = "2125550000",
                            direction   = "in",
                            message     = "",
                            subject     = "Hello",
                            attachments = { { contentFile = "f.jpg", contentType = "image/jpeg" } },
                        },
                    },
                },
            }),
        })
        local r, err = c.messaging:history({ number = "2015550123", type = "dlr" })
        assert.is_nil(err)
        assert.are.equal("DELIV", r.messages[1].value.messageText)
        assert.are.equal("abc-123", r.messages[1].value.transactionGUID)
        assert.are.equal("Hello", r.messages[2].value.subject)
        assert.are.equal("image/jpeg", r.messages[2].value.attachments[1].contentType)
    end)

    it("create_brand + campaign_status + create_campaign", function()
        local c, m = helpers.new_client({
            helpers.ok({ result = { status = "Success" } }),
            helpers.ok({ campaigns = {} }),
            helpers.ok({ result = { status = "Success" } }),
        })
        c.messaging:create_brand({ messagingBrandId = "B1", messagingBrandName = "x" })
        c.messaging:campaign_status("CAMP002,ZZZZZZZ")
        c.messaging:create_campaign({ messagingBrandId = "B1", externalCampaignId = "C1",
                                       campaignDescription = "x" })
        assert.matches("/v2.2/messaging/brands$",    m.calls[1].url)
        assert.matches("/v2.2/messaging/campaigns%?ids=CAMP002%%2CZZZZZZZ$", m.calls[2].url)
        assert.matches("/v2.2/messaging/campaigns$", m.calls[3].url)
    end)

    it("campaign_status surfaces the dca carrier-review table", function()
        local c = helpers.new_client({
            helpers.ok({
                campaigns = {
                    {
                        id      = "CAMP002",
                        status  = "CAMPAIGN_DCA_REJECTED",
                        numbers = { "2015550123" },
                        dca = {
                            electionComplete = true,
                            electedCarriers  = { "AT&T", "T-Mobile", "Verizon Wireless" },
                            carriers = {
                                {
                                    carrier   = "T-Mobile",
                                    status    = "REJECTED",
                                    detail    = "Campaign rejected",
                                    updatedAt = "2026-10-01T00:00:00Z",
                                },
                                {
                                    carrier   = "US Cellular",
                                    status    = "ACTIVE",
                                    detail    = "Campaign approved",
                                    updatedAt = "2026-09-30T00:00:00Z",
                                },
                            },
                        },
                    },
                    {
                        id      = "ZZZZZZZ",
                        status  = "CAMPAIGN_INVALID_ID",
                        numbers = {},
                    },
                },
            }),
        })
        local r, err = c.messaging:campaign_status({ "CAMP002", "ZZZZZZZ" })
        assert.is_nil(err)
        local first = r.campaigns[1]
        assert.are.equal("CAMPAIGN_DCA_REJECTED", first.status)
        assert.is_true(first.dca.electionComplete)
        assert.are.same({ "AT&T", "T-Mobile", "Verizon Wireless" }, first.dca.electedCarriers)
        assert.are.equal(2, #first.dca.carriers)
        assert.are.equal("T-Mobile", first.dca.carriers[1].carrier)
        assert.are.equal("REJECTED", first.dca.carriers[1].status)
        assert.are.equal("Campaign rejected", first.dca.carriers[1].detail)
        assert.are.equal("US Cellular", first.dca.carriers[2].carrier)
        assert.are.equal("ACTIVE", first.dca.carriers[2].status)
        assert.is_nil(r.campaigns[2].dca)
    end)

    it("numbers_state encodes the numbers list", function()
        local c, m = helpers.new_client({ helpers.ok({ numbers = {} }) })
        c.messaging:numbers_state({ "2015550123", "2015555678" })
        assert.matches("numbers=2015550123%%2C2015555678", m.calls[1].url)
    end)

    it("numbers_state accepts a comma-separated string", function()
        local c, m = helpers.new_client({ helpers.ok({ numbers = {} }) })
        c.messaging:numbers_state("2015550123")
        assert.are.equal(
            "https://api.voicetel.com/v2.2/numbers/messaging?numbers=2015550123",
            m.calls[1].url)
    end)

    -- v2.2.15: messaging-health endpoints have no response schema in the spec,
    -- so the decoded JSON table is returned verbatim; bodies/query are still shaped.
    it("health endpoints return the decoded payload verbatim", function()
        local c, m = helpers.new_client({
            helpers.ok({ summary = { numbers = 3, healthy = 2 } }),
            helpers.ok({ enabled = true }),
            helpers.ok({ enabled = false }),
            helpers.ok({ number = "2125550123", inService = true }),
            helpers.ok({ samples = { { reason = "spam" } } }),
        })

        local health, e1 = c.messaging:health()
        assert.is_nil(e1)
        assert.are.equal(3, health.summary.numbers)
        assert.are.equal("GET", m.calls[1].method)
        assert.matches("/v2.2/messaging/health$", m.calls[1].url)

        local alerts, e2 = c.messaging:health_alerts()
        assert.is_nil(e2)
        assert.is_true(alerts.enabled)
        assert.matches("/v2.2/messaging/health/alerts$", m.calls[2].url)

        local off, e3 = c.messaging:set_health_alerts(false)
        assert.is_nil(e3)
        assert.is_false(off.enabled)
        assert.are.equal("PUT", m.calls[3].method)
        assert.is_false(helpers.decode_body(m, 3).enabled)

        local check, e4 = c.messaging:health_check("2125550123")
        assert.is_nil(e4)
        assert.is_true(check.inService)
        assert.are.equal("POST", m.calls[4].method)
        assert.are.equal("2125550123", helpers.decode_body(m, 4).number)

        local samples, e5 = c.messaging:health_samples("2125550123")
        assert.is_nil(e5)
        assert.are.equal("spam", samples.samples[1].reason)
        assert.matches("/v2.2/messaging/health/samples", m.calls[5].url)
        assert.matches("number=2125550123", m.calls[5].url)
    end)

    it("error path on send", function()
        local c = helpers.new_client({ helpers.err(403, "not allowed") })
        local _, err = c.messaging:send({ fromNumber = "a", toNumber = "b", text = "hi" })
        assert.are.equal("permission_denied", err.kind)
    end)
end)
