// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IPositionManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IOlpManager.sol";
import "./interfaces/IRewardDistributor.sol";
import "./tokens/interfaces/IERC20.sol";
import "./oracles/interfaces/IVaultPriceFeed.sol";
import "./AuthorityUtil.sol";
import "./proxy/OwnableUpgradeable.sol";
import "./Utils.sol";

contract ViewAggregator is OwnableUpgradeable, AuthorityUtil {
  struct PositionRequestInfo {
    uint256 requestIndex;
    bool isOpen;
    address account;
    uint256 optionTokenId;
    uint256 amountInOrSize; // amountIn for open position, size for close position
    uint40 blockTime;
    IPositionManager.RequestStatus status;
    uint256 sizeOutOrAmountOut; // sizeOut for open position, amountOut for close position
    uint256 executionPrice;
    uint40 processBlockTime;
    address path0;
    address path1;
  }

  IPositionManager public positionManager;
  IVaultPriceFeed public vaultPriceFeed;

  IVault[3] public vaults;
  IERC20[3] public olps;
  IOlpManager[3] public olpManagers;
  IRewardDistributor[3] public rewardDistributors;
  IVaultUtils[3] public vaultUtils;

  event SetPositionManager(address indexed positionManager);
  event SetVaultPriceFeed(address indexed vaultPriceFeed);

  function initialize(
    address _authority,
    address _positionManager,
    address _vaultPriceFeed,
    address[3] memory _vaults,
    address[3] memory _olps,
    address[3] memory _olpManagers,
    address[3] memory _rewardDistributors,
    address[3] memory _vaultUtils
  ) public initializer {
    require(
      _authority != address(0) &&
      _positionManager != address(0) &&
      _vaultPriceFeed != address(0),
      "ViewAggregator: invalid addresses"
    );
    
    __Ownable_init();
    __AuthorityUtil_init__(IOptionsAuthority(_authority));

    positionManager = IPositionManager(_positionManager);
    vaultPriceFeed = IVaultPriceFeed(_vaultPriceFeed);

    for (uint256 i = 0; i < 3;) {
      require(
        _vaults[i] != address(0) &&
        _olps[i] != address(0) &&
        _olpManagers[i] != address(0) &&
        _rewardDistributors[i] != address(0) &&
        _vaultUtils[i] != address(0),
        "ViewAggregator: invalid addresses"
      );

      vaults[i] = IVault(_vaults[i]);
      olps[i] = IERC20(_olps[i]);
      olpManagers[i] = IOlpManager(_olpManagers[i]);
      rewardDistributors[i] = IRewardDistributor(_rewardDistributors[i]);
      vaultUtils[i] = IVaultUtils(_vaultUtils[i]);

      unchecked { i++; }
    }
  }
  
  function setPositionManager(address _positionManager) external onlyAdmin {
    require(_positionManager != address(0), "ViewAggregator: invalid positionManager");
    positionManager = IPositionManager(_positionManager);
  }

  function setVaultPriceFeed(address _vaultPriceFeed) external onlyAdmin {
      require(_vaultPriceFeed != address(0), "ViewAggregator: invalid vaultPriceFeed");
      vaultPriceFeed = IVaultPriceFeed(_vaultPriceFeed);
      emit SetVaultPriceFeed(_vaultPriceFeed);
  }

  function setVault(uint256 _index, address _vault, address _olp, address _olpManager, address _rewardDistributor, address _vaultUtils) public onlyOwner {
    require(
      _vault != address(0) &&
      _olp != address(0) &&
      _olpManager != address(0) &&
      _rewardDistributor != address(0) &&
      _vaultUtils != address(0),
      "ViewAggregator: invalid addresses"
    );
    
    vaults[_index] = IVault(_vault);
    olps[_index] = IERC20(_olp);
    olpManagers[_index] = IOlpManager(_olpManager);
    rewardDistributors[_index] = IRewardDistributor(_rewardDistributor);
    vaultUtils[_index] = IVaultUtils(_vaultUtils);
  }

  function getVaultAddress(uint256 _index) public view returns (address) {
    return address(vaults[_index]);
  }

  function getOlpAddress(uint256 _index) public view returns (address) {
    return address(olps[_index]);
  }

  function getOlpManagerAddress(uint256 _index) public view returns (address) {
    return address(olpManagers[_index]);
  }

  function positionRequestInfo(uint256 _maxItem) public view returns (PositionRequestInfo[] memory) {
    (uint256 positionRequestKeysStart, uint256 positionRequestKeysLength, ) = positionManager.getRequestQueueLengths();

    uint256 endIndex = positionRequestKeysStart + _maxItem;
    
    if (endIndex > positionRequestKeysLength) {
      endIndex = positionRequestKeysLength;
    }

    uint256 itemCounter;
    unchecked {
      itemCounter = endIndex - positionRequestKeysStart;
    }

    PositionRequestInfo[] memory result = new PositionRequestInfo[](itemCounter);

    for (uint256 i = positionRequestKeysStart; i < endIndex;) {
      bytes32 key = positionManager.positionRequestKeys(i);
      bool isOpen = positionManager.positionRequestTypes(i);
      
      if (isOpen) {
        (
          address account,
          ,
          ,
          uint256 optionTokenId,
          ,
          uint256 amountIn,
          ,
          ,
          uint40 blockTime,
          IPositionManager.RequestStatus status,
          uint256 sizeOut,
          uint256 executionPrice,
          uint40 processBlockTime
          ,
        ) = positionManager.openPositionRequests(key);
        
        address[] memory path = positionManager.getOpenPositionRequestPath(key);
        address path0 = path[0];
        address path1 = path.length > 1 ? path[1] : address(0);

        PositionRequestInfo memory nextRequest;
        nextRequest.requestIndex = i;
        nextRequest.isOpen = isOpen;
        nextRequest.account = account;
        nextRequest.optionTokenId = optionTokenId;
        nextRequest.amountInOrSize = amountIn;
        nextRequest.blockTime = blockTime;
        nextRequest.status = status;
        nextRequest.sizeOutOrAmountOut = sizeOut;
        nextRequest.executionPrice = executionPrice;
        nextRequest.processBlockTime = processBlockTime;
        nextRequest.path0 = path0;
        nextRequest.path1 = path1;

        result[i - positionRequestKeysStart] = nextRequest;
      } else {
        (
          address account,
          ,,
          uint256 optionTokenId,
          uint256 size,
          ,,,
          uint40 blockTime,
          IPositionManager.RequestStatus status,
          uint256 amountOut,
          uint256 executionPrice,
          uint40 processBlockTime
        ) = positionManager.closePositionRequests(key);

        address[] memory path = positionManager.getClosePositionRequestPath(key);
        address path0 = path[0];
        address path1 = path.length > 1 ? path[1] : address(0);

        PositionRequestInfo memory nextRequest;
        nextRequest.requestIndex = i;
        nextRequest.isOpen = isOpen;
        nextRequest.account = account;
        nextRequest.optionTokenId = optionTokenId;
        nextRequest.amountInOrSize = size;
        nextRequest.blockTime = blockTime;
        nextRequest.status = status;
        nextRequest.sizeOutOrAmountOut = amountOut;
        nextRequest.executionPrice = executionPrice;
        nextRequest.processBlockTime = processBlockTime;
        nextRequest.path0 = path0;
        nextRequest.path1 = path1;

        result[i - positionRequestKeysStart] = nextRequest;
      }

      unchecked { i++; }
    }

    return result;
  }

  function positionRequestInfoWithRange(uint256 _startIndex, uint256 _maxItem) public view returns (PositionRequestInfo[] memory) {
    (, uint256 positionRequestKeysLength, ) = positionManager.getRequestQueueLengths();

    uint256 endIndex = _startIndex + _maxItem;
    
    if (endIndex > positionRequestKeysLength) {
      endIndex = positionRequestKeysLength;
    }

    PositionRequestInfo[] memory result = new PositionRequestInfo[](endIndex - _startIndex);

    for (uint256 i = _startIndex; i < endIndex;) {
      bytes32 key = positionManager.positionRequestKeys(i);
      bool isOpen = positionManager.positionRequestTypes(i);

      if (isOpen) {
        (
          address account,
          ,,
          uint256 optionTokenId,
          ,
          uint256 amountIn,
          ,,
          uint40 blockTime,
          IPositionManager.RequestStatus status,
          uint256 sizeOut,
          uint256 executionPrice,
          uint40 processBlockTime
          ,
        ) = positionManager.openPositionRequests(key);

        address[] memory path = positionManager.getOpenPositionRequestPath(key);
        address path0 = path[0];
        address path1 = path.length > 1 ? path[1] : address(0);

        PositionRequestInfo memory nextRequest;
        nextRequest.requestIndex = i;
        nextRequest.isOpen = isOpen;
        nextRequest.account = account;
        nextRequest.optionTokenId = optionTokenId;
        nextRequest.amountInOrSize = amountIn;
        nextRequest.blockTime = blockTime;
        nextRequest.status = status;
        nextRequest.sizeOutOrAmountOut = sizeOut;
        nextRequest.executionPrice = executionPrice;
        nextRequest.processBlockTime = processBlockTime;
        nextRequest.path0 = path0;
        nextRequest.path1 = path1;

        result[i - _startIndex] = nextRequest;
      } else {
        (
          address account,
          ,,
          uint256 optionTokenId,
          uint256 size,
          ,,,
          uint40 blockTime,
          IPositionManager.RequestStatus status,
          uint256 amountOut,
          uint256 executionPrice,
          uint40 processBlockTime
        ) = positionManager.closePositionRequests(key);

        address[] memory path = positionManager.getClosePositionRequestPath(key);
        address path0 = path[0];
        address path1 = path.length > 1 ? path[1] : address(0);

        PositionRequestInfo memory nextRequest;
        nextRequest.requestIndex = i;
        nextRequest.isOpen = isOpen;
        nextRequest.account = account;
        nextRequest.optionTokenId = optionTokenId;
        nextRequest.amountInOrSize = size;
        nextRequest.blockTime = blockTime;
        nextRequest.status = status;
        nextRequest.sizeOutOrAmountOut = amountOut;
        nextRequest.executionPrice = executionPrice;
        nextRequest.processBlockTime = processBlockTime;
        nextRequest.path0 = path0;
        nextRequest.path1 = path1;

        result[i - _startIndex] = nextRequest;
      }

      unchecked { i++; }
    }

    return result;
  }

  function positionRequestInfoWithOlpUtilityRatio(uint256 _maxItem) public view returns (
    PositionRequestInfo[] memory,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256
  ) {
    (uint256 positionRequestKeysStart, uint256 positionRequestKeysLength, ) = positionManager.getRequestQueueLengths();

    uint256 endIndex = positionRequestKeysStart + _maxItem;
    
    if (endIndex > positionRequestKeysLength) {
      endIndex = positionRequestKeysLength;
    }

    PositionRequestInfo[] memory result = new PositionRequestInfo[](endIndex - positionRequestKeysStart);

    for (uint256 i = positionRequestKeysStart; i < endIndex;) {
      bytes32 key = positionManager.positionRequestKeys(i);
      bool isOpen = positionManager.positionRequestTypes(i);

      if (isOpen) {
        (
          address account,
          ,,
          uint256 optionTokenId,
          ,
          uint256 amountIn,
          ,,
          uint40 blockTime,
          IPositionManager.RequestStatus status,
          uint256 sizeOut,
          uint256 executionPrice,
          uint40 processBlockTime
          ,
        ) = positionManager.openPositionRequests(key);

        address[] memory path = positionManager.getOpenPositionRequestPath(key);
        address path0 = path[0];
        address path1 = path.length > 1 ? path[1] : address(0);

        PositionRequestInfo memory nextRequest;
        nextRequest.requestIndex = i;
        nextRequest.isOpen = isOpen;
        nextRequest.account = account;
        nextRequest.optionTokenId = optionTokenId;
        nextRequest.amountInOrSize = amountIn;
        nextRequest.blockTime = blockTime;
        nextRequest.status = status;
        nextRequest.sizeOutOrAmountOut = sizeOut;
        nextRequest.executionPrice = executionPrice;
        nextRequest.processBlockTime = processBlockTime;
        nextRequest.path0 = path0;
        nextRequest.path1 = path1;

        result[i - positionRequestKeysStart] = nextRequest;
      } else {
        (
          address account,
          ,,
          uint256 optionTokenId,
          uint256 size,
          ,,,
          uint40 blockTime,
          IPositionManager.RequestStatus status,
          uint256 amountOut,
          uint256 executionPrice,
          uint40 processBlockTime
        ) = positionManager.closePositionRequests(key);

        address[] memory path = positionManager.getClosePositionRequestPath(key);
        address path0 = path[0];
        address path1 = path.length > 1 ? path[1] : address(0);

        PositionRequestInfo memory nextRequest;
        nextRequest.requestIndex = i;
        nextRequest.isOpen = isOpen;
        nextRequest.account = account;
        nextRequest.optionTokenId = optionTokenId;
        nextRequest.amountInOrSize = size;
        nextRequest.blockTime = blockTime;
        nextRequest.status = status;
        nextRequest.sizeOutOrAmountOut = amountOut;
        nextRequest.executionPrice = executionPrice;
        nextRequest.processBlockTime = processBlockTime;
        nextRequest.path0 = path0;
        nextRequest.path1 = path1;

        result[i - positionRequestKeysStart] = nextRequest;
      }

      unchecked { i++; }
    }

    (uint256 sUtilizedUsd, uint256 sDepositedUsd, uint256 mUtilizedUsd, uint256 mDepositedUsd, uint256 lUtilizedUsd, uint256 lDepositedUsd) = getOlpUtilityRatio();

    return (result, endIndex, sUtilizedUsd, sDepositedUsd, mUtilizedUsd, mDepositedUsd, lUtilizedUsd, lDepositedUsd);
  }

  function getOlpUtilityRatio() public view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
    (,,,, uint256 sTotalUtilizedUsd,, uint256 sTotalDepositedUsd) = olpManagers[0].getTotalOlpAssetUsd(true);
    (,,,, uint256 mTotalUtilizedUsd,, uint256 mTotalDepositedUsd) = olpManagers[1].getTotalOlpAssetUsd(true);
    (,,,, uint256 lTotalUtilizedUsd,, uint256 lTotalDepositedUsd) = olpManagers[2].getTotalOlpAssetUsd(true);

    return (
      sTotalUtilizedUsd, sTotalDepositedUsd,
      mTotalUtilizedUsd, mTotalDepositedUsd,
      lTotalUtilizedUsd, lTotalDepositedUsd
    );
  }

  function getOlpAPRIngredients() public view returns (
    uint256 s_tokensPerInterval, uint256 s_totalRpReleaseUsd, uint256 s_olptv,
    uint256 m_tokensPerInterval, uint256 m_totalRpReleaseUsd, uint256 m_olptv,
    uint256 l_tokensPerInterval, uint256 l_totalRpReleaseUsd, uint256 l_olptv
  ) {
    s_tokensPerInterval = rewardDistributors[0].tokensPerInterval();
    m_tokensPerInterval = rewardDistributors[1].tokensPerInterval();
    l_tokensPerInterval = rewardDistributors[2].tokensPerInterval();

    (, s_totalRpReleaseUsd) = olpManagers[0].getOlpMpRpReleaseUsd(true);
    (, m_totalRpReleaseUsd) = olpManagers[1].getOlpMpRpReleaseUsd(true);
    (, l_totalRpReleaseUsd) = olpManagers[2].getOlpMpRpReleaseUsd(true);
    
    s_olptv = olpManagers[0].getAum(true);
    m_olptv = olpManagers[1].getAum(true);
    l_olptv = olpManagers[2].getAum(true);
  }

  function getOlpAssetAmounts(address[] memory tokens) public view returns (uint256[] memory, uint256[] memory, uint256[] memory) {
    uint256 tokensLength = tokens.length;

    uint256[] memory sOlpAssetAmounts = new uint256[](12);
    uint256[] memory mOlpAssetAmounts = new uint256[](12);
    uint256[] memory lOlpAssetAmounts = new uint256[](12);

    for (uint256 i = 0; i < tokensLength;) {
      (,,,,uint256 utilizedAmounts, uint256 availableAmounts, uint256 depositedAmounts) = olpManagers[0].getOlpAssetAmounts(tokens[i]);
      sOlpAssetAmounts[i * 3] = utilizedAmounts;
      sOlpAssetAmounts[i * 3 + 1] = availableAmounts;
      sOlpAssetAmounts[i * 3 + 2] = depositedAmounts;
      unchecked { i++; }
    }

    for (uint256 i = 0; i < tokensLength;) {
      (,,,,uint256 utilizedAmounts, uint256 availableAmounts, uint256 depositedAmounts) = olpManagers[1].getOlpAssetAmounts(tokens[i]);
      mOlpAssetAmounts[i * 3] = utilizedAmounts;
      mOlpAssetAmounts[i * 3 + 1] = availableAmounts;
      mOlpAssetAmounts[i * 3 + 2] = depositedAmounts;
      unchecked { i++; }
    }

    for (uint256 i = 0; i < tokensLength;) {
      (,,,,uint256 utilizedAmounts, uint256 availableAmounts, uint256 depositedAmounts) = olpManagers[2].getOlpAssetAmounts(tokens[i]);
      lOlpAssetAmounts[i * 3] = utilizedAmounts;
      lOlpAssetAmounts[i * 3 + 1] = availableAmounts;
      lOlpAssetAmounts[i * 3 + 2] = depositedAmounts;
      unchecked { i++; }
    }

    return (sOlpAssetAmounts, mOlpAssetAmounts, lOlpAssetAmounts);
  }

  function getOlpStats() public view returns (uint256[] memory, uint256[] memory, uint256[] memory, bool[] memory) {
    uint256[] memory sOlpStats = new uint256[](3);
    uint256[] memory mOlpStats = new uint256[](3);
    uint256[] memory lOlpStats = new uint256[](3);
    bool[] memory isPvNegative = new bool[](3);

    for (uint256 i = 0; i < 3;) {
      uint256 olpPrice = olpManagers[i].getPrice(true);
      uint256 totalSupply = olps[i].totalSupply();
      (uint256 olpPv, bool isNegative) = vaultPriceFeed.getPVAndSign(address(vaults[i]));

      if (i == 0) {
        sOlpStats[0] = olpPrice;
        sOlpStats[1] = totalSupply;
        sOlpStats[2] = olpPv;
        isPvNegative[0] = isNegative;
      } else if (i == 1) {
        mOlpStats[0] = olpPrice;
        mOlpStats[1] = totalSupply;
        mOlpStats[2] = olpPv;
        isPvNegative[1] = isNegative;
      } else {
        lOlpStats[0] = olpPrice;
        lOlpStats[1] = totalSupply;
        lOlpStats[2] = olpPv;
        isPvNegative[2] = isNegative;
      }

      unchecked { i++; }
    }

    return (sOlpStats, mOlpStats, lOlpStats, isPvNegative);
  }

  // Related to OLP Position

  function getOptionTokens(address _vaultUtils, uint256 _startIndex, uint256 _endIndex) public view returns (uint256[][] memory) {
    IVaultUtils targetVaultUtils = IVaultUtils(_vaultUtils);
    
    uint256[] memory expiries = targetVaultUtils.getSelfOriginExpiries();

    if (_endIndex > expiries.length) {
      _endIndex = expiries.length;
    }

    if (_endIndex == 0) {
      return new uint256[][](0);
    }

    uint256 totalOptionTokensLength = 0;

    for (uint256 i = _startIndex; i < _endIndex;) {
      totalOptionTokensLength += targetVaultUtils.getOptionTokensLengthAtSelfExpiry(expiries[i]);
      unchecked { i++; }
    }

    uint256[][] memory result = new uint256[][](totalOptionTokensLength);
    uint256 currentIndex = 0;

    for (uint256 i = _startIndex; i < _endIndex;) {
      IVaultUtils.OptionToken[] memory optionTokens = targetVaultUtils.getOptionTokensAtSelfOriginExpiry(expiries[i]);
      
      for (uint256 j = 0; j < optionTokens.length;) {
        result[currentIndex] = new uint256[](2);
        result[currentIndex][0] = optionTokens[j].optionTokenId;
        result[currentIndex][1] = optionTokens[j].size;
        currentIndex++;
        unchecked { j++; }
      }

      unchecked { i++; }
    }

    return result;
  }

  function getAllExpiries() public view returns (uint256[][] memory result) {
    IVaultUtils[3] memory parsedVaultUtils = [
      vaultUtils[0],
      vaultUtils[1],
      vaultUtils[2]
    ];

    result = new uint256[][](3);

    for (uint256 i = 0; i < 3;) {
      uint256[] memory expiries = parsedVaultUtils[i].getSelfOriginExpiries();

      result[i] = new uint256[](expiries.length);

      for (uint256 j = 0; j < expiries.length;) {
        result[i][j] = expiries[j];
        unchecked { j++; }
      }

      unchecked { i++; }
    }

    return result;
  }

  function getAllOptionToken() public view returns (uint256[][][] memory result) {
    result = new uint256[][][](3);

    for (uint256 i = 0; i < vaultUtils.length;) {
      fetchOptionTokens(vaultUtils[i], i, result);
      unchecked { i++; }
    }
  }

  function fetchOptionTokens(IVaultUtils _vaultUtils, uint256 _vaultUtilsIndex, uint256[][][] memory _result) private view {
    uint256[] memory selfOriginExpiries = _vaultUtils.getSelfOriginExpiries();

    uint256 totalOptionTokensLength = 0;

    for (uint256 i = 0; i < selfOriginExpiries.length; ) {
      totalOptionTokensLength += _vaultUtils.getOptionTokensLengthAtSelfExpiry(selfOriginExpiries[i]);
      unchecked { i++; }
    }

    _result[_vaultUtilsIndex] = new uint256[][](totalOptionTokensLength);
    uint256 currentIndex = 0;

    for (uint256 i = 0; i < selfOriginExpiries.length; ) {
      IVaultUtils.OptionToken[] memory optionTokens = _vaultUtils.getOptionTokensAtSelfOriginExpiry(selfOriginExpiries[i]);
      
      for (uint256 j = 0; j < optionTokens.length;) {
        _result[_vaultUtilsIndex][currentIndex] = new uint256[](2);
        _result[_vaultUtilsIndex][currentIndex][0] = optionTokens[j].optionTokenId;
        _result[_vaultUtilsIndex][currentIndex][1] = optionTokens[j].size;
        currentIndex++;
        unchecked { j++; }
      }

      unchecked { i++; }
    }
  }

  function getFeeReservesUsdAndEthAvailableUsd() public view returns (uint256[] memory, uint256[] memory) {
    // this is assuming whitelistedTokens are the same for all vaults
    address[] memory whitelistedTokens = vaultUtils[0].getWhitelistedTokens();
    
    uint256[] memory feeReservesUsd = new uint256[](3);
    uint256[] memory ethAvailableUsd = new uint256[](3);

    for (uint256 i = 0; i < whitelistedTokens.length;) {
      address token = whitelistedTokens[i];
      uint256 spotPrice = vaultPriceFeed.getSpotPrice(token, true);  

      for (uint256 j = 0; j < 3;) {
        uint256 tokenFeeReservesAmount = vaults[j].feeReserves(token);
        uint256 tokenDecimals = vaults[j].tokenDecimals(token);
        uint256 tokenFeeReservesUsd = tokenFeeReservesAmount * spotPrice / (10 ** tokenDecimals);

        feeReservesUsd[j] += tokenFeeReservesUsd;
        
        unchecked { j++; }
      }

      unchecked { i++; }
    }

    for (uint256 i = 0; i < 3;) {
      (,,,,, uint256 availableUsd,) = olpManagers[i].getOlpAssetUsd(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, true);
      ethAvailableUsd[i] = availableUsd;

      unchecked { i++; }
    }

    return (feeReservesUsd, ethAvailableUsd);
  }
}