// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IAmm.sol";
import "./IPriceOracle.sol";
import "./IUniswapV3Factory.sol";
import "./IUniswapV3Pool.sol";
import "./FullMath.sol";
import "./Math.sol";
import "./TickMath.sol";
import "./UniswapV3TwapGetter.sol";
import "./FixedPoint96.sol";
import "./V3Oracle.sol";
import "./Initializable.sol";

contract PriceOracle is IPriceOracle, Initializable {
    using Math for uint256;
    using FullMath for uint256;
    using V3Oracle for V3Oracle.Observation[65535];

    uint8 public constant priceGap = 10;
    uint16 public constant cardinality = 60;
    uint32 public constant twapInterval = 900; // 15 min

    address public WETH;
    address public v3Factory;
    uint24[3] public v3Fees;

    // baseToken => quoteToken => v3Pool
    mapping(address => mapping(address => address)) public v3Pools;
    mapping(address => V3Oracle.Observation[65535]) public ammObservations;
    mapping(address => uint16) public ammObservationIndex;

    function initialize(address WETH_, address v3Factory_) public initializer {
        WETH = WETH_;
        v3Factory = v3Factory_;
        v3Fees[0] = 500;
        v3Fees[1] = 3000;
        v3Fees[2] = 10000;
    }

    function setupTwap(address amm) external override {
        require(!ammObservations[amm][0].initialized, "PriceOracle.setupTwap: ALREADY_SETUP");
        address baseToken = IAmm(amm).baseToken();
        address quoteToken = IAmm(amm).quoteToken();

        address pool = getTargetPool(baseToken, quoteToken);
        if (pool != address(0)) {
            _setupV3Pool(baseToken, quoteToken, pool);
        } else {
            pool = getTargetPool(baseToken, WETH);
            require(pool != address(0), "PriceOracle.setupTwap: POOL_NOT_FOUND");
            _setupV3Pool(baseToken, WETH, pool);

            pool = getTargetPool(WETH, quoteToken);
            require(pool != address(0), "PriceOracle.setupTwap: POOL_NOT_FOUND");
            _setupV3Pool(WETH, quoteToken, pool);
        }

        ammObservationIndex[amm] = 0;
        ammObservations[amm].initialize(_blockTimestamp());
        ammObservations[amm].grow(1, cardinality);
    }

    function updateAmmTwap(address amm) external override {
        uint160 sqrtPriceX96 = _getSqrtPriceX96(amm);
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        uint16 index = ammObservationIndex[amm];
        (uint16 indexUpdated, ) = ammObservations[amm].write(index, _blockTimestamp(), tick, cardinality, cardinality);
        ammObservationIndex[amm] = indexUpdated;
    }

    function quoteFromAmmTwap(address amm, uint256 baseAmount) external view override returns (uint256 quoteAmount) {
        uint160 sqrtPriceX96 = _getSqrtPriceX96(amm);
        uint16 index = ammObservationIndex[amm];
        V3Oracle.Observation memory observation = ammObservations[amm][(index + 1) % cardinality];
        if (!observation.initialized) {
            observation = ammObservations[amm][0];
        }
        uint32 currentTime = _blockTimestamp();
        uint32 delta = currentTime - observation.blockTimestamp;
        if (delta > 0) {
            address _amm = amm;
            uint32 _twapInterval = twapInterval;
            if (delta < _twapInterval) _twapInterval = delta;
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = twapInterval; // from (before)
            secondsAgos[1] = 0; // to (now)
            int56[] memory tickCumulatives = ammObservations[_amm].observe(
                currentTime,
                secondsAgos,
                TickMath.getTickAtSqrtRatio(sqrtPriceX96),
                index,
                cardinality
            );
            // tick(imprecise as it's an integer) to price
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
                int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(_twapInterval)))
            );
        }
        // priceX96 = token1/token0, this price is scaled by 2^96
        uint256 priceX96 = UniswapV3TwapGetter.getPriceX96FromSqrtPriceX96(sqrtPriceX96);
        quoteAmount = baseAmount.mulDiv(priceX96, FixedPoint96.Q96);
        require(quoteAmount > 0, "PriceOracle.quoteFromAmmTwap: ZERO_AMOUNT");
    }

    function quote(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) public view override returns (uint256 quoteAmount, uint8 source) {
        quoteAmount = quoteSingle(baseToken, quoteToken, baseAmount);
        if (quoteAmount == 0) {
            uint256 wethAmount = quoteSingle(baseToken, WETH, baseAmount);
            quoteAmount = quoteSingle(WETH, quoteToken, wethAmount);
        }
        require(quoteAmount > 0, "PriceOracle.quote: ZERO_AMOUNT");
    }

    // the price is scaled by 1e18. example: 1eth = 2000usdt, price = 2000*1e18
    function getIndexPrice(address amm) public view override returns (uint256) {
        address baseToken = IAmm(amm).baseToken();
        address quoteToken = IAmm(amm).quoteToken();
        uint256 baseDecimals = IERC20(baseToken).decimals();
        uint256 quoteDecimals = IERC20(quoteToken).decimals();
        (uint256 quoteAmount, ) = quote(baseToken, quoteToken, 10**baseDecimals);
        return quoteAmount * (10**(18 - quoteDecimals));
    }

    function getMarketPrice(address amm) public view override returns (uint256) {
        (uint112 baseReserve, uint112 quoteReserve, ) = IAmm(amm).getReserves();
        uint8 baseDecimals = IERC20(IAmm(amm).baseToken()).decimals();
        uint8 quoteDecimals = IERC20(IAmm(amm).quoteToken()).decimals();
        uint256 exponent = uint256(10**(18 + baseDecimals - quoteDecimals));
        return exponent.mulDiv(quoteReserve, baseReserve);
    }

    // the price is scaled by 1e18. example: 1eth = 2000usdt, price = 2000*1e18
    function getMarkPrice(address amm) public view override returns (uint256 price, bool isIndexPrice) {
        price = getMarketPrice(amm);
        uint256 indexPrice = getIndexPrice(amm);
        if (price * 100 >= indexPrice * (100 + priceGap) || price * 100 <= indexPrice * (100 - priceGap)) {
            price = indexPrice;
            isIndexPrice = true;
        }
    }

    function getMarkPriceAfterSwap(
        address amm,
        uint256 quoteAmount,
        uint256 baseAmount
    ) public view override returns (uint256 price, bool isIndexPrice) {
        (uint112 baseReserveBefore, uint112 quoteReserveBefore, ) = IAmm(amm).getReserves();
        address baseToken = IAmm(amm).baseToken();
        address quoteToken = IAmm(amm).quoteToken();
        uint256 baseReserveAfter;
        uint256 quoteReserveAfter;
        if (quoteAmount > 0) {
            uint256[2] memory amounts = IAmm(amm).estimateSwap(quoteToken, baseToken, quoteAmount, 0);
            baseReserveAfter = uint256(baseReserveBefore) - amounts[1];
            quoteReserveAfter = uint256(quoteReserveBefore) + quoteAmount;
        } else {
            uint256[2] memory amounts = IAmm(amm).estimateSwap(baseToken, quoteToken, baseAmount, 0);
            baseReserveAfter = uint256(baseReserveBefore) + baseAmount;
            quoteReserveAfter = uint256(quoteReserveBefore) - amounts[1];
        }

        uint8 baseDecimals = IERC20(baseToken).decimals();
        uint8 quoteDecimals = IERC20(quoteToken).decimals();
        uint256 exponent = uint256(10**(18 + baseDecimals - quoteDecimals));
        price = exponent.mulDiv(quoteReserveAfter, baseReserveAfter);

        address amm_ = amm; // avoid stack too deep
        uint256 indexPrice = getIndexPrice(amm_);
        if (price * 100 >= indexPrice * (100 + priceGap) || price * 100 <= indexPrice * (100 - priceGap)) {
            price = indexPrice;
            isIndexPrice = true;
        }
    }

    // example: 1eth = 2000usdt, 1eth = 1e18, 1usdt = 1e6, price = (1e6/1e18)*1e18
    function getMarkPriceInRatio(
        address amm,
        uint256 quoteAmount,
        uint256 baseAmount
    )
        public
        view
        override
        returns (
            uint256 resultBaseAmount,
            uint256 resultQuoteAmount,
            bool isIndexPrice
        )
    {
        require(quoteAmount == 0 || baseAmount == 0, "PriceOracle.getMarkPriceInRatio: AT_LEAST_ONE_ZERO");
        uint256 markPrice;
        (markPrice, isIndexPrice) = getMarkPrice(amm);
        if (!isIndexPrice) {
            (markPrice, isIndexPrice) = getMarkPriceAfterSwap(amm, quoteAmount, baseAmount);
        }

        uint8 baseDecimals = IERC20(IAmm(amm).baseToken()).decimals();
        uint8 quoteDecimals = IERC20(IAmm(amm).quoteToken()).decimals();
        uint256 ratio;
        if (quoteDecimals > baseDecimals) {
            ratio = markPrice * 10**(quoteDecimals - baseDecimals);
        } else {
            ratio = markPrice / 10**(baseDecimals - quoteDecimals);
        }
        if (quoteAmount > 0) {
            resultBaseAmount = (quoteAmount * 1e18) / ratio;
        } else {
            resultQuoteAmount = (baseAmount * ratio) / 1e18;
        }
    }

    // get user's mark price, return base amount, it's for checking if user's position can be liquidated.
    // price = ( sqrt(markPrice) +/- beta * quoteAmount / sqrt(x*y) )**2
    function getMarkPriceAcc(
        address amm,
        uint8 beta,
        uint256 quoteAmount,
        bool negative
    ) external view override returns (uint256 baseAmount) {
        (uint112 baseReserve, uint112 quoteReserve, ) = IAmm(amm).getReserves();
        require((2 * beta * quoteAmount) / 100 < quoteReserve, "PriceOracle.getMarkPriceAcc: SLIPPAGE_TOO_LARGE");

        (uint256 baseAmount_, , bool isIndexPrice) = getMarkPriceInRatio(amm, quoteAmount, 0);
        if (!isIndexPrice) {
            // markPrice = y/x
            // price = ( sqrt(y/x) +/- beta * quoteAmount / sqrt(x*y) )**2 = (y +/- beta * quoteAmount)**2 / x*y
            // baseAmount = quoteAmount / price = quoteAmount * x * y / (y +/- beta * quoteAmount)**2
            uint256 rvalue = (quoteAmount * beta) / 100;
            uint256 denominator;
            if (negative) {
                denominator = quoteReserve - rvalue;
            } else {
                denominator = quoteReserve + rvalue;
            }
            denominator = denominator * denominator;
            baseAmount = quoteAmount.mulDiv(uint256(baseReserve) * quoteReserve, denominator);
        } else {
            // price = markPrice(1 +/- 2 * beta * quoteAmount / quoteReserve)
            uint256 markPrice = (quoteAmount * 1e18) / baseAmount_;
            uint256 rvalue = markPrice.mulDiv((2 * beta * quoteAmount) / 100, quoteReserve);
            uint256 price;
            if (negative) {
                price = markPrice - rvalue;
            } else {
                price = markPrice + rvalue;
            }
            baseAmount = quoteAmount.mulDiv(1e18, price);
        }
    }

    //premiumFraction is (marketPrice - indexPrice) / 24h / indexPrice, scale by 1e18
    function getPremiumFraction(address amm) external view override returns (int256) {
        uint256 marketPrice = getMarketPrice(amm);
        uint256 indexPrice = getIndexPrice(amm);
        require(marketPrice > 0 && indexPrice > 0, "PriceOracle.getPremiumFraction: INVALID_PRICE");
        return ((int256(marketPrice) - int256(indexPrice)) * 1e18) / (24 * 3600) / int256(indexPrice);
    }

    function quoteSingle(
        address baseToken,
        address quoteToken,
        uint256 baseAmount
    ) public view returns (uint256 quoteAmount) {
        address pool = v3Pools[baseToken][quoteToken];
        if (pool == address(0)) {
            pool = getTargetPool(baseToken, quoteToken);
        }
        if (pool == address(0)) return 0;
        uint160 sqrtPriceX96 = UniswapV3TwapGetter.getSqrtTwapX96(pool, twapInterval);
        // priceX96 = token1/token0, this price is scaled by 2^96
        uint256 priceX96 = UniswapV3TwapGetter.getPriceX96FromSqrtPriceX96(sqrtPriceX96);
        if (baseToken == IUniswapV3Pool(pool).token0()) {
            quoteAmount = baseAmount.mulDiv(priceX96, FixedPoint96.Q96);
        } else {
            quoteAmount = baseAmount.mulDiv(FixedPoint96.Q96, priceX96);
        }
    }

    function getTargetPool(address baseToken, address quoteToken) public view returns (address) {
        // find out the pool with best liquidity as target pool
        address pool;
        address tempPool;
        uint256 poolLiquidity;
        uint256 tempLiquidity;
        for (uint256 i = 0; i < v3Fees.length; i++) {
            tempPool = IUniswapV3Factory(v3Factory).getPool(baseToken, quoteToken, v3Fees[i]);
            if (tempPool == address(0)) continue;
            tempLiquidity = uint256(IUniswapV3Pool(tempPool).liquidity());
            // use the max liquidity pool as index price source
            if (tempLiquidity > poolLiquidity) {
                poolLiquidity = tempLiquidity;
                pool = tempPool;
            }
        }
        return pool;
    }

    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp); // truncation is desired
    }

    function _getSqrtPriceX96(address amm) internal view returns (uint160) {
        (uint112 baseReserve, uint112 quoteReserve, ) = IAmm(amm).getReserves();
        uint256 priceX192 = uint256(quoteReserve).mulDiv(2**192, baseReserve);
        return uint160(priceX192.sqrt());
    }

    function _setupV3Pool(
        address baseToken,
        address quoteToken,
        address pool
    ) internal {
        if (v3Pools[baseToken][quoteToken] == address(0)) {
            v3Pools[baseToken][quoteToken] = pool;
            IUniswapV3Pool v3Pool = IUniswapV3Pool(pool);
            (, , , , uint16 cardinalityNext, , ) = v3Pool.slot0();
            if (cardinalityNext < cardinality) {
                IUniswapV3Pool(pool).increaseObservationCardinalityNext(cardinality);
            }
        }
    }
}

