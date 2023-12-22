// SPDX-License-Identifier: BSL 1.1

pragma solidity ^0.8.17;

interface IUniswapV3StrategyData {

    struct PNLData {
        int pnl;
        int rewardProfit;
        int slippageLoss;
        address[] borrowedTokens;
        int[] interestPayments;
        int[] interestPaymentsInDepositToken;
        int unrealizedPriceImpact;
        int realizedPriceImpact;
    }

    function balanceInTermsOf(address token, address strategyAddress) external view returns (int balance);

    function getTVL(address strategyAddress) external view returns (uint tvl);
    
    function getPoolRatios(address strategyAddress) external view returns (uint stableRatio, uint volatileRatio, uint volatileRatioInStablePrice);

    function getAmounts(address strategyAddress) external view returns (address[] memory tokens, uint[] memory amounts);
    
    function getDebts(address strategyAddress) external view returns (address[] memory tokens, uint[] memory amounts);
    
    function getHarvestable(address strategyAddress) external view returns (uint harvestable);

    function getFees(address strategyAddress) external view returns (uint stableFee, uint volatileFee);
    
    function getPnl(address strategyAddress) external view returns (PNLData memory pnlData);
}

