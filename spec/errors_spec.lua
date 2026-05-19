-- Tests for voicetel.errors classification + predicates.
local errors = require("voicetel.errors")

describe("errors", function()
    it("maps statuses to kinds", function()
        assert.are.equal(errors.KIND_BAD_REQUEST,      errors.kind_for_status(400))
        assert.are.equal(errors.KIND_AUTHENTICATION,   errors.kind_for_status(401))
        assert.are.equal(errors.KIND_PERMISSION_DENIED, errors.kind_for_status(403))
        assert.are.equal(errors.KIND_NOT_FOUND,        errors.kind_for_status(404))
        assert.are.equal(errors.KIND_CONFLICT,         errors.kind_for_status(409))
        assert.are.equal(errors.KIND_RATE_LIMIT,       errors.kind_for_status(429))
        assert.are.equal(errors.KIND_SERVER,           errors.kind_for_status(500))
        assert.are.equal(errors.KIND_SERVER,           errors.kind_for_status(503))
        assert.are.equal(errors.KIND_UNKNOWN,          errors.kind_for_status(418))
        assert.are.equal(errors.KIND_UNKNOWN,          errors.kind_for_status(0))
    end)

    it("builds an error table", function()
        local e = errors.new(404, "NOT_FOUND", "missing", { id = 1 })
        assert.are.equal(errors.KIND_NOT_FOUND, e.kind)
        assert.are.equal(404, e.status_code)
        assert.are.equal("NOT_FOUND", e.code)
        assert.are.equal("missing", e.message)
        assert.are.same({ id = 1 }, e.body)
    end)

    it("builds a transport error", function()
        local e = errors.new_transport("dns failed")
        assert.are.equal(errors.KIND_UNKNOWN, e.kind)
        assert.are.equal(0, e.status_code)
        assert.are.equal("dns failed", e.message)
    end)

    it("predicates only fire for matching kinds", function()
        local rl = errors.new(429, nil, "slow down", nil)
        assert.is_true(errors.is_rate_limit(rl))
        assert.is_false(errors.is_not_found(rl))
        assert.is_false(errors.is_rate_limit(nil))
        assert.is_false(errors.is_rate_limit("string err"))

        local nf = errors.new(404, nil, "missing", nil)
        assert.is_true(errors.is_not_found(nf))

        local au = errors.new(401, nil, "x", nil)
        assert.is_true(errors.is_authentication(au))

        local fb = errors.new(403, nil, "x", nil)
        assert.is_true(errors.is_permission_denied(fb))

        local cf = errors.new(409, nil, "x", nil)
        assert.is_true(errors.is_conflict(cf))

        local br = errors.new(400, nil, "x", nil)
        assert.is_true(errors.is_bad_request(br))

        local sv = errors.new(503, nil, "x", nil)
        assert.is_true(errors.is_server(sv))
    end)

    it("defaults the message when none supplied", function()
        local e = errors.new(500, nil, nil, nil)
        assert.are.equal("HTTP 500", e.message)
    end)
end)
