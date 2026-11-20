local helpers = require("spec.helpers")

describe("inumbering", function()
    it("search_inventory passes query params", function()
        local c, m = helpers.new_client({ helpers.ok({ numbers = {} }) })
        c.inumbering:search_inventory({ tnMask = "201555*", quantity = 5, province = "NJ" })
        assert.matches("tnMask=201555%%2A", m.calls[1].url)
        assert.matches("quantity=5", m.calls[1].url)
        assert.matches("province=NJ", m.calls[1].url)
    end)

    it("coverage sends the required countBy", function()
        local c, m = helpers.new_client({ helpers.ok({ coverage = {} }) })
        c.inumbering:coverage({ countBy = "state", locState = "NJ" })
        assert.matches("/v2.2/inventory/coverage%?", m.calls[1].url)
        assert.matches("countBy=state", m.calls[1].url)
        assert.matches("locState=NJ", m.calls[1].url)
    end)

    it("order", function()
        local c, m = helpers.new_client({ helpers.ok({ orderId = "abc" }) })
        c.inumbering:order({ numbers = { "2015550123" } })
        assert.are.equal("POST", m.calls[1].method)
        assert.matches("/v2.2/orders$", m.calls[1].url)
    end)

    -- v2.2.20: the 201 response adds `routes` — the route each ordered
    -- number was placed on — and a route may be any gateway id on the
    -- account, not just the global 1-9.
    it("order surfaces routes and accepts a gateway-id route", function()
        local c, m = helpers.new_client({
            helpers.ok({
                orderId        = "ord-1026",
                amountCharged  = 3.0,
                numbersOrdered = { "2015550100", "2015550101" },
                routes         = {
                    { number = "2015550100", route = 4 },
                    { number = "2015550101", route = 12 },
                },
                failed = {},
            }, 201),
        })
        local r, err = c.inumbering:order({
            numbers = { "2015550100", { number = "2015550101", route = 12 } },
        })
        assert.is_nil(err)
        assert.are.equal("ord-1026", r.orderId)
        assert.are.equal(2, #r.routes)
        assert.are.equal("2015550100", r.routes[1].number)
        assert.are.equal(4, r.routes[1].route)
        assert.are.equal("2015550101", r.routes[2].number)
        assert.are.equal(12, r.routes[2].route)

        local body = helpers.decode_body(m, 1)
        assert.are.equal("2015550100", body.numbers[1])
        assert.are.equal(12, body.numbers[2].route)
    end)

    it("ports list + detail + submit", function()
        local c, m = helpers.new_client({
            helpers.ok({ ports = {} }),
            helpers.ok({ port = { id = "x" } }),
            helpers.ok({ pid = "XYZ12" }),
        })
        c.inumbering:ports()
        c.inumbering:port("y0d36") -- id is the 5-char pid string
        c.inumbering:submit_port({ did = { "2015550123" } })
        assert.matches("/v2.2/ports$", m.calls[1].url)
        assert.matches("/v2.2/ports/y0d36$", m.calls[2].url)
        assert.are.equal("POST", m.calls[3].method)
    end)

    -- The wire (camelCase) field names pass through unchanged.
    it("port_availability surfaces localRoutingNumber + rateCenterTier", function()
        local c, m = helpers.new_client({
            helpers.ok({
                number              = "2015550123",
                portable            = true,
                losingCarrier       = "BellSouth",
                localRoutingNumber  = "2015550000",
                rateCenterTier      = "TIER_1",
            }),
        })
        local r, err = c.inumbering:port_availability("2015550123")
        assert.is_nil(err)
        assert.is_true(r.portable)
        assert.are.equal("2015550000", r.localRoutingNumber)
        assert.are.equal("TIER_1", r.rateCenterTier)
        assert.matches("/ports/availability/2015550123$", m.calls[1].url)
    end)

    it("error path", function()
        local c = helpers.new_client({ helpers.err(400, "bad query") })
        local _, err = c.inumbering:search_inventory({})
        assert.are.equal("bad_request", err.kind)
    end)
end)
