// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IOptionsToken.sol";
import "../interfaces/IOptionsMarket.sol";
import "./erc1155/ERC1155Base.sol";
import "./erc1155/ERC1155Enumerable.sol";
import "./introspection/ERC165Base.sol";
import "./ERC20.sol";
import "../AuthorityUtil.sol";
import "../proxy/OwnableUpgradeable.sol";
import "../proxy/ReentrancyGuardUpgradeable.sol";
import "../Utils.sol";

contract OptionsToken is
    IOptionsToken,
    ERC1155Base,
    ERC1155Enumerable,
    ERC165Base,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    AuthorityUtil
{   
    string private _name;
    address private _underlyingAsset;

    address public optionsMarket;
    address public vaultPriceFeed;

    uint256 public totalMintedAmount;

    mapping (uint256 => uint256) public mintedAmount; // optionTokenId => mintedAmount

    mapping (address => bool) public isHandler;

    event SetHandler(address indexed handler, bool isActive);

    function initialize(
        string memory _tokenName, // "BTC-USD Options", "ETH-USD Options"
        address _tokenUnderlyingAsset,
        address _optionsMarket,
        address _vaultPriceFeed,
        IOptionsAuthority _authority
    ) public initializer {
        require(
            _tokenUnderlyingAsset != address(0) &&
            _optionsMarket != address(0) &&
            _vaultPriceFeed != address(0),
            "OptionsToken: invalid addresses"
        );

        __Ownable_init();
        __ReentrancyGuard_init();
        __AuthorityUtil_init__(_authority);

        _name = _tokenName;
        
        _underlyingAsset = _tokenUnderlyingAsset;

        optionsMarket = _optionsMarket;
        vaultPriceFeed = _vaultPriceFeed;
    }

    function setHandler(address _handler, bool _isActive) external onlyAdmin {
        isHandler[_handler] = _isActive;
        emit SetHandler(_handler, _isActive);
    }

    function mint(
        address account,
        uint256 id,
        uint256 amount
    ) public virtual onlyController {
        _mint(account, id, amount, "");

        mintedAmount[id] += amount;
        totalMintedAmount += amount;
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        if (isHandler[msg.sender]) {
            _safeTransfer(msg.sender, from, to, id, amount, data);
            return;
        }

        if (from != msg.sender && !isApprovedForAll(from, msg.sender))
            revert ERC1155Base__NotOwnerOrApproved();
        _safeTransfer(msg.sender, from, to, id, amount, data);
    }

    // @dev Will be called only when (settle, clearing)
    function burn(
        address account,
        uint256 id,
        uint256 amount
    ) public virtual onlyController {
        _burn(account, id, amount);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function underlyingAsset() public view override returns (address) {
        return _underlyingAsset;
    }
    
    function decimals() public view override returns (uint8) {
        return ERC20(_underlyingAsset).decimals();
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
        internal
        virtual
        override(ERC1155BaseInternal, ERC1155EnumerableInternal)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
