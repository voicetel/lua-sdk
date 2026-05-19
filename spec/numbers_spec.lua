local helpers = require("spec.helpers")

describe("numbers", function()
    local function ok(b) return helpers.ok(b) end

    it("list", function()
        local c, m = helpers.new_client({ ok({ numbers = {} }) })
        c.numbers:list()
        assert.matches("/v2.2/numbers$", m.calls[1].url)
    end)

    it("add/get/remove/move/release", function()
        local c, m = helpers.new_client({
            ok({ number = "2015551234", route = 4 }),
            ok({ number = "2015551234" }),
            { status = 204, body = "" },
            ok({ number = "2015551234", accountId = 1000000002, route = 4 }),
            ok({}),
        })
        c.numbers:add({ number = "2015551234" })
        c.numbers:get("2015551234")
        local removed = c.numbers:remove("2015551234")
        c.numbers:move("2015551234", { accountId = 1000000002, route = 4 })
        c.numbers:release("2015551234")
        assert.are.equal("POST",   m.calls[1].method)
        assert.are.equal("GET",    m.calls[2].method)
        assert.are.equal("DELETE", m.calls[3].method)
        assert.are.equal("PATCH",  m.calls[4].method)
        assert.are.equal("POST",   m.calls[5].method)
        assert.matches("/release$", m.calls[5].url)
        assert.is_true(removed)
    end)

    it("set_route / set_translation / set_cnam / set_lidb", function()
        local c, m = helpers.new_client({ ok({}), ok({}), ok({}), ok({}) })
        c.numbers:set_route("2015551234", { route = 4 })
        c.numbers:set_translation("2015551234", { translation = "12345#" })
        c.numbers:set_cnam("2015551234", { enabled = true })
        c.numbers:set_lidb("2015551234", { cnam = "ACME" })
        assert.matches("/route$",       m.calls[1].url)
        assert.matches("/translation$", m.calls[2].url)
        assert.matches("/cnam$",        m.calls[3].url)
        assert.matches("/lidb$",        m.calls[4].url)
        for i = 1, 4 do assert.are.equal("PUT", m.calls[i].method) end
    end)

    it("fax: get / set / remove (204)", function()
        local c, m = helpers.new_client({ ok({}), ok({}), { status = 204, body = "" } })
        c.numbers:get_fax("2015551234")
        c.numbers:set_fax("2015551234", { email = "a@b.com" })
        local r = c.numbers:remove_fax("2015551234")
        assert.is_true(r)
        assert.matches("/fax$", m.calls[1].url)
    end)

    it("forward: set / remove (204)", function()
        local c, m = helpers.new_client({ ok({}), { status = 204, body = "" } })
        c.numbers:set_forward("2015551234", { destination = 2125550000 })
        local r = c.numbers:remove_forward("2015551234")
        assert.is_true(r)
        assert.matches("/forward$", m.calls[1].url)
        assert.matches("/forward$", m.calls[2].url)
    end)

    it("sms: get / set / remove (204)", function()
        local c, m = helpers.new_client({ ok({}), ok({}), { status = 204, body = "" } })
        c.numbers:get_sms("2015551234")
        c.numbers:set_sms("2015551234", { type = "webhook", resource = "https://h" })
        local r = c.numbers:remove_sms("2015551234")
        assert.is_true(r)
        assert.matches("/sms$", m.calls[3].url)
    end)

    it("messaging state get + patch", function()
        local c, m = helpers.new_client({ ok({}), ok({ updated = { "routeIn" } }) })
        c.numbers:get_messaging("2015551234")
        c.numbers:patch_messaging("2015551234", { routeIn = 5 })
        assert.are.equal("PATCH", m.calls[2].method)
    end)

    it("assign / unassign / bulk_unassign campaign", function()
        local c, m = helpers.new_client({
            ok({ campaignId = "ABC1234" }),
            ok({ unassigned = true }),
            ok({ unassignedNumbers = { "2015551234" } }),
        })
        c.numbers:assign_campaign("2015551234", { campaignId = "ABC1234" })
        c.numbers:unassign_campaign("2015551234")
        c.numbers:bulk_unassign_campaign({ "2015551234", "2015555678" })
        assert.are.equal("PUT", m.calls[1].method)

        -- per-number unassign: 200 with body, NOT 204
        assert.are.equal("DELETE", m.calls[2].method)
        local body2 = m.calls[2].body
        assert.is_truthy(not body2 or body2 == "")

        -- bulk unassign sends a JSON body and the response carries data
        assert.are.equal("DELETE", m.calls[3].method)
        assert.matches("/v2.2/numbers/messaging%-campaign$", m.calls[3].url)
        local b = helpers.decode_body(m, 3)
        assert.are.same({ "2015551234", "2015555678" }, b.numbers)
    end)

    it("set_port_out_pin", function()
        local c, m = helpers.new_client({ ok({ portOutPin = "1234" }) })
        c.numbers:set_port_out_pin("2015551234", { pin = "1234" })
        assert.are.equal("PATCH", m.calls[1].method)
        assert.matches("/port%-out%-pin$", m.calls[1].url)
    end)

    it("error path", function()
        local c = helpers.new_client({ helpers.err(404, "no such tn") })
        local _, err = c.numbers:get("9999999999")
        assert.are.equal("not_found", err.kind)
    end)
end)
