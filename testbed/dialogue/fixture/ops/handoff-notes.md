# Handoff notes

- Next owner: the on-call engineer for the platform team.
- Open: the cache storage decision in `app/cache.py`. No code yet.
- Open: `fetch()` in `app/http.py` does not retry HTTP 503. The supplier
  returns 503 during its maintenance window, every Sunday 02:00 to 03:00 UTC.
- Risk: the supplier API key expires on 2026-11-30. See `docs/operations.md`.
- Tests: `python3 -m unittest` passes.
