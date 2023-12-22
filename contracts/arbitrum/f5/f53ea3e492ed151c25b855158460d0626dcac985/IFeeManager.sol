// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IFeeManager {
    /* ========== EVENTS ============ */

    event ReferrerFeesPaid(address indexed referrer, address indexed asset, uint256 amount, address user);

    event WhiteLabelFeesPaid(address indexed whitelabel, address indexed asset, uint256 amount, address user);

    event UpdatedReferralFee(uint256 newReferrerFee);

    event UpdatedStakersFeeAddress(address stakersFeeAddress);

    event UpdatedDevFeeAddress(address devFeeAddress);

    event UpdatedInsuranceFundFeeAddress(address insuranceFundFeeAddress);

    event SetWhitelabelFee(address indexed whitelabelAddress, uint256 feeSize);

    event SetCustomReferralFee(address indexed referrer, uint256 feeSize);

    event SpreadFees(
        address asset,
        uint256 stakersFeeAmount,
        uint256 devFeeAmount,
        uint256 insuranceFundFeeAmount,
        uint256 liquidityPoolFeeAmount,
        address user
    );

    /* ========== CORE FUNCTIONS ========== */

    function depositOpenFees(address user, address asset, uint256 amount, address whitelabelAddress) external;

    function depositCloseFees(address user, address asset, uint256 amount, address whitelabelAddress) external;

    function depositBorrowFees(address asset, uint256 amount) external;

    /* ========== VIEW FUNCTIONS ========== */

    function calculateUserOpenFeeAmount(address user, uint256 amount) external view returns (uint256);

    function calculateUserOpenFeeAmount(address user, uint256 amount, uint256 leverage)
        external
        view
        returns (uint256);

    function calculateUserExtendToLeverageFeeAmount(
        address user,
        uint256 margin,
        uint256 volume,
        uint256 targetLeverage
    ) external view returns (uint256);

    function calculateUserCloseFeeAmount(address user, uint256 amount) external view returns (uint256);
}

