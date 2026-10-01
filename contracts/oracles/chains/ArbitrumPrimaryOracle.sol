// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IArbitrumPrimaryOracle.sol";
import "./interfaces/IPrimaryOracle.sol";
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IChainlinkFlags.sol";

import "../../proxy/OwnableUpgradeable.sol";
import "../../AuthorityUtil.sol";

contract ArbitrumPrimaryOracle is IPrimaryOracle, IArbitrumPrimaryOracle, OwnableUpgradeable, AuthorityUtil {
    uint256 public constant PRICE_PRECISION = 10 ** 30;

    // Identifier of the Sequencer offline flag on the Flags contract
    address constant private FLAG_ARBITRUM_SEQ_OFFLINE = address(bytes20(bytes32(uint256(keccak256("chainlink.flags.arbitrum-seq-offline")) - 1)));

    address public chainlinkFlags;
    uint256 public priceSampleSpace;

    mapping(address => address) public priceFeeds;
    mapping(address => uint256) public priceDecimals;
    
    event SetChainlinkFlags(address indexed chainlinkFlags);
    event SetPriceSampleSpace(uint256 indexed priceSampleSpace);
    event SetTokenConfig(address indexed token, address indexed priceFeed, uint256 priceDecimals);

    error ChainlinkFeedsNotUpdated();

    function initialize(IOptionsAuthority _authority) external initializer {
        __Ownable_init();
        __AuthorityUtil_init__(_authority);

        priceSampleSpace = 1;
    }    

    function setChainlinkFlags(address _chainlinkFlags) external onlyAdmin {
        require(_chainlinkFlags != address(0), "PrimaryOracle: invalid chainlinkFlags");
        chainlinkFlags = _chainlinkFlags;
        emit SetChainlinkFlags(_chainlinkFlags);
    }

    function setPriceSampleSpace(uint256 _priceSampleSpace) external override onlyAdmin {
        require(_priceSampleSpace > 0, "PrimaryOracle: invalid _priceSampleSpace");
        priceSampleSpace = _priceSampleSpace;
        emit SetPriceSampleSpace(_priceSampleSpace);
    }

    function setTokenConfig(address _token, address _priceFeed, uint256 _priceDecimals) external override onlyAdmin {
        require(
            _token != address(0) &&
            _priceFeed != address(0),
            "PrimaryOracle: invalid addresses when setting token config"
        );

        priceFeeds[_token] = _priceFeed;
        priceDecimals[_token] = _priceDecimals;

        emit SetTokenConfig(_token, _priceFeed, _priceDecimals);
    }

    function getPrice(address _token, bool _maximise) public override view returns (uint256) {
        address priceFeedAddress = priceFeeds[_token];
        require(priceFeedAddress != address(0), "PrimaryOracle: invalid price feed");

        if (chainlinkFlags != address(0)) {
            bool isRaised = IChainlinkFlags(chainlinkFlags).getFlag(FLAG_ARBITRUM_SEQ_OFFLINE);
            if (isRaised) {
                // If flag is raised we shouldn't perform any critical operations
                revert ChainlinkFeedsNotUpdated();
            }
        }

        IPriceFeed priceFeed = IPriceFeed(priceFeedAddress);

        uint256 price = 0;
        uint80 roundId = priceFeed.latestRound();

        for (uint80 i = 0; i < priceSampleSpace;) {
            if (roundId <= i) { break; }
            uint256 p;

            if (i == 0) {
                int256 _p = priceFeed.latestAnswer();
                require(_p > 0, "PrimaryOracle: invalid price");
                p = uint256(_p);
            } else {
                uint80 nextRoundId;
                unchecked { nextRoundId = roundId - i; }
                (, int256 _p, , ,) = priceFeed.getRoundData(nextRoundId);
                require(_p > 0, "PrimaryOracle: invalid price");
                p = uint256(_p);
            }

            if (price == 0 || (_maximise && p > price) || (!_maximise && p < price)) {
                price = p;
            }

            unchecked { i++;}
        }

        require(price > 0, "PrimaryOracle: could not fetch price");
        // normalise price precision
        uint256 _priceDecimals = priceDecimals[_token];
        return (price * PRICE_PRECISION / (10 ** _priceDecimals));
    }
}
