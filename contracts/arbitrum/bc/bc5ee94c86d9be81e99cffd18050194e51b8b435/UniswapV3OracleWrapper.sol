// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IUniswapV3OracleWrapper} from "./IUniswapV3OracleWrapper.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "./IPriceOracleGetter.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {IUniswapV3PoolState} from "./IUniswapV3PoolState.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {TickMath} from "./TickMath.sol";
import {SqrtLib} from "./SqrtLib.sol";
import {FullMath} from "./FullMath.sol";
import {IERC20Detailed} from "./IERC20Detailed.sol";
import {UinswapV3PositionData} from "./IUniswapV3PositionInfoProvider.sol";
import {SafeCast} from "./SafeCast.sol";
import {FixedPoint96} from "./libraries_FixedPoint96.sol";

contract UniswapV3OracleWrapper is IUniswapV3OracleWrapper {
    using SafeCast for uint256;

    IUniswapV3Factory immutable UNISWAP_V3_FACTORY;
    INonfungiblePositionManager immutable UNISWAP_V3_POSITION_MANAGER;
    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;

    constructor(
        address _factory,
        address _manager,
        address _addressProvider
    ) {
        UNISWAP_V3_FACTORY = IUniswapV3Factory(_factory);
        UNISWAP_V3_POSITION_MANAGER = INonfungiblePositionManager(_manager);
        ADDRESSES_PROVIDER = IPoolAddressesProvider(_addressProvider);
    }

    struct FeeParams {
        uint256 feeGrowthOutside0X128Lower;
        uint256 feeGrowthOutside1X128Lower;
        uint256 feeGrowthOutside0X128Upper;
        uint256 feeGrowthOutside1X128Upper;
    }

    struct PairOracleData {
        uint256 token0Price;
        uint256 token1Price;
        uint8 token0Decimal;
        uint8 token1Decimal;
        uint160 sqrtPriceX96;
    }

    /**
     * @notice get onchain position data from uniswap for the specified tokenId.
     */
    function getOnchainPositionData(uint256 tokenId)
        public
        view
        returns (UinswapV3PositionData memory)
    {
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint256 tokensOwed0,
            uint256 tokensOwed1
        ) = UNISWAP_V3_POSITION_MANAGER.positions(tokenId);

        IUniswapV3PoolState pool = IUniswapV3PoolState(
            UNISWAP_V3_FACTORY.getPool(token0, token1, fee)
        );
        (uint160 currentPrice, int24 currentTick, , , , , ) = pool.slot0();

        return
            UinswapV3PositionData({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                currentTick: currentTick,
                currentPrice: currentPrice,
                liquidity: liquidity,
                feeGrowthInside0LastX128: feeGrowthInside0LastX128,
                feeGrowthInside1LastX128: feeGrowthInside1LastX128,
                tokensOwed0: tokensOwed0,
                tokensOwed1: tokensOwed1
            });
    }

    /**
     * @notice get onchain liquidity amount for the specified tokenId.
     */
    function getLiquidityAmount(uint256 tokenId)
        external
        view
        returns (uint256 token0Amount, uint256 token1Amount)
    {
        UinswapV3PositionData memory positionData = getOnchainPositionData(
            tokenId
        );
        (token0Amount, token1Amount) = getLiquidityAmountFromPositionData(
            positionData
        );
    }

    /**
     * @notice calculate liquidity amount for the position data.
     * @param positionData The specified position data
     */
    function getLiquidityAmountFromPositionData(
        UinswapV3PositionData memory positionData
    ) public pure returns (uint256 token0Amount, uint256 token1Amount) {
        (token0Amount, token1Amount) = LiquidityAmounts.getAmountsForLiquidity(
            positionData.currentPrice,
            TickMath.getSqrtRatioAtTick(positionData.tickLower),
            TickMath.getSqrtRatioAtTick(positionData.tickUpper),
            positionData.liquidity
        );
    }

    /**
     * @notice get liquidity provider fee amount for the specified tokenId.
     */
    function getLpFeeAmount(uint256 tokenId)
        external
        view
        returns (uint256 token0Amount, uint256 token1Amount)
    {
        UinswapV3PositionData memory positionData = getOnchainPositionData(
            tokenId
        );
        (token0Amount, token1Amount) = getLpFeeAmountFromPositionData(
            positionData
        );
    }

    /**
     * @notice calculate liquidity provider fee amount for the position data.
     * @param positionData The specified position data
     */
    function getLpFeeAmountFromPositionData(
        UinswapV3PositionData memory positionData
    ) public view returns (uint256 token0Amount, uint256 token1Amount) {
        (token0Amount, token1Amount) = _getPendingFeeAmounts(positionData);

        token0Amount += positionData.tokensOwed0;
        token1Amount += positionData.tokensOwed1;
    }

    /**
     * @notice Returns the price for the specified tokenId.
     */
    function getTokenPrice(uint256 tokenId) public view returns (uint256) {
        UinswapV3PositionData memory positionData = getOnchainPositionData(
            tokenId
        );

        PairOracleData memory oracleData = _getOracleData(positionData);

        (uint256 liquidityAmount0, uint256 liquidityAmount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                oracleData.sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(positionData.tickLower),
                TickMath.getSqrtRatioAtTick(positionData.tickUpper),
                positionData.liquidity
            );

        (
            uint256 feeAmount0,
            uint256 feeAmount1
        ) = getLpFeeAmountFromPositionData(positionData);

        return
            (((liquidityAmount0 + feeAmount0) * oracleData.token0Price) /
                10**oracleData.token0Decimal) +
            (((liquidityAmount1 + feeAmount1) * oracleData.token1Price) /
                10**oracleData.token1Decimal);
    }

    function _getOracleData(UinswapV3PositionData memory positionData)
        internal
        view
        returns (PairOracleData memory)
    {
        PairOracleData memory oracleData;
        IPriceOracleGetter oracle = IPriceOracleGetter(
            ADDRESSES_PROVIDER.getPriceOracle()
        );
        oracleData.token0Price = oracle.getAssetPrice(positionData.token0);
        oracleData.token1Price = oracle.getAssetPrice(positionData.token1);

        oracleData.token0Decimal = IERC20Detailed(positionData.token0)
            .decimals();
        oracleData.token1Decimal = IERC20Detailed(positionData.token1)
            .decimals();

        oracleData.sqrtPriceX96 = ((SqrtLib.sqrt(
            ((oracleData.token0Price *
                10 **
                    (36 +
                        oracleData.token1Decimal -
                        oracleData.token0Decimal)) / (oracleData.token1Price))
        ) << FixedPoint96.RESOLUTION) / 1E18).toUint160();

        return oracleData;
    }

    function _getPendingFeeAmounts(UinswapV3PositionData memory positionData)
        internal
        view
        returns (uint256 token0Amount, uint256 token1Amount)
    {
        IUniswapV3PoolState pool = IUniswapV3PoolState(
            UNISWAP_V3_FACTORY.getPool(
                positionData.token0,
                positionData.token1,
                positionData.fee
            )
        );
        FeeParams memory feeParams;

        (
            ,
            ,
            feeParams.feeGrowthOutside0X128Lower,
            feeParams.feeGrowthOutside1X128Lower,
            ,
            ,
            ,

        ) = pool.ticks(positionData.tickLower);
        (
            ,
            ,
            feeParams.feeGrowthOutside0X128Upper,
            feeParams.feeGrowthOutside1X128Upper,
            ,
            ,
            ,

        ) = pool.ticks(positionData.tickUpper);

        uint256 feeGrowthGlobal0X128 = pool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobal1X128 = pool.feeGrowthGlobal1X128();

        unchecked {
            // calculate fee growth below
            uint256 feeGrowthBelow0X128;
            uint256 feeGrowthBelow1X128;
            if (positionData.currentTick >= positionData.tickLower) {
                feeGrowthBelow0X128 = feeParams.feeGrowthOutside0X128Lower;
                feeGrowthBelow1X128 = feeParams.feeGrowthOutside1X128Lower;
            } else {
                feeGrowthBelow0X128 =
                    feeGrowthGlobal0X128 -
                    feeParams.feeGrowthOutside0X128Lower;
                feeGrowthBelow1X128 =
                    feeGrowthGlobal1X128 -
                    feeParams.feeGrowthOutside1X128Lower;
            }

            // calculate fee growth above
            uint256 feeGrowthAbove0X128;
            uint256 feeGrowthAbove1X128;
            if (positionData.currentTick < positionData.tickUpper) {
                feeGrowthAbove0X128 = feeParams.feeGrowthOutside0X128Upper;
                feeGrowthAbove1X128 = feeParams.feeGrowthOutside1X128Upper;
            } else {
                feeGrowthAbove0X128 =
                    feeGrowthGlobal0X128 -
                    feeParams.feeGrowthOutside0X128Upper;
                feeGrowthAbove1X128 =
                    feeGrowthGlobal1X128 -
                    feeParams.feeGrowthOutside1X128Upper;
            }
            uint256 feeGrowthInside0X128;
            uint256 feeGrowthInside1X128;

            feeGrowthInside0X128 =
                feeGrowthGlobal0X128 -
                feeGrowthBelow0X128 -
                feeGrowthAbove0X128;
            feeGrowthInside1X128 =
                feeGrowthGlobal1X128 -
                feeGrowthBelow1X128 -
                feeGrowthAbove1X128;

            token0Amount = uint128(
                FullMath.mulDiv(
                    feeGrowthInside0X128 -
                        positionData.feeGrowthInside0LastX128,
                    positionData.liquidity,
                    Q128
                )
            );

            token1Amount = uint128(
                FullMath.mulDiv(
                    feeGrowthInside1X128 -
                        positionData.feeGrowthInside1LastX128,
                    positionData.liquidity,
                    Q128
                )
            );
        }
    }
}

