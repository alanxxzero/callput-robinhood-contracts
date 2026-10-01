# CallPut — Robinhood Chain Contracts

CallPut is an on-chain options trading protocol. Traders open call and put positions
against liquidity vaults, while liquidity providers earn fees through three pool
tiers (S / M / L). Keepers supply price updates, execute orders and settle positions
at expiry under the protocol's role-based permissions.

This repository contains the Solidity source, build configuration and deployed
contract addresses for **Robinhood Chain mainnet**, including **Deposit & Trade**
accounts funded with **Paxos USDG**.

## Options underlyings — 20 assets

**BTC · ETH · 14 stocks · 4 ETFs** — planned Robinhood market coverage matching
CallPut's full Base asset universe.

| Category | Underlyings |
| --- | --- |
| Crypto | **BTC, ETH** |
| Stocks | **AAPL, AMZN, COIN, CRCL, GOOGL, META, MSFT, MU, NVDA, PLTR, SKHY, SNDK, SPCX, TSLA** |
| ETFs | **DRAM, EWY, QQQ, SPY** |

BTC and ETH markets are registered. Stock/ETF token pairs are predeployed for
future listings; market registration and activation follow separately.
**Robinhood trading has not launched yet.**

## Architecture

| Module | Key contracts | Responsibility |
| --- | --- | --- |
| Trading accounts | `TradingAccountFactory`, `TradingAccountSessionImpl` | Account creation, custody, owner withdrawals and session trading |
| Options market | `OptionsMarket`, `PositionManager`, `Controller` | Markets, order execution and position accounting |
| Liquidity | `Vault`, `VaultUtils`, `OlpManager` | S/M/L pools and liquidity management |
| Settlement | `SettleManager`, `SettlePriceFeed` | Expiry settlement and settlement prices |
| Pricing | `SpotPriceFeed`, `FastPriceFeed`, `VaultPriceFeed`, `PositionValueFeed` | Price inputs and option valuation |
| Tokens and rewards | `OptionsToken`, `USDG`, `OLP`, reward contracts | ERC-1155 positions, pool accounting, LP tokens and rewards |
| Permissions | `OptionsAuthority`, `ProxyAdmin` | Core roles and proxy upgrade administration |
| Referrals and reads | `Referral`, `ViewAggregator` | Referral relationships and aggregated protocol data |

Core contracts use OpenZeppelin transparent proxies (EIP-1967). Trading accounts
use beacon proxies created by a non-upgradeable factory.

### Deposit & Trade

Each owner has a trading account that holds USDG and positions. The owner can
authorize a session key for trading; withdrawals require owner authorization.
Referrals are registered by the trading account. The factory controls account
admission and beacon upgrades, and the beacon currently points to account
implementation **v6**.

## Robinhood mainnet

