# 📞 VoiceTel Lua SDK

The official Lua client for the [VoiceTel REST API](https://voicetel.com/docs/api/v2.2/) — built for **FreeSWITCH `mod_lua`** so you can place CNAM dips, route by LRN, send SMS, and provision e911 directly from your dialplan, with a `socket.http` fallback for offline tests and one-off scripts.

![Version](https://img.shields.io/badge/version-0.1.0-blue)
![Lua](https://img.shields.io/badge/lua-5.2%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Coverage](https://img.shields.io/badge/coverage-93%25-brightgreen)

## 📚 Table of Contents

- [Features](#-features)
- [Installation](#-installation)
- [Quickstart](#-quickstart)
- [FreeSWITCH integration](#-freeswitch-integration)
- [Authentication](#-authentication)
- [Resource Reference](#-resource-reference)
- [Error Handling](#-error-handling)
- [Rate Limits](#-rate-limits)
- [Development](#-development)
- [API Documentation](#-api-documentation)
- [Contributors](#-contributors)
- [Sponsors](#-sponsors)
- [License](#-license)

## ✨ Features

### 🛠️ Built for FreeSWITCH mod_lua
- **Drop-in friendly.** Copy `voicetel.lua` + the `voicetel/` directory into `/usr/share/freeswitch/scripts/` (or `/etc/freeswitch/scripts/`) — no LuaRocks required at runtime.
- **`freeswitch.Curl` first.** When running inside mod_lua, the SDK uses the built-in HTTP client. No extra C libraries to compile, deploy, or audit.
- **`socket.http` fallback.** Outside FreeSWITCH, the same code runs against LuaSocket / LuaSec so unit tests and CLI utilities work in any plain `lua5.2` / `lua5.3` environment.
- **Blocking is fine.** Each call leg gets its own thread, so the SDK uses synchronous HTTP — no coroutines or callbacks to weave through your dialplan.

### 🔁 Production-Grade Transport
- **Automatic retry** on 429 / 5xx with exponential backoff, capped at 8 seconds, honoring integer `Retry-After` headers. Default `max_retries = 2`.
- **Configurable per-request timeout** (default 30s).
- **Bearer auth managed for you** — `client:login(username, password)` exchanges credentials for a 32-hex API key and installs it on the transport.
- **Envelope-stripping built in** — the standard `{ status = "success", data = ... }` wrapper is peeled off before the response is returned, so you always get the inner payload.

### 📞 Complete API Coverage
- **Numbers** — list, get, add, remove, route, translate, CNAM, LIDB, fax, forward, SMS, messaging campaigns, port-out PIN, account moves.
- **Account** — profile, sub-accounts, CDRs, credits, payments, MRC, registration, password recovery.
- **e911** — record provisioning, address validation, lookup, removal.
- **Gateways** — list, create, update, delete, view bound numbers.
- **Messaging** — SMS & MMS sending, message history, 10DLC brand and campaign registration, per-number messaging state.
- **Lookups** — CNAM and LRN dips.
- **iNumbering** — inventory search, coverage queries, number orders, port-in submissions, port-out availability (with the v2.2.10 `local_routing_number` / `rate_center_tier` fields).
- **Support** — ticket create / read / update / delete, threaded messages, replies.
- **ACL** — IP allowlist management with structured 409 conflict bodies.
- **Authentication** — switch between Digest, IP-only, or hybrid modes; rotate passwords.

### 🧪 Battle-Tested
- **93% line coverage** measured with [LuaCov](https://github.com/lunarmodules/luacov).
- **100+ unit tests** under [Busted](https://lunarmodules.github.io/busted/) — every public method has a happy-path and an error-path test, the FreeSWITCH-mode dispatch is verified against a stubbed `freeswitch` global, and the retry/backoff/Retry-After paths are isolated with a fake clock.
- **CI runs on Lua 5.2 and 5.3** to keep the code FreeSWITCH-mod_lua compatible (Lua 5.2 is the floor, since that's what FreeSWITCH bundles).

### 📦 Clean Distribution
- One small Lua-only library — `voicetel.lua` plus a `voicetel/` directory of submodules. Total install footprint is under 50 KB.
- One runtime dependency: [`lua-cjson`](https://github.com/openresty/lua-cjson) (already on most FreeSWITCH boxes; otherwise `apt-get install lua-cjson`).
- LuaRocks-compatible rockspec for users who want it.

## 🚀 Installation

### Drop-in install on a FreeSWITCH server

```bash
# Pick one — different distros use different scripts directories:
SCRIPTS=/usr/share/freeswitch/scripts        # Debian/Ubuntu (.deb)
# SCRIPTS=/etc/freeswitch/scripts            # some self-built/source installs

# Pull the library:
sudo cp -r voicetel.lua voicetel "$SCRIPTS/"

# Make sure lua-cjson is present (it usually already is):
sudo apt-get install -y lua-cjson
```

That's it — `require("voicetel")` now works from any mod_lua dialplan script.

### LuaRocks install (for general-purpose Lua)

```bash
luarocks install voicetel
```

Requires Lua 5.2 or later.

## 🏁 Quickstart

```lua
local voicetel = require("voicetel")

local client = voicetel.new({ api_key = os.getenv("VOICETEL_API_KEY") })

-- Or exchange credentials for an API key:
-- local key, err = client:login(1000000001, "hunter2")

local me, err = client.account:get()
if err then error(err.message) end
print(string.format("Balance: $%.2f  |  Caller ID: %s", me.cash, me.callerId))

local numbers, err = client.numbers:list()
if err then error(err.message) end
for _, n in ipairs(numbers.numbers) do
    print(string.format("%s  route=%d  cnam=%s  sms=%s",
        n.number, n.route, tostring(n.cnam), tostring(n.smsEnabled)))
end
```

Every method returns `(result, err)` — Go-style. `result` is `nil` whenever `err` is set, so the `if err then ... end` pattern is the only one you need.

## ☎️ FreeSWITCH integration

The library ships four ready-to-run example scripts under [`examples/`](./examples) — drop them into your scripts directory and reference them from the dialplan.

### CNAM dip before bridge

```xml
<extension name="cnam-on-inbound">
  <condition field="destination_number" expression="^(\d{10})$">
    <action application="lua"
            data="voicetel-cnam.lua ${caller_id_number}"/>
    <action application="bridge"
            data="sofia/gateway/voicetel/$1"/>
  </condition>
</extension>
```

[`examples/voicetel-cnam.lua`](./examples/voicetel-cnam.lua) installs the returned name on `effective_caller_id_name` and never hard-fails the call — on rate-limit or transport error it logs a warning and falls through.

### LRN-based routing decision

```xml
<action application="lua"
        data="voicetel-lrn-route.lua ${destination_number} ${caller_id_number}"/>
<action application="bridge"
        data="sofia/gateway/${voicetel_route}/${destination_number}"/>
```

[`examples/voicetel-lrn-route.lua`](./examples/voicetel-lrn-route.lua) picks a different gateway for intrastate / non-contiguous-US / default destinations based on the LRN dip.

### Send SMS from the dialplan

```xml
<action application="lua"
        data="voicetel-sms-send.lua 2015551234 ${caller_id_number} 'We missed your call.'"/>
```

See [`examples/voicetel-sms-send.lua`](./examples/voicetel-sms-send.lua).

### Provision e911

[`examples/voicetel-e911-provision.lua`](./examples/voicetel-e911-provision.lua) is a one-shot CLI / `luarun` script that demonstrates the two-step validate-then-provision flow.

### Calling FreeSWITCH directly from a script

If you're invoking the SDK from inside a session-bound `lua` action, the script automatically uses `freeswitch.Curl`. Inside `luarun` or an external script, the same code path is used when the `freeswitch` global is available — there is no separate API to learn.

```lua
local voicetel = require("voicetel")
local client = voicetel.new({ api_key = os.getenv("VOICETEL_API_KEY") })

local r, err = client.lookups:cnam("2015551234")
if err then
    freeswitch.consoleLog("ERR", "CNAM dip failed: " .. err.message .. "\n")
    return
end
freeswitch.consoleLog("INFO", "CNAM: " .. tostring(r.cnam) .. "\n")
```

## 🔑 Authentication

Every endpoint requires `Authorization: Bearer <apikey>` **except** `POST /v2.2/account/api-key`, which exchanges username + password for a fresh key. `client:login()` handles the exchange and installs the returned key on the transport.

Re-fetch the API key after any password change — the old one is invalidated.

> Don't have credentials yet? Get them at **[voicetel.com/docs/api/v2.2/credentials](https://voicetel.com/docs/api/v2.2/credentials/)**.

```lua
local client = voicetel.new({})
local key, err = client:login(1000000001, "hunter2")
-- `key` is the new 32-hex bearer; the client already has it installed.
```

You can also fetch the key out-of-band (from a vault, secret manager, env file) and install it at construction time:

```lua
local client = voicetel.new({ api_key = os.getenv("VOICETEL_API_KEY") })
```

## 🗺️ Resource Reference

| Resource         | Field on Client        | Example                                                          |
| ---------------- | ---------------------- | ---------------------------------------------------------------- |
| Account          | `client.account`        | `client.account:cdr(t1, t2)`                                     |
| ACL              | `client.acl`            | `client.acl:add({ acl = { { cidr = "203.0.113.0/24" } } })`      |
| Authentication   | `client.authentication` | `client.authentication:update({ authType = voicetel.AUTH_TYPE_IP_AUTH })` |
| e911             | `client.e911`           | `client.e911:validate({ address1 = "1 Main St", ... })`          |
| Gateways         | `client.gateways`       | `client.gateways:list()`                                         |
| iNumbering       | `client.inumbering`     | `client.inumbering:search_inventory({ npa = 201 })`              |
| Lookups          | `client.lookups`        | `client.lookups:lrn("2125550000", "2015551234")`                 |
| Messaging        | `client.messaging`      | `client.messaging:send({ from_number = "...", to_number = "...", text = "..." })` |
| Numbers          | `client.numbers`        | `client.numbers:assign_campaign("2015551234", { campaignId = "ABC1234" })` |
| Support          | `client.support`        | `client.support:create({ subject = "...", message = "..." })`    |

73 operations in total — every endpoint in the v2.2.10 spec, with the same method names you'll find in the Go and TypeScript SDKs but in `lower_snake_case` to match Lua idiom.

A few spec quirks worth knowing about:

- **Messaging `send`** translates `from_number` / `to_number` (snake-case, idiomatic Lua) to the wire field names `fromNumber` / `toNumber` so you don't have to remember.
- **`supportConversation.number`** is a *ticket sequence integer* (e.g. `1015`), not a phone number — the SDK passes it through verbatim, so you'll see `ticket.number = 1015` in the returned table.
- **LIDB** is spelled `lidb` everywhere in this SDK (the early v2.2 spec had a `libd` typo; the fix is reflected here).
- **`port_availability`** returns the v2.2.10 fields `local_routing_number` and `rate_center_tier` in addition to the older `number`, `portable`, `losing_carrier`, `reason`.
- **DELETE** endpoints generally return 204 No Content — those methods return `true` on success. Three exceptions return 200 with a body and return that data: `client.acl:remove`, `client.numbers:unassign_campaign`, and `client.numbers:bulk_unassign_campaign`.

## 🚨 Error Handling

All HTTP errors return a structured table — never a thrown error. Inspect `err.kind` or use the helpers:

| `err.kind`           | HTTP status |
| -------------------- | ----------- |
| `"bad_request"`      | 400         |
| `"authentication"`   | 401         |
| `"permission_denied"`| 403         |
| `"not_found"`        | 404         |
| `"conflict"`         | 409         |
| `"rate_limit"`       | 429         |
| `"server"`           | 5xx         |
| `"unknown"`          | transport / other |

```lua
local n, err = client.numbers:get("9999999999")
if err then
    if voicetel.is_not_found(err) then
        print("That number isn't on your account.")
    elseif voicetel.is_rate_limit(err) then
        print("Slow down — backoff and retry.")
    else
        print(string.format("error: status=%d code=%s msg=%s",
            err.status_code, tostring(err.code), err.message))
    end
    return
end
print(n.number)
```

The error table:

```lua
{
    kind        = "rate_limit",
    status_code = 429,
    code        = nil,
    message     = "HTTP 429",
    body        = { ... },  -- the decoded JSON body (or raw string)
}
```

Predicate helpers: `voicetel.is_rate_limit`, `voicetel.is_not_found`, `voicetel.is_authentication`, `voicetel.is_permission_denied`, `voicetel.is_conflict`, `voicetel.is_bad_request`, `voicetel.is_server`.

## ⏱️ Rate Limits

These six endpoints are limited to **6 requests per hour per IP**:

- `account/info` — `client.account:get()`
- `account/cdr` — `client.account:cdr(start, end_ts)`
- `account/recurring-charges` — `client.account:recurring_charges()`
- `account/payments` — `client.account:payments()`
- `account/registration` — `client.account:registration()`
- `account/api-key` — `client:login(username, password)`

The SDK automatically retries 429 responses with `Retry-After` honored, up to `max_retries` (default `2`). To bump it:

```lua
local client = voicetel.new({
    api_key     = key,
    max_retries = 4,
    timeout     = 60,
})
```

## 🛠️ Development

```bash
git clone https://github.com/voicetel/lua-sdk
cd lua-sdk

# Install test dependencies (requires luarocks):
luarocks install --local busted
luarocks install --local luacov
luarocks install --local lua-cjson
eval "$(luarocks path)"

# Run the unit tests:
busted

# With coverage:
busted --coverage
lua -e 'require("luacov.runner").run_report()'
cat luacov.report.out | tail -30
```

Integration tests are skipped unless you set the credential env vars:

```bash
export VOICETEL_USERNAME=1000000001
export VOICETEL_PASSWORD=hunter2
busted spec/integration_spec.lua
```

## 📖 API Documentation

- **Reference docs:** [voicetel.com/docs/api/v2.2/](https://voicetel.com/docs/api/v2.2/)
- **Interactive playground:** [voicetel.com/docs/api/v2.2/playground/](https://voicetel.com/docs/api/v2.2/playground/) — try the API in your browser without writing any code.
- **API credentials:** [voicetel.com/docs/api/v2.2/credentials/](https://voicetel.com/docs/api/v2.2/credentials/)

## 🙌 Contributors

- [Michael Mavroudis](https://github.com/mavroudis) — Lead Developer

Contributions welcome. Open an issue describing the change, or send a pull request against `main`.

## 💖 Sponsors

| Sponsor | Contribution |
|---------|--------------|
| [VoiceTel Communications](https://voicetel.com) | Primary development and production hosting |

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
