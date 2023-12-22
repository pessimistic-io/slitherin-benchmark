// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./IERC20.sol";

interface IFarmingManager {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function depositAll() external;
    function withdrawAll() external;
    function distributeRewards(IERC20 _rewardToken) external returns(uint256 reward);
}
