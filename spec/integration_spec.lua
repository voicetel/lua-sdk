-- Integration spec — only runs when VOICETEL_USERNAME and VOICETEL_PASSWORD
-- are present in the environment. Hits the live API in read-only mode only.
-- Run with:
--   VOICETEL_USERNAME=... VOICETEL_PASSWORD=... busted spec/integration_spec.lua
local username = os.getenv("VOICETEL_USERNAME")
local password = os.getenv("VOICETEL_PASSWORD")
local base_url = os.getenv("VOICETEL_BASE_URL") -- optional override

if not (username and password) then
    describe("integration", function()
        pending("skipped (set VOICETEL_USERNAME + VOICETEL_PASSWORD to enable)")
    end)
    return
end

local voicetel = require("voicetel")

describe("integration (live API, read-only)", function()
    local client

    setup(function()
        local opts = {}
        if base_url and base_url ~= "" then opts.base_url = base_url end
        client = voicetel.new(opts)
        local _, err = client:login(tonumber(username) or username, password)
        assert.is_nil(err, "login failed: " .. (err and err.message or ""))
    end)

    it("can fetch the account profile", function()
        local me, err = client.account:get()
        assert.is_nil(err)
        assert.is_not_nil(me)
    end)

    it("can list numbers", function()
        local data, err = client.numbers:list()
        assert.is_nil(err)
        assert.is_table(data.numbers)
    end)

    it("can list gateways", function()
        local data, err = client.gateways:list()
        assert.is_nil(err)
        assert.is_table(data.gateways)
    end)
end)
