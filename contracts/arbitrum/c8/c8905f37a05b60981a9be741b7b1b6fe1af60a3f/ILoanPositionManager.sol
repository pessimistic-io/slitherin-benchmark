// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IPositionManagerTypes, IPositionManager} from "./IPositionManager.sol";
import {CouponKey} from "./CouponKey.sol";
import {Coupon} from "./Coupon.sol";
import {Epoch} from "./Epoch.sol";
import {LoanPosition} from "./LoanPosition.sol";

interface ILoanPositionManagerTypes is IPositionManagerTypes {
    // liquidationFee = liquidator fee + protocol fee
    // debt = collateral * (1 - liquidationFee)
    struct LoanConfiguration {
        uint32 collateralDecimal;
        uint32 debtDecimal;
        uint32 liquidationThreshold;
        uint32 liquidationFee;
        uint32 liquidationProtocolFee;
        uint32 liquidationTargetLtv;
    }

    event SetLoanConfiguration(
        address indexed collateral,
        address indexed debt,
        uint32 liquidationThreshold,
        uint32 liquidationFee,
        uint32 liquidationProtocolFee,
        uint32 liquidationTargetLtv,
        address hook
    );
    event UpdatePosition(uint256 indexed positionId, uint256 collateralAmount, uint256 debtAmount, Epoch unlockedAt);
    event LiquidatePosition(
        uint256 indexed positionId,
        address indexed liquidator,
        uint256 liquidationAmount,
        uint256 repayAmount,
        uint256 protocolFeeAmount
    );
    event SetTreasury(address indexed newTreasury);

    error TooSmallDebtLeft();
    error InvalidAccess();
    error FullRepaymentRequired();
    error LiquidationThreshold();
    error InvalidPair();
    error InvalidConfiguration();
    error UnableToLiquidate();
}

interface ILoanPositionManager is ILoanPositionManagerTypes, IPositionManager {
    function treasury() external view returns (address);

    function oracle() external view returns (address);

    function minDebtValueInEth() external view returns (uint256);

    function getPosition(uint256 positionId) external view returns (LoanPosition memory);

    function isPairRegistered(address collateral, address debt) external view returns (bool);

    function getLoanConfiguration(address collateral, address debt) external view returns (LoanConfiguration memory);

    function getOwedCouponAmount(address user, uint256 couponId) external view returns (uint256);

    function getLiquidationStatus(uint256 positionId, uint256 maxRepayAmount)
        external
        view
        returns (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount);

    function mint(address collateralToken, address debtToken) external returns (uint256 positionId);

    function adjustPosition(uint256 positionId, uint256 collateralAmount, uint256 debtAmount, Epoch expiredWith)
        external
        returns (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn, int256 collateralDelta, int256 debtDelta);

    function liquidate(uint256 positionId, uint256 maxRepayAmount)
        external
        returns (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount);

    function claimOwedCoupons(CouponKey[] memory couponKeys, bytes calldata data) external;

    function setLoanConfiguration(
        address collateral,
        address debt,
        uint32 liquidationThreshold,
        uint32 liquidationFee,
        uint32 liquidationProtocolFee,
        uint32 liquidationTargetLtv,
        address hook
    ) external;

    function setTreasury(address newTreasury) external;
}

