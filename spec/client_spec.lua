-- Tests for top-level voicetel module + login flow.
local voicetel = require("voicetel")
local helpers  = require("spec.helpers")

describe("voicetel module", function()
    it("exposes version + constants", function()
        assert.are.equal("0.1.0",     voicetel.SDK_VERSION)
        assert.are.equal("v2.2.10",   voicetel.API_VERSION)
        assert.are.equal("https://api.voicetel.com", voicetel.DEFAULT_BASE_URL)
        assert.matches("voicetel%-lua", voicetel.DEFAULT_USER_AGENT)
        assert.are.equal(1, voicetel.AUTH_TYPE_IP_AUTH)
    end)

    it("builds a client with all 10 resource fields", function()
        local c = voicetel.new({ api_key = "k" })
        for _, name in ipairs({
            "account", "acl", "authentication", "e911", "gateways",
            "inumbering", "lookups", "messaging", "numbers", "support",
        }) do
            assert.is_table(c[name], name .. " is missing")
        end
        assert.are.equal("https://api.voicetel.com", c:base_url())
        assert.are.equal("k", c:api_key())
    end)

    it("set_api_key updates the bearer", function()
        local c = voicetel.new({})
        assert.is_nil(c:api_key())
        c:set_api_key("new-key")
        assert.are.equal("new-key", c:api_key())
    end)

    describe("login", function()
        it("exchanges credentials and installs the key", function()
            local c, mock = helpers.new_client({
                helpers.ok({ apikey = "32hex-token" }),
            }, { api_key = nil })
            local key, err = c:login(1000000001, "hunter2")
            assert.is_nil(err)
            assert.are.equal("32hex-token", key)
            assert.are.equal("32hex-token", c:api_key())
            assert.are.equal("POST", mock.calls[1].method)
            assert.matches("/v2.2/account/api%-key$", mock.calls[1].url)
            assert.is_nil(mock.calls[1].headers.Authorization)
            local body = helpers.decode_body(mock, 1)
            assert.are.equal(1000000001, body.username)
            assert.are.equal("hunter2", body.password)
        end)

        it("returns an error when the response lacks apikey", function()
            local c = helpers.new_client({
                helpers.ok({}),
            }, { api_key = nil })
            local key, err = c:login(1, "x")
            assert.is_nil(key)
            assert.is_not_nil(err)
            assert.matches("did not contain", err.message)
        end)

        it("propagates HTTP errors from the api-key endpoint", function()
            local c = helpers.new_client({
                helpers.err(401, "bad credentials"),
            }, { api_key = nil })
            local key, err = c:login(1, "x")
            assert.is_nil(key)
            assert.are.equal("authentication", err.kind)
        end)
    end)

    describe("error predicates", function()
        it("re-exports the predicate helpers", function()
            local rl = voicetel.errors.new(429, nil, "x", nil)
            assert.is_true(voicetel.is_rate_limit(rl))
            local nf = voicetel.errors.new(404, nil, "x", nil)
            assert.is_true(voicetel.is_not_found(nf))
        end)
    end)
end)
