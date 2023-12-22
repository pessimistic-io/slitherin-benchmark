// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.7.6;

import "./IUniswapV3Factory.sol";
import "./TickMath.sol";
import "./FixedPoint96.sol";
import "./FixedPoint128.sol";
import "./FullMath.sol";

import "./IUniswapHelper.sol";
import "./INonfungiblePositionManager.sol";

contract UniswapHelper is IUniswapHelper {
    uint256 public override constant PRECISION_DECIMALS = 12;

    INonfungiblePositionManager public positionManager;
    IUniswapV3Factory public factory;

    constructor(INonfungiblePositionManager _positionManager, IUniswapV3Factory _factory) {
        positionManager = _positionManager;
        factory = _factory;
    }

    struct PositionInfo {
        address token0;
        address token1;
        uint24 poolFee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 positionFeeGrowthInside0LastX128;
        uint256 positionFeeGrowthInside1LastX128;
        uint128 token0Fees;
        uint128 token1Fees;
    }

    struct FeesOfLocals {
        uint256 feeGrowthInside0X128;
        uint256 feeGrowthInside1X128;
        uint256 lowerFeeGrowthOutside0X128;
        uint256 lowerFeeGrowthOutside1X128;
        uint256 upperFeeGrowthOutside0X128;
        uint256 upperFeeGrowthOutside1X128;
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
    }

    function feesOf(uint256 _tokenId) view external override returns (uint256 token0Fees, uint256 token1Fees, IUniswapV3Pool pool) {
        FeesOfLocals memory locals;
        PositionInfo memory positionInfo = getPosition(_tokenId);

        pool = IUniswapV3Pool(factory.getPool(positionInfo.token0, positionInfo.token1, positionInfo.poolFee));

        (,, locals.lowerFeeGrowthOutside0X128, locals.lowerFeeGrowthOutside1X128,,,,) = pool.ticks(positionInfo.tickLower);
        (,, locals.upperFeeGrowthOutside0X128, locals.upperFeeGrowthOutside1X128,,,,) = pool.ticks(positionInfo.tickUpper);
        (, int24 tickCurrent,,,,,) = pool.slot0();

        if (tickCurrent >= positionInfo.tickLower) {
            locals.feeGrowthBelow0X128 = locals.lowerFeeGrowthOutside0X128;
            locals.feeGrowthBelow1X128 = locals.lowerFeeGrowthOutside1X128;
        } else {
            locals.feeGrowthBelow0X128 = pool.feeGrowthGlobal0X128() - locals.lowerFeeGrowthOutside0X128;
            locals.feeGrowthBelow1X128 = pool.feeGrowthGlobal1X128() - locals.lowerFeeGrowthOutside1X128;
        }

        if (tickCurrent < positionInfo.tickUpper) {
            locals.feeGrowthAbove0X128 = locals.upperFeeGrowthOutside0X128;
            locals.feeGrowthAbove1X128 = locals.upperFeeGrowthOutside1X128;
        } else {
            locals.feeGrowthAbove0X128 = pool.feeGrowthGlobal0X128() - locals.upperFeeGrowthOutside0X128;
            locals.feeGrowthAbove1X128 = pool.feeGrowthGlobal1X128() - locals.upperFeeGrowthOutside1X128;
        }

        locals.feeGrowthInside0X128 = pool.feeGrowthGlobal0X128() - locals.feeGrowthBelow0X128 - locals.feeGrowthAbove0X128;
        locals.feeGrowthInside1X128 = pool.feeGrowthGlobal1X128() - locals.feeGrowthBelow1X128 - locals.feeGrowthAbove1X128;

        token0Fees = positionInfo.token0Fees + 
            calculateFees(locals.feeGrowthInside0X128, positionInfo.positionFeeGrowthInside0LastX128, positionInfo.liquidity);
        token1Fees = positionInfo.token1Fees +
            calculateFees(locals.feeGrowthInside1X128, positionInfo.positionFeeGrowthInside1LastX128, positionInfo.liquidity);
    }
	
    // Based on: https://medium.com/blockchain-development-notes/a-guide-on-uniswap-v3-twap-oracle-2aa74a4a97c5
    function getTWAPPrice(IUniswapV3Pool _pool, uint32 _interval, bool _isToken0ETH) external view override returns (uint256 price) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = _interval;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives, ) = _pool.observe(secondsAgos);

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(int24((tickCumulatives[1] - tickCumulatives[0]) / _interval));

        // Converts sqrtPriceX96 to actual price in revelant token decimals 
        // (see calculation here: https://docs.uniswap.org/sdk/guides/fetching-prices)
        price = sqrtX96PriceToUintPrice(sqrtPriceX96, _isToken0ETH);
    }

    function getSpotPrice(IUniswapV3Pool _pool, bool _isToken0ETH) external view override returns (uint256 price) {
        (uint160 sqrtPriceX96,,,,,,) = _pool.slot0();
        price = sqrtX96PriceToUintPrice(sqrtPriceX96, _isToken0ETH);
    }

    function calculateFees(uint256 _feeGrowthInside1X128, uint256 _positionFeeGrowthInside1LastX128, uint128 _liquidity) private pure returns (uint128 fees) {
        fees = uint128(FullMath.mulDiv(_feeGrowthInside1X128 - _positionFeeGrowthInside1LastX128, _liquidity, FixedPoint128.Q128));
    }

    function getPosition(uint256 _tokenId) private view returns (PositionInfo memory result) {
        (,,result.token0, result.token1, result.poolFee, result.tickLower, result.tickUpper, result.liquidity,,,,) = positionManager.positions(_tokenId);
        (,,,,,,,, result.positionFeeGrowthInside0LastX128, result.positionFeeGrowthInside1LastX128, result.token0Fees, result.token1Fees) = positionManager.positions(_tokenId);
    }

    function sqrtX96PriceToUintPrice(uint160 _sqrtPriceX96, bool _isToken0ETH) private pure returns (uint256 price) {
        if (!_isToken0ETH) {
            price = FullMath.mulDiv(FullMath.mulDiv(10 ** PRECISION_DECIMALS, _sqrtPriceX96, FixedPoint96.Q96), _sqrtPriceX96, FixedPoint96.Q96);
        } else {
            // 2 ** 192 / _sqrtPriceX96 ** 2 in a safe way
            //price = 2 ** 192 / _sqrtPriceX96 ** 2;
            price = FullMath.mulDiv(10 ** PRECISION_DECIMALS, FixedPoint96.Q96 ** 2, _sqrtPriceX96) / _sqrtPriceX96;
        }
    }
}
