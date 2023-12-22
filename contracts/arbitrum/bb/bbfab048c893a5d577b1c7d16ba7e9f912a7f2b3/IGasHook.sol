// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title IGasHook
 * @author Ofir Smolinsky
 * @notice Defines an interface for a gas hook, simply returns all additional WEI that should be paid
 * by a vault (L2's specifically have different calcs for htat)
 */
interface IGasHook {
    function getAdditionalGasCost() external view returns (uint256 gasLeft);
}

