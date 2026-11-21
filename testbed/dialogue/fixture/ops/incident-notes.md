# Incident notes, 2026-11-17

- 14:05 UTC: release 2026-11-17.1 of inventory-service deployed to eu-west-1.
- 14:09 UTC: the error rate on `/stock` rose from 0.2% to 37%.
- The errors are HTTP 500. The logs show `RuntimeError: could not reach` from
  the supplier client in `app/http.py`.
- Other regions run release 2026-11-16.3 and are healthy.
- A rollback to 2026-11-16.3 is possible and takes about 10 minutes.
- Unknown: whether orders placed during the window were saved.
