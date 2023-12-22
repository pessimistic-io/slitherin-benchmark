// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {Ownable} from "./Ownable.sol";
import {ERC20} from "./ERC20.sol";
import {ILevelOracle} from "./ILevelOracle.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

struct TokenConfig {
    /// @dev 10 ^ token decimals
    uint256 baseUnits;
    /// @dev precision of price posted by reporter
    uint256 priceUnits;
    /// @dev chainlink pricefeed used to compare with posted price
    AggregatorV3Interface chainlinkPriceFeed;
    uint256 chainlinkDeviation;
    uint256 chainlinkTimeout;
}

/// @title PriceFeed
/// @notice Price feed with guard from
contract LevelOracle is Ownable, ILevelOracle {
    /// @dev This price feed returns price in precision of 10 ^ (30 - token decimals)
    uint256 constant VALUE_PRECISION = 1e30;
    /// @notice precision used for spread, deviation
    uint256 constant PRECISION = 1e6;
    uint256 public constant PRICE_FEED_ERROR = 1 hours;
    uint256 public constant PRICE_FEED_INACTIVE = 5 minutes;
    uint256 public constant PRICE_FEED_ERROR_SPREAD = 5e4; // 5%
    uint256 public constant PRICE_FEED_INACTIVE_SPREAD = 2e3; // 0.2%
    uint256 public constant MAX_DEVIATION = 1e5; // 10%
    uint256 public constant MAX_CHAINLINK_TIMEOUT = 1 days; // 10%
    /// @notice time to wait after sequencer back online
    uint256 public constant SEQUENCER_GRACE_PERIOD_TIME = 1 hours; // 10%
    /// @notice arbitrum sequence uptime feed
    AggregatorV3Interface public constant sequencerUptimeFeed =
        AggregatorV3Interface(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);

    uint256 public constant MAX_PRICE_POST_DELAY = 60;

    mapping(address => TokenConfig) public tokenConfig;
    /// @notice listed tokens, for inspection only
    address[] public whitelistedTokens;
    /// @notice last reported price
    mapping(address => uint256) public lastAnswers;
    mapping(address => uint256) public lastAnswerTimestamp;
    mapping(address => uint256) public lastAnswerBlock;

    mapping(address => bool) public isReporter;
    address[] public reporters;

    // ============ Mutative functions ============

    function postPrices(address[] calldata tokens, uint256[] calldata prices, uint256[] calldata timestamps) external {
        if (!isReporter[msg.sender]) {
            revert NotAllowed();
        }

        uint256 count = tokens.length;
        if (prices.length != count || timestamps.length != count) {
            revert InvalidPriceData();
        }

        for (uint256 i = 0; i < count;) {
            _postPrice(tokens[i], prices[i], timestamps[i]);
            unchecked {
                ++i;
            }
        }
    }

    // ============ View functions ============
    function getMultiplePrices(address[] calldata tokens, bool max) external view returns (uint256[] memory) {
        uint256 len = tokens.length;
        uint256[] memory result = new uint[](len);

        for (uint256 i = 0; i < len;) {
            result[i] = _getPrice(tokens[i], max);
            unchecked {
                ++i;
            }
        }

        return result;
    }

    function getPrice(address token, bool max) external view returns (uint256) {
        return _getPrice(token, max);
    }

    function getLastPrice(address token) external view returns (uint256 lastPrice) {
        (lastPrice,) = _getLastPrice(token);
    }

    function getReferencePrice(address token) external view returns (uint256) {
        TokenConfig memory config = tokenConfig[token];
        return _getReferencePrice(config);
    }

    // =========== Restrited functions ===========

    /// @notice config watched token
    /// @param token token address
    /// @param tokenDecimals token decimals
    /// @param priceFeed the chainlink price feed used for reference
    /// @param priceDecimals precision of price posted by reporter, not the chainlink price feed
    function configToken(
        address token,
        uint256 tokenDecimals,
        address priceFeed,
        uint256 priceDecimals,
        uint256 chainlinkTimeout,
        uint256 chainlinkDeviation
    ) external onlyOwner {
        if (priceFeed == address(0)) revert InvalidAddress();
        if (tokenDecimals == 0 || priceDecimals == 0) revert InvalidDecimals();
        if (chainlinkTimeout == 0 || chainlinkTimeout > MAX_CHAINLINK_TIMEOUT) revert InvalidTimeout();
        if (chainlinkDeviation == 0 || chainlinkDeviation > MAX_DEVIATION) revert InvalidChainlinkDeviation();

        if (tokenConfig[token].baseUnits == 0) {
            whitelistedTokens.push(token);
        }

        tokenConfig[token] = TokenConfig({
            baseUnits: 10 ** tokenDecimals,
            priceUnits: 10 ** priceDecimals,
            chainlinkPriceFeed: AggregatorV3Interface(priceFeed),
            chainlinkTimeout: chainlinkTimeout,
            chainlinkDeviation: chainlinkDeviation
        });
        emit TokenAdded(token);
    }

    function addReporter(address reporter) external onlyOwner {
        if (isReporter[reporter]) revert ReporterExists();

        isReporter[reporter] = true;
        reporters.push(reporter);
        emit ReporterAdded(reporter);
    }

    function removeReporter(address reporter) external onlyOwner {
        if (reporter == address(0)) revert InvalidAddress();
        if (!isReporter[reporter]) revert NotAReporter();

        isReporter[reporter] = false;
        for (uint256 i = 0; i < reporters.length; i++) {
            if (reporters[i] == reporter) {
                reporters[i] = reporters[reporters.length - 1];
                break;
            }
        }
        reporters.pop();
        emit ReporterRemoved(reporter);
    }

    // ========= Internal functions ==========
    /// @notice report token price
    /// allow some authorized reporters only
    function _postPrice(address token, uint256 price, uint256 timestamp) internal {
        TokenConfig memory config = tokenConfig[token];
        if (config.baseUnits == 0) {
            revert TokenNotConfigured();
        }

        uint256 _now = block.timestamp;
        // reject invalid price
        if (timestamp <= lastAnswerTimestamp[token] || timestamp > _now || timestamp + MAX_PRICE_POST_DELAY < _now) {
            return;
        }

        uint256 normalizedPrice = (price * VALUE_PRECISION) / config.baseUnits / config.priceUnits;
        lastAnswers[token] = normalizedPrice;
        lastAnswerTimestamp[token] = timestamp;
        lastAnswerBlock[token] = block.number;
        emit PricePosted(token, normalizedPrice);
    }

    function _getPrice(address token, bool max) internal view returns (uint256) {
        (uint256 lastPrice, uint256 lastPriceTimestamp) = _getLastPrice(token);
        (uint256 refPrice, uint256 lowerBound, uint256 upperBound, uint256 minLowerBound, uint256 maxUpperBound) =
            _getReferencePriceWithBound(token);
        if (lastPriceTimestamp + PRICE_FEED_ERROR < block.timestamp) {
            return _getPriceSpread(refPrice, PRICE_FEED_ERROR_SPREAD, max);
        }

        if (lastPriceTimestamp + PRICE_FEED_INACTIVE < block.timestamp) {
            return _getPriceSpread(refPrice, PRICE_FEED_INACTIVE_SPREAD, max);
        }

        if (lastPrice > upperBound) {
            return max ? _min(lastPrice, maxUpperBound) : refPrice;
        }

        if (lastPrice < lowerBound) {
            return max ? refPrice : _max(lastPrice, minLowerBound);
        }

        // no spread, trust keeper
        return lastPrice;
    }

    function _min(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a < _b ? _a : _b;
    }

    function _max(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a > _b ? _a : _b;
    }

    function _getPriceSpread(uint256 pivot, uint256 spread, bool max) internal pure returns (uint256) {
        return max ? pivot * (PRECISION + spread) / PRECISION : pivot * (PRECISION - spread) / PRECISION;
    }

    function _getReferencePrice(TokenConfig memory config) internal view returns (uint256 refPrice) {
        uint256 _now = block.timestamp;
        (
            /*uint80 roundID*/
            ,
            int256 sequencerUptimeAnswer,
            uint256 sequencerUptimeStartedAt,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = sequencerUptimeFeed.latestRoundData();

        if (sequencerUptimeAnswer != 0) {
            revert SequencerDown();
        }

        if (_now <= sequencerUptimeStartedAt + SEQUENCER_GRACE_PERIOD_TIME) {
            revert SequencerGracePeriodNotOver();
        }

        (, int256 guardPrice,, uint256 updatedAt,) = config.chainlinkPriceFeed.latestRoundData();
        if (_now > updatedAt + config.chainlinkTimeout) {
            revert ChainlinkStaled();
        }

        refPrice = (uint256(guardPrice) * VALUE_PRECISION) / config.baseUnits / config.priceUnits;
    }

    function _getReferencePriceWithBound(address token)
        internal
        view
        returns (uint256 refPrice, uint256 lowerBound, uint256 upperBound, uint256 minLowerBound, uint256 maxUpperBound)
    {
        TokenConfig memory config = tokenConfig[token];
        refPrice = _getReferencePrice(config);
        lowerBound = refPrice * (PRECISION - config.chainlinkDeviation) / PRECISION;
        minLowerBound = refPrice * (PRECISION - 3 * config.chainlinkDeviation) / PRECISION;
        upperBound = refPrice * (PRECISION + config.chainlinkDeviation) / PRECISION;
        maxUpperBound = refPrice * (PRECISION + 3 * config.chainlinkDeviation) / PRECISION;
    }

    function _getLastPrice(address token) internal view returns (uint256 price, uint256 timestamp) {
        return (lastAnswers[token], lastAnswerTimestamp[token]);
    }

    // =========== Events ===========
    event ReporterAdded(address indexed);
    event ReporterRemoved(address indexed);
    event PricePosted(address indexed token, uint256 price);
    event TokenAdded(address indexed token);

    // ============ Errors =============
    error NotAllowed();
    error InvalidPriceData();

    error InvalidDecimals();
    error InvalidTimeout();
    error InvalidChainlinkDeviation();
    error InvalidAddress();
    error ReporterExists();
    error NotAReporter();

    error TokenNotConfigured();
    error ChainlinkStaled();
    error SequencerDown();
    error SequencerGracePeriodNotOver();
}

