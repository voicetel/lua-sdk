local helpers = require("spec.helpers")

describe("inumbering", function()
    it("search_inventory passes query params", function()
        local c, m = helpers.new_client({ helpers.ok({ numbers = {} }) })
        c.inumbering:search_inventory({ npa = 201, state = "NJ", limit = 5 })
        assert.matches("npa=201", m.calls[1].url)
        assert.matches("state=NJ", m.calls[1].url)
        assert.matches("limit=5", m.calls[1].url)
    end)

    it("coverage", function()
        local c, m = helpers.new_client({ helpers.ok({ coverage = {} }) })
        c.inumbering:coverage({ state = "NJ" })
        assert.matches("/v2.2/inventory/coverage%?", m.calls[1].url)
    end)

    it("order", function()
        local c, m = helpers.new_client({ helpers.ok({ orderId = "abc" }) })
        c.inumbering:order({ numbers = { "2015551234" } })
        assert.are.equal("POST", m.calls[1].method)
        assert.matches("/v2.2/orders$", m.calls[1].url)
    end)

    it("ports list + detail + submit", function()
        local c, m = helpers.new_client({
            helpers.ok({ ports = {} }),
            helpers.ok({ port = { id = "x" } }),
            helpers.ok({ pid = "XYZ12" }),
        })
        c.inumbering:ports()
        c.inumbering:port(42)
        c.inumbering:submit_port({ did = { "2015551234" } })
        assert.matches("/v2.2/ports$", m.calls[1].url)
        assert.matches("/v2.2/ports/42$", m.calls[2].url)
        assert.are.equal("POST", m.calls[3].method)
    end)

    -- v2.2.10 added local_routing_number + rate_center_tier to the response.
    it("port_availability surfaces v2.2.10 fields", function()
        local c, m = helpers.new_client({
            helpers.ok({
                number              = "2015551234",
                portable            = true,
                losing_carrier      = "BellSouth",
                local_routing_number = "2015550000",
                rate_center_tier    = "TIER_1",
                reason              = nil,
            }),
        })
        local r, err = c.inumbering:port_availability("2015551234")
        assert.is_nil(err)
        assert.is_true(r.portable)
        assert.are.equal("2015550000", r.local_routing_number)
        assert.are.equal("TIER_1", r.rate_center_tier)
        assert.matches("/ports/availability/2015551234$", m.calls[1].url)
    end)

    it("error path", function()
        local c = helpers.new_client({ helpers.err(400, "bad query") })
        local _, err = c.inumbering:search_inventory({})
        assert.are.equal("bad_request", err.kind)
    end)
end)