| Setting | Value |
| --- | --- |
| Chain ID | `4663` |
| Explorer | [Robinhood Chain Blockscout](https://robinhoodchain.blockscout.com) |
| Public RPC | `https://rpc.mainnet.chain.robinhood.com` |
| Gas token | ETH |
| Settlement asset | Paxos USDG (6 decimals) |
| Registered markets | BTC, ETH |
| Planned stock/ETF markets | 18; see the underlying list above |
| Deployment status | Contracts deployed; account admission closed (`openToAll = false`) |

Application and keeper-service rollout is separate from this contract deployment.

## Compiler settings

| Setting | Value |
| --- | --- |
| Solidity | `0.8.16+commit.07a7930e` |
| Optimizer | enabled, `runs: 10` |
| viaIR | `true` |
| EVM target | `london` |
| OpenZeppelin Contracts | `4.9.6` |
| Remapping | `@openzeppelin/=node_modules/@openzeppelin/` |

Compiler settings agree in [hardhat.config.js](hardhat.config.js) and
[foundry.toml](foundry.toml). Dependencies are pinned in
[package-lock.json](package-lock.json).

## Deployed addresses

Addresses and implementation links below come from the
[mainnet deployment manifest](deployments/robinhood-mainnet.json).
For transparent proxies, integrations use the **Address** column;
**Implementation** links point to the underlying logic contract. Multiple
proxies of the same type can share an implementation.

Explorer source-verification status is described in [Verification](#verification).
An implementation link alone does not indicate explorer-verified source.

### Trading accounts

| Contract | Address (explorer) | Role |
| --- | --- | --- |
| TradingAccountFactory | [`0xbcaC622Bb396B2f868b37D7C41F34695c9be1862`](https://robinhoodchain.blockscout.com/address/0xbcaC622Bb396B2f868b37D7C41F34695c9be1862) | Account creation, registry and administration |
| UpgradeableBeacon | [`0x5685d4DD5114c74C805322d4612CA5D73EAcdc62`](https://robinhoodchain.blockscout.com/address/0x5685d4DD5114c74C805322d4612CA5D73EAcdc62) | Shared account implementation; owned by the factory |
| TradingAccountSessionImpl | [`0x2436A7575cf8A3289c7A07154f89f05660756312`](https://robinhoodchain.blockscout.com/address/0x2436A7575cf8A3289c7A07154f89f05660756312) | Account implementation v6 |

These are the factory, beacon and implementation contracts. Individual trading
account addresses are created through the factory.

### Core protocol

| Contract | Address (explorer) | Implementation |
| --- | --- | --- |
| OptionsMarket | [`0x3271d35afAc70C0D4989F984Abb2d918bf672C7e`](https://robinhoodchain.blockscout.com/address/0x3271d35afAc70C0D4989F984Abb2d918bf672C7e) | [impl](https://robinhoodchain.blockscout.com/address/0x100291F9Fc52CE39e177DfD6d4bC72aDF906A1d9#code) |
| Controller | [`0x0D240c1EbEeE7F74B40d6611326f5df98AB00e1B`](https://robinhoodchain.blockscout.com/address/0x0D240c1EbEeE7F74B40d6611326f5df98AB00e1B) | [impl](https://robinhoodchain.blockscout.com/address/0x66C1F85b71eCA648E27B860213676f9116f5eE9A#code) |
| PositionManager | [`0x426a6b482893557E58cF38de635fEbB30Fd6a3C3`](https://robinhoodchain.blockscout.com/address/0x426a6b482893557E58cF38de635fEbB30Fd6a3C3) | [impl](https://robinhoodchain.blockscout.com/address/0x9D83c9f0581a695c5D1fbD7B41EB8ddc5143246D#code) |
| SettleManager | [`0xd328D581f3Fb1Ca86D28D573bA1f17409e5112EF`](https://robinhoodchain.blockscout.com/address/0xd328D581f3Fb1Ca86D28D573bA1f17409e5112EF) | [impl](https://robinhoodchain.blockscout.com/address/0x7B968a70467C1dc0553B84E0Fd7ef25c7B357A25#code) |
| OptionsAuthority | [`0x85e00a193d5E340339484336dd9EA09f942A0b7B`](https://robinhoodchain.blockscout.com/address/0x85e00a193d5E340339484336dd9EA09f942A0b7B) | [impl](https://robinhoodchain.blockscout.com/address/0x8B4290fffB0700ee1618BBbA88299449E92fD022#code) |
| ViewAggregator | [`0xf277D41cc8093667bf1A023f4FBbeB8328900bb7`](https://robinhoodchain.blockscout.com/address/0xf277D41cc8093667bf1A023f4FBbeB8328900bb7) | [impl](https://robinhoodchain.blockscout.com/address/0x3E52762fAE476de0F70fE241f188dbAE0c90C2c8#code) |
| Referral | [`0xBa64c819A8C5a80E51ce5f929C3BF08DD187D6c9`](https://robinhoodchain.blockscout.com/address/0xBa64c819A8C5a80E51ce5f929C3BF08DD187D6c9) | [impl](https://robinhoodchain.blockscout.com/address/0x51B48222a31413F1FD58C18Aa13b51c35020cB9c#code) |
| FeeDistributor | [`0x42260a98bc6e1AA2f4CEC5508146d713BfD72c41`](https://robinhoodchain.blockscout.com/address/0x42260a98bc6e1AA2f4CEC5508146d713BfD72c41) | [impl](https://robinhoodchain.blockscout.com/address/0x9D441286DCf5e6aaE87706d88bc6Fa772D18847F#code) |

### Liquidity pools

| Contract | Address (explorer) | Implementation |
| --- | --- | --- |
| Vault — S | [`0x21bA39e9394657A6196f6948C2701D9fD9612289`](https://robinhoodchain.blockscout.com/address/0x21bA39e9394657A6196f6948C2701D9fD9612289) | [impl](https://robinhoodchain.blockscout.com/address/0x9954964Af61DC7Ba9e82B7A7C5A6bF7caB54358d#code) |
| Vault — M | [`0xA60e4A30c8D56C81c7E7c607a9E092cEb25241eE`](https://robinhoodchain.blockscout.com/address/0xA60e4A30c8D56C81c7E7c607a9E092cEb25241eE) | [impl](https://robinhoodchain.blockscout.com/address/0x9954964Af61DC7Ba9e82B7A7C5A6bF7caB54358d#code) |
| Vault — L | [`0xCaf6Cf834Dc1b0C86206B6e9E797f5D27ca63897`](https://robinhoodchain.blockscout.com/address/0xCaf6Cf834Dc1b0C86206B6e9E797f5D27ca63897) | [impl](https://robinhoodchain.blockscout.com/address/0x9954964Af61DC7Ba9e82B7A7C5A6bF7caB54358d#code) |
| VaultUtils — S | [`0xfB970601A11254bA465fE52eC88546299E1E002c`](https://robinhoodchain.blockscout.com/address/0xfB970601A11254bA465fE52eC88546299E1E002c) | [impl](https://robinhoodchain.blockscout.com/address/0xdc813f312ce0f92C69C996cD6Df53cb90d41b7c7#code) |
| VaultUtils — M | [`0x5B52c79Cc4E7c09BF51716C37fd6301aEB793066`](https://robinhoodchain.blockscout.com/address/0x5B52c79Cc4E7c09BF51716C37fd6301aEB793066) | [impl](https://robinhoodchain.blockscout.com/address/0xdc813f312ce0f92C69C996cD6Df53cb90d41b7c7#code) |
| VaultUtils — L | [`0x05cfa0574F4daA5B2d3Fd9E6c25ffe725f38b573`](https://robinhoodchain.blockscout.com/address/0x05cfa0574F4daA5B2d3Fd9E6c25ffe725f38b573) | [impl](https://robinhoodchain.blockscout.com/address/0xdc813f312ce0f92C69C996cD6Df53cb90d41b7c7#code) |
| OlpManager — S | [`0xbed7fB763bb9391e45AD2c70FE19887CAD7Ec9B8`](https://robinhoodchain.blockscout.com/address/0xbed7fB763bb9391e45AD2c70FE19887CAD7Ec9B8) | [impl](https://robinhoodchain.blockscout.com/address/0x4eD46e1df37dbfE9B0D31137a912e78D997f72Dc#code) |
| OlpManager — M | [`0x7eBbdF7ffCaB33e244D465E7FA08756Fd7F7738b`](https://robinhoodchain.blockscout.com/address/0x7eBbdF7ffCaB33e244D465E7FA08756Fd7F7738b) | [impl](https://robinhoodchain.blockscout.com/address/0x4eD46e1df37dbfE9B0D31137a912e78D997f72Dc#code) |
| OlpManager — L | [`0x887Af039C15CCe9636195C80254B46a8Faf03FDc`](https://robinhoodchain.blockscout.com/address/0x887Af039C15CCe9636195C80254B46a8Faf03FDc) | [impl](https://robinhoodchain.blockscout.com/address/0x4eD46e1df37dbfE9B0D31137a912e78D997f72Dc#code) |

Each pool has its own vault, accounting/LP tokens and reward contracts.

### Oracles

| Contract | Address (explorer) | Implementation |
| --- | --- | --- |
| VaultPriceFeed | [`0x2666ce652b1929D4F5a2dBBf094E5DfD38d1b9f1`](https://robinhoodchain.blockscout.com/address/0x2666ce652b1929D4F5a2dBBf094E5DfD38d1b9f1) | [impl](https://robinhoodchain.blockscout.com/address/0x5f549AAbE9586224988F23FE88f5f15a23224bf3#code) |
| SpotPriceFeed | [`0x2318040e26791777d675cFeF87FE25BDcE36439A`](https://robinhoodchain.blockscout.com/address/0x2318040e26791777d675cFeF87FE25BDcE36439A) | [impl](https://robinhoodchain.blockscout.com/address/0xd2BCAB3d76600e61c64FDba6726D495F1B6B92CB#code) |
| FastPriceFeed | [`0xA936FCaD3C5CDda9106F72499729877E9dF5918a`](https://robinhoodchain.blockscout.com/address/0xA936FCaD3C5CDda9106F72499729877E9dF5918a) | [impl](https://robinhoodchain.blockscout.com/address/0x479B6Bf0A40c5359C68352B91e504977Ae65D7DC#code) |
| FastPriceEvents | [`0x1e5A834eb298288E28C07b6f2369e0008a5d156C`](https://robinhoodchain.blockscout.com/address/0x1e5A834eb298288E28C07b6f2369e0008a5d156C) | [impl](https://robinhoodchain.blockscout.com/address/0x049D3b6455a5E393a3C0761CfCFE75ff2221cbb6#code) |
| SettlePriceFeed | [`0xB51EC03d51e8880FDc2A24f918072694516FB626`](https://robinhoodchain.blockscout.com/address/0xB51EC03d51e8880FDc2A24f918072694516FB626) | [impl](https://robinhoodchain.blockscout.com/address/0xfe3F5FF9e740AeD8213dc6327E1DdC13718D6702#code) |
| PositionValueFeed | [`0x32847298142A9E692EfE1c259aADe4f260bDe94C`](https://robinhoodchain.blockscout.com/address/0x32847298142A9E692EfE1c259aADe4f260bDe94C) | [impl](https://robinhoodchain.blockscout.com/address/0x60Acd6ca57b279065D8629d091cCEb891C5751F4#code) |
| PrimaryOracle | [`0x9D1e3c557F3E3078dCBd8ac77Dfe1950db9B8c0B`](https://robinhoodchain.blockscout.com/address/0x9D1e3c557F3E3078dCBd8ac77Dfe1950db9B8c0B) | [impl](https://robinhoodchain.blockscout.com/address/0x66cAAcF4F6635b553B2Ff984DCA1877c0fDAD324#code) |

### Protocol tokens

| Contract | Address (explorer) | Implementation |
| --- | --- | --- |
| OptionsToken — BTC | [`0x080084D6A1e9b6657EDc8DBa071BAa9D15Fcc500`](https://robinhoodchain.blockscout.com/address/0x080084D6A1e9b6657EDc8DBa071BAa9D15Fcc500) | [impl](https://robinhoodchain.blockscout.com/address/0x8ba18F54908852A798BC8e1aB28235FfeeD5DFc9#code) |
| OptionsToken — ETH | [`0x84D4ef4062E00F78B0Ea5aaC06D7D08Ab1258B02`](https://robinhoodchain.blockscout.com/address/0x84D4ef4062E00F78B0Ea5aaC06D7D08Ab1258B02) | [impl](https://robinhoodchain.blockscout.com/address/0x8ba18F54908852A798BC8e1aB28235FfeeD5DFc9#code) |
| USDG — S | [`0xb4193D3618E45231A3D4a73600170ef5cbF62E0F`](https://robinhoodchain.blockscout.com/address/0xb4193D3618E45231A3D4a73600170ef5cbF62E0F) | [impl](https://robinhoodchain.blockscout.com/address/0x355E932F8ED363cC3E3d7AB4F326F8553360229a#code) |
| USDG — M | [`0x4E4E9EF8f0170fb9190608816068610E6e9D9184`](https://robinhoodchain.blockscout.com/address/0x4E4E9EF8f0170fb9190608816068610E6e9D9184) | [impl](https://robinhoodchain.blockscout.com/address/0x355E932F8ED363cC3E3d7AB4F326F8553360229a#code) |
| USDG — L | [`0x42A7D4dcd0c84ee14547d3C738D40C14D7f66fA4`](https://robinhoodchain.blockscout.com/address/0x42A7D4dcd0c84ee14547d3C738D40C14D7f66fA4) | [impl](https://robinhoodchain.blockscout.com/address/0x355E932F8ED363cC3E3d7AB4F326F8553360229a#code) |
| OLP — S | [`0x463811B783f53c7adf01Bc51aFb7880b6d95A5d5`](https://robinhoodchain.blockscout.com/address/0x463811B783f53c7adf01Bc51aFb7880b6d95A5d5) | [impl](https://robinhoodchain.blockscout.com/address/0x67FCdaB641Ab053DB3bcA63dC4d8ee5c12260706#code) |
| OLP — M | [`0xcc0BA1Bbc4D0625bDb6c16A935bF1317788d39D1`](https://robinhoodchain.blockscout.com/address/0xcc0BA1Bbc4D0625bDb6c16A935bF1317788d39D1) | [impl](https://robinhoodchain.blockscout.com/address/0x67FCdaB641Ab053DB3bcA63dC4d8ee5c12260706#code) |
| OLP — L | [`0xc163528C97d005b70095E2DD20e582F6408Cc96c`](https://robinhoodchain.blockscout.com/address/0xc163528C97d005b70095E2DD20e582F6408Cc96c) | [impl](https://robinhoodchain.blockscout.com/address/0x67FCdaB641Ab053DB3bcA63dC4d8ee5c12260706#code) |

`OptionsToken` is ERC-1155. `S_USDG`, `M_USDG` and `L_USDG` are internal
18-decimal vault accounting tokens; `OLP` tokens represent pool liquidity.

<details>
<summary>Reward and liquidity queue contracts</summary>

| Contract | Address (explorer) | Implementation |
| --- | --- | --- |
| RewardTracker — S | [`0x6b8979E1662a1e7524ecBBA625AA31cf87247Ea5`](https://robinhoodchain.blockscout.com/address/0x6b8979E1662a1e7524ecBBA625AA31cf87247Ea5) | [impl](https://robinhoodchain.blockscout.com/address/0x79AD98fA252D64A9095f83cc6FaF4243E0d01d48#code) |
| RewardTracker — M | [`0xC7223e6F948C0804D62FfC4FD33A02225A743A1D`](https://robinhoodchain.blockscout.com/address/0xC7223e6F948C0804D62FfC4FD33A02225A743A1D) | [impl](https://robinhoodchain.blockscout.com/address/0x79AD98fA252D64A9095f83cc6FaF4243E0d01d48#code) |
| RewardTracker — L | [`0x0899213428E3eF7f1D590e37BF8363E19Cc27f4e`](https://robinhoodchain.blockscout.com/address/0x0899213428E3eF7f1D590e37BF8363E19Cc27f4e) | [impl](https://robinhoodchain.blockscout.com/address/0x79AD98fA252D64A9095f83cc6FaF4243E0d01d48#code) |
| RewardDistributor — S | [`0xD339d220bb30603e66cf15394657C9cAaC97274E`](https://robinhoodchain.blockscout.com/address/0xD339d220bb30603e66cf15394657C9cAaC97274E) | [impl](https://robinhoodchain.blockscout.com/address/0x6090cd3cb1c8d46471A600f363237D0E3b4388cb#code) |
| RewardDistributor — M | [`0x30654838D2f3F3Ba475dd53a24Ce3aed3d4280DE`](https://robinhoodchain.blockscout.com/address/0x30654838D2f3F3Ba475dd53a24Ce3aed3d4280DE) | [impl](https://robinhoodchain.blockscout.com/address/0x6090cd3cb1c8d46471A600f363237D0E3b4388cb#code) |
| RewardDistributor — L | [`0x9C8DDe98a6b09fD484eBFB74C2A016148B0D7378`](https://robinhoodchain.blockscout.com/address/0x9C8DDe98a6b09fD484eBFB74C2A016148B0D7378) | [impl](https://robinhoodchain.blockscout.com/address/0x6090cd3cb1c8d46471A600f363237D0E3b4388cb#code) |
| RewardRouterV2 — S | [`0x0BA1292c9e205c0a12d926406b0ab5bc3EF879f0`](https://robinhoodchain.blockscout.com/address/0x0BA1292c9e205c0a12d926406b0ab5bc3EF879f0) | [impl](https://robinhoodchain.blockscout.com/address/0x306Da5cfa8640a989684432f5b2BC9a27E216E80#code) |
| RewardRouterV2 — M | [`0x95420DdB175A1550f5fC66Ca5847352B53b6E0cA`](https://robinhoodchain.blockscout.com/address/0x95420DdB175A1550f5fC66Ca5847352B53b6E0cA) | [impl](https://robinhoodchain.blockscout.com/address/0x306Da5cfa8640a989684432f5b2BC9a27E216E80#code) |
| RewardRouterV2 — L | [`0x366c7f855d9bc013da3F9aC10C98b3F4EF7A5Ed8`](https://robinhoodchain.blockscout.com/address/0x366c7f855d9bc013da3F9aC10C98b3F4EF7A5Ed8) | [impl](https://robinhoodchain.blockscout.com/address/0x306Da5cfa8640a989684432f5b2BC9a27E216E80#code) |
| OlpQueue — S | [`0xFC121FEaAAf0bEdc93E5Da7a9C7D161357C89e16`](https://robinhoodchain.blockscout.com/address/0xFC121FEaAAf0bEdc93E5Da7a9C7D161357C89e16) | [impl](https://robinhoodchain.blockscout.com/address/0xD959B771c5244d290072cD319FDdFe6aa7b2Ad66#code) |
| OlpQueue — M | [`0x95D1013be04e2D7da6C7E6e96fbC4dAE16Ee23F2`](https://robinhoodchain.blockscout.com/address/0x95D1013be04e2D7da6C7E6e96fbC4dAE16Ee23F2) | [impl](https://robinhoodchain.blockscout.com/address/0xD959B771c5244d290072cD319FDdFe6aa7b2Ad66#code) |
| OlpQueue — L | [`0xF82fb623BEE693351bD7099Cc3650FBE46FB8349`](https://robinhoodchain.blockscout.com/address/0xF82fb623BEE693351bD7099Cc3650FBE46FB8349) | [impl](https://robinhoodchain.blockscout.com/address/0xD959B771c5244d290072cD319FDdFe6aa7b2Ad66#code) |

</details>

### Stock & ETF underlyings (18)

Each underlying is a zero-supply ERC-20 identifier with a matching `OptionsToken`
proxy, reusing the BTC/ETH OptionsToken implementation. These contracts are
predeployed and **not yet registered as Robinhood markets**. The underlying tokens
are protocol identifiers; they do not represent ownership of shares or ETF units.

| Underlying | Underlying address | OptionsToken address |
| --- | --- | --- |
| TSLA | [`0x2e3827D35687e4D2c7DD94fce14E6D6fEAfD873d`](https://robinhoodchain.blockscout.com/address/0x2e3827D35687e4D2c7DD94fce14E6D6fEAfD873d) | [`0x9C007762CBf1ABF0Bb3e1C67660023bD3Ad1734D`](https://robinhoodchain.blockscout.com/address/0x9C007762CBf1ABF0Bb3e1C67660023bD3Ad1734D) |
| QQQ | [`0x2d4a28f9d7Fa0754B9E6a4e768891AA5AE5CAee1`](https://robinhoodchain.blockscout.com/address/0x2d4a28f9d7Fa0754B9E6a4e768891AA5AE5CAee1) | [`0x951D61C56CC4c3b79CF7078C371C474917480FDd`](https://robinhoodchain.blockscout.com/address/0x951D61C56CC4c3b79CF7078C371C474917480FDd) |
| SPY | [`0xD552a5358908e3B30439D925ca1F1fCe5Ab009F7`](https://robinhoodchain.blockscout.com/address/0xD552a5358908e3B30439D925ca1F1fCe5Ab009F7) | [`0x334D4fbf590Cbc3553fBdd6f11a2C0d7C1221e8A`](https://robinhoodchain.blockscout.com/address/0x334D4fbf590Cbc3553fBdd6f11a2C0d7C1221e8A) |
| EWY | [`0xAe8fedfa2BAbF1792854429d6040799062E075EE`](https://robinhoodchain.blockscout.com/address/0xAe8fedfa2BAbF1792854429d6040799062E075EE) | [`0x35D2Cd90b6Ba62ea33F38A711DbB99C6C3D81Ba7`](https://robinhoodchain.blockscout.com/address/0x35D2Cd90b6Ba62ea33F38A711DbB99C6C3D81Ba7) |
| NVDA | [`0x894AB41c5353eB9795FFC44B412628eE1b2197FB`](https://robinhoodchain.blockscout.com/address/0x894AB41c5353eB9795FFC44B412628eE1b2197FB) | [`0xcA2bc103CD18EC0b7646969dcB383D64037cb5bB`](https://robinhoodchain.blockscout.com/address/0xcA2bc103CD18EC0b7646969dcB383D64037cb5bB) |
| COIN | [`0x04D773Cc8C88895FA29380a09E90613bFABEB4D4`](https://robinhoodchain.blockscout.com/address/0x04D773Cc8C88895FA29380a09E90613bFABEB4D4) | [`0x48E93EbC08ccaa3D3fC9E388bfEfD8209922D1cb`](https://robinhoodchain.blockscout.com/address/0x48E93EbC08ccaa3D3fC9E388bfEfD8209922D1cb) |
| SPCX | [`0x973533762B5F0Fa16B15854A54a920Ce7560e926`](https://robinhoodchain.blockscout.com/address/0x973533762B5F0Fa16B15854A54a920Ce7560e926) | [`0x0EAe421365011aE66dfa8bb9D1E8Baee54e5402d`](https://robinhoodchain.blockscout.com/address/0x0EAe421365011aE66dfa8bb9D1E8Baee54e5402d) |
| MU | [`0xB694AC94B1f0C22013B66AF948A7F02E7Ed64daa`](https://robinhoodchain.blockscout.com/address/0xB694AC94B1f0C22013B66AF948A7F02E7Ed64daa) | [`0x1868dB80a42E6D303E3A961886ba4534b6f56d40`](https://robinhoodchain.blockscout.com/address/0x1868dB80a42E6D303E3A961886ba4534b6f56d40) |
| SKHY | [`0x53FFa4E63165fc7ed5390e02277e4c0e36336c50`](https://robinhoodchain.blockscout.com/address/0x53FFa4E63165fc7ed5390e02277e4c0e36336c50) | [`0x0a750ABB292C902D9752C5f508Ec6f5ec9Be7FCd`](https://robinhoodchain.blockscout.com/address/0x0a750ABB292C902D9752C5f508Ec6f5ec9Be7FCd) |
| SNDK | [`0x467be03f40beE63606Ad208a100Fb14B5e9b7bFE`](https://robinhoodchain.blockscout.com/address/0x467be03f40beE63606Ad208a100Fb14B5e9b7bFE) | [`0x5dBd79079fc1abA28F0a270beEcD855aCda98c88`](https://robinhoodchain.blockscout.com/address/0x5dBd79079fc1abA28F0a270beEcD855aCda98c88) |
| DRAM | [`0x9e5B63e8Dc02576A31b88DA04A14C5282D7a5bfd`](https://robinhoodchain.blockscout.com/address/0x9e5B63e8Dc02576A31b88DA04A14C5282D7a5bfd) | [`0xC3827d938c96232b3a08E83D71D084965Eb7e3Fb`](https://robinhoodchain.blockscout.com/address/0xC3827d938c96232b3a08E83D71D084965Eb7e3Fb) |
| META | [`0x126e5CdBc6D04880D7b17E1FC7bF44a39279d419`](https://robinhoodchain.blockscout.com/address/0x126e5CdBc6D04880D7b17E1FC7bF44a39279d419) | [`0x778d648c02c8F521bE22f903Fd2edb8bD6F34DFB`](https://robinhoodchain.blockscout.com/address/0x778d648c02c8F521bE22f903Fd2edb8bD6F34DFB) |
| GOOGL | [`0xB00bC91af828AA279100b1D482aD4C07F80078b9`](https://robinhoodchain.blockscout.com/address/0xB00bC91af828AA279100b1D482aD4C07F80078b9) | [`0x84d0040153e67618D49C49EDb3f50e6Ed8de0d7D`](https://robinhoodchain.blockscout.com/address/0x84d0040153e67618D49C49EDb3f50e6Ed8de0d7D) |
| AAPL | [`0x08817cf3D786d36b56bFa1fc5F71273314468fb1`](https://robinhoodchain.blockscout.com/address/0x08817cf3D786d36b56bFa1fc5F71273314468fb1) | [`0xCa103C4D4bb8CEf8bf3A8622b0a3fCA58d835118`](https://robinhoodchain.blockscout.com/address/0xCa103C4D4bb8CEf8bf3A8622b0a3fCA58d835118) |
| CRCL | [`0x8d210Af1Ec489310c0A74d6eAa0cfa471F9De6cC`](https://robinhoodchain.blockscout.com/address/0x8d210Af1Ec489310c0A74d6eAa0cfa471F9De6cC) | [`0x4A87676cbF3d0e725aeF3DaF8962Ea805Dda569e`](https://robinhoodchain.blockscout.com/address/0x4A87676cbF3d0e725aeF3DaF8962Ea805Dda569e) |
| AMZN | [`0x0Af16c8F8731FB9c0b8d4851e1509130CFbe5f68`](https://robinhoodchain.blockscout.com/address/0x0Af16c8F8731FB9c0b8d4851e1509130CFbe5f68) | [`0x53a0B4cB036BeCE074194171B3A6f885276d61C3`](https://robinhoodchain.blockscout.com/address/0x53a0B4cB036BeCE074194171B3A6f885276d61C3) |
| MSFT | [`0x3cD315EEf182EF06e0d12f4396AC50035AB4F211`](https://robinhoodchain.blockscout.com/address/0x3cD315EEf182EF06e0d12f4396AC50035AB4F211) | [`0x9AA5a975b26432730173AEeAa20E9DD1C999Ee99`](https://robinhoodchain.blockscout.com/address/0x9AA5a975b26432730173AEeAa20E9DD1C999Ee99) |
| PLTR | [`0x2d7a46adE1FE818D3D00A915D7f38938AE0fb404`](https://robinhoodchain.blockscout.com/address/0x2d7a46adE1FE818D3D00A915D7f38938AE0fb404) | [`0x3DbD73E6BE453E79D28968503bb88c6c5f7d12BA`](https://robinhoodchain.blockscout.com/address/0x3DbD73E6BE453E79D28968503bb88c6c5f7d12BA) |

### External assets

These token contracts already exist on Robinhood Chain.

| Asset | Address (explorer) | Decimals | Role |
| --- | --- | --- | --- |
| Paxos USDG | [`0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`](https://robinhoodchain.blockscout.com/address/0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168) | 6 | Deposits, trading collateral and withdrawals |
| WBTC | [`0x6bac06600D220Ac5Ac281AD1f504D2Cf0F90F6e6`](https://robinhoodchain.blockscout.com/address/0x6bac06600D220Ac5Ac281AD1f504D2Cf0F90F6e6) | 8 | BTC underlying asset |
| WETH | [`0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`](https://robinhoodchain.blockscout.com/address/0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73) | 18 | ETH underlying asset |

**Paxos USDG is separate from CallPut's internal USDG accounting tokens.** The
existing ABI names `USDC` and `core.usdc` reference Paxos USDG on this chain.

## Verification

| Check | Status |
| --- | --- |
| Standalone compilation | Passed with the settings above |
| Deployment receipts and runtime code | Passed; bootstrap, oracle upgrade and 18 stock pairs |
| Account v6, factory/beacon wiring and admin/keeper roles | Passed |
| Source verification | **110 addresses:** 110 on Blockscout |

Application implementation bytecode matches the standalone build, with immutable
bindings checked on-chain. Transparent proxy and ProxyAdmin shells match the
deployment plugin's bundled OpenZeppelin artifacts
(`@openzeppelin/upgrades-core` `1.40.0`).

All 110 deployed addresses, including proxy shells and the superseded oracle
implementation, are fully source-verified on **Blockscout**.
See the [address-by-address results](deployments/source-verification.json).

See the [deployment verification record](docs/robinhood-mainnet-deployment.md)
for transaction records, runtime hashes and the scope of completed checks.

## Build

```sh
git clone https://github.com/alanxxzero/callput-robinhood-contracts.git
cd callput-robinhood-contracts
npm ci
npm run compile
```

Hardhat uses the pinned local `solc` WASM compiler. After dependency installation,
compilation needs no RPC connection, wallet key or compiler download. The first
optimized build can take several minutes.

## Source

The source contains 126 unchanged Solidity files from CallPut main commit
`928af0840f8c7a081b5db8f90f3dbe1c2824fdbb`, plus the chain-neutral
[`PrimaryOracle`](contracts/oracles/PrimaryOracle.sol) placeholder: **127 files**
in total. The primary feed remains disabled; `VaultPriceFeed` is configured to use
`SpotPriceFeed`. See
[SOURCE.json](SOURCE.json) and the
[changes since the Giwa snapshot](docs/changes-since-giwa.md).

Frontend, relayer, keeper and deployment tooling are maintained separately.
Test utilities included in the source tree are not part of the mainnet deployment.

## License

[MIT](LICENSE). Original per-file license and copyright notices are preserved.
