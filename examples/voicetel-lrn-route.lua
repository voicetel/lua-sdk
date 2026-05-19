--[[
voicetel-lrn-route.lua — LRN-based routing decision.

Looks up the LRN for the dialed number and chooses a carrier gateway based
on the destination state (cheap example heuristic). Real production logic
will be more nuanced — this is the basic shape.

Dialplan:

    <action application="lua"
            data="voicetel-lrn-route.lua ${destination_number} ${caller_id_number}"/>
    <action application="bridge"
            data="sofia/gateway/${voicetel_route}/${destination_number}"/>
]]

local voicetel = require("voicetel")

local args = argv or {}
local destination = args[1]
local ani         = args[2]

if not (destination and ani) then
    freeswitch.consoleLog("ERR", "voicetel-lrn-route: usage: <destination> <ani>\n")
    return
end

local client = voicetel.new({
    api_key = os.getenv("VOICETEL_API_KEY") or "REPLACE_WITH_YOUR_API_KEY",
    timeout = 5,
})

local result, err = client.lookups:lrn(destination, ani)
if err then
    freeswitch.consoleLog("ERR",
        "voicetel-lrn-route: dip failed (" .. err.message .. "); using default route\n")
    if session then session:setVariable("voicetel_route", "default") end
    return
end

local lrn = result and result.lrn or {}
local state = lrn.state or ""
local jurisdiction = lrn.jurisdiction or ""

freeswitch.consoleLog("INFO",
    "voicetel-lrn-route: dst=" .. destination ..
    " lrn=" .. tostring(lrn.lrn) ..
    " state=" .. state ..
    " juris=" .. jurisdiction .. "\n")

-- Pick a route based on the dip. Replace these gateway names with whatever
-- you have configured in your sofia profile.
local route
if jurisdiction == "intra" then
    route = "voicetel-intrastate"
elseif state == "AK" or state == "HI" then
    route = "voicetel-noncontig"
else
    route = "voicetel-interstate"
end

if session then
    session:setVariable("voicetel_route", route)
    session:setVariable("voicetel_lrn", lrn.lrn or "")
end
