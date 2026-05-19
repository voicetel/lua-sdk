local helpers = require("spec.helpers")

describe("support", function()
    it("list", function()
        local c, m = helpers.new_client({ helpers.ok({ tickets = {} }) })
        c.support:list()
        assert.matches("/v2.2/support/tickets$", m.calls[1].url)
    end)

    it("create / get / update / delete (204)", function()
        local c, m = helpers.new_client({
            helpers.ok({ ticket = { id = 1, status = "active" } }),
            helpers.ok({ ticket = { id = 1, status = "active" } }),
            helpers.ok({ status = "success" }),
            { status = 204, body = "" },
        })
        c.support:create({ subject = "s", message = "m" })
        c.support:get(1)
        c.support:update(1, { status = "closed" })
        local r = c.support:delete(1)
        assert.are.equal("POST",   m.calls[1].method)
        assert.are.equal("GET",    m.calls[2].method)
        assert.are.equal("PUT",    m.calls[3].method)
        assert.are.equal("DELETE", m.calls[4].method)
        assert.is_true(r)
    end)

    -- supportConversation.number is a ticket sequence integer (e.g. 1015),
    -- NOT a TN. The SDK passes the field through verbatim from the wire.
    it("preserves ticket sequence number as `number`", function()
        local c = helpers.new_client({
            helpers.ok({ ticket = { id = 7, number = 1015, status = "active" } }),
        })
        local r = c.support:get(7)
        assert.are.equal(1015, r.ticket.number)
    end)

    it("messages + reply", function()
        local c, m = helpers.new_client({
            helpers.ok({ messages = {} }),
            helpers.ok({ message = "Reply added" }),
        })
        c.support:messages(1)
        c.support:reply(1, { message = "thanks" })
        assert.matches("/messages$", m.calls[1].url)
        assert.matches("/replies$", m.calls[2].url)
        assert.are.equal("POST", m.calls[2].method)
    end)

    it("error path", function()
        local c = helpers.new_client({ helpers.err(404, "no ticket") })
        local _, err = c.support:get(99999)
        assert.are.equal("not_found", err.kind)
    end)
end)
