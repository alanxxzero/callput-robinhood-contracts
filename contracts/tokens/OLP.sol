// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./MintableBaseToken.sol";

import "../proxy/OwnableUpgradeable.sol";

contract OLP is MintableBaseToken, OwnableUpgradeable {
    function initialize(
        string memory _name,
        string memory _symbol,
        IOptionsAuthority _authority
    ) public initializer {
        __Ownable_init();
        __MintableBaseToken_init__(_name, _symbol, 0, _authority);
    }

    function id() external view returns (string memory) {
        return symbol;
    }
}
