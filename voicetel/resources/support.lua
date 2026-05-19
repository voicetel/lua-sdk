-- voicetel.resources.support — support ticket lifecycle.
--
-- Important spec quirk: in the wire form, supportConversation.number is a
-- *ticket sequence number* (1015, 2114, ...), NOT a phone number. This SDK
-- passes the JSON through as-is; you'll see `ticket.number = 1015` in the
-- returned table. We document this here so the next reader doesn't think
-- "number" means a TN.

local M = {}
M.__index = M

function M.new(transport) return setmetatable({ _t = transport }, M) end

-- list returns every ticket on the account.
-- GET /v2.2/support/tickets
function M:list()
    return self._t:request("GET", "/v2.2/support/tickets", nil, nil, true)
end

-- create opens a new support ticket.
-- POST /v2.2/support/tickets   body: { subject, message, email? }
function M:create(body)
    return self._t:request("POST", "/v2.2/support/tickets", nil, body or {}, true)
end

-- get fetches one ticket by id.
-- GET /v2.2/support/tickets/{id}
function M:get(id)
    return self._t:request("GET", "/v2.2/support/tickets/" .. tostring(id), nil, nil, true)
end

-- update changes a ticket's status.
-- PUT /v2.2/support/tickets/{id}   body: { status = "closed" }
function M:update(id, body)
    return self._t:request("PUT", "/v2.2/support/tickets/" .. tostring(id), nil, body or {}, true)
end

-- delete removes a ticket. Admin only. Returns `true` on 204.
-- DELETE /v2.2/support/tickets/{id}
function M:delete(id)
    return self._t:request("DELETE", "/v2.2/support/tickets/" .. tostring(id), nil, nil, true)
end

-- messages returns every thread (message) on a ticket.
-- GET /v2.2/support/tickets/{id}/messages
function M:messages(id)
    return self._t:request("GET",
        "/v2.2/support/tickets/" .. tostring(id) .. "/messages", nil, nil, true)
end

-- reply adds a reply to a ticket.
-- POST /v2.2/support/tickets/{id}/replies   body: { message = "..." }
function M:reply(id, body)
    return self._t:request("POST",
        "/v2.2/support/tickets/" .. tostring(id) .. "/replies", nil, body or {}, true)
end

return M
