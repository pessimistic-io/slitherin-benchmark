// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC20 } from "./IERC20.sol";

interface IUrdStake {
    function userInfo(address _user) external view returns (uint256, uint256);

    function stake(address _to, uint256 _amount) external;

    function unstake(address _to, uint256 _amount) external;

    function claimRewards(address _to) external;

    function pendingReward(address _to) external view returns (uint256);

    function URD() external view returns (IERC20);

    function URO() external view returns (IERC20);
}

