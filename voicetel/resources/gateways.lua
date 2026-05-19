-- voicetel.resources.gateways — operations under /v2.2/gateways.

local M = {}
M.__index = M

function M.new(transport) return setmetatable({ _t = transport }, M) end

-- list returns every gateway on the account.
-- GET /v2.2/gateways
function M:list()
    return self._t:request("GET", "/v2.2/gateways", nil, nil, true)
end

-- add creates a new outbound termination gateway.
-- POST /v2.2/gateways   body: { gateway = "1.2.3.4:5060", prefix = "1", limit = 23 }
function M:add(body)
    return self._t:request("POST", "/v2.2/gateways", nil, body or {}, true)
end

-- get fetches a single gateway by id.
-- GET /v2.2/gateways/{id}
function M:get(id)
    return self._t:request("GET", "/v2.2/gateways/" .. tostring(id), nil, nil, true)
end

-- update partial-updates a gateway.
-- PUT /v2.2/gateways/{id}
function M:update(id, body)
    return self._t:request("PUT", "/v2.2/gateways/" .. tostring(id), nil, body or {}, true)
end

-- remove deletes a gateway. Returns `true` on 204.
-- DELETE /v2.2/gateways/{id}
function M:remove(id)
    return self._t:request("DELETE", "/v2.2/gateways/" .. tostring(id), nil, nil, true)
end

-- numbers returns every TN routed through gateway `id`.
-- GET /v2.2/gateways/{id}/numbers
function M:numbers(id)
    return self._t:request("GET", "/v2.2/gateways/" .. tostring(id) .. "/numbers", nil, nil, true)
end

return M
