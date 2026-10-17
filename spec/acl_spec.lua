local helpers = require("spec.helpers")

describe("acl", function()
    it("list", function()
        local c, m = helpers.new_client({ helpers.ok({ acl = { { cidr = "10.0.0.0/24" } } }) })
        local r = c.acl:list()
        assert.are.equal("10.0.0.0/24", r.acl[1].cidr)
        assert.are.equal("GET", m.calls[1].method)
    end)

    it("add", function()
        local c, m = helpers.new_client({ helpers.ok({ added = { { cidr = "10.0.0.0/24" } } }) })
        c.acl:add({ acl = { { cidr = "10.0.0.0/24" } } })
        assert.are.equal("POST", m.calls[1].method)
    end)

    -- DELETE /v2.2/acl returns 200 with a body, NOT 204. The CIDRs travel in
    -- the required `cidrs` query parameter; there is no request body. Make
    -- sure the SDK surfaces the body as `removed`, not as `true`.
    it("remove sends cidrs as a query param and returns 200 with body (not 204)", function()
        local c, m = helpers.new_client({
            helpers.ok({ removed = { { cidr = "10.0.0.0/24" } } }, 200),
        })
        local r = c.acl:remove({ "10.0.0.0/24" })
        assert.are.equal("DELETE", m.calls[1].method)
        assert.matches("cidrs=10%.0%.0%.0%%2F24", m.calls[1].url)
        local body = m.calls[1].body
        assert.is_truthy(not body or body == "")
        assert.are.equal("10.0.0.0/24", r.removed[1].cidr)
    end)

    it("409 conflict is surfaced with body", function()
        local c = helpers.new_client({
            helpers.err(409, "partial", nil, { failed = { { cidr = "x", reason = "y" } } }),
        })
        local r, err = c.acl:add({ acl = {} })
        assert.is_nil(r)
        assert.are.equal("conflict", err.kind)
        assert.are.equal("partial", err.message)
        assert.are.equal("y", err.body.data.failed[1].reason)
    end)
end)
