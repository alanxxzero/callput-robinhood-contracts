// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IRewardRouterV2 {
    enum EpochStage {
        REQUEST_SUBMISSION, // 0
        QUEUE_PROCESSING // 1
    }

    function wnat() external view returns (address);
    function olp() external view returns (address);
    function feeOlpTracker() external view returns (address);
    function olpManager() external view returns (address);
    function olpQueue() external view returns (address);
    function controller() external view returns (address);

    function epochStage() external view returns (EpochStage);
    function epochRound() external view returns (uint256);

    function mintAndStakeOlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minOlp) external returns (uint256);
    function mintAndStakeOlpNAT(uint256 _minUsdg, uint256 _minOlp) external payable returns (uint256);
    function submitMintAndStakeOlp(address _token, uint256 _amount, uint256 _minOut, address payable _receiver, bool _isNative) external payable returns (uint256);
    function processMintAndStakeOlp(address _token, uint256 _amount, uint256 _minOut, address _receiver) external returns (uint256);

    function unstakeAndRedeemOlp(address _tokenOut, uint256 _olpAmount, uint256 _minOut, address _receiver) external returns (uint256);
    function unstakeAndRedeemOlpNAT(uint256 _olpAmount, uint256 _minOut, address payable _receiver) external returns (uint256);
    function submitUnstakeAndRedeemOlp(address _tokenOut, uint256 _olpAmount, uint256 _minOut, address _receiver, bool _isNative) external returns (uint256);
    function processUnstakeAndRedeemOlp(address _account, address _tokenOut, uint256 _olpAmount, uint256 _minOut, address payable _receiver, bool _isNative) external returns (uint256);

    function handleRewards(
        bool _shouldClaimReward, // will be always true
        bool _shouldConvertRewardToNAT
    ) external;
}
