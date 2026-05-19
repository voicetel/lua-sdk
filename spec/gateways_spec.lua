local helpers = require("spec.helpers")

describe("gateways", function()
    it("list", function()
        local c, m = helpers.new_client({ helpers.ok({ gateways = {} }) })
        c.gateways:list()
        assert.matches("/v2.2/gateways$", m.calls[1].url)
    end)

    it("add", function()
        local c, m = helpers.new_client({ helpers.ok({ id = 17 }) })
        c.gateways:add({ gateway = "1.2.3.4:5060", prefix = "1", limit = 50 })
        assert.are.equal("POST", m.calls[1].method)
        local body = helpers.decode_body(m, 1)
        assert.are.equal("1.2.3.4:5060", body.gateway)
    end)

    it("get/update/remove/numbers", function()
        local c, m = helpers.new_client({
            helpers.ok({ id = 17 }),
            helpers.ok({ id = 17, limit = 100 }),
            { status = 204, body = "" },
            helpers.ok({ numbers = {} }),
        })
        c.gateways:get(17)
        c.gateways:update(17, { limit = 100 })
        local removed = c.gateways:remove(17)
        c.gateways:numbers(17)
        assert.are.equal("GET",    m.calls[1].method)
        assert.are.equal("PUT",    m.calls[2].method)
        assert.are.equal("DELETE", m.calls[3].method)
        assert.are.equal("GET",    m.calls[4].method)
        assert.matches("/gateways/17/numbers$", m.calls[4].url)
        assert.is_true(removed)
    end)

    it("error path", function()
        local c = helpers.new_client({ helpers.err(404, "no gw") })
        local _, err = c.gateways:get(123)
        assert.are.equal("not_found", err.kind)
    end)
end)
