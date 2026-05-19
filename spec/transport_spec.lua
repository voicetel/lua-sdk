-- Tests for the low-level voicetel.transport behaviors (retries, decoding,
-- envelope-stripping, auth requirement, query encoding).
local transport = require("voicetel.transport")
local helpers   = require("spec.helpers")

local function new_transport(responses, extra)
    extra = extra or {}
    local mock = helpers.mock_backend(responses)
    local key
    if extra.api_key_unset then
        key = nil
    else
        key = extra.api_key or "k"
    end
    local t = transport.new({
        base_url     = "https://api.voicetel.com",
        user_agent   = "voicetel-lua-test/0.1",
        api_key      = key,
        max_retries  = extra.max_retries or 0,
        http_backend = mock.backend,
        sleep        = function(_) end,
    })
    return t, mock
end

describe("transport", function()
    describe("URL + headers", function()
        it("appends a sorted query string", function()
            local t, mock = new_transport({ helpers.ok({}) })
            local _, err = t:request("GET", "/v2.2/x", { b = 2, a = 1, c = "hi there" }, nil, true)
            assert.is_nil(err)
            assert.are.equal("https://api.voicetel.com/v2.2/x?a=1&b=2&c=hi%20there", mock.calls[1].url)
        end)

        it("sets Authorization, User-Agent, Accept", function()
            local t, mock = new_transport({ helpers.ok({}) })
            t:request("GET", "/v2.2/x", nil, nil, true)
            local h = mock.calls[1].headers
            assert.are.equal("Bearer k", h.Authorization)
            assert.are.equal("application/json", h.Accept)
            assert.are.equal("voicetel-lua-test/0.1", h["User-Agent"])
            assert.is_nil(h["Content-Type"])
        end)

        it("sets Content-Type when there is a body", function()
            local t, mock = new_transport({ helpers.ok({}) })
            t:request("POST", "/v2.2/x", nil, { a = 1 }, true)
            assert.are.equal("application/json", mock.calls[1].headers["Content-Type"])
            assert.matches('"a":1', mock.calls[1].body)
        end)

        it("omits Authorization when require_auth is false", function()
            local t, mock = new_transport({ helpers.ok({ apikey = "x" }) })
            t:request("POST", "/v2.2/account/api-key", nil, { username = 1 }, false)
            assert.is_nil(mock.calls[1].headers.Authorization)
        end)
    end)

    describe("envelope + decode", function()
        it("strips the {status, data} envelope", function()
            local t = new_transport({ helpers.ok({ hello = "world" }) })
            local v, err = t:request("GET", "/v2.2/x", nil, nil, true)
            assert.is_nil(err)
            assert.are.same({ hello = "world" }, v)
        end)

        it("returns true for 204 No Content", function()
            local t = new_transport({ { status = 204, body = "" } })
            local v, err = t:request("DELETE", "/v2.2/x", nil, nil, true)
            assert.is_nil(err)
            assert.is_true(v)
        end)

        it("decodes a non-enveloped JSON success body", function()
            local t = new_transport({ { status = 200, body = '{"x":1}' } })
            local v = t:request("GET", "/v2.2/x", nil, nil, true)
            assert.are.same({ x = 1 }, v)
        end)
    end)

    describe("errors", function()
        it("returns a structured error for 404", function()
            local t = new_transport({ helpers.err(404, "not found", "NOT_FOUND") })
            local v, err = t:request("GET", "/v2.2/x", nil, nil, true)
            assert.is_nil(v)
            assert.are.equal("not_found", err.kind)
            assert.are.equal(404, err.status_code)
            assert.are.equal("not found", err.message)
            assert.are.equal("NOT_FOUND", err.code)
        end)

        it("handles a non-JSON error body", function()
            local t = new_transport({ { status = 502, body = "<html>oops</html>" } })
            local _, err = t:request("GET", "/v2.2/x", nil, nil, true)
            assert.are.equal("server", err.kind)
            assert.are.equal(502, err.status_code)
        end)

        it("refuses to make a call without an api key when require_auth=true", function()
            local t = new_transport({ }, { api_key_unset = true })
            local _, err = t:request("GET", "/v2.2/x", nil, nil, true)
            assert.is_not_nil(err)
            assert.matches("no api key", err.message)
        end)
    end)

    describe("retries", function()
        it("retries on 429 then succeeds", function()
            local t, mock = new_transport({
                helpers.err(429, "slow"),
                helpers.ok({ ok = true }),
            }, { max_retries = 1 })
            local v, err = t:request("GET", "/v2.2/x", nil, nil, true)
            assert.is_nil(err)
            assert.are.same({ ok = true }, v)
            assert.are.equal(2, #mock.calls)
        end)

        it("retries on 503 then surfaces the final error", function()
            local t, mock = new_transport({
                helpers.err(503, "boom"),
                helpers.err(503, "still boom"),
            }, { max_retries = 1 })
            local _, err = t:request("GET", "/v2.2/x", nil, nil, true)
            assert.is_not_nil(err)
            assert.are.equal(503, err.status_code)
            assert.are.equal(2, #mock.calls)
        end)

        it("honors integer Retry-After header", function()
            local slept = {}
            local t, mock = new_transport({
                { status = 429, headers = { ["Retry-After"] = "3" }, body = '{"message":"slow"}' },
                helpers.ok({ ok = 1 }),
            }, { max_retries = 1 })
            -- replace the sleep used by this transport so we can capture the requested delay
            t.sleep_fn = function(secs) slept[#slept+1] = secs end
            local _, err = t:request("GET", "/v2.2/x", nil, nil, true)
            assert.is_nil(err)
            assert.are.equal(3, slept[1])
            assert.are.equal(2, #mock.calls)
        end)

        it("retries on transport-level failures", function()
            local t, mock = new_transport({
                "dns explosion",
                helpers.ok({ ok = 1 }),
            }, { max_retries = 1 })
            local v, err = t:request("GET", "/v2.2/x", nil, nil, true)
            assert.is_nil(err)
            assert.are.same({ ok = 1 }, v)
            assert.are.equal(2, #mock.calls)
        end)

        it("surfaces a final transport error when retries exhaust", function()
            local t = new_transport({ "boom1", "boom2" }, { max_retries = 1 })
            local _, err = t:request("GET", "/v2.2/x", nil, nil, true)
            assert.are.equal(0, err.status_code)
            assert.matches("transport error", err.message)
        end)
    end)

    describe("misc helpers", function()
        it("backoff caps at 8 seconds", function()
            local d = transport._backoff_delay(20, nil)
            assert.are.equal(8, d)
        end)

        it("url-encodes special characters", function()
            local got = transport._url_encode("a b/c?d&e")
            assert.are.equal("a%20b%2Fc%3Fd%26e", got)
        end)

        it("build_query returns empty string for nil/empty", function()
            assert.are.equal("", transport._build_query(nil))
            assert.are.equal("", transport._build_query({}))
        end)
    end)
end)
