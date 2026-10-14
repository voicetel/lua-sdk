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
            ok({ number = "2015550123", route = 4 }),
            ok({ number = "2015550123" }),
            { status = 204, body = "" },
            ok({ number = "2015550123", accountId = 1000000002, route = 4 }),
            ok({}),
        })
        c.numbers:add({ number = "2015550123" })
        c.numbers:get("2015550123")
        local removed = c.numbers:remove("2015550123")
        c.numbers:move("2015550123", { accountId = 1000000002, route = 4 })
        c.numbers:release("2015550123")
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
        c.numbers:set_route("2015550123", { route = 4 })
        c.numbers:set_translation("2015550123", { translation = "12345#" })
        c.numbers:set_cnam("2015550123", { enabled = true })
        c.numbers:set_lidb("2015550123", { cnam = "ACME" })
        assert.matches("/route$",       m.calls[1].url)
        assert.matches("/translation$", m.calls[2].url)
        assert.matches("/cnam$",        m.calls[3].url)
        assert.matches("/lidb$",        m.calls[4].url)
        for i = 1, 4 do assert.are.equal("PUT", m.calls[i].method) end
    end)

    it("fax: get / set / remove (204)", function()
        local c, m = helpers.new_client({ ok({}), ok({}), { status = 204, body = "" } })
        c.numbers:get_fax("2015550123")
        c.numbers:set_fax("2015550123", { email = "a@b.com" })
        local r = c.numbers:remove_fax("2015550123")
        assert.is_true(r)
        assert.matches("/fax$", m.calls[1].url)
    end)

    it("forward: set / remove (204)", function()
        local c, m = helpers.new_client({ ok({}), { status = 204, body = "" } })
        c.numbers:set_forward("2015550123", { destination = 2125550000 })
        local r = c.numbers:remove_forward("2015550123")
        assert.is_true(r)
        assert.matches("/forward$", m.calls[1].url)
        assert.matches("/forward$", m.calls[2].url)
    end)

    it("sms: get / set / remove (204)", function()
        local c, m = helpers.new_client({ ok({}), ok({}), { status = 204, body = "" } })
        c.numbers:get_sms("2015550123")
        c.numbers:set_sms("2015550123", { type = "webhook", resource = "https://h" })
        local r = c.numbers:remove_sms("2015550123")
        assert.is_true(r)
        assert.matches("/sms$", m.calls[3].url)
    end)

    it("messaging state get + patch", function()
        local c, m = helpers.new_client({
            ok({
                enabled  = true,
                carrier  = 1,
                network  = "C",
                campaign = { id = "CAMP002", network = "C", status = "ACTIVE", upstreamCnpId = "BANDW" },
                pending  = {
                    campaignId = "CAMP002",
                    state      = "assigning",
                    message    = "assigning number",
                    createdAt  = "2026-10-13T16:00:00Z",
                    updatedAt  = "2026-10-13T16:05:00Z",
                },
            }),
            ok({ updated = { "routeIn" } }),
        })
        local r = c.numbers:get_messaging("2015550123")
        c.numbers:patch_messaging("2015550123", { routeIn = 5 })
        assert.are.equal("C", r.network)
        assert.are.equal("CAMP002", r.pending.campaignId)
        assert.are.equal("assigning", r.pending.state)
        assert.are.equal("assigning number", r.pending.message)
        assert.are.equal("PATCH", m.calls[2].method)
    end)

    it("assign campaign (path C) surfaces status/job/warning", function()
        local c = helpers.new_client({
            ok({
                number     = "2015550123",
                campaignId = "CAMP002",
                status     = "pending",
                network    = "C",
                carrier    = 1,
                upstreamCnpId = "BANDW",
                alreadyAssigned = false,
                previousNetworkCleared = false,
                message = "accepted; provisioning on path C",
                job = {
                    campaignId = "CAMP002",
                    state      = "queued",
                    message    = "queued",
                    createdAt  = "2026-10-13T16:00:00Z",
                    updatedAt  = "2026-10-13T16:00:01Z",
                },
            }),
        })
        local r, err = c.numbers:assign_campaign("2015550123", { campaignId = "CAMP002" })
        assert.is_nil(err)
        assert.are.equal("pending", r.status)
        assert.is_false(r.alreadyAssigned)
        assert.is_nil(r.orderId)
        assert.are.equal("accepted; provisioning on path C", r.message)
        assert.are.equal("queued", r.job.state)
        assert.are.equal("CAMP002", r.job.campaignId)
    end)

    it("assign campaign (path B) surfaces status/orderId/warning", function()
        local c = helpers.new_client({
            ok({
                number     = "2015550123",
                campaignId = "ABC1234",
                status     = "enabled",
                network    = "B",
                carrier    = 19,
                upstreamCnpId = "CAMP003",
                alreadyAssigned = false,
                orderId    = "1029384756",
                previousNetwork = "A",
                previousNetworkCleared = true,
                warning = "stale registration on path A; removal requested",
            }),
        })
        local r, err = c.numbers:assign_campaign("2015550123", { campaignId = "ABC1234" })
        assert.is_nil(err)
        assert.are.equal("enabled", r.status)
        assert.are.equal("1029384756", r.orderId)
        assert.are.equal("B", r.network)
        assert.are.equal("A", r.previousNetwork)
        assert.is_true(r.previousNetworkCleared)
        assert.is_nil(r.job)
        assert.are.equal("stale registration on path A; removal requested", r.warning)
    end)

    it("assign / unassign / bulk_unassign campaign", function()
        local c, m = helpers.new_client({
            ok({ campaignId = "ABC1234" }),
            ok({ unassigned = true }),
            ok({ unassignedNumbers = { "2015550123" } }),
        })
        c.numbers:assign_campaign("2015550123", { campaignId = "ABC1234" })
        c.numbers:unassign_campaign("2015550123")
        c.numbers:bulk_unassign_campaign({ "2015550123", "2015555678" })
        assert.are.equal("PUT", m.calls[1].method)

        -- per-number unassign: 200 with body, NOT 204
        assert.are.equal("DELETE", m.calls[2].method)
        local body2 = m.calls[2].body
        assert.is_truthy(not body2 or body2 == "")

        -- bulk unassign sends a JSON body and the response carries data
        assert.are.equal("DELETE", m.calls[3].method)
        assert.matches("/v2.2/numbers/messaging%-campaign$", m.calls[3].url)
        local b = helpers.decode_body(m, 3)
        assert.are.same({ "2015550123", "2015555678" }, b.numbers)
    end)

    it("set_port_out_pin surfaces changed/portOutPin", function()
        local c, m = helpers.new_client({
            ok({ number = "2015550123", portOutPin = "1234", changed = true }),
        })
        local r, err = c.numbers:set_port_out_pin("2015550123", { pin = "1234" })
        assert.is_nil(err)
        assert.is_true(r.changed)
        assert.are.equal("1234", r.portOutPin)
        assert.are.equal("PATCH", m.calls[1].method)
        assert.matches("/port%-out%-pin$", m.calls[1].url)
    end)

    it("set_port_out_pin reports changed=false for an already-locked PIN", function()
        local c = helpers.new_client({
            ok({ number = "2015550123", portOutPin = "9999", changed = false }),
        })
        local r, err = c.numbers:set_port_out_pin("2015550123", { pin = "1234" })
        assert.is_nil(err)
        assert.is_false(r.changed)
        assert.are.equal("9999", r.portOutPin)
    end)

    it("error path", function()
        local c = helpers.new_client({ helpers.err(404, "no such tn") })
        local _, err = c.numbers:get("9999999999")
        assert.are.equal("not_found", err.kind)
    end)
end)
