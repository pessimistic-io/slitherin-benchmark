// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {Math} from "./Math.sol";

import {Epoch, EpochLibrary} from "./Epoch.sol";
import {Coupon, CouponLibrary} from "./Coupon.sol";

struct BondPosition {
    address asset;
    uint64 nonce;
    Epoch expiredWith;
    bool isSettled;
    uint256 amount;
}

library BondPositionLibrary {
    error UnmatchedPosition();
    error InvalidPositionEpoch();

    using EpochLibrary for Epoch;

    function getAndIncrementNonce(BondPosition storage positionStorage) internal returns (uint64 nonce) {
        nonce = positionStorage.nonce++;
    }

    function calculateCouponRequirement(BondPosition memory oldPosition, BondPosition memory newPosition)
        internal
        view
        returns (Coupon[] memory mintCoupons, Coupon[] memory burnCoupons)
    {
        if (!(oldPosition.asset == newPosition.asset && oldPosition.nonce == newPosition.nonce)) {
            revert UnmatchedPosition();
        }

        Epoch latestExpiredEpoch = EpochLibrary.lastExpiredEpoch();
        if (latestExpiredEpoch > newPosition.expiredWith || latestExpiredEpoch > oldPosition.expiredWith) {
            revert InvalidPositionEpoch();
        }
        uint256 mintCouponsLength = newPosition.expiredWith.sub(latestExpiredEpoch);
        uint256 burnCouponsLength = oldPosition.expiredWith.sub(latestExpiredEpoch);
        unchecked {
            uint256 minCount = Math.min(mintCouponsLength, burnCouponsLength);
            if (newPosition.amount > oldPosition.amount) {
                burnCouponsLength -= minCount;
            } else if (newPosition.amount < oldPosition.amount) {
                mintCouponsLength -= minCount;
            } else {
                mintCouponsLength -= minCount;
                burnCouponsLength -= minCount;
            }
        }

        mintCoupons = new Coupon[](mintCouponsLength);
        burnCoupons = new Coupon[](burnCouponsLength);
        mintCouponsLength = 0;
        burnCouponsLength = 0;
        uint256 farthestExpiredEpochs = newPosition.expiredWith.max(oldPosition.expiredWith).sub(latestExpiredEpoch);
        unchecked {
            Epoch epoch = latestExpiredEpoch;
            for (uint256 i = 0; i < farthestExpiredEpochs; ++i) {
                epoch = epoch.add(1);
                uint256 newAmount = newPosition.expiredWith < epoch ? 0 : newPosition.amount;
                uint256 oldAmount = oldPosition.expiredWith < epoch ? 0 : oldPosition.amount;
                if (newAmount > oldAmount) {
                    mintCoupons[mintCouponsLength++] =
                        CouponLibrary.from(oldPosition.asset, epoch, newAmount - oldAmount);
                } else if (newAmount < oldAmount) {
                    burnCoupons[burnCouponsLength++] =
                        CouponLibrary.from(oldPosition.asset, epoch, oldAmount - newAmount);
                }
            }
        }
    }
}

