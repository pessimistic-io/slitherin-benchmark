// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

interface IRewardController {
    function rewardToken() external view returns (address);

    function claimableJuniorRewards(address account) external returns (uint256);

    function claimableSeniorRewards(address account) external returns (uint256);

    function claimSeniorRewardFor(address account, address receiver) external returns (uint256);

    function claimJuniorRewardFor(address account, address receiver) external returns (uint256);

    function updateRewards(address account) external;

    function notifyRewards(
        address[] memory rewardTokens,
        uint256[] memory rewardAmounts,
        uint256 utilizedAmount
    ) external;
}

