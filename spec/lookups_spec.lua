local helpers = require("spec.helpers")

describe("lookups", function()
    it("cnam", function()
        local c, m = helpers.new_client({
            helpers.ok({ cnam = "ACME INC", number = "2015551234" }),
        })
        local r = c.lookups:cnam("2015551234")
        assert.are.equal("ACME INC", r.cnam)
        assert.matches("/v2.2/cnam/2015551234$", m.calls[1].url)
    end)

    it("lrn", function()
        local c, m = helpers.new_client({
            helpers.ok({ ani = "2015551234", destination = "2125550000",
                         lrn = { lrn = "2125550000", state = "NY" } }),
        })
        local r = c.lookups:lrn("2125550000", "2015551234")
        assert.are.equal("2125550000", r.lrn.lrn)
        assert.matches("/v2.2/lrn/2125550000/2015551234$", m.calls[1].url)
    end)

    it("error path", function()
        local c = helpers.new_client({ helpers.err(404, "no cnam") })
        local _, err = c.lookups:cnam("9999999999")
        assert.are.equal("not_found", err.kind)
    end)
end)
