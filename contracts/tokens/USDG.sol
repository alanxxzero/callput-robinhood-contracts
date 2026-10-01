// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IUSDG.sol";
import "./YieldToken.sol";

import "../proxy/OwnableUpgradeable.sol";

contract USDG is YieldToken, IUSDG, OwnableUpgradeable {
    mapping (address => bool) public vaults;

    event SetVault(address indexed vault, bool isVault);

    modifier onlyVault() {
        require(vaults[msg.sender], "USDG: forbidden");
        _;
    }

    function initialize(
        address _vault,
        string memory _name,
        string memory _symbol,
        IOptionsAuthority _authority
    ) public initializer {
        require(_vault != address(0), "USDG: invalid address");

        __Ownable_init();
        __YieldToken_init__(_name, _symbol, 0, _authority);

        vaults[_vault] = true;
    }

    function setVault(address _vault, bool _isVault) external override onlyAdmin {
        require(_vault != address(0), "USDG: invalid vault");
        vaults[_vault] = _isVault;

        emit SetVault(_vault, _isVault);
    }
    
    function mint(address _account, uint256 _amount) external override onlyVault {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external override onlyVault {
        _burn(_account, _amount);
    }
}
