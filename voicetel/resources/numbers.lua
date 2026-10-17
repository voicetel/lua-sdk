-- voicetel.resources.numbers — every operation on a TN owned by the account.

local url_encode = require("voicetel.transport")._url_encode

local M = {}
M.__index = M

function M.new(transport) return setmetatable({ _t = transport }, M) end

-- csv normalizes a comma-separated string (or an array of strings) into the
-- comma-separated string form the API expects on the wire.
local function csv(v)
    if type(v) == "table" then return table.concat(v, ",") end
    return v
end

-- list returns every TN on the account.
-- GET /v2.2/numbers
function M:list()
    return self._t:request("GET", "/v2.2/numbers", nil, nil, true)
end

-- add attaches a TN to the account.
-- POST /v2.2/numbers   body: { number = "...", route = 4 }
-- `route` is the global route type: 1 USER, 2 T30, 3 VOICE_BRIDGE, 4 DID
-- (default), 5 T38, 6 VOICEML, 8 SDN, 9 MOBILE.
function M:add(body)
    return self._t:request("POST", "/v2.2/numbers", nil, body or {}, true)
end

-- get fetches one TN's routing/feature state.
-- GET /v2.2/numbers/{number}
function M:get(number)
    return self._t:request("GET", "/v2.2/numbers/" .. url_encode(number), nil, nil, true)
end

-- remove detaches a TN. Returns `true` on 204.
-- DELETE /v2.2/numbers/{number}
function M:remove(number)
    return self._t:request("DELETE", "/v2.2/numbers/" .. url_encode(number), nil, nil, true)
end

-- move transfers a TN to another account on the same org.
-- PATCH /v2.2/numbers/{number}   body: { accountId = 1000000002, route = 4 }
-- `route` is the global route type on the destination account: 1 USER,
-- 2 T30, 3 VOICE_BRIDGE, 4 DID (default), 5 T38, 6 VOICEML, 8 SDN, 9 MOBILE.
function M:move(number, body)
    return self._t:request("PATCH", "/v2.2/numbers/" .. url_encode(number), nil, body or {}, true)
end

-- release returns a TN to the network.
-- POST /v2.2/numbers/{number}/release
function M:release(number)
    return self._t:request("POST", "/v2.2/numbers/" .. url_encode(number) .. "/release", nil, nil, true)
end

-- set_route updates a TN's outbound route.
-- PUT /v2.2/numbers/{number}/route   body: { route = 4 }
-- `route` is the global route type: 1 USER, 2 T30, 3 VOICE_BRIDGE, 4 DID
-- (default), 5 T38, 6 VOICEML, 8 SDN, 9 MOBILE.
function M:set_route(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. url_encode(number) .. "/route", nil, body or {}, true)
end

-- set_translation updates a TN's DNIS translation.
-- PUT /v2.2/numbers/{number}/translation
function M:set_translation(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. url_encode(number) .. "/translation", nil, body or {}, true)
end

-- set_cnam toggles inbound CNAM lookup.
-- PUT /v2.2/numbers/{number}/cnam
function M:set_cnam(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. url_encode(number) .. "/cnam", nil, body or {}, true)
end

-- set_lidb updates a TN's outbound caller name (LIDB).
-- (Spec previously had a `Libd` typo; this SDK uses the corrected `Lidb`.)
-- PUT /v2.2/numbers/{number}/lidb
function M:set_lidb(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. url_encode(number) .. "/lidb", nil, body or {}, true)
end

-- get_fax reads fax-to-email routing.
-- GET /v2.2/numbers/{number}/fax
function M:get_fax(number)
    return self._t:request("GET", "/v2.2/numbers/" .. url_encode(number) .. "/fax", nil, nil, true)
end

-- set_fax enables fax-to-email routing.
-- PUT /v2.2/numbers/{number}/fax
function M:set_fax(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. url_encode(number) .. "/fax", nil, body or {}, true)
end

-- remove_fax disables fax-to-email. Returns `true` on 204.
-- DELETE /v2.2/numbers/{number}/fax
function M:remove_fax(number)
    return self._t:request("DELETE", "/v2.2/numbers/" .. url_encode(number) .. "/fax", nil, nil, true)
end

-- set_forward enables call forwarding.
-- PUT /v2.2/numbers/{number}/forward
function M:set_forward(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. url_encode(number) .. "/forward", nil, body or {}, true)
end

-- remove_forward disables call forwarding. Returns `true` on 204.
-- DELETE /v2.2/numbers/{number}/forward
function M:remove_forward(number)
    return self._t:request("DELETE", "/v2.2/numbers/" .. url_encode(number) .. "/forward", nil, nil, true)
end

-- get_sms reads SMS routing.
-- GET /v2.2/numbers/{number}/sms
function M:get_sms(number)
    return self._t:request("GET", "/v2.2/numbers/" .. url_encode(number) .. "/sms", nil, nil, true)
end

-- set_sms configures SMS routing.
-- PUT /v2.2/numbers/{number}/sms
function M:set_sms(number, body)
    return self._t:request("PUT", "/v2.2/numbers/" .. url_encode(number) .. "/sms", nil, body or {}, true)
