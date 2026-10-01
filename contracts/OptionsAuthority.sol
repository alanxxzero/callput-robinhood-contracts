// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IOptionsAuthority.sol";
import "./proxy/OwnableUpgradeable.sol";

contract OptionsAuthority is IOptionsAuthority, OwnableUpgradeable {
    mapping(address => bool) public override isAdmin;
    mapping(address => bool) public override isKeeper;
    mapping(address => bool) public override isPositionKeeper;
    mapping(address => bool) public override isFastPriceFeed;
    mapping(address => bool) public override isController;
    mapping(address => bool) public override isFeeDistributor;

    event SetAdmin(address indexed _admin, bool _isAdmin);
    event SetKeeper(address indexed _keeper, bool _isKeeper);
    event SetPositionKeeper(address indexed _positionKeeper, bool _isPositionKeeper);
    event SetFastPriceFeed(address indexed _fastPriceFeed, bool _isFastPriceFeed);
    event SetController(address indexed _controller, bool _isController);
    event SetFeeDistributor(address indexed _feeDistributor, bool _isFeeDistributor);

    modifier onlyAdmin() {
        require(isAdmin[msg.sender], "only admin");
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
        isAdmin[msg.sender] = true;
    }

    function setAdmin(address _admin, bool _isAdmin) public onlyOwner {
        isAdmin[_admin] = _isAdmin;
        emit SetAdmin(_admin, _isAdmin);
    }

    // (EOA) Keeper
    function setKeeper(address _keeper, bool _isKeeper) public onlyAdmin {
        isKeeper[_keeper] = _isKeeper;
        emit SetKeeper(_keeper, _isKeeper);
    }

    function setPositionKeeper(address _positionKeeper, bool _isPositionKeeper) public onlyAdmin {
        isPositionKeeper[_positionKeeper] = _isPositionKeeper;
        emit SetPositionKeeper(_positionKeeper, _isPositionKeeper);
    }   

    function setFastPriceFeed(address _fastPriceFeed, bool _isFastPriceFeed) public onlyAdmin {
        isFastPriceFeed[_fastPriceFeed] = _isFastPriceFeed;
        emit SetFastPriceFeed(_fastPriceFeed, _isFastPriceFeed);
    }

    function setController(address _controller, bool _isController) public onlyAdmin {
        isController[_controller] = _isController;
        emit SetController(_controller, _isController);
    }
    
    function setFeeDistributor(address _feeDistributor, bool _isFeeDistributor) public onlyAdmin {
        isFeeDistributor[_feeDistributor] = _isFeeDistributor;
        emit SetFeeDistributor(_feeDistributor, _isFeeDistributor);
    }
}
