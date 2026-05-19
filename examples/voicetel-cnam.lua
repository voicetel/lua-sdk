--[[
voicetel-cnam.lua — FreeSWITCH dialplan helper that performs a CNAM dip on
the calling number and installs the result on the channel before bridging.

Wire it into a dialplan extension like:

    <extension name="cnam-on-inbound">
      <condition field="destination_number" expression="^(\d{10})$">
        <action application="lua" data="voicetel-cnam.lua ${caller_id_number}"/>
        <action application="bridge" data="sofia/gateway/voicetel/$1"/>
      </condition>
    </extension>

The script logs to FreeSWITCH's standard log and never hard-fails the call —
on any API error it simply falls through with the original caller-id intact.
]]

local voicetel = require("voicetel")

local args = argv or {}                          -- argv[1] is the TN
local caller_number = args[1]

if not caller_number or not caller_number:match("^%d+$") then
    freeswitch.consoleLog("WARNING", "voicetel-cnam: missing or non-numeric caller_id\n")
    return
end

-- Credentials should live in /etc/freeswitch/vars.xml or a sibling secrets
-- file — DO NOT commit the API key into the dialplan.
local api_key = os.getenv("VOICETEL_API_KEY") or "REPLACE_WITH_YOUR_API_KEY"

local client = voicetel.new({
    api_key     = api_key,
    timeout     = 5,
    max_retries = 1, -- one quick retry on 429/5xx; a single dip is cheap
})

local result, err = client.lookups:cnam(caller_number)
if err then
    if voicetel.is_rate_limit(err) then
        freeswitch.consoleLog("WARNING",
            "voicetel-cnam: rate-limited; using original caller-id\n")
    elseif voicetel.is_not_found(err) then
        freeswitch.consoleLog("INFO",
            "voicetel-cnam: no CNAM record for " .. caller_number .. "\n")
    else
        freeswitch.consoleLog("ERR",
            "voicetel-cnam: " .. tostring(err.message) .. "\n")
    end
    return
end

if result and result.cnam and result.cnam ~= "" then
    if session then
        session:setVariable("effective_caller_id_name", result.cnam)
    end
    freeswitch.consoleLog("INFO",
        "voicetel-cnam: " .. caller_number .. " -> " .. result.cnam .. "\n")
end