end

-- remove_sms clears SMS routing. Returns `true` on 204.
-- DELETE /v2.2/numbers/{number}/sms
function M:remove_sms(number)
    return self._t:request("DELETE", "/v2.2/numbers/" .. url_encode(number) .. "/sms", nil, nil, true)
end

-- get_messaging returns the messaging state for one TN.
--   { enabled, carrier, routeIn, resource,
--     network  = "A" | "B" | "C" | nil,
--     campaign = { id, network, status, upstreamCnpId },
--     pending  = { campaignId, state, message, createdAt, updatedAt } }
-- `pending` carries the asynchronous (path C) enablement job while it is in
-- flight: state moves queued -> hosting -> assigning -> routing -> done, or
-- failed (see message). The number keeps its previous routing until done.
-- GET /v2.2/numbers/{number}/messaging
function M:get_messaging(number)
    return self._t:request("GET", "/v2.2/numbers/" .. url_encode(number) .. "/messaging", nil, nil, true)
end

-- patch_messaging updates inbound/outbound routing for one TN.
--   body: { routeIn  = <numbers_sms row id; 0 to detach>,
--           routeOut = <outbound carrier id; 0 = outbound off> }
-- At least one of routeIn/routeOut must be present. To move a number to
-- another campaign or messaging path use assign_campaign instead.
-- PATCH /v2.2/numbers/{number}/messaging
function M:patch_messaging(number, body)
    return self._t:request("PATCH", "/v2.2/numbers/" .. url_encode(number) .. "/messaging", nil, body or {}, true)
end

-- assign_campaign binds a 10DLC campaign to a TN.
--   body: { campaignId = "ABC1234" }
--
-- Response data:
--   status     = "enabled" (bound now, path B) | "already" (the number was
--                already bound to this campaign; records reconciled, no new
--                order) | "pending" (accepted and being provisioned on path
--                C — poll get_messaging's `pending` job until its state is
--                done or failed)
--   alreadyAssigned     = true when already bound (see "already")
--   orderId             = network order id for a path-B assignment; nil for
--                         path C (see job), idempotent no-ops, and
--                         assignments confirmed without a new order
--   message             = human-readable note for a pending enablement
--   warning             = non-fatal condition detected during the assignment
--   job                 = { campaignId, state, message, createdAt, updatedAt }
--                         for a pending (path C) enablement; nil otherwise
--   network             = "B" | "C" (path B is assigned synchronously; path
--                         C is provisioned asynchronously, status "pending")
--   previousNetwork     = "A" | "B" | nil (path before this call)
--   carrier             = outbound carrier id once enabled (19 = path B,
--                         1 = path C)
--   upstreamCnpId       = CAMP003 (path B) | BANDW (path C)
-- PUT /v2.2/numbers/{number}/messaging-campaign   body: { campaignId = "ABC1234" }
function M:assign_campaign(number, body)
    return self._t:request("PUT",
        "/v2.2/numbers/" .. url_encode(number) .. "/messaging-campaign", nil, body or {}, true)
end

-- unassign_campaign removes the campaign binding from a TN.
--   campaign_id (required): TCR campaign id the number is being removed from,
--     sent as the campaignId query parameter. No request body.
-- (DELETE returns 200 with a body — NOT 204.)
-- DELETE /v2.2/numbers/{number}/messaging-campaign   query: { campaignId }
function M:unassign_campaign(number, campaign_id)
    return self._t:request("DELETE",
        "/v2.2/numbers/" .. url_encode(number) .. "/messaging-campaign",
        { campaignId = campaign_id }, nil, true)
end

-- bulk_unassign_campaign removes the campaign binding from many TNs at once.
--   numbers     (required): comma-separated string (or array) of up to 1000
--                 10-digit telephone numbers to remove from the campaign.
--   campaign_id (required): TCR campaign id the numbers are being removed
--                 from. Both travel as query parameters; there is NO body.
-- (DELETE returns 200 with a body — NOT 204.)
-- DELETE /v2.2/numbers/messaging-campaign   query: { numbers, campaignId }
function M:bulk_unassign_campaign(numbers, campaign_id)
    return self._t:request("DELETE", "/v2.2/numbers/messaging-campaign",
        { numbers = csv(numbers), campaignId = campaign_id }, nil, true)
end

-- set_port_out_pin sets the port-out PIN for a TN.
--   body: { pin = "1234" }   (four digits)
-- A PIN is locked for 30 days once set. The response carries `changed`
-- (true if this request set the PIN; false if the number already had one,
-- in which case the existing value is returned unchanged) and `portOutPin`
-- (the value now on file — just set, or the pre-existing locked value).
-- PATCH /v2.2/numbers/{number}/port-out-pin
function M:set_port_out_pin(number, body)
    return self._t:request("PATCH",
        "/v2.2/numbers/" .. url_encode(number) .. "/port-out-pin", nil, body or {}, true)
end

return M
