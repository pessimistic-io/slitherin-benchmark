// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IPositionManagerTypes, IPositionManager} from "./IPositionManager.sol";
import {Epoch} from "./Epoch.sol";
import {Coupon} from "./Coupon.sol";
import {BondPosition} from "./BondPosition.sol";

interface IBondPositionManagerTypes is IPositionManagerTypes {
    event RegisterAsset(address indexed asset);
    event UpdatePosition(uint256 indexed tokenId, uint256 amount, Epoch expiredWith);

    error InvalidAccess();
    error UnregisteredAsset();
    error InvalidEpoch();
    error AlreadyExpired();
}

interface IBondPositionManager is IBondPositionManagerTypes, IPositionManager {
    // View Functions //
    function MAX_EPOCH() external view returns (Epoch maxEpoch);

    function getPosition(uint256 tokenId) external view returns (BondPosition memory);

    function isAssetRegistered(address asset) external view returns (bool);

    // User Functions //
    function mint(address asset) external returns (uint256 positionId);

    function adjustPosition(uint256 tokenId, uint256 amount, Epoch expiredWith)
        external
        returns (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn, int256 amountDelta);

    // Admin Functions //
    function registerAsset(address asset) external;
}

