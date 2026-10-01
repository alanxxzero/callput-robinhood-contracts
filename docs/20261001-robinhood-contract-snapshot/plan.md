# Robinhood contract submission snapshot

2026-10-01. Prepare `alanxxzero/callput-robinhood-contracts` in the same
contract-only format as the public Giwa repository, using the latest merged
CallPut source. Create a fresh history authored only by `alanxxzero`.

- [x] Export all 126 Solidity files byte-for-byte from main `928af084`.
- [x] Document the Deposit account architecture, source provenance and changes
  since the Giwa snapshot; distinguish source review from chain deployment.
- [x] Pin build dependencies and validate the standalone package without
  environment files, RPC connections or wallet credentials. The complete build
  passed after increasing the initial 600-second execution window.
- [x] Verify source parity, publication contents and commit attribution; publish.

No contract logic changes, application code, private history or internal operating
records are included. Preserve upstream license notices. Reuse existing
source-review evidence; validate the new package.

Alan subsequently requested mainnet deployment. Scripts remain in the separate
CallPut monorepo worktree; this repository publishes verified addresses and
transaction records only. The payment asset is Paxos USDG.

- [x] Deploy the current core protocol and Deposit v6 to chain 4663.
- [x] Verify all 198 transactions and 48 named CallPut contracts on-chain.
- [x] Publish actual addresses, implementation hashes and verification limits.

- [x] Add and deploy the common PrimaryOracle placeholder; retain the proxy address.
- [x] Predeploy 18 Base stock/ETF token pairs and verify all 36 creations.
- [x] Publish source-verification results and the 20-asset universe (all 110
  creation addresses fully verified on Blockscout).
