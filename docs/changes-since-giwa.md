# Changes since the Giwa contract snapshot

Comparison against
[`callput-giwa-contracts` at `6e142b82`](https://github.com/alanxxzero/callput-giwa-contracts/tree/6e142b82ec803d0caff4a6657643dc72e8649476)
(2026-07-28). This compares published source trees, not live chain state.

The latest snapshot contains **126 Solidity files: 112 unchanged, 3 changed and
11 added**. No existing source file was removed.

## Added Deposit account sources

| Source | Purpose |
| --- | --- |
| `account/TradingAccountFactory.sol` | Deterministic beacon-proxy accounts, registry, shared configuration and upgrade administration |
| `account/TradingAccountImpl.sol` | Account custody, owner operations, settlement and account-based referral selection |
| `account/TradingAccountSessionImpl.sol` | Session trading, signed owner operations and authorization funding |
| `account/SessionHash.sol` | Typed authorization hashes |
| `account/SessionPolicy.sol` | Canonical spread validation |
| `account/UpgradeableBeaconArtifact.sol` | Import wrapper for the beacon artifact |
| `account/interfaces/ITradingAccount.sol` | Base account interface |
| `account/interfaces/ITradingAccountFactory.sol` | Factory interface |
| `account/interfaces/ITradingAccountSessions.sol` | Session and signed-operation interface |
| `account/interfaces/IReceiveWithAuthorization.sol` | Token authorization-funding interface |

`peripherals/PublicFaucet.sol` is the eleventh addition. It is a testnet utility,
separate from the Deposit account architecture, and is not a production token.

## Changed existing sources

| Source | Main changes |
| --- | --- |
| `BasePositionManager.sol` | Custom errors in place of revert strings; existing administrative asset movement remains available |
| `PositionManager.sol` | Keeper recovery of expired pending requests, custom errors and internal code-size optimizations |
| `Utils.sol` | Correct strike decoding from a 42-bit mask to the existing 46-bit encoded width |

Expired-request recovery returns principal or positions to the request account
and pays the current global execution fee to the recovering keeper. A failed
return reverts the transaction; it does not create a deferred claim balance.
Retired fee/claim storage slots remain reserved for upgrade compatibility.

The proposed separate USDC execution-fee charge is not included. Owner-selected
account referrals are implemented through the new account contract; the existing
`Referral.sol` source is unchanged.

Although `Controller.sol` source is unchanged, rebuilding it incorporates the
corrected internal `Utils` parser. A source comparison must not be interpreted as
proof that existing deployed Controller bytecode already includes the correction.
