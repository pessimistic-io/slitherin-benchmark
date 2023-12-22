// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// Inheritance
import "./ProxyOwned.sol";
import "./UniswapMath.sol";

// Libraries
import "./Initializable.sol";
import "./SafeMath.sol";

// Internal references
// AggregatorInterface from Chainlink represents a decentralized pricing network for a single currency key
import "./AggregatorV2V3Interface.sol";

import "./IUniswapV3Pool.sol";

contract PriceFeed is Initializable, ProxyOwned {
    using SafeMath for uint;

    // Decentralized oracle networks that feed into pricing aggregators
    mapping(bytes32 => AggregatorV2V3Interface) public aggregators;

    mapping(bytes32 => uint8) public currencyKeyDecimals;

    bytes32[] public aggregatorKeys;

    // List of currency keys for convenient iteration
    bytes32[] public currencyKeys;
    mapping(bytes32 => IUniswapV3Pool) public pools;

    int56 public twapInterval;

    struct RateAndUpdatedTime {
        uint216 rate;
        uint40 time;
    }

    address public _ETH;
    address public _wETH;

    mapping(bytes32 => bool) public useLastTickForTWAP;

    function initialize(address _owner) external initializer {
        setOwner(_owner);
        twapInterval = 300;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function addAggregator(bytes32 currencyKey, address aggregatorAddress) external onlyOwner {
        AggregatorV2V3Interface aggregator = AggregatorV2V3Interface(aggregatorAddress);
        require(aggregator.latestRound() >= 0, "Given Aggregator is invalid");
        uint8 decimals = aggregator.decimals();
        require(decimals <= 18, "Aggregator decimals should be lower or equal to 18");
        if (address(aggregators[currencyKey]) == address(0)) {
            currencyKeys.push(currencyKey);
        }
        aggregators[currencyKey] = aggregator;
        currencyKeyDecimals[currencyKey] = decimals;
        emit AggregatorAdded(currencyKey, address(aggregator));
    }

    function addPool(bytes32 currencyKey, address currencyAddress, address poolAddress) external onlyOwner {
        // check if aggregator exists for given currency key
        AggregatorV2V3Interface aggregator = aggregators[currencyKey];
        require(address(aggregator) == address(0), "Aggregator already exists for key");

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        address token0 = pool.token0();
        address token1 = pool.token1();
        bool token0valid = token0 == _wETH || token0 == _ETH;
        bool token1valid = token1 == _wETH || token1 == _ETH;

        // check if one of tokens is wETH or ETH
        require(token0valid || token1valid, "Pool not valid: ETH is not an asset");
        // check if currency is asset in given
        require(currencyAddress == token0 || currencyAddress == token1, "Pool not valid: currency is not an asset");
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        require(sqrtPriceX96 > 0, "Pool not valid");
        if (address(pools[currencyKey]) == address(0)) {
            currencyKeys.push(currencyKey);
        }
        pools[currencyKey] = pool;
        currencyKeyDecimals[currencyKey] = 18;
        emit PoolAdded(currencyKey, address(pool));
    }

    function removeAggregator(bytes32 currencyKey) external onlyOwner {
        address aggregator = address(aggregators[currencyKey]);
        require(aggregator != address(0), "No aggregator exists for key");
        delete aggregators[currencyKey];
        delete currencyKeyDecimals[currencyKey];

        bool wasRemoved = removeFromArray(currencyKey, currencyKeys);

        if (wasRemoved) {
            emit AggregatorRemoved(currencyKey, aggregator);
        }
    }

    function removePool(bytes32 currencyKey) external onlyOwner {
        address pool = address(pools[currencyKey]);
        require(pool != address(0), "No pool exists for key");
        delete pools[currencyKey];

        bool wasRemoved = removeFromArray(currencyKey, currencyKeys);
        if (wasRemoved) {
            emit PoolRemoved(currencyKey, pool);
        }
    }

    function getRates() external view returns (uint[] memory rates) {
        uint count = 0;
        rates = new uint[](currencyKeys.length);
        for (uint i = 0; i < currencyKeys.length; i++) {
            bytes32 currencyKey = currencyKeys[i];
            rates[count++] = _getRateAndUpdatedTime(currencyKey).rate;
        }
    }

    function getCurrencies() external view returns (bytes32[] memory) {
        return currencyKeys;
    }

    function rateForCurrency(bytes32 currencyKey) external view returns (uint) {
        return _getRateAndUpdatedTime(currencyKey).rate;
    }

    function rateAndUpdatedTime(bytes32 currencyKey) external view returns (uint rate, uint time) {
        RateAndUpdatedTime memory rateAndTime = _getRateAndUpdatedTime(currencyKey);
        return (rateAndTime.rate, rateAndTime.time);
    }

    function removeFromArray(bytes32 entry, bytes32[] storage array) internal returns (bool) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == entry) {
                delete array[i];
                array[i] = array[array.length - 1];
                array.pop();
                return true;
            }
        }
        return false;
    }

    function setTwapInterval(int56 _twapInterval) external onlyOwner {
        twapInterval = _twapInterval;
        emit TwapIntervalChanged(_twapInterval);
    }

    function setLastTickForTWAP(bytes32 _currencyKey) external onlyOwner {
        useLastTickForTWAP[_currencyKey] = !useLastTickForTWAP[_currencyKey];
        emit LastTickForTWAPChanged(_currencyKey);
    }

    function setWETH(address token) external onlyOwner {
        _wETH = token;
        emit AddressChangedwETH(token);
    }

    function setETH(address token) external onlyOwner {
        _ETH = token;
        emit AddressChangedETH(token);
    }

    function _formatAnswer(bytes32 currencyKey, int256 rate) internal view returns (uint) {
        require(rate >= 0, "Negative rate not supported");
        if (currencyKeyDecimals[currencyKey] > 0) {
            uint multiplier = 10**uint(SafeMath.sub(18, currencyKeyDecimals[currencyKey]));
            return uint(uint(rate).mul(multiplier));
        }
        return uint(rate);
    }

    function _getRateAndUpdatedTime(bytes32 currencyKey) internal view returns (RateAndUpdatedTime memory) {
        AggregatorV2V3Interface aggregator = aggregators[currencyKey];
        IUniswapV3Pool pool = pools[currencyKey];
        require(address(aggregator) != address(0) || address(pool) != address(0), "No aggregator or pool exists for key");

        if (aggregator != AggregatorV2V3Interface(address(0))) {
            return _getAggregatorRate(address(aggregator), currencyKey);
        } else {
            require(address(aggregators["ETH"]) != address(0), "Price for ETH does not exist");
            uint256 ratio = _getPriceFromSqrtPrice(_getTwap(address(pool), currencyKey));
            uint256 ethPrice = _getAggregatorRate(address(aggregators["ETH"]), "ETH").rate * 10**18; 
            address token0 = pool.token0();
            uint answer;

            if(token0 == _ETH || token0 == _wETH) {
                answer = ethPrice / ratio;
            } else {
                answer = ethPrice * ratio;
            }
            return
                RateAndUpdatedTime({
                    rate: uint216(_formatAnswer(currencyKey, int256(answer))),
                    time: uint40(block.timestamp)
                });
        }
    }

    function _getAggregatorRate(address aggregator, bytes32 currencyKey) internal view returns (RateAndUpdatedTime memory ) {
        // this view from the aggregator is the most gas efficient but it can throw when there's no data,
        // so let's call it low-level to suppress any reverts
        bytes memory payload = abi.encodeWithSignature("latestRoundData()");
        // solhint-disable avoid-low-level-calls
        (bool success, bytes memory returnData) = aggregator.staticcall(payload);

        if (success) {
            (, int256 answer, , uint256 updatedAt, ) = abi.decode(
                returnData,
                (uint80, int256, uint256, uint256, uint80)
            );
            return RateAndUpdatedTime({rate: uint216(_formatAnswer(currencyKey, answer)), time: uint40(updatedAt)});
        }

        // must return assigned value
        return RateAndUpdatedTime({rate: 0, time: 0});
    }

    function _getTwap(address pool, bytes32 currencyKey) internal view returns (uint160 sqrtPriceX96) {
        if (twapInterval == 0 || useLastTickForTWAP[currencyKey]) {
            // return the current price
            (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = uint32(uint56(twapInterval));
            secondsAgos[1] = 0; // to (now)

            (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(secondsAgos);
            // tick(imprecise as it's an integer) to price
            sqrtPriceX96 = UniswapMath.getSqrtRatioAtTick(int24((tickCumulatives[1] - tickCumulatives[0]) / twapInterval));
        }
    }

    function _getPriceFromSqrtPrice(uint160 sqrtPriceX96) internal pure returns (uint256 priceX96) {
        uint256 price = UniswapMath.mulDiv(sqrtPriceX96, sqrtPriceX96, UniswapMath.Q96);
        return UniswapMath.mulDiv(price, 10**18, UniswapMath.Q96);
    }

    function transferCurrencyKeys() external onlyOwner {
        require(currencyKeys.length == 0, "Currency keys is not empty");
        for (uint i = 0; i < aggregatorKeys.length; i++) {
            currencyKeys[i] = aggregatorKeys[i];
        }
    }

    /* ========== EVENTS ========== */
    event AggregatorAdded(bytes32 currencyKey, address aggregator);
    event AggregatorRemoved(bytes32 currencyKey, address aggregator);
    event PoolAdded(bytes32 currencyKey, address pool);
    event PoolRemoved(bytes32 currencyKey, address pool);
    event AddressChangedETH(address token);
    event AddressChangedwETH(address token);
    event LastTickForTWAPChanged(bytes32 currencyKey);
    event TwapIntervalChanged(int56 twapInterval);
}

