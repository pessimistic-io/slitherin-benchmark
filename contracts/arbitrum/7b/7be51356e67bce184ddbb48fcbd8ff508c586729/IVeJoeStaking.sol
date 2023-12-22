// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IVeJoeStaking {
    struct UserInfo {
        uint256 balance;
        uint256 rewardDebt;
        uint256 lastClaimTimestamp;
        uint256 speedUpEndTimestamp;
    }

    function userInfos(address account) external view returns (UserInfo memory);

    function deposit(uint256 amount) external;
}

