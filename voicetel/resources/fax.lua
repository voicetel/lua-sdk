-- voicetel.resources.fax — the Fax tag (spec v2.2.21).
--
-- Five operations: list fax-capable numbers, send a fax (multipart), list
-- history, get one job, and download the rendered PDF (binary).

local transport_mod = require("voicetel.transport")
local errors        = require("voicetel.errors")
local url_encode    = transport_mod._url_encode

local M = {}
M.__index = M

function M.new(transport) return setmetatable({ _t = transport }, M) end

-- numbers returns every fax-capable number on the account with the email each
-- delivers to (`destinationId` 0 = the account email).
-- GET /v2.2/numbers/fax
-- Response: { numbers = { { number, destinationId, email }, ... } }
function M:numbers()
    return self._t:request("GET", "/v2.2/numbers/fax", nil, nil, true)
end

-- send submits a fax for delivery. opts:
--   from_number | fromNumber - 10-digit fax number on the account
--   to_number   | toNumber   - 10-digit US/CA destination
--   documents   - array of { name = "contract.pdf", content_type =
--                   "application/pdf", data = "<bytes>" } (1..10 files,
--                   PDF/DOC/DOCX checked by content; 8 MiB each and total)
--   idempotency_key - optional client UUID; resubmitting the same documents
--                   with the same key returns the original job instead of
--                   sending twice. Generated when omitted.
--
-- The body is hand-built multipart/form-data (no multipart library exists on
-- the LuaSocket stack). Rate limit: 10 sends/minute/account (429 + Retry-After).
-- POST /v2.2/faxes (HTTP 201)
-- Response: { id, fromNumber, toNumber, status = "queued",
--             documents = { { name, size, contentType } } }
function M:send(opts)
    opts = opts or {}
    local from = opts.fromNumber or opts.from_number
    local to   = opts.toNumber or opts.to_number
    local documents = opts.documents or {}

    if not from then
        return nil, errors.new_transport("fax send requires from_number")
    end
    if not to then
        return nil, errors.new_transport("fax send requires to_number")
    end
    if #documents == 0 then
        return nil, errors.new_transport("fax send requires at least one document")
    end

    local files = {}
    for i, doc in ipairs(documents) do
        files[i] = {
            name         = "documents",
            filename     = doc.name or doc.filename,
            content_type = doc.content_type or doc.contentType
                or "application/octet-stream",
            data         = doc.data or doc.content,
        }
    end

    return self._t:request("POST", "/v2.2/faxes", nil, nil, true, {
        multipart = {
            fields = {
                { name = "fromNumber", value = from },
                { name = "toNumber",   value = to },
            },
            files  = files,
        },
        idempotency_key = opts.idempotency_key,
    })
end

-- history lists faxes sent from one of your fax numbers, newest first, with
-- cursor paging. opts (all optional except number):
--   number - a fax number on the account (required)
--   from   - newer edge of the range, unix seconds (defaults to now)
--   to     - older edge of the range, unix seconds (defaults to 24h ago)
--   limit  - page size, 1..100 (default 50)
--   cursor - opaque paging cursor from a previous response nextCursor
--   status - "all" | "active" | "queued" | "sending" | "retry_pending" |
--            "sent" | "failed"
-- GET /v2.2/faxes
-- Response: { number, fromTs, toTs, faxes = { job... }, nextCursor }
function M:history(opts)
    opts = opts or {}
    local q = {}
    if opts.number then q.number = opts.number end
    if opts.from   then q.from   = opts.from   end
    if opts.to     then q.to     = opts.to     end
    if opts.limit  then q.limit  = opts.limit  end
    if opts.cursor then q.cursor = opts.cursor end
    if opts.status then q.status = opts.status end
    return self._t:request("GET", "/v2.2/faxes", q, nil, true)
end

-- get returns one fax job by id (poll until status is "sent" or "failed").
-- GET /v2.2/faxes/{id}
function M:get(id)
    return self._t:request("GET", "/v2.2/faxes/" .. url_encode(id), nil, nil, true)
end

-- document downloads the PDF rendering of a fax job and returns the raw
-- bytes as a Lua string (write them out with io.open(path, "wb")).
-- Available when the job reports documentAvailable = true; 404 otherwise.
-- GET /v2.2/faxes/{id}/document
function M:document(id)
    return self._t:request("GET", "/v2.2/faxes/" .. url_encode(id) .. "/document",
        nil, nil, true, { raw = true })
end

return M
