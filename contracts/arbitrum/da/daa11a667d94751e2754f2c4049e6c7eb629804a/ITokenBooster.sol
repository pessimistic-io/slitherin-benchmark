// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface ITokenBooster {
    function getWeek() external view returns (uint256);

    function weeklyWeight(address user, uint256 week)
        external
        view
        returns (uint256, uint256);

    function userWeight(address _user) external view returns (uint256);

    function startTime() external view returns (uint256);
}

