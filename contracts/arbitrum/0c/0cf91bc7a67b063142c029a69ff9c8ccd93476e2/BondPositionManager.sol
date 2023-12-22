// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {Ownable2Step} from "./Ownable2Step.sol";

import {IBondPositionManager} from "./IBondPositionManager.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {BondPosition, BondPositionLibrary} from "./BondPosition.sol";
import {Coupon, CouponLibrary} from "./Coupon.sol";
import {Epoch, EpochLibrary} from "./Epoch.sol";
import {PositionManager} from "./PositionManager.sol";

contract BondPositionManager is IBondPositionManager, PositionManager, Ownable2Step {
    using EpochLibrary for Epoch;
    using BondPositionLibrary for BondPosition;
    using CouponLibrary for Coupon;

    Epoch public constant override MAX_EPOCH = Epoch.wrap(947); // Ends at 31 Dec 2048 23:59:59 GMT

    mapping(address asset => bool) public override isAssetRegistered;
    mapping(uint256 id => BondPosition) private _positionMap;

    constructor(address coupon_, address assetPool_, string memory baseURI_, string memory contractURI_)
        PositionManager(coupon_, assetPool_, baseURI_, contractURI_, "Bond Position", "BP")
    {}

    function getPosition(uint256 positionId) external view returns (BondPosition memory) {
        return _positionMap[positionId];
    }

    function mint(address asset) external onlyByLocker returns (uint256 positionId) {
        if (!isAssetRegistered[asset]) revert UnregisteredAsset();

        unchecked {
            positionId = nextId++;
        }
        _positionMap[positionId].asset = asset;
        _mint(msg.sender, positionId);
    }

    function adjustPosition(uint256 positionId, uint256 amount, Epoch expiredWith)
        external
        onlyByLocker
        modifyPosition(positionId)
        returns (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn, int256 amountDelta)
    {
        if (!_isApprovedOrOwner(msg.sender, positionId)) revert InvalidAccess();
        Epoch lastExpiredEpoch = EpochLibrary.lastExpiredEpoch();
        if (amount == 0 || expiredWith == Epoch.wrap(0)) {
            amount = 0;
            expiredWith = lastExpiredEpoch;
        }

        if (expiredWith < lastExpiredEpoch || MAX_EPOCH < expiredWith) revert InvalidEpoch();

        BondPosition memory position = _positionMap[positionId];

        _positionMap[positionId].amount = amount;
        if (Epoch.wrap(0) < position.expiredWith && position.expiredWith <= lastExpiredEpoch) {
            if (amount > 0) revert AlreadyExpired();
        } else {
            _positionMap[positionId].expiredWith = expiredWith;
            if (position.expiredWith == Epoch.wrap(0)) position.expiredWith = lastExpiredEpoch;

            (couponsToMint, couponsToBurn) = position.calculateCouponRequirement(_positionMap[positionId]);
        }

        unchecked {
            for (uint256 i = 0; i < couponsToMint.length; ++i) {
                _accountDelta(couponsToMint[i].id(), 0, couponsToMint[i].amount);
            }
            for (uint256 i = 0; i < couponsToBurn.length; ++i) {
                _accountDelta(couponsToBurn[i].id(), couponsToBurn[i].amount, 0);
            }
        }
        amountDelta = _accountDelta(uint256(uint160(position.asset)), amount, position.amount);
    }

    function settlePosition(uint256 positionId) public override(IPositionManager, PositionManager) onlyByLocker {
        super.settlePosition(positionId);
        BondPosition memory position = _positionMap[positionId];
        if (MAX_EPOCH < position.expiredWith) revert InvalidEpoch();
        if (position.amount == 0) {
            _burn(positionId);
        } else if (position.expiredWith < EpochLibrary.current()) {
            revert InvalidEpoch();
        }
        emit UpdatePosition(positionId, position.amount, position.expiredWith);
    }

    function registerAsset(address asset) external onlyOwner {
        isAssetRegistered[asset] = true;
        emit RegisterAsset(asset);
    }

    function nonces(uint256 positionId) external view returns (uint256) {
        return _positionMap[positionId].nonce;
    }

    function _getAndIncrementNonce(uint256 positionId) internal override returns (uint256) {
        return _positionMap[positionId].getAndIncrementNonce();
    }

    function _isSettled(uint256 positionId) internal view override returns (bool) {
        return _positionMap[positionId].isSettled;
    }

    function _setPositionSettlement(uint256 positionId, bool settled) internal override {
        _positionMap[positionId].isSettled = settled;
    }
}

