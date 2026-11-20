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

    -- v2.2.20: directory listing (411) subresource. PUT/DELETE return HTTP
    -- 202 with a body — accepted at once, applied in the background.
    it("directory listing: get / set (202) / remove (202)", function()
        local c, m = helpers.new_client({
            ok({
                number   = "2015550123",
                status   = "listed",
                eligible = true,
                listing  = {
                    type = "B", name = "Acme Corp",
                    streetNumber = "100", streetName = "Broadway", streetType = "St",
                    streetSuffix = "", location = "Suite 900",
                    city = "New York", state = "NY", zip = "10005",
                    complex = false,
                },
                pending = nil,
            }),
            ok({ number = "2015550123", status = "pending", orderId = "1026472",
                 listing = { type = "B", name = "Acme Corp", city = "New York",
                             state = "NY", zip = "10005" } }, 202),
            ok({ number = "2015550123", status = "removing", orderId = "1026473" }, 202),
        })
        local r = c.numbers:get_directory_listing("2015550123")
        assert.are.equal("listed", r.status)
        assert.is_true(r.eligible)
        assert.are.equal("B", r.listing.type)
        assert.are.equal("Acme Corp", r.listing.name)
        assert.are.equal("10005", r.listing.zip)
        assert.is_false(r.listing.complex)

        local put, perr = c.numbers:set_directory_listing("2015550123", {
            type = "business", name = "Acme Corp",
            streetNumber = "100", streetName = "Broadway",
            city = "New York", state = "NY", zip = "10005",
        })
        assert.is_nil(perr)
        assert.are.equal("pending", put.status)
        assert.are.equal("1026472", put.orderId)

        local del, derr = c.numbers:remove_directory_listing("2015550123")
        assert.is_nil(derr)
        assert.are.equal("removing", del.status)
        assert.are.equal("1026473", del.orderId)

        assert.matches("/v2.2/numbers/2015550123/directory%-listing$", m.calls[1].url)
        assert.are.equal("GET",    m.calls[1].method)
        assert.are.equal("PUT",    m.calls[2].method)
        assert.are.equal("DELETE", m.calls[3].method)
        local body = helpers.decode_body(m, 2)
        assert.are.equal("business", body.type)
        assert.are.equal("Acme Corp", body.name)
        assert.are.equal("NY", body.state)
        assert.are.equal("10005", body.zip)
    end)

    it("directory listing: delete of a pending add cancels it (202, no orderId)", function()
        local c = helpers.new_client({
            ok({ number = "2015550123", status = "not_listed" }, 202),
        })
        local r, err = c.numbers:remove_directory_listing("2015550123")
        assert.is_nil(err)
        assert.are.equal("not_listed", r.status)
        assert.is_nil(r.orderId)
    end)

    it("directory listing: error paths", function()
        local c = helpers.new_client({
            helpers.err(402, "balance too low"),
            helpers.err(409, "number already has a pending change"),
        })
        local _, e1 = c.numbers:set_directory_listing("2015550123",
            { type = "business", name = "Acme Corp", city = "New York", state = "NY", zip = "10005" })
        assert.are.equal("payment_required", e1.kind) -- 402 = insufficient balance
        assert.are.equal(402, e1.status_code)
        local _, e2 = c.numbers:remove_directory_listing("2015550123")
        assert.are.equal("conflict", e2.kind)
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
        c.numbers:unassign_campaign("2015550123", "ABC1234")
        c.numbers:bulk_unassign_campaign({ "2015550123", "2015555678" }, "ABC1234")
        assert.are.equal("PUT", m.calls[1].method)

        -- per-number unassign: 200 with body, NOT 204; campaignId is a
        -- required query param and there is no request body
        assert.are.equal("DELETE", m.calls[2].method)
        assert.matches("campaignId=ABC1234", m.calls[2].url)
        local body2 = m.calls[2].body
        assert.is_truthy(not body2 or body2 == "")

        -- bulk unassign: numbers + campaignId as required query params, no body
        assert.are.equal("DELETE", m.calls[3].method)
        assert.matches("/v2.2/numbers/messaging%-campaign%?", m.calls[3].url)
        assert.matches("numbers=2015550123%%2C2015555678", m.calls[3].url)
        assert.matches("campaignId=ABC1234", m.calls[3].url)
        local body3 = m.calls[3].body
        assert.is_truthy(not body3 or body3 == "")
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
