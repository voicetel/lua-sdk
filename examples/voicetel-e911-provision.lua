--[[
voicetel-e911-provision.lua — One-shot e911 provisioning.

Standalone script (not a dialplan callback). Runs from the shell:

    lua voicetel-e911-provision.lua 2015551234 "ACME INC" "1 Main St" "" "Hoboken" "NJ" "07030"

or from FreeSWITCH's mod_lua console:

    luarun voicetel-e911-provision.lua 2015551234 ...

Demonstrates the two-step validate-then-provision flow. e911:create() does
both in one call, but doing them separately lets you surface the validated
address back to a user for confirmation.
]]

local voicetel = require("voicetel")

local arg = arg or argv or {}
local dn         = arg[1]
local callername = arg[2]
local address1   = arg[3]
local address2   = arg[4]
local city       = arg[5]
local state      = arg[6]
local zip        = arg[7]

if not (dn and callername and address1 and city and state and zip) then
    io.stderr:write("usage: <dn> <callername> <addr1> <addr2-or-empty> <city> <ST> <zip>\n")
    os.exit(2)
end

local client = voicetel.new({
    api_key = os.getenv("VOICETEL_API_KEY")
                or error("VOICETEL_API_KEY env var is required"),
})

-- Step 1: validate the address.
local validated, err = client.e911:validate({
    address1 = address1,
    address2 = (address2 ~= "" and address2) or nil,
    city     = city,
    state    = state,
    zip      = zip,
})
if err then
    io.stderr:write("address validation failed: " .. err.message .. "\n")
    os.exit(1)
end

local addressid = validated.address.addressid
print(string.format("Validated address #%d: %s, %s, %s %s",
    addressid, address1, city, state, zip))

-- Step 2: provision the record.
local record, perr = client.e911:provision(dn, {
    callername = callername,
    addressid  = addressid,
})
if perr then
    io.stderr:write("provisioning failed: " .. perr.message .. "\n")
    os.exit(1)
end

print(string.format("Provisioned e911 for %s (callername=%s)",
    record.record.dn, record.record.callername))
