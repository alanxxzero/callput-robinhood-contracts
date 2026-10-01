// contracts/ProxyAdmin.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract MyProxyAdmin is ProxyAdmin {
    constructor() ProxyAdmin() {}
}