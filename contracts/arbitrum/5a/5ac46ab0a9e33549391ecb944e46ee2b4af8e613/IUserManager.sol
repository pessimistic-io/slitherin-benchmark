// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

/// @notice Enum for the different fee tiers
enum Tier {
    ZERO,
    ONE,
    TWO,
    THREE,
    FOUR,
    FIVE,
    SIX
}

interface IUserManager {
    /* ========== EVENTS ========== */

    event FeeSizeUpdated(uint256 indexed feeIndex, uint256 feeSize);

    event FeeVolumeUpdated(uint256 indexed feeIndex, uint256 feeVolume);

    event UserVolumeAdded(address indexed user, address indexed tradePair, uint256 volume);

    event UserManualTierUpdated(address indexed user, Tier tier, uint256 validUntil);

    event UserReferrerAdded(address indexed user, address referrer);

    /* =========== CORE FUNCTIONS =========== */

    function addUserVolume(address user, uint40 volume) external;

    function setUserReferrer(address user, address referrer) external;

    function setUserManualTier(address user, Tier tier, uint32 validUntil) external;

    /* ========== MUTATIVE FUNCTIONS ========== */

    function setFeeVolumes(uint256[] calldata feeIndexes, uint32[] calldata feeVolumes) external;

    function setFeeSizes(uint256[] calldata feeIndexes, uint8[] calldata feeSizes) external;

    /* ========== VIEW FUNCTIONS ========== */

    function getUserFee(address user) external view returns (uint256);

    function getUserReferrer(address user) external view returns (address referrer);
}

