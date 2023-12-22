// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

import {IDepositController} from "./IDepositController.sol";
import {IBondPositionManager} from "./IBondPositionManager.sol";
import {IPositionLocker} from "./IPositionLocker.sol";
import {BondPosition} from "./BondPosition.sol";
import {Epoch, EpochLibrary} from "./Epoch.sol";
import {CouponKey} from "./CouponKey.sol";
import {Coupon} from "./Coupon.sol";
import {ISubstitute} from "./ISubstitute.sol";
import {SubstituteLibrary} from "./Substitute.sol";
import {Controller} from "./Controller.sol";
import {ERC20PermitParams, PermitSignature, PermitParamsLibrary} from "./PermitParams.sol";

contract DepositController is IDepositController, Controller, IPositionLocker {
    using PermitParamsLibrary for *;
    using EpochLibrary for Epoch;
    using SubstituteLibrary for ISubstitute;

    IBondPositionManager private immutable _bondPositionManager;

    modifier onlyPositionOwner(uint256 positionId) {
        if (_bondPositionManager.ownerOf(positionId) != msg.sender) revert InvalidAccess();
        _;
    }

    constructor(
        address wrapped1155Factory,
        address cloberMarketFactory,
        address couponManager,
        address weth,
        address bondPositionManager
    ) Controller(wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
        _bondPositionManager = IBondPositionManager(bondPositionManager);
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory result) {
        if (msg.sender != address(_bondPositionManager)) revert InvalidAccess();

        uint256 positionId;
        address user;
        (positionId, user, data) = abi.decode(data, (uint256, address, bytes));
        if (positionId == 0) {
            address asset;
            (asset, data) = abi.decode(data, (address, bytes));
            positionId = _bondPositionManager.mint(asset);
            result = abi.encode(positionId);
        }
        BondPosition memory position = _bondPositionManager.getPosition(positionId);

        int256 interestThreshold;
        (position.amount, position.expiredWith, interestThreshold) = abi.decode(data, (uint256, Epoch, int256));
        (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn, int256 amountDelta) =
            _bondPositionManager.adjustPosition(positionId, position.amount, position.expiredWith);
        if (amountDelta < 0) _bondPositionManager.withdrawToken(position.asset, address(this), uint256(-amountDelta));
        if (couponsToMint.length > 0) {
            _bondPositionManager.mintCoupons(couponsToMint, address(this), "");
            _wrapCoupons(couponsToMint);
        }

        _executeCouponTrade(
            user,
            position.asset,
            couponsToMint,
            couponsToBurn,
            amountDelta > 0 ? uint256(amountDelta) : 0,
            interestThreshold
        );

        if (amountDelta > 0) {
            IERC20(position.asset).approve(address(_bondPositionManager), uint256(amountDelta));
            _bondPositionManager.depositToken(position.asset, uint256(amountDelta));
        }
        if (couponsToBurn.length > 0) {
            _unwrapCoupons(couponsToBurn);
            _bondPositionManager.burnCoupons(couponsToBurn);
        }

        _bondPositionManager.settlePosition(positionId);
    }

    function deposit(
        address asset,
        uint256 amount,
        Epoch expiredWith,
        int256 minEarnInterest,
        ERC20PermitParams calldata tokenPermitParams
    ) external payable nonReentrant wrapAndRefundETH returns (uint256 positionId) {
        tokenPermitParams.tryPermit(_getUnderlyingToken(asset), msg.sender, address(this));
        bytes memory lockData = abi.encode(amount, expiredWith, -minEarnInterest);
        bytes memory result = _bondPositionManager.lock(abi.encode(0, msg.sender, abi.encode(asset, lockData)));
        positionId = abi.decode(result, (uint256));

        ISubstitute(asset).burnAll(msg.sender);

        _bondPositionManager.transferFrom(address(this), msg.sender, positionId);
    }

    function adjust(
        uint256 positionId,
        uint256 amount,
        Epoch expiredWith,
        int256 interestThreshold,
        ERC20PermitParams calldata tokenPermitParams,
        PermitSignature calldata positionPermitParams
    ) external payable nonReentrant wrapAndRefundETH onlyPositionOwner(positionId) {
        positionPermitParams.tryPermit(_bondPositionManager, positionId, address(this));
        BondPosition memory position = _bondPositionManager.getPosition(positionId);
        tokenPermitParams.tryPermit(position.asset, msg.sender, address(this));

        bytes memory lockData = abi.encode(amount, expiredWith, interestThreshold);
        _bondPositionManager.lock(abi.encode(positionId, msg.sender, lockData));

        ISubstitute(position.asset).burnAll(msg.sender);
    }
}

