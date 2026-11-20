local helpers = require("spec.helpers")

describe("lookups", function()
    it("cnam", function()
        local c, m = helpers.new_client({
            helpers.ok({ cnam = "ACME INC", number = "2015550123" }),
        })
        local r = c.lookups:cnam("2015550123")
        assert.are.equal("ACME INC", r.cnam)
        assert.matches("/v2.2/cnam/2015550123$", m.calls[1].url)
    end)

    it("carrier surfaces the upstream snake_case field names", function()
        local c, m = helpers.new_client({
            helpers.ok({
                number  = "2015550123",
                carrier = {
                    name                 = "EXAMPLE CARRIER",
                    type                 = "voip",
                    mobile_country_code  = nil,
                    mobile_network_code  = nil,
                    error_code           = nil,
                },
            }),
        })
        local r, err = c.lookups:carrier("2015550123")
        assert.is_nil(err)
        assert.are.equal("2015550123", r.number)
        assert.are.equal("EXAMPLE CARRIER", r.carrier.name)
        assert.are.equal("voip", r.carrier.type)
        assert.is_nil(r.carrier.mobile_country_code)
        assert.is_nil(r.carrier.mobile_network_code)
        assert.is_nil(r.carrier.error_code)
        assert.matches("/v2.2/carrier/2015550123$", m.calls[1].url)
        assert.are.equal("GET", m.calls[1].method)
    end)

    it("carrier fills mobile codes and error_code", function()
        local c = helpers.new_client({
            helpers.ok({
                number  = "2125550123",
                carrier = {
                    name                 = "EXAMPLE MOBILE",
                    type                 = "mobile",
                    mobile_country_code  = "310",
                    mobile_network_code  = "456",
                    error_code           = 0,
                },
            }),
        })
        local r, err = c.lookups:carrier("2125550123")
        assert.is_nil(err)
        assert.are.equal("mobile", r.carrier.type)
        assert.are.equal("310", r.carrier.mobile_country_code)
        assert.are.equal("456", r.carrier.mobile_network_code)
        assert.are.equal(0, r.carrier.error_code)
    end)

    it("lrn", function()
        local c, m = helpers.new_client({
            helpers.ok({ ani = "2015550123", destination = "2125550000",
                         lrn = { lrn = "2125550000", state = "NY" } }),
        })
        local r = c.lookups:lrn("2125550000", "2015550123")
        assert.are.equal("2125550000", r.lrn.lrn)
        assert.matches("/v2.2/lrn/2125550000/2015550123$", m.calls[1].url)
    end)

    it("error path", function()
        local c = helpers.new_client({ helpers.err(404, "no cnam") })
        local _, err = c.lookups:cnam("9999999999")
        assert.are.equal("not_found", err.kind)
    end)
end)
