-- voicetel.resources.numbers — every operation on a TN owned by the account.

local M = {}
M.__index = M

function M.new(transport) return setmetatable({ _t = transport }, M) end

local function path(...)
    return table.concat({ ... })
end

-- list returns every TN on the account.
-- GET /v2.2/numbers
function M:list()
    return self._t:request("GET", "/v2.2/numbers", nil, nil, true)
end

-- add attaches a TN to the account.
-- POST /v2.2/numbers   body: { number = "...", route = 4 }
function M:add(body)
    return self._t:request("POST", "/v2.2/numbers", nil, body or {}, true)
end

-- get fetches one TN's routing/feature state.
-- GET /v2.2/numbers/{number}
function M:get(number)
    return self._t:request("GET", "/v2.2/numbers/" .. tostring(number), nil, nil, true)
end

-- remove detaches a TN. Returns `true` on 204.
-- DELETE /v2.2/numbers/{number}
function M:remove(number)
    return self._t:request("DELETE", "/v2.2/numbers/" .. tostring(number), nil, nil, true)
end

-- move transfers a TN to another account on the same org.
-- PATCH /v2.2/numbers/{number}   body: { accountId = 1000000002, route = 4 }
function M:move(number, body)
    return self._t:request("PATCH", "/v2.2/numbers/" .. tostring(number), nil, body or {}, true)
end

-- release returns a TN to the network.
-- POST /v2.2/numbers/{number}/release
function M:release(number)
    return self._t:request("POST", "/v2.2/numbers/" .. tostring(number) .. "/release", nil, nil, true)
end

-- set_route updates a TN's outbound route.
-- PUT /v2.2/numbers/{number}/route
function M:set_route(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. tostring(number) .. "/route", nil, body or {}, true)
end

-- set_translation updates a TN's DNIS translation.
-- PUT /v2.2/numbers/{number}/translation
function M:set_translation(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. tostring(number) .. "/translation", nil, body or {}, true)
end

-- set_cnam toggles inbound CNAM lookup.
-- PUT /v2.2/numbers/{number}/cnam
function M:set_cnam(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. tostring(number) .. "/cnam", nil, body or {}, true)
end

-- set_lidb updates a TN's outbound caller name (LIDB).
-- (Spec previously had a `Libd` typo; this SDK uses the corrected `Lidb`.)
-- PUT /v2.2/numbers/{number}/lidb
function M:set_lidb(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. tostring(number) .. "/lidb", nil, body or {}, true)
end

-- get_fax reads fax-to-email routing.
-- GET /v2.2/numbers/{number}/fax
function M:get_fax(number)
    return self._t:request("GET", "/v2.2/numbers/" .. tostring(number) .. "/fax", nil, nil, true)
end

-- set_fax enables fax-to-email routing.
-- PUT /v2.2/numbers/{number}/fax
function M:set_fax(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. tostring(number) .. "/fax", nil, body or {}, true)
end

-- remove_fax disables fax-to-email. Returns `true` on 204.
-- DELETE /v2.2/numbers/{number}/fax
function M:remove_fax(number)
    return self._t:request("DELETE", "/v2.2/numbers/" .. tostring(number) .. "/fax", nil, nil, true)
end

-- set_forward enables call forwarding.
-- PUT /v2.2/numbers/{number}/forward
function M:set_forward(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. tostring(number) .. "/forward", nil, body or {}, true)
end

-- remove_forward disables call forwarding. Returns `true` on 204.
-- DELETE /v2.2/numbers/{number}/forward
function M:remove_forward(number)
    return self._t:request("DELETE", "/v2.2/numbers/" .. tostring(number) .. "/forward", nil, nil, true)
end

-- get_sms reads SMS routing.
-- GET /v2.2/numbers/{number}/sms
function M:get_sms(number)
    return self._t:request("GET", "/v2.2/numbers/" .. tostring(number) .. "/sms", nil, nil, true)
end

-- set_sms configures SMS routing.
-- PUT /v2.2/numbers/{number}/sms
function M:set_sms(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. tostring(number) .. "/sms", nil, body or {}, true)
end

-- remove_sms clears SMS routing. Returns `true` on 204.
-- DELETE /v2.2/numbers/{number}/sms
function M:remove_sms(number)
    return self._t:request("DELETE", "/v2.2/numbers/" .. tostring(number) .. "/sms", nil, nil, true)
end

-- get_messaging returns the messaging state for one TN.
-- GET /v2.2/numbers/{number}/messaging
function M:get_messaging(number)
    return self._t:request("GET", "/v2.2/numbers/" .. tostring(number) .. "/messaging", nil, nil, true)
end

-- patch_messaging updates inbound/outbound routing for one TN.
-- PATCH /v2.2/numbers/{number}/messaging
function M:patch_messaging(number, body)
    return self._t:request("PATCH", "/v2.2/numbers/" .. tostring(number) .. "/messaging", nil, body or {}, true)
end

-- assign_campaign binds a 10DLC campaign to a TN.
-- PUT /v2.2/numbers/{number}/messaging-campaign   body: { campaignId = "ABC1234" }
function M:assign_campaign(number, body)
    return self._t:request("PUT",
        "/v2.2/numbers/" .. tostring(number) .. "/messaging-campaign", nil, body or {}, true)
end

-- unassign_campaign removes the campaign binding from a TN.
-- (DELETE returns 200 with a body — NOT 204.)
-- DELETE /v2.2/numbers/{number}/messaging-campaign
function M:unassign_campaign(number)
    return self._t:request("DELETE",
        "/v2.2/numbers/" .. tostring(number) .. "/messaging-campaign", nil, nil, true)
end

-- bulk_unassign_campaign removes the campaign binding from many TNs at once.
-- (DELETE returns 200 with a body — NOT 204.)
-- DELETE /v2.2/numbers/messaging-campaign   body: { numbers = { "...", ... } }
function M:bulk_unassign_campaign(numbers)
    local body = { numbers = numbers or {} }
    return self._t:request("DELETE", "/v2.2/numbers/messaging-campaign", nil, body, true)
end

-- set_port_out_pin sets the port-out PIN for a TN.
-- PATCH /v2.2/numbers/{number}/port-out-pin
function M:set_port_out_pin(number, body)
    return self._t:request("PATCH",
        "/v2.2/numbers/" .. tostring(number) .. "/port-out-pin", nil, body or {}, true)
end

return M
