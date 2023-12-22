// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IERC20Upgradeable.sol";
import "./IAtlasMine.sol";

interface IBattleflyAtlasStakerV02 {
    struct Vault {
        uint16 fee;
        uint16 claimRate;
        bool enabled;
    }

    struct VaultStake {
        uint64 lockAt;
        uint64 unlockAt;
        uint64 retentionUnlock;
        uint256 amount;
        uint256 paidEmission;
        address vault;
        IAtlasMine.Lock lock;
    }

    function MAGIC() external returns (IERC20Upgradeable);

    function deposit(uint256, IAtlasMine.Lock) external returns (uint256);

    function withdraw(uint256) external returns (uint256);

    function claim(uint256) external returns (uint256);

    function requestWithdrawal(uint256) external returns (uint64);

    function currentDepositId() external view returns (uint256);

    function getAllowedLocks() external view returns (IAtlasMine.Lock[] memory);

    function getVaultStake(uint256) external view returns (VaultStake memory);

    function getClaimableEmission(uint256) external view returns (uint256, uint256);

    function canWithdraw(uint256 _depositId) external view returns (bool withdrawable);

    function canRequestWithdrawal(uint256 _depositId) external view returns (bool requestable);

    function currentEpoch() external view returns (uint64 epoch);

    function transitionEpoch() external view returns (uint64 epoch);

    function getLockPeriod(IAtlasMine.Lock) external view returns (uint64 epoch);

    function setPause(bool _paused) external;

    function depositIdsOfVault(address vault) external view returns (uint256[] memory depositIds);

    function activeAtlasPositionSize() external view returns (uint256);

    function totalStakedAtEpochForLock(IAtlasMine.Lock lock, uint64 epoch) external view returns (uint256);

    function totalPerShareAtEpochForLock(IAtlasMine.Lock lock, uint64 epoch) external view returns (uint256);

    function FEE_DENOMINATOR() external pure returns (uint96);

    function pausedUntil() external view returns (uint256);

    function getVault(address _vault) external view returns (Vault memory);

    function getTotalClaimableEmission(uint256 _depositId) external view returns (uint256 emission, uint256 fee);

    function getApyAtEpochIn1000(uint64 epoch) external view returns (uint256);

    // ========== Events ==========
    event AddedSuperAdmin(address who);
    event RemovedSuperAdmin(address who);

    event AddedVault(address indexed vault, uint16 fee, uint16 claimRate);
    event RemovedVault(address indexed vault);

    event StakedTreasure(address staker, uint256 tokenId, uint256 amount);
    event UnstakedTreasure(address staker, uint256 tokenId, uint256 amount);

    event StakedLegion(address staker, uint256 tokenId);
    event UnstakedLegion(address staker, uint256 tokenId);

    event SetTreasury(address treasury);
    event SetBattleflyBot(address bot);

    event NewDeposit(address indexed vault, uint256 amount, uint256 unlockedAt, uint256 indexed depositId);
    event WithdrawPosition(address indexed vault, uint256 amount, uint256 indexed depositId);
    event ClaimEmission(address indexed vault, uint256 amount, uint256 indexed depositId);
    event RequestWithdrawal(address indexed vault, uint64 withdrawalEpoch, uint256 indexed depositId);

    event DepositedAllToMine(uint256 amount);

    event SetPause(bool paused);
}

