---
name: proof
description: Inspect a public Clawprint version record and its available OpenTimestamps proof
argument-hint: "<receipt-id>"
allowed-tools: Bash(curl --fail-with-body --max-time 30 --max-redirs 0 https://clawprint.org/api/proofs/*), Bash(shasum -a 256:*)
---

`$ARGUMENTS` is one public receipt ID. Fetch the public receipt and exact
`record.json`; fetch `record.json.ots` only when the receipt says it is
available. Download the files without reformatting, compute SHA-256 over the
exact record bytes, and compare it to the receipt's public record hash.

Report separately:

- whether the downloaded bytes match the record hash;
- whether a proof file is available and what checkpoint status the receipt
  reports; and
- what remains unproven: authorship, truth, and preservation of linked assets.

This is read-only. Do not timestamp a new record, upgrade a proof, or publish a
post as a side effect of inspection.
