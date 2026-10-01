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
- [ ] Verify source parity, publication contents and commit attribution; publish.

No contract logic changes, live deployment, address manifest, application code,
private history or internal operating records are included. Preserve upstream
license notices. Reuse existing source-review evidence; validate the new package.

Alan subsequently requested mainnet deployment. Deployment scripts are prepared
in the separate CallPut monorepo worktree. The payment asset is Paxos USDG;
deployed CallPut addresses will be added only after on-chain verification.
