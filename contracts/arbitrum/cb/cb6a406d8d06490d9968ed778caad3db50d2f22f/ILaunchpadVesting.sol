// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface ILaunchpadVesting {
    function vestTokens(
        bool isWhitelistedVesting,
        uint256 amount,
        address vestFor
    ) external;

    function setVestingStartTime(uint256 _startTime) external;
}

