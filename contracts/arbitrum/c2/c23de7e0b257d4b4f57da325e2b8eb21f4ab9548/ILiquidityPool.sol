// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

/**
 * @notice Struct to be returned by view functions to inform about locked and unlocked pool shares of a user
 * @custom:member totalPoolShares Total amount of pool shares of the user in this pool
 * @custom:member unlockedPoolShares Total amount of unlocked pool shares of the user in this pool
 * @custom:member totalShares Total amount of pool shares of the user in this pool
 * @custom:member unlockedShares Total amount of unlocked pool shares of the user in this pool
 * @custom:member totalAssets  Total amount of assets of the user in this pool
 * @custom:member unlockedAssets Total amount of unlocked assets of the user in this pool
 */
struct UserPoolDetails {
    uint256 poolId;
    uint256 totalPoolShares;
    uint256 unlockedPoolShares;
    uint256 totalShares;
    uint256 unlockedShares;
    uint256 totalAssets;
    uint256 unlockedAssets;
}

interface ILiquidityPool {
    /* ========== EVENTS ========== */

    event PoolAdded(uint256 indexed poolId, uint256 lockTime, uint256 multiplier);

    event PoolUpdated(uint256 indexed poolId, uint256 lockTime, uint256 multiplier);

    event AddedToPool(uint256 indexed poolId, uint256 assetAmount, uint256 amount, uint256 shares);

    event RemovedFromPool(address indexed user, uint256 indexed poolId, uint256 poolShares, uint256 lpShares);

    event DepositedFees(address liquidityPoolAdapter, uint256 amount);

    event UpdatedDefaultLockTime(uint256 defaultLockTime);

    event UpdatedEarlyWithdrawalFee(uint256 earlyWithdrawalFee);

    event UpdatedEarlyWithdrawalTime(uint256 earlyWithdrawalTime);

    event UpdatedMinimumAmount(uint256 minimumAmount);

    event DepositedProfit(address indexed liquidityPoolAdapter, uint256 profit);

    event PayedOutLoss(address indexed liquidityPoolAdapter, uint256 loss);

    event CollectedEarlyWithdrawalFee(address user, uint256 amount);

    /* ========== CORE FUNCTIONS ========== */

    function deposit(uint256 amount, uint256 minOut) external returns (uint256);

    function withdraw(uint256 lpAmount, uint256 minOut) external returns (uint256);

    function depositAndLock(uint256 amount, uint256 minOut, uint256 poolId) external returns (uint256);

    function requestLossPayout(uint256 loss) external;

    function depositProfit(uint256 profit) external;

    function depositFees(uint256 amount) external;

    function previewPoolsOf(address user) external view returns (UserPoolDetails[] memory);

    function previewRedeemPoolShares(uint256 poolShares_, uint256 poolId_) external view returns (uint256);

    /* ========== MUTATIVE FUNCTIONS ========== */

    function updateDefaultLockTime(uint256 defaultLockTime) external;

    function updateEarlyWithdrawalFee(uint256 earlyWithdrawalFee) external;

    function updateEarlyWithdrawalTime(uint256 earlyWithdrawalTime) external;

    function updateMinimumAmount(uint256 minimumAmount) external;

    function addPool(uint40 lockTime_, uint16 multiplier_) external returns (uint256);

    function updatePool(uint256 poolId_, uint40 lockTime_, uint16 multiplier_) external;

    /* ========== VIEW FUNCTIONS ========== */

    function availableLiquidity() external view returns (uint256);

    function canTransferLps(address user) external view returns (bool);

    function canWithdrawLps(address user) external view returns (bool);

    function userWithdrawalFee(address user) external view returns (uint256);
}

