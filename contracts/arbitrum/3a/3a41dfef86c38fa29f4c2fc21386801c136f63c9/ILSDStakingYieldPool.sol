// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

interface ILSDStakingYieldPool {
    function getReward() external;
    function earned(address account) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
    function rewards(address account) external view returns (uint256);

    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
}

