// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IUniswapV3Storage {
    function PRECISION() external view returns (uint);
    function provider() external view returns (address);
    function addresses() external view returns (address want, address stableToken, address volatileToken, address positionsManager);
    function thresholds() external view returns (uint ammCheckThreshold, uint slippage, uint healthThreshold);
    function parameters() external view returns (uint leverage, uint minLeverage, uint maxLeverage, int24 tick0, int24 tick1);
    function positionId() external view returns (uint);
    function priceAnchor() external view returns (uint);
    function harvested() external view returns (uint);
    function numRebalances() external view returns (uint);
    function withdrawn() external view returns (uint);
    function cache() external view returns (address[] memory, uint[] memory, address[] memory, uint[] memory, uint);
    function prevBalance() external view returns (int);
    function prevDeposited() external view returns (uint);
    function prevDebt() external view returns (uint);
    function prevHarvestable() external view returns (int);
    function slippageImpact() external view returns (int);
    function unrealizedPriceChangeImpact() external view returns (int);
    function realizedPriceChangeImpact() external view returns (int);
    function interestPayments(address token) external view returns (int);
    function interestPaymentsInDepositToken(address token) external view returns (int);
    function prevBalances(address token) external view returns (uint);
    function prevDebtsAtRepayBorrow(address token) external view returns (uint);
    function prevDebts(address token) external view returns (uint);
    function prevTvl() external view returns (int);
    function prevHarvestables(address token) external view returns (uint);
    function interchangeableTokens(address token, uint index) external view returns (address);
}
