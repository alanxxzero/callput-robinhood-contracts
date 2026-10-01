# CallPut — Robinhood Chain Contracts

CallPut is an on-chain options protocol with pooled liquidity, keeper-executed
orders and cash settlement. This repository contains the latest protocol and
**Deposit & Trade** smart contracts deployed on Robinhood Chain.

**Deployed on Robinhood mainnet (chain 4663)** using **Paxos USDG** as the
settlement asset. All 198 deployment/initialization transactions and 48 named
CallPut contracts passed receipt, runtime-code and configuration checks.
Account admission remains closed; the application is not launched by this
contract bootstrap. Explorer source registration is pending (verification API HTTP 403).

See the [full address list and verification record](docs/robinhood-mainnet-deployment.md)
or [JSON manifest](deployments/robinhood-mainnet.json).

| Contract | Mainnet address |
| --- | --- |
| Trading account factory | [`0xbcaC622Bb396B2f868b37D7C41F34695c9be1862`](https://robinhoodchain.blockscout.com/address/0xbcaC622Bb396B2f868b37D7C41F34695c9be1862) |
| Trading account implementation (v6) | [`0x2436A7575cf8A3289c7A07154f89f05660756312`](https://robinhoodchain.blockscout.com/address/0x2436A7575cf8A3289c7A07154f89f05660756312) |
| Trading account beacon | [`0x5685d4DD5114c74C805322d4612CA5D73EAcdc62`](https://robinhoodchain.blockscout.com/address/0x5685d4DD5114c74C805322d4612CA5D73EAcdc62) |
| Position manager | [`0x426a6b482893557E58cF38de635fEbB30Fd6a3C3`](https://robinhoodchain.blockscout.com/address/0x426a6b482893557E58cF38de635fEbB30Fd6a3C3) |

## Source snapshot

The 126 Solidity files in `contracts/` are an unmodified export of
`contract/contracts/` from CallPut main commit
`928af0840f8c7a081b5db8f90f3dbe1c2824fdbb` (2026-10-01).
See [SOURCE.json](SOURCE.json) for the source tree hash and
[changes since the Giwa snapshot](docs/changes-since-giwa.md).

This repository contains contracts and standalone build configuration. The
frontend, relayer, keepers, indexer and production deployment tooling live outside
this source snapshot.

## Architecture

| Module | Main contracts | Responsibility |
| --- | --- | --- |
| Trading accounts | `TradingAccountFactory`, `TradingAccountImpl`, `TradingAccountSessionImpl` | Deterministic accounts, deposits, withdrawals and delegated trading |
| Session authorization | `SessionHash`, `SessionPolicy` | Typed signed intents and permitted position structure |
| Orders and positions | `OptionsMarket`, `PositionManager`, `Controller` | Market configuration, queued orders, execution and position accounting |
| Liquidity | `Vault`, `VaultUtils`, `OlpManager` | Risk-tiered pools and liquidity management |
| Settlement | `SettleManager`, `SettlePriceFeed` | Expiry settlement and settlement prices |
| Pricing | `SpotPriceFeed`, `FastPriceFeed`, `VaultPriceFeed`, `PositionValueFeed` | Price inputs and option valuation |
| Tokens and rewards | `OptionsToken`, `OLP`, `USDG`, reward contracts | ERC-1155 positions, liquidity tokens and LP rewards |
| Permissions | `OptionsAuthority`, `AuthorityUtil` | Core administration and keeper permissions |
| Referrals and reads | `Referral`, `ViewAggregator` | Referral relationships and aggregated views |

Core protocol contracts use transparent upgradeable proxies. Trading accounts
use **beacon proxies** created by a non-upgradeable factory. The factory holds
the core configuration and controls beacon upgrades through its admin authority.

## Deposit & Trade

The intended Robinhood application mode is Deposit & Trade:

```text
Owner wallet
    |
    | deposit / owner authorization
    v
Trading account (Paxos USDG and position custody)
    |
    | owner calls or authorized session intents
    v
PositionManager / SettleManager -> core options protocol
```

- Each account records its owner and sub-account index. Its CREATE2 address is
  derived by the factory; funds and positions belong to the trading account.
- Session keys authorize scoped trading actions without another owner-wallet
  signature for each order. Grants, nonces, deadlines, revocation and epochs
  constrain that authorization.
- Withdrawals require the owner, either through a direct call or an owner-signed
  withdrawal. A trading session alone does not authorize arbitrary withdrawals.
- Account settlement reverts if any requested position cannot settle, avoiding a
  partially successful batch being presented as complete.
- The owner selects the account's referrer through `setReferral(parent)`.
  `Referral` sees the trading account as the caller, independently of the owner's
  wallet referral. The underlying `Referral` contract is unchanged.

The shared contracts retain owner-operated and legacy wallet entry points.
Deposit-only is the intended application policy; this snapshot does not claim to
remove those existing contract functions.

## Build

With Node.js and npm installed:

```sh
git clone https://github.com/alanxxzero/callput-robinhood-contracts.git
cd callput-robinhood-contracts
npm ci
npm run compile
```

| Setting | Value |
| --- | --- |
| Solidity | `0.8.16+commit.07a7930e` |
| Optimizer | enabled, 10 runs |
| viaIR | `true` |
| EVM target | `london` (Solidity 0.8.16 default) |
| OpenZeppelin Contracts | `4.9.6` |

Dependencies are pinned in `package-lock.json`. Hardhat uses the locked local
`solc` package, so compilation after installation needs no compiler download,
RPC connection, environment file or wallet key. A matching `foundry.toml` and
remapping are provided for `forge build` after installing the npm dependencies.

See the [snapshot verification record](docs/20261001-robinhood-contract-snapshot/implementation.md)
for checks performed and build-verification limits.

The complete standalone build passed on 2026-10-01: 154 source units including
dependencies. All 58 contracts with runtime bytecode under `contracts/` are
below the 24,576-byte EVM runtime limit. The pinned compiler runs as WASM;
the first optimized build can take several minutes.

## Deployment scope

This is a full source snapshot, not a list of contracts to deploy unchanged on
every network. `PublicFaucet`, mocks and existing chain adapters are included for
source completeness; they are not a Robinhood production deployment plan.

### Two different USDG tokens

| Token | Role | Decimals |
| --- | --- | --- |
| **Paxos Global Dollar (USDG)** | External deposit, trading and withdrawal asset | 6 |
| **CallPut vault USDG** (`S_USDG`, `M_USDG`, `L_USDG`) | Existing internal vault accounting tokens | 18 |

Robinhood and Paxos publish the external USDG address as
[`0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`](https://robinhoodchain.blockscout.com/address/0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168).
This is an existing third-party token, **not** a CallPut deployment.
See [Paxos's token registry](https://docs.paxos.com/guides/stablecoin/usdg/mainnet).

The shared contract ABI retains names such as `USDC` and `core.usdc`; on
Robinhood those settlement-token slots reference Paxos USDG. This preserves
the existing contract code and does not rename or replace the internal vault
tokens. Off-chain integrations must configure USDG's address, symbol, decimals
and signing domain explicitly. CCTP is not part of this deployment scope.

Before enabling funding methods in the application, complete nonzero real-USDG
and smart-wallet integration checks. The deployment record distinguishes local
mock-token rehearsal, read-only mainnet checks and explorer source registration.

Application implementation bytecode matches this build, with immutable bindings
checked on-chain. Transparent proxy and ProxyAdmin shells use the deployment
plugin's bundled OpenZeppelin artifacts, as documented in the verification record.
This snapshot and deployment record are not an independent protocol audit.

## License

[MIT](LICENSE). Original per-file license and copyright notices are preserved.
