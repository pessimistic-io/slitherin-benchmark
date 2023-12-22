// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IStrategyConfig {
    function withdraw(uint256 amountNeeded) external;

    /**
     * @dev Returns the total amount of the underlying asset that is “managed” by Strategy.
     *
     * - SHOULD include any compounding that occurs from yield.
     * - MUST include tokens stored on the strategy proxy.
     * - MUST include tokens currently invested in strategy.
     * - MUST NOT revert.
     */
    function strategyBalance() external view returns (uint256);
}

