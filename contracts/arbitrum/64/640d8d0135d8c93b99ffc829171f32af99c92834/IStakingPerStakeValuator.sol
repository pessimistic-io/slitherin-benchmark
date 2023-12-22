// SPDX-License-Identifier: MIT

import { IERC20 } from "./IERC20.sol";
import { ISnapshottable } from "./ISnapshottable.sol";

pragma solidity ^0.8.0;

/**
 * @title IStakingPerTierController
 * @dev Minimal interface for staking that StakeValuator requires
 */
interface IStakingPerStakeValuator is ISnapshottable {
    function stakeFor(address _account, uint256 _amount) external;
    function getUserTokens(address user) external view returns (IERC20[] memory);
    function getVestedTokens(address user, IERC20 token) external view returns (uint256);
    function getVestedTokensAtSnapshot(address user, IERC20 _token, uint256 blockNumber) external view returns (uint256);
    function getStakers(uint256 idx) external view returns (address);
    function getStakersCount() external view returns (uint256);
    function token() external view returns (IERC20);
    function tokens(uint256 idx) external view returns (IERC20);
    function tokensLength() external view returns (uint256);
}
