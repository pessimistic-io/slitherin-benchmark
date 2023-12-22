// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import "./FixedPoint96.sol";
import "./INonfungiblePositionManager.sol";
import "./IERC20Metadata.sol";
import "./TickMath.sol";
import "./SafeERC20.sol";
import "./ConcentratedLiquidityLibrary.sol";
import "./BaseConcentratedLiquidityStrategy.sol";

/// @author YLDR <admin@apyflow.com>
library UniswapV3Library {
    using SafeERC20 for IERC20;

    struct Data {
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
        INonfungiblePositionManager positionManager;
        IUniswapV3Pool pool;
        uint256 positionTokenId;
    }

    function performApprovals(Data storage self) public {
        IERC20(self.token0).safeIncreaseAllowance(address(self.positionManager), type(uint256).max);
        IERC20(self.token1).safeIncreaseAllowance(address(self.positionManager), type(uint256).max);
    }

    function getPoolData(Data storage self) public view returns (int24 currentTick, uint160 sqrtPriceX96) {
        (sqrtPriceX96, currentTick,,,,,) = self.pool.slot0();
    }

    function getPositionData(Data storage self)
        public
        view
        returns (BaseConcentratedLiquidityStrategy.PositionData memory)
    {
        (,,,,, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) =
            self.positionManager.positions(self.positionTokenId);
        return BaseConcentratedLiquidityStrategy.PositionData({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity
        });
    }

    function mint(Data storage self, int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1) public {
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: self.token0,
            token1: self.token1,
            fee: self.fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });
        (self.positionTokenId,,,) = self.positionManager.mint(params);
    }

    function increaseLiquidity(Data storage self, uint256 amount0, uint256 amount1) public {
        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
            tokenId: self.positionTokenId,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });
        self.positionManager.increaseLiquidity(params);
    }

    function decreaseLiquidity(Data storage self, uint128 liquidity)
        public
        returns (uint256 amount0, uint256 amount1)
    {
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: self.positionTokenId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });
        (amount0, amount1) = self.positionManager.decreaseLiquidity(params);
    }

    function collect(Data storage self, uint256 amount0Max, uint256 amount1Max) public {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: self.positionTokenId,
            recipient: address(this),
            amount0Max: uint128(amount0Max),
            amount1Max: uint128(amount1Max)
        });
        self.positionManager.collect(params);
    }

    function burn(Data storage self) public {
        self.positionManager.burn(self.positionTokenId);
        self.positionTokenId = 0;
    }
}

