# Snapshot verification

The initial snapshot and bootstrap below are historical records. The final
PrimaryOracle and stock-token additions are recorded at the end of this document.

2026-10-01. Source: CallPut main `928af0840f8c7a081b5db8f90f3dbe1c2824fdbb`.

- All 126 Solidity files match the source commit byte-for-byte, including the
  account-owner referral implementation and 46-bit strike parser correction.
- Against the 2026-07-28 Giwa repository: 112 unchanged files, 3 changed files,
  11 additions, no removals. See the [change inventory](../changes-since-giwa.md).
- README describes both transparent core proxies and beacon trading accounts.
  Mainnet deployment and runtime comparison are now recorded separately; no
  explorer verified-source status or independent protocol audit is claimed.
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
claimed. Published at `alanxxzero/callput-robinhood-contracts`, initial commit
`07df3f75293cf34faabb999dc41fb1d031a2c73c`. GitHub confirmed `alanxxzero` as
the only contributor and as both commit author and committer.

## Mainnet deployment

The authorized bootstrap completed on chain 4663: all 198 transactions succeeded.
Read-only verification matched every receipt, nonce, calldata hash and canonical
block, and all 48 named CallPut contract runtimes and implementation bindings.
Admin/keeper roles, account v6, factory/beacon wiring, closed admission and USDG
configuration passed. Total gas paid: 0.00229202790167 ETH.

All 154 compiler source units and application runtime bytecodes match the public
standalone build. OpenZeppelin proxy/admin shells match the actual deployment
plugin's bundled artifacts rather than locally recompiled shells. No Solidity
files changed. See the [deployment record](../robinhood-mainnet-deployment.md)
and [manifest](../../deployments/robinhood-mainnet.json).

At bootstrap, explorer source registration was pending (API HTTP 403). Nonzero real-USDG funding,
smart-wallet funding and live trading were not part of this bootstrap. The local
mock-token deposit/withdrawal rehearsal passed; application/service rollout is
separate. Only public addresses, transaction records and verification metadata
were exported; no credentials or private deployment tooling were copied.

## Final oracle and stock-token additions

Added the independent `PrimaryOracle.sol` placeholder; the original 126 files
remain byte-identical to the upstream snapshot. The public package now contains
127 Solidity files. Standalone compilation and ABI/storage compatibility passed.
The existing proxy was upgraded in two transactions without changing its owner,
authority or disabled primary-feed setting.

Predeployed all 18 stock/ETF token pairs from Base in 36 transactions, reusing the
OptionsToken implementation and ProxyAdmin. No market registration, token minting
or trading activation was performed. Base metadata was matched on-chain; local
36-creation rehearsal, permissions/initialization checks and read-only mainnet
receipt/calldata/runtime verification passed. Opus reviewed each deployment batch;
accepted preflight guards were applied and checked before broadcasting.

Final transaction count: 236. Total gas: 0.002816924745948 ETH. Detailed source
verification status is maintained in the README and deployment manifest.

Source publication covers all 110 creation addresses: 100 are fully verified on
Blockscout and 10 have exact creation/runtime matches on Sourcify. The remaining
Blockscout submissions returned HTTP 500. Address-specific REST checks distinguish
verified contracts from unverified contracts merely displaying a verified twin.
All 36 stock/ETF creations and the current PrimaryOracle implementation are fully
verified on Blockscout. The README highlights all 20 planned underlyings and
distinguishes deployed token pairs from market activation.
