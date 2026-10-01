// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./libraries/Address.sol";

import "./interfaces/IOptionsMarket.sol";
import "./interfaces/IBasePositionManager.sol";
import "./interfaces/IController.sol";
import "./interfaces/IVault.sol";

import "./tokens/interfaces/IWNAT.sol";
import "./tokens/interfaces/IERC20.sol";
import "./tokens/libraries/SafeERC20.sol";
import "./tokens/interfaces/IOptionsToken.sol";

import "./AuthorityUtil.sol";
import "./Utils.sol";

import "./proxy/ReentrancyGuardUpgradeable.sol";

contract BasePositionManager is IBasePositionManager, ReentrancyGuardUpgradeable, AuthorityUtil {
    using SafeERC20 for IERC20;
    using Address for address payable;

    // @desc The address of the wrapped native token (WNAT)
    // @info
    // - For Arbitrum, WNAT is the wrapped ETH token
    // - For Berachain, WNAT is the wrapped BERA token
    address public wnat;

    address public optionsMarket;
    address public controller;

    uint256 public natTransferGasLimit;

    error ZeroAddress();
    error InvalidNatSender();
    error InvalidSwapPathLength();
    error InsufficientAmountOut();

    event SetNatTransferGasLimit(uint256 indexed natTransferGasLimit);

    function __BasePositionManager_init__(
        address _optionsMarket,
        address _controller,
        address _wnat,
        IOptionsAuthority _authority
    ) public initializer {
        __ReentrancyGuard_init();
        __AuthorityUtil_init__(_authority);

        if (
            _optionsMarket == address(0) ||
            _controller == address(0) ||
            _wnat == address(0)
        ) revert ZeroAddress();

        optionsMarket = _optionsMarket;
        controller = _controller;
        wnat = _wnat;

        natTransferGasLimit = 500_000;
    }

    receive() external payable {
        if (msg.sender != wnat) revert InvalidNatSender();
    }

    function setNatTransferGasLimit(uint256 _natTransferGasLimit) external onlyAdmin {
        natTransferGasLimit = _natTransferGasLimit;
        emit SetNatTransferGasLimit(_natTransferGasLimit);
    }

    function approve(address _token, address _spender, uint256 _amount) external onlyAdmin {
        IERC20(_token).approve(_spender, _amount);
    }

    function sendValue(address payable _receiver, uint256 _amount) external onlyAdmin {
        _receiver.sendValue(_amount);
    }

    function _swap(address _vault, address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver) internal returns (uint256) {
        IERC20(_path[0]).safeTransfer(_vault, _amountIn);
        if (_path.length != 2) revert InvalidSwapPathLength();
        return _vaultSwap(_vault, _path[0], _path[1], _minOut, _receiver);
    }

    function _vaultSwap(address _vault, address _tokenIn, address _tokenOut, uint256 _minOut, address _receiver) internal returns (uint256) {
        uint256 amountOut = IVault(_vault).swap(_tokenIn, _tokenOut, _receiver);
        if (amountOut < _minOut) revert InsufficientAmountOut();
        return amountOut;
    }

    function _transferInNAT() internal {
        if (msg.value != 0) {
            IWNAT(wnat).deposit{value: msg.value}();
        }
    }

    function _transferOutNATWithGasLimitFallbackToWnat(uint256 _amountOut, address payable _receiver) internal {
        IWNAT _wnat = IWNAT(wnat);
        _wnat.withdraw(_amountOut);

        // re-assign natTransferGasLimit since only local variables
        // can be used in assembly calls
        uint256 _natTransferGasLimit = natTransferGasLimit;

        bool success;
        // use an assembly call to avoid loading large data into memory
        // input mem[in…(in+insize)]
        // output area mem[out…(out+outsize))]
        assembly {
            success := call(
                _natTransferGasLimit, // gas limit
                _receiver, // receiver
                _amountOut, // value
                0, // in
                0, // insize
                0, // out
                0 // outsize
            )
        }

        if (success) { return; }

        // if the transfer failed, re-wrap the token and send it to the receiver
        _wnat.deposit{ value: _amountOut }();
        _wnat.transfer(address(_receiver), _amountOut);
    }
}
