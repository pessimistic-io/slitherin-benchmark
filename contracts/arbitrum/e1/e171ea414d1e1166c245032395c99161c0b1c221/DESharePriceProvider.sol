//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.6;

import "./Denominations.sol";

import "./FeedRegistryInterface.sol";
import "./TickMath.sol";
import "./PositionKey.sol";
import "./FixedPoint128.sol";
import "./LiquidityAmounts.sol";
import "./IERC20Metadata.sol";
import "./IChainlinkAggregatorV3Interface.sol";
import "./IDEAccountManager.sol";
import "./IUnboundBase.sol";
import "./IDefiEdgeStrategy.sol";

library DESharePriceProvider {

    uint256 constant BASE = 1e18;

    // to get rid of stack too deep error
    struct LocalVariable_PositionData {
        uint128 liquidity;
        uint256 feeGrowthInside0Last;
        uint256 feeGrowthInside1Last;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        uint256 position0;
        uint256 position1;
        uint256 fee0;
        uint256 fee1;
    }

    struct LocalVariables_FeesData {
        uint256 feeGrowthGlobal0X;
        uint256 feeGrowthGlobal1X;
        uint256 feeGrowthOutside0XLower;
        uint256 feeGrowthOutside1XLower;
        uint256 feeGrowthOutside0XUpper;
        uint256 feeGrowthOutside1XUpper;
        uint256 feeGrowthBelow0X;
        uint256 feeGrowthBelow1X;
        uint256 feeGrowthAbove0X;
        uint256 feeGrowthAbove1X;
        uint256 feeGrowthInside0X;
        uint256 feeGrowthInside1X;
    }

    /**
     * Calculates the price of the pair token using the formula of arithmetic mean.
     * @param _shareToken Address of the Uniswap V2 pair
     * @param _reserve0 Total usd value for token 0.
     * @param _reserve1 Total usd value for token 1.
     * @return Arithematic mean of _reserve0 and _reserve1
     */
    function getArithmeticMean(
        IDefiEdgeStrategy _shareToken,
        uint256 _reserve0,
        uint256 _reserve1
    ) internal view returns (uint256) {
        uint256 totalValue = _reserve0 + _reserve1;
        return (totalValue * BASE) / getTotalSupply(_shareToken);
    }

    /**
     * @notice Returns Uniswap V2 pair total supply at the time of withdrawal.
     * @param _shareToken Address of the pair
     * @return totalSupply Total supply of the Defiedge share token at the time user withdraws
     */
    function getTotalSupply(IDefiEdgeStrategy _shareToken)
        internal
        view
        returns (uint256 totalSupply)
    {
        totalSupply = _shareToken.totalSupply();
        return totalSupply;
    }

    /**
     * @notice Returns normalised value in 18 digits
     * @param _value Value which we want to normalise
     * @param _decimals Number of decimals from which we want to normalise
     * @return normalised Returns normalised value in 1e18 format
     */
    function normalise(uint256 _value, uint256 _decimals)
        internal
        pure
        returns (uint256 normalised)
    {
        normalised = _value;
        if (_decimals < 18) {
            uint256 missingDecimals = uint256(18) - _decimals;
            normalised = uint256(_value) * 10**(missingDecimals);
        } else if (_decimals > 18) {
            uint256 extraDecimals = _decimals - uint256(18);
            normalised = uint256(_value) / 10**(extraDecimals);
        }
    }

    /**
     * @notice Returns latest Chainlink price, and normalise it
     * @param _registry registry
     * @param _base Base Asset
     * @param _quote Quote Asset
     * @param _validPeriod period for last oracle price update
     */
    function getChainlinkPrice(
        FeedRegistryInterface _registry,
        address _base,
        address _quote,
        uint256 _validPeriod
    ) internal view returns (uint256 price) {
        (, int256 _price, , uint256 updatedAt, ) = _registry.latestRoundData(
            _base,
            _quote
        );

        // check if the oracle is expired
        require(block.timestamp - updatedAt < _validPeriod, "OLD_PRICE");
        require(_price > 0, "ERR_NO_ORACLE_PRICE");

        // normalise the price to 18 decimals
        uint256 _decimals = _registry.decimals(_base, _quote);

        if (_decimals < 18) {
            uint256 missingDecimals = uint256(18) - _decimals;
            price = uint256(_price) * (10**(missingDecimals));
        } else if (_decimals > 18) {
            uint256 extraDecimals = _decimals - uint256(18);
            price = uint256(_price) / (10**(extraDecimals));
        }

        return price;
    }

    /**
     * @notice Returns reserve value in dollars
     * @param _price Chainlink Price.
     * @param _reserve Token reserves.
     * @param _decimals Number of decimals in the the reserve value
     * @return Returns normalised reserve value in 1e18
     */
    function getReserveValue(
        uint256 _price,
        uint256 _reserve,
        uint256 _decimals
    ) internal pure returns (uint256) {
        uint256 reservePrice = normalise(_reserve, _decimals);
        return (reservePrice * _price) / BASE;
    }

    function getSqrtRatioForPrice(
        uint256 _token0Price,
        uint256 _token1Price,
        uint256 _token0Decimals,
        uint256 _token1Decimals
    ) internal pure returns (uint160 sqrtRatioX96) {
        sqrtRatioX96 = toUint160(
            sqrt(
                ((_token0Price * (10 ** _token1Decimals)) * (1 << 96)) /
                    (_token1Price * (10 ** _token0Decimals))
            ) << 48
        );
    }

    /**
     * @notice Calculate strategy AUM
     * @param _strategy Defiedge strategy contract instance
     * @param _pool UniswapV3 pool instance
     */
    function _getStrategyReserves(
        IDefiEdgeStrategy _strategy,
        IUniswapV3Pool _pool,
        uint160 sqrtRatioX96
    ) internal view returns (uint256 reserve0, uint256 reserve1) {

        // query all ticks from strategy
        IDefiEdgeStrategy.Tick[] memory ticks = _strategy.getTicks();

        // get unused amounts
        reserve0 = IERC20(_pool.token0()).balanceOf(address(_strategy));
        reserve1 = IERC20(_pool.token1()).balanceOf(address(_strategy));

        (, int24 tick, , , , , ) = _pool.slot0();

        // get AUM from each tick
        for (uint256 i = 0; i < ticks.length; i++) {
            IDefiEdgeStrategy.Tick memory _currTick = ticks[i];

            (uint256 amount0, uint256 amount1) = _calculateAUMAtTick(
                _currTick,
                _strategy,
                _pool,
                sqrtRatioX96,
                tick
            );

            reserve0 += amount0;
            reserve1 += amount1;
        }
    }

    // calculate strategy liquidity at specific tick
    function _calculateAUMAtTick(
        IDefiEdgeStrategy.Tick memory _tick,
        IDefiEdgeStrategy _strategy,
        IUniswapV3Pool _pool,
        uint160 sqrtRatioX96,
        int24 _tickSlot0
    ) internal view returns (uint256 amount0, uint256 amount1) {
        LocalVariable_PositionData memory _posData;
        // get current liquidity of strategy from the pool
        (
            _posData.liquidity,
            _posData.feeGrowthInside0Last,
            _posData.feeGrowthInside1Last,
            _posData.tokensOwed0,
            _posData.tokensOwed1
        ) = _pool.positions(
            PositionKey.compute(
                address(_strategy),
                _tick.tickLower,
                _tick.tickUpper
            )
        );

        // calculate x positions in the pool from liquidity
        (_posData.position0, _posData.position1) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(_tick.tickLower),
                TickMath.getSqrtRatioAtTick(_tick.tickUpper),
                _posData.liquidity
            );

        // compute current fees earned
        (_posData.fee0, _posData.fee1) = _calculateUnclaimedFeesTotal(
            _posData.feeGrowthInside0Last,
            _posData.feeGrowthInside1Last,
            _tickSlot0,
            _posData.liquidity,
            _pool,
            _tick.tickLower,
            _tick.tickUpper
        );

        // sum of liquidity at specific tick, generated fees and tokenOwed
        amount0 +=
            _posData.position0 +
            _posData.fee0 +
            uint256(_posData.tokensOwed0);
        amount1 +=
            _posData.position1 +
            _posData.fee1 +
            uint256(_posData.tokensOwed1);
    }

    // calculate unclaimed fees for token0 and token1
    function _calculateUnclaimedFeesTotal(
        uint256 feeGrowthInside0Last,
        uint256 feeGrowthInside1Last,
        int24 tickCurrent,
        uint128 liquidity,
        IUniswapV3Pool pool,
        int24 lowerTick,
        int24 upperTick
    ) internal view returns (uint256 fee0, uint256 fee1) {
        LocalVariables_FeesData memory feesData;

        feesData.feeGrowthGlobal0X = pool.feeGrowthGlobal0X128();
        feesData.feeGrowthGlobal1X = pool.feeGrowthGlobal1X128();

        ( , , feesData.feeGrowthOutside0XLower, feesData.feeGrowthOutside1XLower, , , ,) = pool.ticks(lowerTick);
        ( , , feesData.feeGrowthOutside0XUpper, feesData.feeGrowthOutside1XUpper, , , ,) = pool.ticks(upperTick);

        // calculate fee growth below
        if (tickCurrent >= lowerTick) {
            feesData.feeGrowthBelow0X = feesData.feeGrowthOutside0XLower;
            feesData.feeGrowthBelow1X = feesData.feeGrowthOutside1XLower;
        } else {
            feesData.feeGrowthBelow0X =
                feesData.feeGrowthGlobal0X -
                feesData.feeGrowthOutside0XLower;
            feesData.feeGrowthBelow1X =
                feesData.feeGrowthGlobal1X -
                feesData.feeGrowthOutside1XLower;
        }

        // calculate fee growth above
        if (tickCurrent < upperTick) {
            feesData.feeGrowthAbove0X = feesData.feeGrowthOutside0XUpper;
            feesData.feeGrowthAbove1X = feesData.feeGrowthOutside1XUpper;
        } else {
            feesData.feeGrowthAbove0X =
                feesData.feeGrowthGlobal0X -
                feesData.feeGrowthOutside0XUpper;
            feesData.feeGrowthAbove1X =
                feesData.feeGrowthGlobal1X -
                feesData.feeGrowthOutside1XUpper;
        }

        feesData.feeGrowthInside0X =
            feesData.feeGrowthGlobal0X -
            feesData.feeGrowthBelow0X -
            feesData.feeGrowthAbove0X;
        feesData.feeGrowthInside1X =
            feesData.feeGrowthGlobal1X -
            feesData.feeGrowthBelow1X -
            feesData.feeGrowthAbove1X;

        fee0 = FullMath.mulDiv(
            feesData.feeGrowthInside0X - feeGrowthInside0Last,
            liquidity,
            FixedPoint128.Q128
        );

        fee1 = FullMath.mulDiv(
            feesData.feeGrowthInside1X - feeGrowthInside1Last,
            liquidity,
            FixedPoint128.Q128
        );
    }

    function _requireNoReentrant(IDefiEdgeStrategy defiedgeStrategy)
        internal
    {

        // revert if stratgy call failed with reentrant call error
        try defiedgeStrategy.burn(type(uint256).max, 0, 0) {} catch Error(
            string memory reason
        ) {
            if (
                keccak256(abi.encodePacked(reason)) ==
                keccak256(abi.encodePacked("ReentrancyGuard: reentrant call"))
            ) {
                revert(reason);
            }
        }
    }

    /**
     * @dev Returns the pair's price.
     *   It calculates the price using Chainlink as an external price source and the pair's tokens reserves using the arithmetic mean formula.
     * @param _accountManager Instance of AccountManager contract
     * @return int256 price
     */
    function latestAnswer(IDEAccountManager _accountManager)
        internal
        returns (int256)
    {
        FeedRegistryInterface chainLinkRegistry = FeedRegistryInterface(
            _accountManager.chainLinkRegistry()
        );

        uint256 _allowedDelay = _accountManager.allowedDelay();

        IDefiEdgeStrategy defiedgeStrategy = IDefiEdgeStrategy(
            address(_accountManager.depositToken())
        );

        // prevent reentrant calls from defiedge strategy contract
        _requireNoReentrant(defiedgeStrategy);

        IUniswapV3Pool pool = defiedgeStrategy.pool();

        uint256 token0Decimals = IERC20Metadata(pool.token0()).decimals();
        uint256 token1Decimals = IERC20Metadata(pool.token1()).decimals();

        uint256 chainlinkPrice0 = uint256(
            getChainlinkPrice(
                chainLinkRegistry,
                pool.token0(),
                Denominations.USD,
                _allowedDelay
            )
        );
        uint256 chainlinkPrice1 = uint256(
            getChainlinkPrice(
                chainLinkRegistry,
                pool.token1(),
                Denominations.USD,
                _allowedDelay
            )
        );

        // calculate sqrtRatio for defined chainlink price
        uint160 sqrtRatioX96 = getSqrtRatioForPrice(
            chainlinkPrice0,
            chainlinkPrice1,
            token0Decimals,
            token1Decimals
        );

        //Get token reserves in strategy
        (uint256 reserve0, uint256 reserve1) = _getStrategyReserves(
            defiedgeStrategy,
            pool,
            sqrtRatioX96
        );

        uint256 reserveInStablecoin0 = getReserveValue(
            chainlinkPrice0,
            reserve0,
            token0Decimals
        );
        uint256 reserveInStablecoin1 = getReserveValue(
            chainlinkPrice1,
            reserve1,
            token1Decimals
        );

        //Calculate the arithmetic mean
        return
            int256(
                getArithmeticMean(
                    defiedgeStrategy,
                    reserveInStablecoin0,
                    reserveInStablecoin1
                )
            );
    }

    function toUint160(uint256 x) private pure returns (uint160 z) {
        require((z = uint160(x)) == x, "uint160-overflow");
    }

    // FROM https://github.com/abdk-consulting/abdk-libraries-solidity/blob/16d7e1dd8628dfa2f88d5dadab731df7ada70bdd/ABDKMath64x64.sol#L687
    function sqrt(uint256 _x) private pure returns (uint128) {
        if (_x == 0) return 0;
        else {
            uint256 xx = _x;
            uint256 r = 1;
            if (xx >= 0x100000000000000000000000000000000) {
                xx >>= 128;
                r <<= 64;
            }
            if (xx >= 0x10000000000000000) {
                xx >>= 64;
                r <<= 32;
            }
            if (xx >= 0x100000000) {
                xx >>= 32;
                r <<= 16;
            }
            if (xx >= 0x10000) {
                xx >>= 16;
                r <<= 8;
            }
            if (xx >= 0x100) {
                xx >>= 8;
                r <<= 4;
            }
            if (xx >= 0x10) {
                xx >>= 4;
                r <<= 2;
            }
            if (xx >= 0x8) {
                r <<= 1;
            }
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1; // Seven iterations should be enough
            uint256 r1 = _x / r;
            return uint128(r < r1 ? r : r1);
        }
    }
}

