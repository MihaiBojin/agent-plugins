# Operations

## Supplier API key

- The service reads the key from the `INVENTORY_API_KEY` environment variable
  on the host.
- The supplier portal issues new keys. An old key stays valid for 24 hours
  after the portal issues a new one.
- The service reads the variable only at start, so it must restart after the
  variable changes.
- Revoke the old key in the portal once the service runs on the new one.
- The current key expires on 2026-11-30.
