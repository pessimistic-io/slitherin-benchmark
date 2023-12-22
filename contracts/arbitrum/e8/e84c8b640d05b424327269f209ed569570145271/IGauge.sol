// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IGauge {

    function earned(
        address token,
        address account
    ) external view returns (uint256);

    function rewardPerToken(address) external view returns(uint256);

    function derivedBalances(address) external view returns(uint256);

    function userRewardPerTokenStored(address,address) external view returns(uint256);

    function storedRewardsPerUser(address,address) external view returns(uint256);

    function rewardRate(address) external view returns(uint256);

    function lastUpdateTime(address token) external view returns(uint256);

    function lastTimeRewardApplicable(address token) external view returns(uint256);

    function derivedSupply() external view returns(uint256);

    function withdraw(uint256 amount) external;

    function withdrawAll() external;
    
    function depositAll(uint256 tokenId) external;

    function deposit(uint256 amount, uint256 tokenId) external;

    function getReward(address account, address[] memory tokens) external;

    function claimFees() external returns (uint claimed0, uint claimed1);

    function voter() external view returns (address);
}

