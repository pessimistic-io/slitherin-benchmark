// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

import {IBorrowController} from "./IBorrowController.sol";
import {ILoanPositionManager} from "./ILoanPositionManager.sol";
import {LoanPosition} from "./LoanPosition.sol";
import {Coupon} from "./Coupon.sol";
import {Epoch, EpochLibrary} from "./Epoch.sol";
import {Controller} from "./Controller.sol";
import {IPositionLocker} from "./IPositionLocker.sol";

contract BorrowController is IBorrowController, Controller, IPositionLocker {
    using EpochLibrary for Epoch;

    ILoanPositionManager private immutable _loanPositionManager;

    modifier onlyPositionOwner(uint256 positionId) {
        if (_loanPositionManager.ownerOf(positionId) != msg.sender) revert InvalidAccess();
        _;
    }

    constructor(
        address wrapped1155Factory,
        address cloberMarketFactory,
        address couponManager,
        address weth,
        address loanPositionManager
    ) Controller(wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
        _loanPositionManager = ILoanPositionManager(loanPositionManager);
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory result) {
        if (msg.sender != address(_loanPositionManager)) revert InvalidAccess();

        uint256 positionId;
        address user;
        (positionId, user, data) = abi.decode(data, (uint256, address, bytes));
        if (positionId == 0) {
            address collateralToken;
            address debtToken;
            (collateralToken, debtToken, data) = abi.decode(data, (address, address, bytes));
            positionId = _loanPositionManager.mint(collateralToken, debtToken);
            result = abi.encode(positionId);
        }
        LoanPosition memory position = _loanPositionManager.getPosition(positionId);

        uint256 maxPayInterest;
        uint256 minEarnInterest;
        (position.collateralAmount, position.debtAmount, position.expiredWith, maxPayInterest, minEarnInterest) =
            abi.decode(data, (uint256, uint256, Epoch, uint256, uint256));

        (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn, int256 collateralDelta, int256 debtDelta) =
        _loanPositionManager.adjustPosition(
            positionId, position.collateralAmount, position.debtAmount, position.expiredWith
        );
        if (collateralDelta < 0) {
            _loanPositionManager.withdrawToken(position.collateralToken, address(this), uint256(-collateralDelta));
        }
        if (debtDelta > 0) _loanPositionManager.withdrawToken(position.debtToken, address(this), uint256(debtDelta));
        if (couponsToMint.length > 0) {
            _loanPositionManager.mintCoupons(couponsToMint, address(this), "");
            _wrapCoupons(couponsToMint);
        }

        _executeCouponTrade(
            user,
            position.debtToken,
            couponsToMint,
            couponsToBurn,
            debtDelta < 0 ? uint256(-debtDelta) : 0,
            maxPayInterest,
            minEarnInterest
        );

        if (collateralDelta > 0) {
            _ensureBalance(position.collateralToken, user, uint256(collateralDelta));
            IERC20(position.collateralToken).approve(address(_loanPositionManager), uint256(collateralDelta));
            _loanPositionManager.depositToken(position.collateralToken, uint256(collateralDelta));
        }
        if (debtDelta < 0) {
            IERC20(position.debtToken).approve(address(_loanPositionManager), uint256(-debtDelta));
            _loanPositionManager.depositToken(position.debtToken, uint256(-debtDelta));
        }
        if (couponsToBurn.length > 0) {
            _unwrapCoupons(couponsToBurn);
            _loanPositionManager.burnCoupons(couponsToBurn);
        }

        _loanPositionManager.settlePosition(positionId);
    }

    function borrow(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxPayInterest,
        uint16 loanEpochs,
        ERC20PermitParams calldata collateralPermitParams
    ) external payable nonReentrant wrapETH {
        _permitERC20(collateralToken, collateralPermitParams);

        bytes memory lockData =
            abi.encode(collateralAmount, borrowAmount, EpochLibrary.current().add(loanEpochs - 1), maxPayInterest, 0);
        lockData = abi.encode(0, msg.sender, abi.encode(collateralToken, debtToken, lockData));
        bytes memory result = _loanPositionManager.lock(lockData);
        uint256 positionId = abi.decode(result, (uint256));

        _burnAllSubstitute(collateralToken, msg.sender);
        _burnAllSubstitute(debtToken, msg.sender);
        _loanPositionManager.transferFrom(address(this), msg.sender, positionId);
    }

    function borrowMore(
        uint256 positionId,
        uint256 amount,
        uint256 maxPayInterest,
        PermitSignature calldata positionPermitParams
    ) external nonReentrant onlyPositionOwner(positionId) {
        _permitERC721(_loanPositionManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanPositionManager.getPosition(positionId);
        position.debtAmount += amount;

        _loanPositionManager.lock(_encodeAdjustData(positionId, position, maxPayInterest, 0));

        _burnAllSubstitute(position.debtToken, msg.sender);
    }

    function addCollateral(
        uint256 positionId,
        uint256 amount,
        PermitSignature calldata positionPermitParams,
        ERC20PermitParams calldata collateralPermitParams
    ) external payable nonReentrant onlyPositionOwner(positionId) wrapETH {
        _permitERC721(_loanPositionManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanPositionManager.getPosition(positionId);
        _permitERC20(position.collateralToken, collateralPermitParams);
        position.collateralAmount += amount;

        _loanPositionManager.lock(_encodeAdjustData(positionId, position, 0, 0));

        _burnAllSubstitute(position.collateralToken, msg.sender);
    }

    function removeCollateral(uint256 positionId, uint256 amount, PermitSignature calldata positionPermitParams)
        external
        nonReentrant
        onlyPositionOwner(positionId)
    {
        _permitERC721(_loanPositionManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanPositionManager.getPosition(positionId);
        position.collateralAmount -= amount;

        _loanPositionManager.lock(_encodeAdjustData(positionId, position, 0, 0));

        _burnAllSubstitute(position.collateralToken, msg.sender);
    }

    function extendLoanDuration(
        uint256 positionId,
        uint16 epochs,
        uint256 maxPayInterest,
        PermitSignature calldata positionPermitParams,
        ERC20PermitParams calldata debtPermitParams
    ) external payable nonReentrant onlyPositionOwner(positionId) wrapETH {
        _permitERC721(_loanPositionManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanPositionManager.getPosition(positionId);
        _permitERC20(position.debtToken, debtPermitParams);
        position.expiredWith = position.expiredWith.add(epochs);

        _loanPositionManager.lock(_encodeAdjustData(positionId, position, maxPayInterest, 0));

        _burnAllSubstitute(position.debtToken, msg.sender);
    }

    function shortenLoanDuration(
        uint256 positionId,
        uint16 epochs,
        uint256 minEarnInterest,
        PermitSignature calldata positionPermitParams
    ) external nonReentrant onlyPositionOwner(positionId) {
        _permitERC721(_loanPositionManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanPositionManager.getPosition(positionId);
        position.expiredWith = position.expiredWith.sub(epochs);

        _loanPositionManager.lock(_encodeAdjustData(positionId, position, 0, minEarnInterest));

        _burnAllSubstitute(position.debtToken, msg.sender);
    }

    function repay(
        uint256 positionId,
        uint256 amount,
        uint256 minEarnInterest,
        PermitSignature calldata positionPermitParams,
        ERC20PermitParams calldata debtPermitParams
    ) external payable nonReentrant onlyPositionOwner(positionId) wrapETH {
        _permitERC721(_loanPositionManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanPositionManager.getPosition(positionId);
        _permitERC20(position.debtToken, debtPermitParams);
        position.debtAmount -= amount;

        _loanPositionManager.lock(_encodeAdjustData(positionId, position, 0, minEarnInterest));

        _burnAllSubstitute(position.debtToken, msg.sender);
    }

    function _encodeAdjustData(uint256 id, LoanPosition memory p, uint256 maxPay, uint256 minEarn)
        internal
        view
        returns (bytes memory)
    {
        bytes memory data = abi.encode(p.collateralAmount, p.debtAmount, p.expiredWith, maxPay, minEarn);
        return abi.encode(id, msg.sender, data);
    }
}

