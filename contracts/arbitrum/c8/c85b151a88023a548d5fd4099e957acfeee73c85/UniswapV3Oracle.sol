// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import "./TickMath.sol";
import "./FullMath.sol";
import "./ERC20.sol";
import "./AggregatorV3Interface.sol";
import "./IOracle.sol";
import "./IAddressProvider.sol";
import "./AccessControl.sol";

/**
 * @notice Oracle that uses Uniswap V3's pools to calculate time weighted averge price for tokens
 */
contract UniswapV3Oracle is IOracle, AccessControl {
    IUniswapV3Factory public factory;
    AggregatorV3Interface public chainlinkPriceFeed;

    /**
     * @notice Initializes the upgradeable contract with the provided parameters
     * @dev factory.getPool, and chainlinkPriceFeed.latestRoundData are called as a form of input validation
     * @dev A chainlink price feed for the network token (WETH) is used to circumvent inaccurate prices from stablecoin depegs
     * This is achieved by calculating the price of a token in terms of the network token and then converting that to USD
     * with the help of the price feed
     */
    function initialize(address _factory, address _addressProvider, address _priceFeed) external initializer {
        __AccessControl_init(_addressProvider);
        factory = IUniswapV3Factory(_factory);
        chainlinkPriceFeed = AggregatorV3Interface(_priceFeed);
        factory.getPool(provider.networkToken(), address(0), 100);
        chainlinkPriceFeed.latestRoundData();
    }

    /**
     * @notice Set the uniswap v3 factory address
     */
    function setFactory(address _factory) external restrictAccess(GOVERNOR) {
        factory = IUniswapV3Factory(_factory);
        factory.getPool(provider.networkToken(), address(0), 100);
    }

    /**
     * @notice Update the network token price feed address
     */
    function setPriceFeed(address _priceFeed) external restrictAccess(GOVERNOR) {
        chainlinkPriceFeed = AggregatorV3Interface(_priceFeed);
        chainlinkPriceFeed.latestRoundData();
    }

    /// @inheritdoc IOracle
    /// @dev In case the price feed fails, the price in terms of usdc will be returned instead
    function getPrice(address token) public view returns (uint price) {
        uint priceInTermsOfNetworkToken = getPriceInTermsOf(token, provider.networkToken());

        try chainlinkPriceFeed.latestRoundData() returns (
            uint80 roundId,
            int256 networkTokenPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            uint networkTokenPriceInUsd = uint(networkTokenPrice) * 10**10;
            price = priceInTermsOfNetworkToken * networkTokenPriceInUsd / 10**ERC20(provider.networkToken()).decimals();
        } catch {
            price = getPriceInTermsOf(token, provider.usdc());
        }
    }

    /// @inheritdoc IOracle
    function getPriceInTermsOf(address token, address inTermsOf) public view returns (uint price) {
        if (token==inTermsOf) return 10**ERC20(token).decimals();
        IUniswapV3Pool pool = getPool(token, inTermsOf);

        uint160 sqrtPriceX96 = getSqrtTwapX96(pool);
        uint decimals = 10**ERC20(token).decimals();
        if (token==pool.token1()) {
            price = FullMath.mulDiv(decimals, 2**192, uint256(sqrtPriceX96) ** 2);
        } else {
            price = FullMath.mulDiv(decimals, uint256(sqrtPriceX96)**2, 2**192);
        }
    }

    /// @inheritdoc IOracle
    function getValue(address token, uint amount) external view returns (uint value) {
        uint256 price = getPrice(token);
        uint decimals = 10**ERC20(token).decimals();
        value = amount*uint(price)/decimals;
    }

    /// @inheritdoc IOracle
    function getValueInTermsOf(address token, uint amount, address inTermsOf) external view returns (uint value) {
        uint256 price = getPriceInTermsOf(token, inTermsOf);
        uint decimals = 10**ERC20(token).decimals();
        value = (price * amount) / decimals;
    }

    /**
     * @notice Calculates the square root of the time-weighted average price (TWAP) for a Uniswap V3 pool.
     * @param pool The Uniswap V3 pool for which the square root TWAP should be calculated.
     * @return sqrtPriceX96 The square root TWAP value represented as a fixed-point number with 96 bits of precision.
     */
    function getSqrtTwapX96(IUniswapV3Pool pool) internal view returns (uint160 sqrtPriceX96) {
        uint32 twapInterval = 30;
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapInterval; // from (before)
        secondsAgos[1] = 0; // to (now)

        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);

        // tick(imprecise as it's an integer) to price
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
            int24((tickCumulatives[1] - tickCumulatives[0]) / int(uint(twapInterval)))
        );
    }

    /**
     * @notice Gets the uniswap v3 pool with the mmost liquidity for two tokens
     */
    function getPool(address tokenA, address tokenB) internal view returns (IUniswapV3Pool) {
        uint24[] memory feeTiers = new uint24[](4);
        feeTiers[0] = 100;   // 0.01% fee tier
        feeTiers[1] = 500;   // 0.05% fee tier
        feeTiers[2] = 3000;  // 0.3% fee tier
        feeTiers[3] = 10000; // 1% fee tier

        IUniswapV3Pool selectedPool;
        uint128 maxLiquidity = 0;

        for (uint256 i = 0; i < feeTiers.length; i++) {
            address poolAddress = factory.getPool(tokenA, tokenB, feeTiers[i]);
            if (poolAddress==address(0)) continue;
            IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

            uint128 liquidity = pool.liquidity();
            if (liquidity > maxLiquidity) {
                maxLiquidity = liquidity;
                selectedPool = pool;
            }
        }

        require(address(selectedPool) != address(0), "No pool found or no liquidity available");

        return selectedPool;
    }
}
