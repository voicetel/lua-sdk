-- voicetel.version — semantic version + API target metadata.
local M = {}

M.SDK_VERSION    = "2.2.10"
M.API_VERSION    = "v2.2.10"
M.DEFAULT_BASE_URL = "https://api.voicetel.com"
M.DEFAULT_USER_AGENT = "voicetel-lua/" .. M.SDK_VERSION .. " (+https://github.com/voicetel/lua-sdk)"

return M
