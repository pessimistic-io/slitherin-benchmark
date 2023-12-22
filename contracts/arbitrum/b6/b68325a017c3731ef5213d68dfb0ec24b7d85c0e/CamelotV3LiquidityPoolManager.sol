// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {ILiquidityPoolManager} from "./ILiquidityPoolManager.sol";
import {IAlgebraPool} from "./IAlgebraPool.sol";
import {IAlgebraMintCallback} from "./IAlgebraMintCallback.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";

//libraries
import {SafeCast} from "./SafeCast.sol";
import {TickMath} from "./TickMath.sol";
import {FullMath, LiquidityAmounts} from "./LiquidityAmounts.sol";

// import "forge-std/console2.sol";

contract CamelotV3LiquidityPoolManager is ILiquidityPoolManager, IAlgebraMintCallback {
    using SafeERC20 for IERC20;
    using TickMath for int24;

    /* ========== Structs ========== */

    /* ========== CONSTANTS ========== */
    uint16 private constant MAGIC_SCALE_1E4 = 10000; //for slippage

    /* ========== STORAGES ========== */

    /* ========== PARAMETERS ========== */
    IAlgebraPool public pool;
    bool public immutable reversed; //if baseToken > targetToken of Vault, true
    address public vault;

    /* ========== MODIFIER ========== */
    modifier onlyVault() {
        if (msg.sender != vault) revert("ONLY_VAULT");
        _;
    }

    /* ========== Initializable ========== */
    constructor(address _token0, address _token1, address _pool) {
        reversed = _token0 > _token1 ? true : false;

        pool = IAlgebraPool(_pool);
    }

    function setVault(address _vault) external {
        if (vault != address(0)) revert("ALREADY_SET");
        vault = _vault;
    }

    /* ========== VIEW FUNCTIONS ========== */
    function getTwap(uint32 _minute) external view returns (int24 avgTick) {
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = _minute;
        secondsAgo[1] = 0;
        (int56[] memory tickCumulatives, , , ) = pool.getTimepoints(secondsAgo);
        if (tickCumulatives.length != 2) revert("array len");
        unchecked {
            avgTick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(_minute)));
        }
    }

    function getCurrentTick() external view returns (int24 tick) {
        (, tick, , , , , , ) = pool.globalState();
    }

    function getCurrentLiquidity(int24 _lowerTick, int24 _upperTick) external view returns (uint128) {
        (uint256 _liquidity, , , , , ) = pool.positions(_createKey(address(this), _lowerTick, _upperTick));
        return SafeCast.toUint128(_liquidity);
    }

    function getAmountsForLiquidity(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external view returns (uint256, uint256) {
        (uint160 _sqrtRatioX96, , , , , , , ) = pool.globalState();
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            _sqrtRatioX96,
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            liquidity
        );
        return reversed ? (amount1, amount0) : (amount0, amount1);
    }

    function getLiquidityForAmounts(
        int24 lowerTick,
        int24 upperTick,
        uint256 amount0,
        uint256 amount1
    ) external view returns (uint128 liquidity) {
        (uint160 _sqrtRatioX96, , , , , , , ) = pool.globalState();
        (uint256 _amount0, uint256 _amount1) = reversed ? (amount1, amount0) : (amount0, amount1);

        return
            LiquidityAmounts.getLiquidityForAmounts(
                _sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                _amount0,
                _amount1
            );
    }

    ///@notice Cheking tickSpacing
    function validateTicks(int24 _lowerTick, int24 _upperTick) external view {
        int24 _spacing = pool.tickSpacing();
        if (_lowerTick < _upperTick && _lowerTick % _spacing == 0 && _upperTick % _spacing == 0) {
            return;
        }
        revert("INVALID_TICKS");
    }

    function getFeesEarned(int24 lowerTick, int24 upperTick) external view returns (uint256, uint256) {
        (
            uint256 liquidity,
            ,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(_createKey(address(this), lowerTick, upperTick));
        uint256 _fee0 = _computeFeesEarned(
            pool.token0(),
            feeGrowthInside0Last,
            SafeCast.toUint128(liquidity),
            lowerTick,
            upperTick
        ) + uint256(tokensOwed0);
        uint256 _fee1 = _computeFeesEarned(
            pool.token1(),
            feeGrowthInside1Last,
            SafeCast.toUint128(liquidity),
            lowerTick,
            upperTick
        ) + uint256(tokensOwed1);

        return reversed ? (_fee1, _fee0) : (_fee0, _fee1);
    }

    ///@notice Compute one of fee amount
    ///@dev similar to Arrakis'
    function _computeFeesEarned(
        address token,
        uint256 feeGrowthInsideLast,
        uint128 liquidity,
        int24 _lowerTick,
        int24 _upperTick
    ) internal view returns (uint256 fee_) {
        (, int24 _tick, , , , , , ) = pool.globalState();

        bool isZero = (token == pool.token0()) ? true : false;

        uint256 feeGrowthOutsideLower;
        uint256 feeGrowthOutsideUpper;
        uint256 feeGrowthGlobal;
        if (isZero) {
            feeGrowthGlobal = pool.totalFeeGrowth0Token();
            (, , feeGrowthOutsideLower, , , , , ) = pool.ticks(_lowerTick);
            (, , feeGrowthOutsideUpper, , , , , ) = pool.ticks(_upperTick);
        } else {
            feeGrowthGlobal = pool.totalFeeGrowth1Token();
            (, , , feeGrowthOutsideLower, , , , ) = pool.ticks(_lowerTick);
            (, , , feeGrowthOutsideUpper, , , , ) = pool.ticks(_upperTick);
        }

        unchecked {
            // calculate fee growth below
            uint256 feeGrowthBelow;
            if (_tick >= _lowerTick) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            // calculate fee growth above
            uint256 feeGrowthAbove;
            if (_tick < _upperTick) {
                feeGrowthAbove = feeGrowthOutsideUpper;
            } else {
                feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;
            }

            uint256 feeGrowthInside = feeGrowthGlobal - feeGrowthBelow - feeGrowthAbove;

            fee_ = FullMath.mulDiv(
                uint256(liquidity),
                feeGrowthInside - feeGrowthInsideLast,
                0x100000000000000000000000000000000
            );
        }
    }

    function _createKey(address _owner, int24 _lowerTick, int24 _upperTick) internal pure returns (bytes32 key_) {
        assembly {
            key_ := or(shl(24, or(shl(24, _owner), and(_lowerTick, 0xFFFFFF))), and(_upperTick, 0xFFFFFF))
        }
    }

    /* ========== WRITE FUNCTIONS ========== */

    function mint(int24 lowerTick, int24 upperTick, uint128 liquidity) external onlyVault returns (uint256, uint256) {
        bytes memory data = abi.encode(msg.sender);

        (uint256 amount0, uint256 amount1, ) = pool.mint(
            msg.sender,
            address(this),
            lowerTick,
            upperTick,
            liquidity,
            data
        );
        return reversed ? (amount1, amount0) : (amount0, amount1);
    }

    function collect(int24 lowerTick, int24 upperTick) external onlyVault returns (uint128, uint128) {
        (uint128 _amount0, uint128 _amount1) = pool.collect(
            msg.sender,
            lowerTick,
            upperTick,
            type(uint128).max,
            type(uint128).max
        );
        return reversed ? (_amount1, _amount0) : (_amount0, _amount1);
    }

    function burn(int24 lowerTick, int24 upperTick, uint128 liquidity) external onlyVault returns (uint256, uint256) {
        (uint256 _burn0, uint256 _burn1) = pool.burn(lowerTick, upperTick, liquidity);
        return reversed ? (_burn1, _burn0) : (_burn0, _burn1);
    }

    function burnAndCollect(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external onlyVault returns (uint256, uint256) {
        uint256 _burn0;
        uint256 _burn1;
        if (liquidity > 0) {
            (_burn0, _burn1) = pool.burn(lowerTick, upperTick, liquidity);
        }
        pool.collect(msg.sender, lowerTick, upperTick, type(uint128).max, type(uint128).max);
        return reversed ? (_burn1, _burn0) : (_burn0, _burn1);
    }

    /* ========== CALLBACK FUNCTIONS ========== */

    /// @notice callback fn, called back on pool.mint
    function algebraMintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata _data) external override {
        if (msg.sender != address(pool)) {
            revert("ONLY_CALLBACK_CALLER");
        }
        address sender = abi.decode(_data, (address));

        if (amount0Owed > 0) {
            // if (amount0Owed > IERC20(pool.token0()).balanceOf(sender)) {
            //     console2.log("algebraMintCallback amount0 > balance");
            //     console2.log(amount0Owed, IERC20(pool.token0()).balanceOf(sender));
            // }
            IERC20(pool.token0()).safeTransferFrom(sender, msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            // if (amount1Owed > IERC20(pool.token1()).balanceOf(sender)) {
            //     console2.log("algebraMintCallback amount1 > balance");
            //     console2.log(amount1Owed, IERC20(pool.token1()).balanceOf(sender));
            // }
            IERC20(pool.token1()).safeTransferFrom(sender, msg.sender, amount1Owed);
        }
    }
}

