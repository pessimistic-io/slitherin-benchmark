// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {TickMath} from "./TickMath.sol";
import {OracleLibrary} from "./OracleLibrary.sol";

import {IERC20} from "./IERC20.sol";
import {IERC1155Receiver} from "./ERC1155Receiver.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
import {SafeCast} from "./SafeCast.sol";
import {AccessControlEnumerable} from "./AccessControlEnumerable.sol";
import {ERC20} from "./ERC20.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";

import {IUniswapV3SingleTickLiquidityHandler} from "./IUniswapV3SingleTickLiquidityHandler.sol";
import {UniswapV3SingleTickLiquidityLib} from "./UniswapV3SingleTickLiquidityLib.sol";
import {IDopexV2PositionManager} from "./IDopexV2PositionManager.sol";

interface IAutomator {
    function manager() external view returns (IDopexV2PositionManager);

    function handler() external view returns (IUniswapV3SingleTickLiquidityHandler);

    function pool() external view returns (IUniswapV3Pool);

    function router() external view returns (ISwapRouter);

    function asset() external view returns (IERC20);

    function counterAsset() external view returns (IERC20);

    function poolTickSpacing() external view returns (int24);

    function minDepositAssets() external view returns (uint256);

    function depositCap() external view returns (uint256);

    function getActiveTicks() external view returns (int24[] memory);

    // Structs
    struct LockedDopexShares {
        uint256 tokenId;
        uint256 shares;
    }

    struct RebalanceSwapParams {
        uint256 assetsShortage;
        uint256 counterAssetsShortage;
        uint256 maxCounterAssetsUseForSwap;
        uint256 maxAssetsUseForSwap;
    }

    struct RebalanceTickInfo {
        int24 tick;
        uint128 liquidity;
    }

    // Functions
    function setDepositCap(uint256 _depositCap) external;

    function totalAssets() external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function getTickAllLiquidity(int24 tick) external view returns (uint128);

    function getTickFreeLiquidity(int24 tick) external view returns (uint128);

    function calculateRebalanceSwapParamsInRebalance(
        RebalanceTickInfo[] memory ticksMint,
        RebalanceTickInfo[] memory ticksBurn
    ) external view returns (RebalanceSwapParams memory);

    function deposit(uint256 assets) external returns (uint256 shares);

    function redeem(
        uint256 shares,
        uint256 minAssets
    ) external returns (uint256 assets, LockedDopexShares[] memory lockedDopexShares);

    function checkMintValidity(int24 lowerTick) external view returns (bool);

    // Add any other public or external functions from the Automator contract here
    function rebalance(
        RebalanceTickInfo[] calldata ticksMint,
        RebalanceTickInfo[] calldata ticksBurn,
        RebalanceSwapParams calldata swapParams
    ) external;
}

