--[[
voicetel-sms-send.lua — Send an SMS from the dialplan.

Useful for sending the inbound caller a follow-up text when the called party
doesn't answer. Wire it into the dialplan:

    <action application="lua"
            data="voicetel-sms-send.lua 2015551234 ${caller_id_number} 'We missed your call. Reply to schedule a callback.'"/>
]]

local voicetel = require("voicetel")

local args = argv or {}
local from_tn = args[1]
local to_tn   = args[2]
local text    = args[3] or "Test message"

if not (from_tn and to_tn) then
    freeswitch.consoleLog("ERR", "voicetel-sms-send: usage: <from> <to> [text]\n")
    return
end

local client = voicetel.new({
    api_key = os.getenv("VOICETEL_API_KEY") or "REPLACE_WITH_YOUR_API_KEY",
    timeout = 10,
})

-- The SDK accepts both `from_number`/`to_number` (snake-case) and the wire
-- spellings `fromNumber`/`toNumber`. Use whichever style you prefer.
local result, err = client.messaging:send({
    from_number = from_tn,
    to_number   = to_tn,
    text        = text,
})

if err then
    freeswitch.consoleLog("ERR",
        "voicetel-sms-send: failed (" .. err.message .. ")\n")
    return
end

freeswitch.consoleLog("INFO",
    "voicetel-sms-send: queued id=" .. tostring(result.id) ..
    " parts=" .. tostring(result.parts) .. "\n")
