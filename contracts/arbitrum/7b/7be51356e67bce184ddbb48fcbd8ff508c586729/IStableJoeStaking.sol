// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./IERC20.sol";

interface IStableJoeStaking {
    struct UserInfo {
        uint256 amount;
        mapping(IERC20 => uint256) rewardDebt;
    }

    function getUserInfo(address user, IERC20 rewardToken) external view returns (uint256, uint256);

    function deposit(uint256 amount) external;

    function depositFeePercent() external returns (uint256);

    function DEPOSIT_FEE_PERCENT_PRECISION() external returns (uint256);
}

