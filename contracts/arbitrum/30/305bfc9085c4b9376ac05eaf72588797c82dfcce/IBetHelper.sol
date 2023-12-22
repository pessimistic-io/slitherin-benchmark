// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IBetHelper {
    function matchBet(address, uint256) external;
    function setLpBetPercent(uint8) external;
    function getLiquidityAvailableForBet(address)
        external
        view
        returns (uint256);
}

