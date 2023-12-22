// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

import "./IUniswapV3LiquidityManager.sol";
import "./ISwapRouter.sol";

interface IThetaVaultManagement {

    event RangeSet(uint160 minPriceSqrtX96, uint160 maxPriceSqrtX96);
    event SwapRouterSet(address newSwapRouter);
    event LiquidityManagerSet(address newLiquidityManager);
    event ManagerSet(address newManager);
    event RebaserSet(address newRebaser);
    event DepositorSet(address newDepositor);
    event MinPoolSkewSet(uint16 newMinPoolSkewPercentage);
    event LiquidityPercentagesSet(uint32 newExtraLiquidityPercentage, uint16 minDexPercentageAllowed);
    event MinRebalanceDiffSet(uint256 newMinRebalanceDiff);
    event DepositHoldingsSet(uint16 newDepositHoldingsPercentage);

    function rebalance(uint32 cviValue) external;
    function rebaseCVI() external;

    function setRange(uint160 minPriceSqrtX96, uint160 maxPriceSqrtX96) external;

    function setSwapRouter(ISwapRouter newSwapRouter) external;
    function setLiquidityManager(IUniswapV3LiquidityManager newLiquidityManager) external;
    function setManager(address newManager) external;
    function setRebaser(address newRebaser) external;
    function setDepositor(address newDepositor) external;
    function setMinPoolSkew(uint16 newMinPoolSkewPercentage) external;
    function setLiquidityPercentages(uint32 newExtraLiquidityPercentage, uint16 minDexPercentageAllowed) external;
    function setMinRebalanceDiff(uint256 newMinRebalanceDiff) external;
    function setDepositHoldings(uint16 newDepositHoldingsPercentage) external;
}

