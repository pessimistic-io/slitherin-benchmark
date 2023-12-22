// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;
import "./IAtlasMine.sol";

interface IBattleflyAtlasStaker {
    // ============= Events ==============

    event VaultDeposit(
        address indexed vault,
        uint256 indexed depositId,
        uint256 amount,
        uint256 unlockAt,
        IAtlasMine.Lock lock
    );
    event VaultWithdraw(address indexed vault, uint256 indexed depositId, uint256 amount, uint256 reward);
    event VaultClaim(address indexed vault, uint256 indexed depositId, uint256 reward);
    event MineStake(uint256 currentDepositId, uint256 unlockTime);
    event MineHarvest(uint256 earned, uint256 feeEarned, uint256 feeRefunded);
    event StakeNFT(address indexed vault, address indexed nft, uint256 tokenId, uint256 amount, uint256 currentBoost);
    event UnstakeNFT(address indexed vault, address indexed nft, uint256 tokenId, uint256 amount, uint256 currentBoost);
    event StakingPauseToggle(bool paused);
    event WithdrawFeesToTreasury(uint256 amount);
    event SetFeeWhitelistVault(address vault, bool isSet);
    event SetBattleflyVault(address vault, bool isSet);

    // ================= Data Types ==================

    struct Stake {
        uint256 amount;
        uint256 unlockAt;
        uint256 depositId;
    }

    struct VaultStake {
        uint256 amount;
        uint256 unlockAt;
        int256 rewardDebt;
        IAtlasMine.Lock lock;
    }
    struct VaultOwner {
        uint256 share;
        int256 rewardDebt;
        address owner;
        uint256 unclaimedReward;
    }

    // =============== View Functions ================

    function getVaultStake(address vault, uint256 depositId) external returns (VaultStake memory);

    // function vaultTotalStake(address vault) external returns (uint256);

    function pendingRewards(address vault, uint256 depositId) external view returns (uint256);

    function pendingRewardsAll(address vault) external returns (uint256);

    function totalMagic() external returns (uint256);

    // function totalPendingStake() external returns (uint256);

    function totalWithdrawableMagic() external returns (uint256);

    // ============= Staking Operations ==============

    function deposit(uint256 _amount, IAtlasMine.Lock lock) external returns (uint256);

    function withdraw(uint256 depositId) external;

    function withdrawAll() external;

    function claim(uint256 depositId) external returns (uint256);

    function claimAll() external returns (uint256);

    // function withdrawEmergency() external;

    function stakeScheduled() external;

    // ============= Owner Operations ==============

    function unstakeAllFromMine() external;

    function unstakeToTarget(uint256 target) external;

    // function emergencyUnstakeAllFromMine() external;

    function setBoostAdmin(address _hoard, bool isSet) external;

    function approveNFTs() external;

    // function revokeNFTApprovals() external;

    // function setMinimumStakingWait(uint256 wait) external;

    function toggleSchedulePause(bool paused) external;
}

