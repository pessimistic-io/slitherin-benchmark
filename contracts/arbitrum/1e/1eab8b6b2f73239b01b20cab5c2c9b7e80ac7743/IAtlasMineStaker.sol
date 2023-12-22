// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IAtlasMineStaker {
    // ============= Events ==============

    event UserDeposit(address indexed user, uint256 amount);
    event UserWithdraw(address indexed user, uint256 indexed depositId, uint256 amount, uint256 reward);
    event UserClaim(address indexed user, uint256 indexed depositId, uint256 reward);
    event MineStake(uint256 currentDepositId, uint256 unlockTime);
    event MineHarvest(uint256 earned, uint256 feeEarned, uint256[] depositIds);
    event StakeNFT(address indexed user, address indexed nft, uint256 tokenId, uint256 amount, uint256 currentBoost);
    event UnstakeNFT(address indexed user, address indexed nft, uint256 tokenId, uint256 amount, uint256 currentBoost);
    event SetFee(uint256 fee);
    event StakingPauseToggle(bool paused);
    event SetMinimumStakingWait(uint256 wait);
    event SetAccrualWindows(uint256[] windows);
    event SetAccrualIncentive(uint256 reward);

    // ================= Data Types ==================

    struct Stake {
        uint256 amount;
        uint256 unlockAt;
        uint256 depositId;
    }

    struct UserStake {
        uint256 amount;
        uint256 unlockAt;
        int256 rewardDebt;
    }

    // =============== View Functions ================

    function getUserStake(address user, uint256 depositId) external returns (UserStake memory);

    function userTotalStake(address user) external returns (uint256);

    function pendingRewards(address user, uint256 depositId) external returns (uint256);

    function pendingRewardsAll(address user) external returns (uint256);

    function totalMagic() external returns (uint256);

    function totalPendingStake() external returns (uint256);

    function totalWithdrawableMagic() external returns (uint256);

    function totalRewardsEarned() external returns (uint256);

    // ============= Staking Operations ==============

    function deposit(uint256 _amount) external;

    function withdraw(uint256 depositId, uint256 amount) external;

    function withdrawAll() external;

    function claim(uint256 depositId) external;

    function claimAll() external;

    function withdrawEmergency() external;

    function stakeScheduled() external;

    function accrue(uint256[] calldata depositIds) external;

    // ============= Hoard Operations ==============

    function stakeTreasure(uint256 _tokenId, uint256 _amount) external;

    function unstakeTreasure(uint256 _tokenId, uint256 _amount) external;

    function stakeLegion(uint256 _tokenId) external;

    function unstakeLegion(uint256 _tokenId) external;

    // ============= Owner Operations ==============

    function unstakeAllFromMine() external;

    function unstakeToTarget(uint256 target) external;

    function emergencyUnstakeAllFromMine() external;

    function setFee(uint256 _fee) external;

    function setHoard(address _hoard, bool isSet) external;

    function approveNFTs() external;

    function revokeNFTApprovals() external;

    function setMinimumStakingWait(uint256 wait) external;

    function toggleSchedulePause(bool paused) external;

    function withdrawFees() external;

    function setAccrualWindows(uint256[] calldata windows) external;
}

