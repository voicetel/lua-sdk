-- voicetel.resources.inumbering — operations covering inventory + orders + ports.

local url_encode = require("voicetel.transport")._url_encode

local M = {}
M.__index = M

function M.new(transport) return setmetatable({ _t = transport }, M) end

-- search_inventory searches available TNs.
-- GET /v2.2/inventory   query: { tnMask (required string; prefix or wildcard
--   pattern, e.g. "201", "201555", "201555*"), quantity (optional, 1-1000,
--   default 10), province (2-letter US state or Canadian province code),
--   rateCenter (rate-center name), lata }
function M:search_inventory(query)
    return self._t:request("GET", "/v2.2/inventory", query or {}, nil, true)
end

-- coverage returns aggregated availability buckets.
-- GET /v2.2/inventory/coverage   query: { countBy (required; one of "state",
--   "city", "rateCenter", "npanxx", "block"), locState, city, rcAbbre, npa,
--   lata }
function M:coverage(query)
    return self._t:request("GET", "/v2.2/inventory/coverage", query or {}, nil, true)
end

-- order purchases new TNs.
--   body: { numbers = { "2015550123", { number = "...", route = 4 } } }
-- Response data: { orderId, amountCharged (amount deducted from the account
--   balance), numbersOrdered, failed }
-- POST /v2.2/orders
function M:order(body)
    return self._t:request("POST", "/v2.2/orders", nil, body or {}, true)
end

-- ports lists every port-in record on the account.
-- GET /v2.2/ports
function M:ports()
    return self._t:request("GET", "/v2.2/ports", nil, nil, true)
end

-- port fetches detail for one port-in by id. `id` is the short 5-character
-- pid string from the port record (e.g. "y0d36"), not the long stable id.
-- GET /v2.2/ports/{id}
function M:port(id)
    return self._t:request("GET", "/v2.2/ports/" .. url_encode(id), nil, nil, true)
end

-- submit_port submits a port-in order.
-- POST /v2.2/ports
function M:submit_port(body)
    return self._t:request("POST", "/v2.2/ports", nil, body or {}, true)
end

-- port_availability checks whether a TN can be ported in.
-- GET /v2.2/ports/availability/{number}
--
-- Response data (v2.2.14+): { number, portable, losingCarrier, reason,
--   localRoutingNumber, rateCenterTier }. Wire field names are camelCase —
-- the SDK passes the decoded JSON through unchanged.
function M:port_availability(number)
    return self._t:request("GET", "/v2.2/ports/availability/" .. url_encode(number), nil, nil, true)
end

return M
