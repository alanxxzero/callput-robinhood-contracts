# Snapshot verification

2026-10-01. Source: CallPut main `928af0840f8c7a081b5db8f90f3dbe1c2824fdbb`.

- All 126 Solidity files match the source commit byte-for-byte, including the
  account-owner referral implementation and 46-bit strike parser correction.
- Against the 2026-07-28 Giwa repository: 112 unchanged files, 3 changed files,
  11 additions, no removals. See the [change inventory](../changes-since-giwa.md).
- README describes both transparent core proxies and beacon trading accounts.
  No Robinhood CallPut deployment, explorer match or independent audit is claimed.
  Mainnet chain 4663 and external Paxos USDG are the selected deployment target.
- Package versions and lockfile agree: Hardhat 2.22.18, solc 0.8.16 and
  OpenZeppelin Contracts 4.9.6. Local compiler selection follows the
  [Hardhat 2 guide](https://v2.hardhat.org/hardhat-runner/docs/other-guides/using-custom-solc).
- Source inventory, local README links, config syntax and dependency URLs pass
  validation. No environment files, keys or original Git history were imported.
- The exported Git tree is `b0d96549cdf740c735053a54dbb0677d952f5681`,
  exactly matching the upstream `contract/contracts` tree. Upstream whitespace
  is preserved for byte identity; new documentation/configuration passes the
  Git whitespace check.

## Build result

Full standalone Hardhat compilation **PASS**: 154 source units including
dependencies, Solidity 0.8.16, optimizer 10, viaIR, London. No credentials, RPC or
environment files were used. All 58 runtime-bearing contracts in the exported
source are below EIP-170's 24,576-byte limit. Largest: Controller 22,765 bytes,
TradingAccountSessionImpl 22,516, Vault 22,142, PositionManager 21,086.

The first full build exceeded its 600-second execution limit. The cached native
compiler is an Intel macOS binary and cannot execute on this Apple Silicon host.
The pinned WASM compiler is compatible but slower; a complete run with a longer
window succeeded. Separate all-source ABI and seven-target bytecode checks also
passed. Existing Solidity compiler warnings remain; no warning-free claim.

Source review evidence is inherited from the unchanged upstream implementation;
this export is not a new protocol audit.
Foundry is not installed in the publishing environment, so no Forge result is
claimed. Publication uses a new history with `alanxxzero` as author and committer.
