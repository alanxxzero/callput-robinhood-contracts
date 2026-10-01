// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// Artifact-only import: makes Hardhat compile OpenZeppelin 4.9.6 `UpgradeableBeacon` (used unmodified as
// the TradingAccount beacon, owner = Safe) so `scripts/deploy/deployContracts/deployTradingAccount.ts`
// can fetch it with its fully qualified name. No code of our own lives here.
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
