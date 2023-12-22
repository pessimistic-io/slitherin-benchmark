// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

interface IMasterChef {
    struct LockDetail {
        uint256 lockAmount;
        uint256 unlockAmount;
        uint256 unlockTimestamp;
    }

    // Info of each user.
    struct VestingInfo {
        uint256 vestingReward;
        uint256 claimTime;
        bool isClaimed;
    }

    function addRewardToPool(uint256 amount) external;

    function deposit(uint256 _pid, uint256 _amount) external;

    function deposit(address to) external;

    function depositLock(uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function withdraw(address to) external;

    function withdraw(address[] calldata to) external;

    function withdrawLock(uint256 _amount) external;

    function getShareThatShouldDistribute() external view returns (uint256 share);

    function totalStake(uint256 _pid) external returns (uint256 stakeAmount);

    function pendingReward(uint256 _pid, address _user) external view returns (uint256);

    function userPendingReward(address user) external view returns (uint256 pendingReward);

    function userInfo(uint256 _pid, address user) external view returns (uint256 amount, uint256 debt);

    function poolInfo(
        uint256 _pid
    )
        external
        view
        returns (
            address stakeToken,
            address rewardToken,
            uint256 lastRewardTimestamp,
            uint256 rewardPerSecond,
            uint256 rewardPerShare, //multiply 1e20
            bool isDynamicReward
        );

    function getLockAmount(address user) external view returns (uint256 amount);

    function getLockInfo(address user) external view returns (LockDetail[] memory locks);

    function getUnlockableAmount(address user) external view returns (uint256 amount);

    function getUserVestingInfo(address user) external returns (VestingInfo[] memory);

    function vestingPendingReward(bool claim) external;

    function claimVestingReward() external;

    function emergencyWithdraw(uint256 _pid) external;

    function estimateARVCirculatingSupply() external view returns (uint256 circulatingSupply);

    function cauldronPoolInfo(address cauldron) external view returns (uint256);
}

