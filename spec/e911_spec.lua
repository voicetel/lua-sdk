local helpers = require("spec.helpers")

describe("e911", function()
    it("list", function()
        local c, m = helpers.new_client({ helpers.ok({ records = {} }) })
        c.e911:list()
        assert.are.equal("GET", m.calls[1].method)
        assert.matches("/v2.2/e911$", m.calls[1].url)
    end)

    it("create", function()
        local c, m = helpers.new_client({ helpers.ok({ record = { dn = "12015550123" } }) })
        c.e911:create({ dn = "2015550123", callername = "ACME" })
        assert.are.equal("POST", m.calls[1].method)
    end)

    it("validate returns a string addressid", function()
        local c, m = helpers.new_client({
            helpers.ok({ address = { addressid = "123a45b678c9d012e3f45a67b890c123" } }),
        })
        local r = c.e911:validate({ address1 = "1 main", city = "x", state = "NJ", zip = "07030" })
        assert.are.equal("123a45b678c9d012e3f45a67b890c123", r.address.addressid)
        assert.matches("/v2.2/e911/validations$", m.calls[1].url)
    end)

    it("get", function()
        local c, m = helpers.new_client({ helpers.ok({ record = { dn = "12015550123" } }) })
        c.e911:get("2015550123")
        assert.matches("/v2.2/e911/2015550123$", m.calls[1].url)
    end)

    it("provision sends the addressid as a string", function()
        local c, m = helpers.new_client({ helpers.ok({ record = {} }) })
        c.e911:provision("2015550123",
            { callername = "ACME", addressid = "123a45b678c9d012e3f45a67b890c123" })
        assert.are.equal("PUT", m.calls[1].method)
        local body = helpers.decode_body(m, 1)
        assert.are.equal("123a45b678c9d012e3f45a67b890c123", body.addressid)
    end)

    -- v2.2.20 truth fix: addressid is a hex STRING on the wire, in both the
    -- validations response and the provision-by-id request.
    it("addressid round-trips as a string from validate to provision", function()
        local c, m = helpers.new_client({
            helpers.ok({ address = { addressid = "123a45b678c9d012e3f45a67b890c123",
                                     address1 = "1 MAIN ST", city = "RIVERTON",
                                     state = "NJ", zip = "07082" } }),
            helpers.ok({ record = { dn = "12015550123" } }),
        })
        local validated, err = c.e911:validate({ address1 = "1 main", city = "x", state = "NJ", zip = "07030" })
        assert.is_nil(err)
        c.e911:provision("2015550123", { callername = "ACME", addressid = validated.address.addressid })
        local body = helpers.decode_body(m, 2)
        assert.is_string(body.addressid)
        assert.are.equal("123a45b678c9d012e3f45a67b890c123", body.addressid)
    end)

    it("remove returns true on 204", function()
        local c = helpers.new_client({ { status = 204, body = "" } })
        local r, err = c.e911:remove("2015550123")
        assert.is_nil(err)
        assert.is_true(r)
    end)

    it("404 error path", function()
        local c = helpers.new_client({ helpers.err(404, "no such dn") })
        local _, err = c.e911:get("9999999999")
        assert.are.equal("not_found", err.kind)
    end)
end)
