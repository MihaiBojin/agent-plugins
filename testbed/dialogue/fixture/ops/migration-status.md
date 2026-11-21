# Migration: stock levels to PostgreSQL

- Done: the schema exists, and the read path is behind the `use_postgres` flag,
  which is off.
- In progress: the backfill is 62% complete, with about 3 hours left.
- Blocked: the write path needs a decision on the transaction isolation level.
- Next: turn on the read flag in staging after the backfill finishes.
