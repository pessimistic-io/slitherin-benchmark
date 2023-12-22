// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
struct LockedBalance {
    uint256 amount;
    uint256 unlockTime;
}

interface IMultiFeeDistribution {
    function addReward(address rewardsToken) external;

    function mint(
        address user,
        uint256 amount,
        bool withPenalty
    ) external;

    function exit(bool claimRewards, address onBehalfOf) external;

    function stake(
        uint256 amount,
        bool lock,
        address onBehalfOf
    ) external;

    function lockedBalances(address user)
        external
        view
        returns (
            uint256 total,
            uint256 unlockable,
            uint256 locked,
            LockedBalance[] memory lockData
        );

    function getReward(address[] memory _rewardTokens) external;

    function rewardTokens(uint256 _index) external view returns (address);

    function withdrawExpiredLocks() external;

    function withdraw(uint256 _amount) external;

    function withdrawableBalance(address user)
        external
        view
        returns (uint256 amount, uint256 penaltyAmount);
}

