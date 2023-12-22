// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

struct LiquidityPoolConfig {
    address poolAddress;
    uint96 percentage;
}

interface ILiquidityPoolAdapter {
    /* ========== EVENTS ========== */

    event PayedOutLoss(address indexed tradePair, uint256 loss);

    event DepositedProfit(address indexed tradePair, uint256 profit);

    event UpdatedMaxPayoutProportion(uint256 maxPayoutProportion);

    event UpdatedLiquidityPools(LiquidityPoolConfig[] liquidityPools);

    /* ========== CORE FUNCTIONS ========== */

    function requestLossPayout(uint256 profit) external returns (uint256);

    function depositProfit(uint256 profit) external;

    function depositFees(uint256 fee) external;

    /* ========== VIEW FUNCTIONS ========== */

    function availableLiquidity() external view returns (uint256);
}

