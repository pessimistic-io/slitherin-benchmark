// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./IStrategyStatistics.sol";

interface IStrategyVenus {
    function farmingPair() external view returns (address);

    function lendToken() external;

    function build(uint256 usdAmount) external;

    function destroy(uint256 percentage) external;

    function claimRewards(uint8 mode) external;
}

interface IStrategy {
    function releaseToken(uint256 amount, address token) external; // onlyMultiLogicProxy

    function logic() external view returns (address);

    function useToken() external; // Automation

    function rebalance() external; // Automation

    function checkUseToken() external view returns (bool); // Automation

    function checkRebalance() external view returns (bool); // Automation

    function destroyAll() external; // onlyOwnerAdmin

    function claimRewards() external; // onlyOwnerAdmin
}

interface IStrategyFarmingV3 {
    function checkRebalancePriceRange() external view returns (bool); // Automation

    function rebalancePriceRange() external; // Automation

    function collectFees() external; // Automation

    function getPairs() external view returns (Pair[] memory);
}

interface ILbfPairManager {
    function build(uint256 _usdAmount) external;

    function destroy(uint256 _usdAmount, DestroyMode _mode) external;

    function getPairs() external view returns (Pair[] memory);

    function getTokens()
        external
        view
        returns (address[] memory arrTokens, uint256 len);

    function buildPair(uint256 index) external;

    function buildPair(
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) external;

    function destroyPair(uint256 index)
        external
        returns (uint256 amount0Out, uint256 amount1Out);

    function destroyPair(
        uint256 index,
        uint256 amount0,
        uint256 amount1,
        uint128 liquidity,
        bool shoudBurn
    ) external returns (uint256 amount0Out, uint256 amount1Out);
}

