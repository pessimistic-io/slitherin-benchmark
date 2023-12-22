// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IGauge {
    struct UserRewardData {
        uint256 userRewardPerTokenPaid;
        uint256 userEarnedStored;
    }

    function deposit(uint256 amount, uint256 tokenId) external;

    function deposit(uint256 amount) external;

    function depositAndOptIn(
        uint256 amount,
        uint256 tokenId,
        address[] memory optInPools
    ) external;

    function withdraw(uint256 amount) external;

    function getReward(address account, address[] memory tokens) external;

    function getReward() external;

    function userRewardData(
        address userAddress,
        address tokenAddress
    ) external view returns (UserRewardData calldata);

    function optIn(address[] memory tokens) external;

    function optOut(address[] memory tokens) external;

    function storedRewardsPerUser(
        address account,
        address token
    ) external view returns (uint256);
}

