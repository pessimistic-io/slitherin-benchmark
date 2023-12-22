// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.17;

import {IERC20Permit, IERC20} from "./draft-ERC20Permit.sol";
import {IAlgebraPool} from "./IAlgebraPool.sol";
import {IAlgebraMintCallback} from "./IAlgebraMintCallback.sol";

interface ILiquidityManager is IERC20Permit, IAlgebraMintCallback {
    function deposit(uint256, uint256, address, uint256[4] memory minIn) external returns (uint256);

    function withdraw(uint256, address, uint256[4] memory) external returns (uint256, uint256);

    function collectAllFees() external returns (uint256 baseFees0, uint256 baseFees1, uint256 limitFees0, uint256 limitFees1);

    function compound(uint256[4] memory inMax, uint256[4] memory inMin) external;

    function swapToken(IERC20 token, uint256 amountIn, uint256 amountOutMin, uint160 maxSlippage) external returns (uint256);

    function rebalance(int24[4] memory ranges, uint256[4] memory inMax, uint256[4] memory minIn, uint256[4] memory outMin) external;

    function pullLiquidity(int24 tickLower, int24 tickUpper, uint128 shares, uint256[2] memory amountMin) external returns (uint256 base0, uint256 base1);

    function directDeposit() external view returns (bool directDeposit);

    function feeBP() external view returns (uint16 fee);

    function pool() external view returns (IAlgebraPool);

    function tickSpacing() external view returns (int24 spacing);

    function positionsSettings() external view returns (int24 baseLower, int24 baseUpper, int24 limitLower, int24 limitUpper);

    function token0() external view returns (IERC20);

    function token1() external view returns (IERC20);

    function getTotalAmounts() external view returns (uint256 total0, uint256 total1);

    function getBasePosition() external view returns (uint256 liquidity, uint256 total0, uint256 total1);
    function getLimitPosition() external view returns (uint256 liq, uint256 amount0, uint256 amount1);

    function getCurrentTick() external view returns (int24 tick);

    function getCurrentSqrtRatioX96() external view returns (uint160 sqrtPriceX96);

    function setFeeBP(uint16 newFee) external;

    function setFeeRecipient(address feeRecipient) external;

    function setWhitelistStatus(address _address, bool status) external;
}

