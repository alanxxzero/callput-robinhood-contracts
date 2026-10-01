// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./BaseToken.sol";
import "./interfaces/IMintable.sol";

contract MintableBaseToken is BaseToken, IMintable {
    mapping (address => bool) public override isMinter;

    event SetMinter(address indexed minter, bool isActive);

    modifier onlyMinter() {
        require(isMinter[msg.sender], "MintableBaseToken: forbidden");
        _;
    }

    function __MintableBaseToken_init__(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        IOptionsAuthority _authority
    ) public initializer {
        __BaseToken_init__(_name, _symbol, _initialSupply, _authority);
    }

    function setMinter(address _minter, bool _isActive) external override onlyAdmin {
        isMinter[_minter] = _isActive;
        emit SetMinter(_minter, _isActive);
    }

    function mint(address _account, uint256 _amount) external override onlyMinter {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override onlyMinter {
        _burn(_account, _amount);
    }
}
