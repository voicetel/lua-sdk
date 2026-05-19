local helpers = require("spec.helpers")

describe("account", function()
    local function setup(responses)
        return helpers.new_client(responses)
    end

    it("get", function()
        local c, m = setup({ helpers.ok({ username = "1000000001", cash = 12.34 }) })
        local r, err = c.account:get()
        assert.is_nil(err)
        assert.are.equal("1000000001", r.username)
        assert.are.equal("GET", m.calls[1].method)
        assert.matches("/v2.2/account$", m.calls[1].url)
    end)

    it("update", function()
        local c, m = setup({ helpers.ok({ updated = { "notify" } }) })
        local r, err = c.account:update({ notify = true })
        assert.is_nil(err)
        assert.are.same({ "notify" }, r.updated)
        assert.are.equal("PUT", m.calls[1].method)
        assert.are.same({ notify = true }, helpers.decode_body(m, 1))
    end)

    it("add", function()
        local c, m = setup({ helpers.ok({ username = "1000000002" }) })
        c.account:add({ username = 1000000002, name = "Sub", email = "a@b.com" })
        assert.are.equal("POST", m.calls[1].method)
    end)

    it("signup", function()
        local c, m = setup({ helpers.ok({ username = "1000000003" }) })
        c.account:signup({ name = "x", email = "x@y.com" })
        assert.matches("/v2.2/accounts$", m.calls[1].url)
    end)

    it("cdr passes start/end in query", function()
        local c, m = setup({ helpers.ok({ cdr = {}, start = 1, ["end"] = 2 }) })
        c.account:cdr(1, 2)
        assert.matches("start=1", m.calls[1].url)
        assert.matches("end=2", m.calls[1].url)
    end)

    it("credits + recurring_charges + payments + registration", function()
        local c, m = setup({
            helpers.ok({ credits = {} }),
            helpers.ok({ charges = {}, total = 0 }),
            helpers.ok({ payments = {} }),
            helpers.ok({ agent = "uac" }),
        })
        c.account:credits()
        c.account:recurring_charges()
        c.account:payments()
        c.account:registration()
        assert.matches("/credits$", m.calls[1].url)
        assert.matches("/recurring%-charges$", m.calls[2].url)
        assert.matches("/payments$", m.calls[3].url)
        assert.matches("/registration$", m.calls[4].url)
    end)

    it("recover (no auth)", function()
        local c, m = setup({ helpers.ok({ message = "sent" }) })
        local r = c.account:recover({ email = "x@y.com" })
        assert.are.equal("sent", r.message)
        assert.is_nil(m.calls[1].headers.Authorization)
    end)

    it("error path on get", function()
        local c = setup({ helpers.err(401, "unauthorized") })
        local r, err = c.account:get()
        assert.is_nil(r)
        assert.are.equal("authentication", err.kind)
    end)
end)
