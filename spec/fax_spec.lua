local helpers = require("spec.helpers")

-- Minimal PDF-ish payload with a magic byte prefix and an embedded 0x00 so a
-- lossy (text-mode) transport would corrupt it.
local PDF_BYTES = "%PDF-1.7\n%\x00\x01\x02trailer<</Root 1 0 R>>"

local function uuid_pattern_ok(s)
    return type(s) == "string"
        and s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

describe("fax", function()
    it("numbers lists fax-capable numbers", function()
        local c, m = helpers.new_client({
            helpers.ok({ numbers = { { number = "2015550123", destinationId = 7, email = "fax@example.com" } } }),
        })
        local r = c.fax:numbers()
        assert.are.equal("GET", m.calls[1].method)
        assert.are.equal("https://api.voicetel.com/v2.2/numbers/fax", m.calls[1].url)
        assert.are.equal("2015550123", r.numbers[1].number)
        assert.are.equal(7, r.numbers[1].destinationId)
    end)

    it("send posts multipart with a UUID Idempotency-Key", function()
        local c, m = helpers.new_client({
            helpers.ok({
                id = "9f8c2b41a", fromNumber = "2015550123", toNumber = "2125550123",
                status = "queued",
                documents = { { name = "contract.pdf", size = 123456, contentType = "application/pdf" } },
            }, 201),
        })
        local r = c.fax:send({
            from_number = "2015550123",
            to_number   = "2125550123",
            documents   = { { name = "contract.pdf", content_type = "application/pdf", data = PDF_BYTES } },
        })

        assert.are.equal("queued", r.status)
        assert.are.equal("contract.pdf", r.documents[1].name)

        local call = m.calls[1]
        assert.are.equal("POST", call.method)
        assert.are.equal("https://api.voicetel.com/v2.2/faxes", call.url)
        assert.truthy(uuid_pattern_ok(call.headers["Idempotency-Key"]))

        local ct = call.headers["Content-Type"]
        assert.truthy(ct and ct:match("^multipart/form%-data; boundary="))
        local boundary = ct:match("boundary=([^%s]+)")

        local body = call.body
        -- text fields use the exact wire names
        assert.truthy(body:find('name="fromNumber"\r\n\r\n2015550123\r\n', 1, true))
        assert.truthy(body:find('name="toNumber"\r\n\r\n2125550123\r\n', 1, true))
        -- file part carries the part name, filename, content type and bytes
        assert.truthy(body:find('name="documents"; filename="contract.pdf"', 1, true))
        assert.truthy(body:find("Content-Type: application/pdf\r\n\r\n", 1, true))
        assert.truthy(body:find(PDF_BYTES, 1, true))
        -- the boundary delimits the form
        assert.truthy(body:find("--" .. boundary .. "--\r\n", 1, true))
    end)

    it("send accepts a caller-supplied idempotency key and camelCase fields", function()
        local c, m = helpers.new_client({ helpers.ok({ id = "x", status = "queued" }, 201) })
        c.fax:send({
            fromNumber      = "2015550123",
            toNumber        = "2125550123",
            idempotency_key = "123e4567-e89b-12d3-a456-426614174000",
            documents       = { { name = "a.doc", content_type = "application/msword", data = "\xD0\xCF\x11\xE0" } },
        })
        assert.are.equal(
            "123e4567-e89b-12d3-a456-426614174000",
            m.calls[1].headers["Idempotency-Key"])
        assert.truthy(m.calls[1].body:find('filename="a.doc"', 1, true))
    end)

    it("send rejects a request with no documents before hitting the wire", function()
        local c, m = helpers.new_client({})
        local r, err = c.fax:send({ from_number = "2015550123", to_number = "2125550123" })
        assert.is_nil(r)
        assert.truthy(err.message:find("document"))
        assert.are.equal(0, #m.calls)
    end)

    it("send error envelopes may carry serverTime and still parse", function()
        local c = helpers.new_client({
            { status = 402, body = {
                status = "error",
                error = { code = 402, message = "Your account needs a positive balance to send faxes." },
                serverTime = 1795100000,
            } },
        })
        local r, err = c.fax:send({
            from_number = "2015550123", to_number = "2125550123",
            documents = { { name = "x.pdf", data = PDF_BYTES } },
        })
        assert.is_nil(r)
        assert.are.equal("payment_required", err.kind)
        assert.are.equal(402, err.status_code)
        assert.are.equal("Your account needs a positive balance to send faxes.", err.message)
        assert.are.equal(1795100000, err.body.serverTime)
    end)

    it("send maps 402 and 413 to dedicated kinds", function()
        local c = helpers.new_client({
            helpers.err(402, "Your account needs a positive balance to send faxes."),
            helpers.err(413, "The documents must total 8 MiB or smaller"),
        })
        local _, e1 = c.fax:send({
            from_number = "2015550123", to_number = "2125550123",
            documents = { { name = "x.pdf", data = PDF_BYTES } },
        })
        assert.are.equal("payment_required", e1.kind)
        assert.are.equal(402, e1.status_code)
        local _, e2 = c.fax:send({
            from_number = "2015550123", to_number = "2125550123",
            documents = { { name = "big.pdf", data = PDF_BYTES } },
        })
        assert.are.equal("request_too_large", e2.kind)
        assert.are.equal(413, e2.status_code)
    end)

    it("history sends the exact spec query names", function()
        local c, m = helpers.new_client({
            helpers.ok({ number = "2015550123", fromTs = 1795100000, toTs = 1795013600,
                         faxes = { { id = "9f8c2b41a", status = "sent" } }, nextCursor = nil }),
        })
        local r = c.fax:history({
            number = "2015550123", from = 1795100000, to = 1795013600,
            limit = 25, cursor = "cur=sor", status = "sent",
        })
        assert.are.equal("https://api.voicetel.com/v2.2/faxes"
            .. "?cursor=cur%3Dsor&from=1795100000&limit=25&number=2015550123&status=sent&to=1795013600",
            m.calls[1].url)
        assert.are.equal("sent", r.faxes[1].status)
        assert.is_nil(r.nextCursor)
    end)

    it("get fetches one job by id", function()
        local c, m = helpers.new_client({
            helpers.ok({ id = "9f8c2b41a", status = "sending", attempts = 1, failureReason = "null" }),
        })
        local r = c.fax:get("9f8c2b41a")
        assert.are.equal("GET", m.calls[1].method)
        assert.are.equal("https://api.voicetel.com/v2.2/faxes/9f8c2b41a", m.calls[1].url)
        assert.are.equal("sending", r.status)
    end)

    it("get url-encodes the id", function()
        local c, m = helpers.new_client({ helpers.ok({ id = "a b" }) })
        c.fax:get("a b")
        assert.are.equal("https://api.voicetel.com/v2.2/faxes/a%20b", m.calls[1].url)
    end)

    it("document returns the raw PDF bytes", function()
        local c, m = helpers.new_client({
            { status = 200, body = PDF_BYTES,
              headers = { ["Content-Type"] = "application/pdf",
                          ["Content-Disposition"] = 'attachment; filename="contract.pdf"' } },
        })
        local r = c.fax:document("9f8c2b41a")
        assert.are.equal("GET", m.calls[1].method)
        assert.are.equal("https://api.voicetel.com/v2.2/faxes/9f8c2b41a/document", m.calls[1].url)
        -- byte-for-byte equality, NULs included
        assert.are.equal(#PDF_BYTES, #r)
        assert.are.equal(PDF_BYTES, r)
    end)

    it("document 404 maps to not_found", function()
        local c = helpers.new_client({
            { status = 404, body = {
                status = "error",
                error = { code = 404, message = "Not found" },
                serverTime = 1795100000,
            } },
        })
        local r, err = c.fax:document("nope")
        assert.is_nil(r)
        assert.are.equal("not_found", err.kind)
        assert.are.equal("Not found", err.message)
    end)
end)
