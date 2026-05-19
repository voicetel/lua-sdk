-- voicetel.resources.inumbering — operations covering inventory + orders + ports.

local M = {}
M.__index = M

function M.new(transport) return setmetatable({ _t = transport }, M) end

-- search_inventory searches available TNs.
-- GET /v2.2/inventory   query: { npa, nxx, state, ratecenter, contains, endswith, limit }
function M:search_inventory(query)
    return self._t:request("GET", "/v2.2/inventory", query or {}, nil, true)
end

-- coverage returns aggregated availability buckets.
-- GET /v2.2/inventory/coverage   query: { state, ratecenter }
function M:coverage(query)
    return self._t:request("GET", "/v2.2/inventory/coverage", query or {}, nil, true)
end

-- order purchases new TNs.
-- POST /v2.2/orders   body: { numbers = { "2015551234", { number = "...", route = 4 } } }
function M:order(body)
    return self._t:request("POST", "/v2.2/orders", nil, body or {}, true)
end

-- ports lists every port-in record on the account.
-- GET /v2.2/ports
function M:ports()
    return self._t:request("GET", "/v2.2/ports", nil, nil, true)
end

-- port fetches detail for one port-in by id.
-- GET /v2.2/ports/{id}
function M:port(id)
    return self._t:request("GET", "/v2.2/ports/" .. tostring(id), nil, nil, true)
end

-- submit_port submits a port-in order.
-- POST /v2.2/ports
function M:submit_port(body)
    return self._t:request("POST", "/v2.2/ports", nil, body or {}, true)
end

-- port_availability checks whether a TN can be ported in.
-- GET /v2.2/ports/availability/{number}
--
-- Response data (v2.2.10): { number, portable, losing_carrier, reason,
--   local_routing_number, rate_center_tier }
function M:port_availability(number)
    return self._t:request("GET", "/v2.2/ports/availability/" .. tostring(number), nil, nil, true)
end

return M
