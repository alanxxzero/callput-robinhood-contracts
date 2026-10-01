// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IOlpQueue {
    enum ActionType {
        MINT_AND_STAKE,
        UNSTAKE_AND_REDEEM
    }

    enum ProcessStatus {
        ENQUEUED,
        PROCESSED,
        CANCELLED
    }

    enum CancelMode {
        BY_USER,
        BY_KEEPER
    }

    struct QueueAction {
        ActionType actionType;
        address user;
        address token;
        uint256 amount;
        uint256 minOut;
        address receiver;
        bool isNative; // NAT 사용 여부
        uint40 blockTime;
        ProcessStatus status;
        uint256 amountOut;
        uint40 processBlockTime;
    }

    function queue(uint256 _index) external view returns (QueueAction memory);

    function queueLength() external view returns (uint256);

    function lastProcessedIndex() external view returns (uint256);

    function hasPendingQueue() external view returns (bool);

    function enqueueMintAndStake(
        address _user,
        address _token,
        uint256 _amount,
        uint256 _minOut,
        address _receiver,
        bool _isNative
    ) external returns (uint256);

    function enqueueUnstakeAndRedeem(
        address _user,
        address _tokenOut,
        uint256 _olpAmount,
        uint256 _minOut,
        address _receiver,
        bool _isNative
    ) external returns (uint256);

    function executeQueue(uint256 _endIndex) external;

    function process(uint256 _index) external returns (bool);

    function cancel(uint256 _index, CancelMode _cancelMode) external returns (bool);
}

