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

    -- DELETE /v2.2/acl returns 200 with a body, NOT 204. Since spec v2.2.21
    -- the handler takes the SAME {acl: [{cidr}]} JSON body as POST /acl; the
    -- old `cidrs` query parameter is not read. Make sure the body carries the
    -- entries and the query string is EMPTY.
    it("remove sends the {acl:[...]} body and no query string", function()
        local c, m = helpers.new_client({
            helpers.ok({ removed = { { cidr = "10.0.0.0/24" } } }, 200),
        })
        local r = c.acl:remove({ acl = { { cidr = "10.0.0.0/24" } } })
        assert.are.equal("DELETE", m.calls[1].method)
        assert.are.equal("https://api.voicetel.com/v2.2/acl", m.calls[1].url)
        local body = helpers.decode_body(m, 1)
        assert.are.same({ acl = { { cidr = "10.0.0.0/24" } } }, body)
        assert.are.equal("application/json", m.calls[1].headers["Content-Type"])
        assert.are.equal("10.0.0.0/24", r.removed[1].cidr)
    end)

    it("remove accepts a plain cidrs array for convenience", function()
        local c, m = helpers.new_client({
            helpers.ok({ removed = { { cidr = "10.0.0.0/24" } } }, 200),
        })
        c.acl:remove({ "10.0.0.0/24" })
        assert.are.same({ acl = { { cidr = "10.0.0.0/24" } } }, helpers.decode_body(m, 1))
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

    it("remove 409 surfaces removed + failed from the data object", function()
        local c, m = helpers.new_client({
            helpers.err(409, "One or more ACL entries could not be removed", nil, {
                removed = { { cidr = "203.0.113.0/24" } },
                failed  = { { cidr = "203.0.113.9/32", reason = "DB delete failed" } },
            }),
        })
        local r, err = c.acl:remove({ acl = { { cidr = "203.0.113.0/24" }, { cidr = "203.0.113.9/32" } } })
        assert.is_nil(r)
        assert.are.equal("conflict", err.kind)
        assert.are.equal("DB delete failed", err.body.data.failed[1].reason)
        assert.are.equal("203.0.113.0/24", err.body.data.removed[1].cidr)
        assert.is_nil(string.find(m.calls[1].url, "?", 1, true))
    end)
end)
