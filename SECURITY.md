# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| 2.2.x   | ✅        |
| < 2.2   | ❌        |

## Reporting a Vulnerability

Please **do not** open a public issue for security vulnerabilities.

Use GitHub's private vulnerability reporting for this repository:
**Security → Report a vulnerability** (or
<https://github.com/voicetel/lua-sdk/security/advisories/new>).

Include, where possible:

- A description of the issue and its impact
- Steps to reproduce or a proof of concept
- Affected version(s) and configuration

You can expect an acknowledgement within a few business days. Please
allow reasonable time for a fix before any public disclosure.

## Scope Notes

This SDK constructs authenticated HTTPS requests to the VoiceTel REST
API at <https://api.voicetel.com>. Hardening expectations on the
consumer side:

- Do not log the API key or the `Authorization` header — the 32-hex
  key is the only credential and grants full tenant access. Treat it
  as a production password.
- Fetch the key once via `POST /v2.2/account/apikey` (the only
  endpoint that does not require an `Authorization` header) and store
  the result in a secret manager or environment, never in source
  control. Re-fetch after any password change; the prior key is
  invalidated server-side.
- The SDK runs on LuaSocket + LuaSec (or FreeSWITCH's bundled cURL)
  with TLS 1.2+ and a per-host connection pool to reuse TLS sessions.
  If you swap the HTTP backend, you are responsible for matching
  that posture.
- Retries on 429 / 5xx replay the same request body, but every
  POST / PUT / PATCH carries an `Idempotency-Key` header so the
  server can collapse duplicates. Do not strip it.
- Rate-limited endpoints (`account/info`, `account/mrc`, `account/cdr`,
  `account/apikey`) are capped at 6 requests per hour per IP. Sustained
  abuse is rejected at the edge.

Out of scope: vulnerabilities in the `voicetel` LuaRocks package
caused by a forked / vendored copy that has been modified.
