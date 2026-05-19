-- voicetel.json — thin wrapper around lua-cjson with a tiny API surface:
--
--   encode(v)            -> json text
--   decode(text)         -> value, err
--   empty_array()        -> a value that always encodes as []
--   null                 -> a value that always encodes as JSON null
--
-- Why wrap cjson? Two reasons:
--   1. Empty Lua tables encode as JSON objects by default; for fields like
--      `mediaUrls = {}` we need the JSON array form. cjson exposes a sentinel
--      (`cjson.empty_array`) and an `array_mt` metatable for this.
--   2. Tests can monkey-patch this module to inject a deterministic encoder
--      without touching the C library.
local M = {}

local ok, cjson = pcall(require, "cjson")
if not ok then
    -- cjson.safe is what some distros ship; try it before giving up.
    local ok2, cjson_safe = pcall(require, "cjson.safe")
    if not ok2 then
        error("voicetel: lua-cjson is required (luarocks install lua-cjson)")
    end
    cjson = cjson_safe
end

M._cjson = cjson
M.null = cjson.null
M._array_mt = cjson.array_mt or { __jsontype = "array" }

-- empty_array returns a fresh table tagged as a JSON array, so that
-- `json.encode(json.empty_array())` always yields `[]`.
function M.empty_array()
    return setmetatable({}, M._array_mt)
end

-- as_array tags an existing table as a JSON array. Returns the same table.
function M.as_array(t)
    return setmetatable(t or {}, M._array_mt)
end

function M.encode(v)
    return cjson.encode(v)
end

-- decode never raises; returns (value, nil) on success, (nil, err_string) on failure.
function M.decode(text)
    if text == nil or text == "" then return nil, nil end
    local ok2, val_or_err = pcall(cjson.decode, text)
    if not ok2 then return nil, tostring(val_or_err) end
    return val_or_err, nil
end

return M
