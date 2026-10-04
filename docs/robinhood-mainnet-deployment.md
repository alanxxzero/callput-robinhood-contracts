# Robinhood mainnet deployment

This is the historical 2026-10-01 bootstrap inventory, including legacy
contracts. The current service uses one shared USDG liquidity pool (`S_VAULT`);
other vault deployments in this record are not offered as trading pools.
For current functionality and access, see the [README](../README.md#implementation-and-deployment-status).

Deployed on chain **4663** with **236 successful transactions**: 198 bootstrap
transactions, 2 oracle-upgrade transactions and 36 stock-token creations.
Bootstrap checks passed at block **77336947**, oracle checks at **77364304** and
stock-token checks at **77376626**.

The complete history contains 110 contract creations and 126 configuration calls.
There are 84 named contracts and 26 implementation deployments, including the
superseded Base placeholder. Deposit account v6 itself accounts for four
transactions. Each transaction was submitted once; interruptions were reconciled
from existing receipts without redeployment.

The protocol and Deposit account v6 are deployed. Account creation remains under closed admission (`openToAll = false`). This is a contract bootstrap; liquidity, live prices, keepers, relayer, indexer and frontend rollout are separate.

Initial deployer and admin: [`0x542e4610B63FcEDeF7e645dd12D1f7Ddf3d1E64E`](https://robinhoodchain.blockscout.com/address/0x542e4610B63FcEDeF7e645dd12D1f7Ddf3d1E64E). The same address owns ProxyAdmin and controls the account factory. Multisig migration is deferred. The account factory owns its upgradeable beacon.

Total gas paid: **0.002816924745948 ETH**, including the oracle upgrade and stock
tokens. The cumulative reservation remained below the configured 0.02 ETH cap.

## Final additions

- The existing primary-oracle proxy now uses the independent `PrimaryOracle`
  placeholder at `0x66cAAcF4F6635b553B2Ff984DCA1877c0fDAD324`. Its owner,
  authority, proxy address and disabled-primary/enabled-spot configuration are
  unchanged. No new price-feed behavior was introduced.
- All 18 stock/ETF pairs from Base were predeployed using the existing ERC20 and
  OptionsToken sources. The live Base inventory was checked at block **52033640**.
  Underlying supply and options minted amount are zero. Market mappings and
  Controller handlers remain unset; `nextUnderlyingAssetIndex` is still **3**.
  See the [stock address table](../README.md#stock--etf-underlyings-18).

## Addresses

Use the **Address** column for proxy integrations; implementation addresses are published in the [machine-readable manifest](../deployments/robinhood-mainnet.json) with code hashes and all transaction receipts.

| Key | Contract | Address |
| --- | --- | --- |
| `OPTIONS_AUTHORITY` | `OptionsAuthority` | [`0x85e00a193d5E340339484336dd9EA09f942A0b7B`](https://robinhoodchain.blockscout.com/address/0x85e00a193d5E340339484336dd9EA09f942A0b7B) |
| `VAULT_PRICE_FEED` | `VaultPriceFeed` | [`0x2666ce652b1929D4F5a2dBBf094E5DfD38d1b9f1`](https://robinhoodchain.blockscout.com/address/0x2666ce652b1929D4F5a2dBBf094E5DfD38d1b9f1) |
| `OPTIONS_MARKET` | `OptionsMarket` | [`0x3271d35afAc70C0D4989F984Abb2d918bf672C7e`](https://robinhoodchain.blockscout.com/address/0x3271d35afAc70C0D4989F984Abb2d918bf672C7e) |
| `S_VAULT` | `Vault` | [`0x21bA39e9394657A6196f6948C2701D9fD9612289`](https://robinhoodchain.blockscout.com/address/0x21bA39e9394657A6196f6948C2701D9fD9612289) |
| `M_VAULT` | `Vault` | [`0xA60e4A30c8D56C81c7E7c607a9E092cEb25241eE`](https://robinhoodchain.blockscout.com/address/0xA60e4A30c8D56C81c7E7c607a9E092cEb25241eE) |
| `L_VAULT` | `Vault` | [`0xCaf6Cf834Dc1b0C86206B6e9E797f5D27ca63897`](https://robinhoodchain.blockscout.com/address/0xCaf6Cf834Dc1b0C86206B6e9E797f5D27ca63897) |
| `S_VAULT_UTILS` | `VaultUtils` | [`0xfB970601A11254bA465fE52eC88546299E1E002c`](https://robinhoodchain.blockscout.com/address/0xfB970601A11254bA465fE52eC88546299E1E002c) |
| `M_VAULT_UTILS` | `VaultUtils` | [`0x5B52c79Cc4E7c09BF51716C37fd6301aEB793066`](https://robinhoodchain.blockscout.com/address/0x5B52c79Cc4E7c09BF51716C37fd6301aEB793066) |
| `L_VAULT_UTILS` | `VaultUtils` | [`0x05cfa0574F4daA5B2d3Fd9E6c25ffe725f38b573`](https://robinhoodchain.blockscout.com/address/0x05cfa0574F4daA5B2d3Fd9E6c25ffe725f38b573) |
| `CONTROLLER` | `Controller` | [`0x0D240c1EbEeE7F74B40d6611326f5df98AB00e1B`](https://robinhoodchain.blockscout.com/address/0x0D240c1EbEeE7F74B40d6611326f5df98AB00e1B) |
| `S_USDG` | `USDG` | [`0xb4193D3618E45231A3D4a73600170ef5cbF62E0F`](https://robinhoodchain.blockscout.com/address/0xb4193D3618E45231A3D4a73600170ef5cbF62E0F) |
| `PROXY_ADMIN` | `ProxyAdmin` | [`0x182aA7Cb0Eab75E33ee861902B5C49Ae2dD0ce10`](https://robinhoodchain.blockscout.com/address/0x182aA7Cb0Eab75E33ee861902B5C49Ae2dD0ce10) |
| `M_USDG` | `USDG` | [`0x4E4E9EF8f0170fb9190608816068610E6e9D9184`](https://robinhoodchain.blockscout.com/address/0x4E4E9EF8f0170fb9190608816068610E6e9D9184) |
| `L_USDG` | `USDG` | [`0x42A7D4dcd0c84ee14547d3C738D40C14D7f66fA4`](https://robinhoodchain.blockscout.com/address/0x42A7D4dcd0c84ee14547d3C738D40C14D7f66fA4) |
| `S_OLP` | `OLP` | [`0x463811B783f53c7adf01Bc51aFb7880b6d95A5d5`](https://robinhoodchain.blockscout.com/address/0x463811B783f53c7adf01Bc51aFb7880b6d95A5d5) |
| `M_OLP` | `OLP` | [`0xcc0BA1Bbc4D0625bDb6c16A935bF1317788d39D1`](https://robinhoodchain.blockscout.com/address/0xcc0BA1Bbc4D0625bDb6c16A935bF1317788d39D1) |
| `L_OLP` | `OLP` | [`0xc163528C97d005b70095E2DD20e582F6408Cc96c`](https://robinhoodchain.blockscout.com/address/0xc163528C97d005b70095E2DD20e582F6408Cc96c) |
| `S_OLP_MANAGER` | `OlpManager` | [`0xbed7fB763bb9391e45AD2c70FE19887CAD7Ec9B8`](https://robinhoodchain.blockscout.com/address/0xbed7fB763bb9391e45AD2c70FE19887CAD7Ec9B8) |
| `M_OLP_MANAGER` | `OlpManager` | [`0x7eBbdF7ffCaB33e244D465E7FA08756Fd7F7738b`](https://robinhoodchain.blockscout.com/address/0x7eBbdF7ffCaB33e244D465E7FA08756Fd7F7738b) |
| `L_OLP_MANAGER` | `OlpManager` | [`0x887Af039C15CCe9636195C80254B46a8Faf03FDc`](https://robinhoodchain.blockscout.com/address/0x887Af039C15CCe9636195C80254B46a8Faf03FDc) |
| `S_REWARD_TRACKER` | `RewardTracker` | [`0x6b8979E1662a1e7524ecBBA625AA31cf87247Ea5`](https://robinhoodchain.blockscout.com/address/0x6b8979E1662a1e7524ecBBA625AA31cf87247Ea5) |
| `M_REWARD_TRACKER` | `RewardTracker` | [`0xC7223e6F948C0804D62FfC4FD33A02225A743A1D`](https://robinhoodchain.blockscout.com/address/0xC7223e6F948C0804D62FfC4FD33A02225A743A1D) |
| `L_REWARD_TRACKER` | `RewardTracker` | [`0x0899213428E3eF7f1D590e37BF8363E19Cc27f4e`](https://robinhoodchain.blockscout.com/address/0x0899213428E3eF7f1D590e37BF8363E19Cc27f4e) |
| `S_REWARD_DISTRIBUTOR` | `RewardDistributor` | [`0xD339d220bb30603e66cf15394657C9cAaC97274E`](https://robinhoodchain.blockscout.com/address/0xD339d220bb30603e66cf15394657C9cAaC97274E) |
| `M_REWARD_DISTRIBUTOR` | `RewardDistributor` | [`0x30654838D2f3F3Ba475dd53a24Ce3aed3d4280DE`](https://robinhoodchain.blockscout.com/address/0x30654838D2f3F3Ba475dd53a24Ce3aed3d4280DE) |
| `L_REWARD_DISTRIBUTOR` | `RewardDistributor` | [`0x9C8DDe98a6b09fD484eBFB74C2A016148B0D7378`](https://robinhoodchain.blockscout.com/address/0x9C8DDe98a6b09fD484eBFB74C2A016148B0D7378) |
| `S_REWARD_ROUTER_V2` | `RewardRouterV2` | [`0x0BA1292c9e205c0a12d926406b0ab5bc3EF879f0`](https://robinhoodchain.blockscout.com/address/0x0BA1292c9e205c0a12d926406b0ab5bc3EF879f0) |
| `M_REWARD_ROUTER_V2` | `RewardRouterV2` | [`0x95420DdB175A1550f5fC66Ca5847352B53b6E0cA`](https://robinhoodchain.blockscout.com/address/0x95420DdB175A1550f5fC66Ca5847352B53b6E0cA) |
| `L_REWARD_ROUTER_V2` | `RewardRouterV2` | [`0x366c7f855d9bc013da3F9aC10C98b3F4EF7A5Ed8`](https://robinhoodchain.blockscout.com/address/0x366c7f855d9bc013da3F9aC10C98b3F4EF7A5Ed8) |
| `S_OLP_QUEUE` | `OlpQueue` | [`0xFC121FEaAAf0bEdc93E5Da7a9C7D161357C89e16`](https://robinhoodchain.blockscout.com/address/0xFC121FEaAAf0bEdc93E5Da7a9C7D161357C89e16) |
| `M_OLP_QUEUE` | `OlpQueue` | [`0x95D1013be04e2D7da6C7E6e96fbC4dAE16Ee23F2`](https://robinhoodchain.blockscout.com/address/0x95D1013be04e2D7da6C7E6e96fbC4dAE16Ee23F2) |
| `L_OLP_QUEUE` | `OlpQueue` | [`0xF82fb623BEE693351bD7099Cc3650FBE46FB8349`](https://robinhoodchain.blockscout.com/address/0xF82fb623BEE693351bD7099Cc3650FBE46FB8349) |
| `POSITION_MANAGER` | `PositionManager` | [`0x426a6b482893557E58cF38de635fEbB30Fd6a3C3`](https://robinhoodchain.blockscout.com/address/0x426a6b482893557E58cF38de635fEbB30Fd6a3C3) |
| `SETTLE_MANAGER` | `SettleManager` | [`0xd328D581f3Fb1Ca86D28D573bA1f17409e5112EF`](https://robinhoodchain.blockscout.com/address/0xd328D581f3Fb1Ca86D28D573bA1f17409e5112EF) |
| `FEE_DISTRIBUTOR` | `FeeDistributor` | [`0x42260a98bc6e1AA2f4CEC5508146d713BfD72c41`](https://robinhoodchain.blockscout.com/address/0x42260a98bc6e1AA2f4CEC5508146d713BfD72c41) |
| `BTC_OPTIONS_TOKEN` | `OptionsToken` | [`0x080084D6A1e9b6657EDc8DBa071BAa9D15Fcc500`](https://robinhoodchain.blockscout.com/address/0x080084D6A1e9b6657EDc8DBa071BAa9D15Fcc500) |
| `ETH_OPTIONS_TOKEN` | `OptionsToken` | [`0x84D4ef4062E00F78B0Ea5aaC06D7D08Ab1258B02`](https://robinhoodchain.blockscout.com/address/0x84D4ef4062E00F78B0Ea5aaC06D7D08Ab1258B02) |
| `FAST_PRICE_EVENTS` | `FastPriceEvents` | [`0x1e5A834eb298288E28C07b6f2369e0008a5d156C`](https://robinhoodchain.blockscout.com/address/0x1e5A834eb298288E28C07b6f2369e0008a5d156C) |
| `FAST_PRICE_FEED` | `FastPriceFeed` | [`0xA936FCaD3C5CDda9106F72499729877E9dF5918a`](https://robinhoodchain.blockscout.com/address/0xA936FCaD3C5CDda9106F72499729877E9dF5918a) |
| `POSITION_VALUE_FEED` | `PositionValueFeed` | [`0x32847298142A9E692EfE1c259aADe4f260bDe94C`](https://robinhoodchain.blockscout.com/address/0x32847298142A9E692EfE1c259aADe4f260bDe94C) |
| `SETTLE_PRICE_FEED` | `SettlePriceFeed` | [`0xB51EC03d51e8880FDc2A24f918072694516FB626`](https://robinhoodchain.blockscout.com/address/0xB51EC03d51e8880FDc2A24f918072694516FB626) |
| `SPOT_PRICE_FEED` | `SpotPriceFeed` | [`0x2318040e26791777d675cFeF87FE25BDcE36439A`](https://robinhoodchain.blockscout.com/address/0x2318040e26791777d675cFeF87FE25BDcE36439A) |
| `PRIMARY_ORACLE` | `PrimaryOracle` | [`0x9D1e3c557F3E3078dCBd8ac77Dfe1950db9B8c0B`](https://robinhoodchain.blockscout.com/address/0x9D1e3c557F3E3078dCBd8ac77Dfe1950db9B8c0B) |
| `VIEW_AGGREGATOR` | `ViewAggregator` | [`0xf277D41cc8093667bf1A023f4FBbeB8328900bb7`](https://robinhoodchain.blockscout.com/address/0xf277D41cc8093667bf1A023f4FBbeB8328900bb7) |
| `REFERRAL` | `Referral` | [`0xBa64c819A8C5a80E51ce5f929C3BF08DD187D6c9`](https://robinhoodchain.blockscout.com/address/0xBa64c819A8C5a80E51ce5f929C3BF08DD187D6c9) |
| `TRADING_ACCOUNT_IMPL` | `TradingAccountSessionImpl` | [`0x2436A7575cf8A3289c7A07154f89f05660756312`](https://robinhoodchain.blockscout.com/address/0x2436A7575cf8A3289c7A07154f89f05660756312) |
| `TRADING_ACCOUNT_BEACON` | `UpgradeableBeacon` | [`0x5685d4DD5114c74C805322d4612CA5D73EAcdc62`](https://robinhoodchain.blockscout.com/address/0x5685d4DD5114c74C805322d4612CA5D73EAcdc62) |
| `TRADING_ACCOUNT_FACTORY` | `TradingAccountFactory` | [`0xbcaC622Bb396B2f868b37D7C41F34695c9be1862`](https://robinhoodchain.blockscout.com/address/0xbcaC622Bb396B2f868b37D7C41F34695c9be1862) |

## Existing external tokens

| Token | Decimals | Address |
| --- | --- | --- |
| PAXOS_USDG | 6 | [`0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`](https://robinhoodchain.blockscout.com/address/0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168) |
| WBTC | 8 | [`0x6bac06600D220Ac5Ac281AD1f504D2Cf0F90F6e6`](https://robinhoodchain.blockscout.com/address/0x6bac06600D220Ac5Ac281AD1f504D2Cf0F90F6e6) |
| WETH | 18 | [`0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`](https://robinhoodchain.blockscout.com/address/0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73) |

Paxos USDG is the external deposit and settlement asset. The unchanged ABI names `USDC` and `core.usdc` reference that token. `S_USDG`, `M_USDG` and `L_USDG` are separate 18-decimal CallPut accounting tokens. WBTC and WETH are existing underlying asset identifiers, not new CallPut token deployments.

## Verification

- Every transaction receipt, nonce, calldata hash and canonical block matched the deployment record.
- All 48 bootstrap contracts matched their expected runtime code. Proxy implementation bytecode matches the public build; immutable bindings were checked through getters.
- Transparent proxy and ProxyAdmin shells match the OpenZeppelin upgrades plugin’s bundled artifacts (`@openzeppelin/upgrades-core` 1.40.0), which differ from locally recompiled shells. Application implementations use the compiler settings in the README.
- Admin and keeper roles, v6 factory/beacon wiring, closed admission and external/internal USDG configuration passed read-only mainnet checks.
- The oracle upgrade preserves the previous storage and settings. All 36 stock
  creations match their exact constructor/initializer data and runtime code;
  receipts and canonical blocks were independently rechecked.

All 110 creation addresses are fully source-verified on Blockscout; see the
[per-address verification results](../deployments/source-verification.json).
Checks confirm each address's own full verification, not source displayed from
a verified twin. No source registrations remain pending.

Nonzero real-USDG funding, smart-wallet funding and live trading were not exercised
in this bootstrap; local mock-token deposit/withdrawal rehearsal passed. This
record is not an independent protocol audit.
