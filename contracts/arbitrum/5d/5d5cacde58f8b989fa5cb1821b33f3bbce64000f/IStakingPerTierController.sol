// SPDX-License-Identifier: MIT

import { IERC20 } from "./IERC20.sol";
import { ISnapshottable } from "./ISnapshottable.sol";

pragma solidity ^0.8.0;

/**
 * @title IStakingPerTierController
 * @dev Minimal interface for staking that TierController requires
 */
interface IStakingPerTierController is ISnapshottable {
    function getVestedTokens(address user) external view returns (uint256);
    function getVestedTokensAtSnapshot(address user, uint256 blockNumber) external view returns (uint256);
    function token() external view returns (IERC20);
}
