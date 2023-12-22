// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IUniswapV3StrategyLogic {

    function trackPriceChangeImpact() external;

    function updateTrackers() external;

    function swapTokensTo(address token) external;

    function transferToVault(uint amount) external;

    function deposit() external;

    function withdraw(uint fraction) external;

    function harvest() external;

    function repay(uint fraction) external;

    function setTicks(int24 multiplier0, int24 multiplier1) external;
}

