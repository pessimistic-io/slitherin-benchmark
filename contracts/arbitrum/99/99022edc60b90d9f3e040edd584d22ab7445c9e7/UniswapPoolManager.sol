// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "./IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "./IUniswapV3SwapCallback.sol";

import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {FullMath} from "./LiquidityAmounts.sol";

// import "forge-std/console2.sol";

interface IUniswapV3TickSpacing {
    function tickSpacing() external view returns (int24);
}

contract UniswapPoolManager is IUniswapV3MintCallback, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;

    IUniswapV3Pool public pool;
    IERC20 public token0; //token0
    IERC20 public token1; //token1

    constructor(address _pool) {
        pool = IUniswapV3Pool(_pool);

        // setting adresses and approving
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());
        token0.safeApprove(_pool, type(uint256).max);
        token1.safeApprove(_pool, type(uint256).max);
    }

    /* ========== VIEW FUNCTIONS ========== */
    function _getPositionID(int24 _lowerTick, int24 _upperTick) internal view returns (bytes32 positionID) {
        return keccak256(abi.encodePacked(address(this), _lowerTick, _upperTick));
    }

    function _computeFeesEarned(
        bool isZero,
        uint256 feeGrowthInsideLast,
        uint128 liquidity,
        int24 _lowerTick,
        int24 _upperTick,
        int24 _currentTick
    ) internal view returns (uint256 fee) {
        uint256 feeGrowthOutsideLower;
        uint256 feeGrowthOutsideUpper;
        uint256 feeGrowthGlobal;
        if (isZero) {
            feeGrowthGlobal = pool.feeGrowthGlobal0X128();
            (, , feeGrowthOutsideLower, , , , , ) = pool.ticks(_lowerTick);
            (, , feeGrowthOutsideUpper, , , , , ) = pool.ticks(_upperTick);
        } else {
            feeGrowthGlobal = pool.feeGrowthGlobal1X128();
            (, , , feeGrowthOutsideLower, , , , ) = pool.ticks(_lowerTick);
            (, , , feeGrowthOutsideUpper, , , , ) = pool.ticks(_upperTick);
        }

        unchecked {
            // calculate fee growth below
            uint256 feeGrowthBelow;
            if (_currentTick >= _lowerTick) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            // calculate fee growth above
            uint256 feeGrowthAbove;
            if (_currentTick < _upperTick) {
                feeGrowthAbove = feeGrowthOutsideUpper;
            } else {
                feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;
            }

            uint256 feeGrowthInside = feeGrowthGlobal - feeGrowthBelow - feeGrowthAbove;
            fee = FullMath.mulDiv(
                liquidity,
                feeGrowthInside - feeGrowthInsideLast,
                0x100000000000000000000000000000000
            );
        }
    }

    /* ========== CALLBACK FUNCTIONS ========== */

    function _validateTicks(int24 _lowerTick, int24 _upperTick) internal view returns (bool) {
        int24 _spacing = IUniswapV3TickSpacing(address(pool)).tickSpacing();
        return _lowerTick < _upperTick && _lowerTick % _spacing == 0 && _upperTick % _spacing == 0;
    }

    /// @notice Uniswap V3 callback fn, called back on pool.mint
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata /*_data*/
    ) external override {
        if (msg.sender != address(pool)) {
            revert("CallbackCaller");
        }

        if (amount0Owed > 0) {
            token0.safeTransfer(msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            token1.safeTransfer(msg.sender, amount1Owed);
        }
    }

    /// @notice Uniswap v3 callback fn, called back on pool.swap
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /*data*/
    ) external override {
        if (msg.sender != address(pool)) {
            revert("CallbackCaller");
        }

        if (amount0Delta > 0) {
            token0.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            token1.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }
}

