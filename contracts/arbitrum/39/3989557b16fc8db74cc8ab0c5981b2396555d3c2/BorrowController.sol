// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

import {IBorrowController} from "./IBorrowController.sol";
import {ILoanPositionManager} from "./ILoanPositionManager.sol";
import {ISubstitute} from "./ISubstitute.sol";
import {SubstituteLibrary} from "./Substitute.sol";
import {IPositionLocker} from "./IPositionLocker.sol";
import {LoanPosition} from "./LoanPosition.sol";
import {Coupon} from "./Coupon.sol";
import {Epoch, EpochLibrary} from "./Epoch.sol";
import {Controller} from "./Controller.sol";
import {ERC20PermitParams, PermitSignature, PermitParamsLibrary} from "./PermitParams.sol";

contract BorrowController is IBorrowController, Controller, IPositionLocker {
    using PermitParamsLibrary for *;
    using EpochLibrary for Epoch;
    using SubstituteLibrary for ISubstitute;

    ILoanPositionManager private immutable _loanPositionManager;
    address private immutable _router;

    modifier onlyPositionOwner(uint256 positionId) {
        if (_loanPositionManager.ownerOf(positionId) != msg.sender) revert InvalidAccess();
        _;
    }

    constructor(
        address wrapped1155Factory,
        address cloberMarketFactory,
        address couponManager,
        address weth,
        address loanPositionManager,
        address router
    ) Controller(wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
        _loanPositionManager = ILoanPositionManager(loanPositionManager);
        _router = router;
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory result) {
        if (msg.sender != address(_loanPositionManager)) revert InvalidAccess();

        uint256 positionId;
        address user;
        SwapParams memory swapParams;
        (positionId, user, swapParams, data) = abi.decode(data, (uint256, address, SwapParams, bytes));
        if (positionId == 0) {
            address collateralToken;
            address debtToken;
            (collateralToken, debtToken, data) = abi.decode(data, (address, address, bytes));
            positionId = _loanPositionManager.mint(collateralToken, debtToken);
            result = abi.encode(positionId);
        }
        LoanPosition memory position = _loanPositionManager.getPosition(positionId);

        int256 interestThreshold;
        (position.collateralAmount, position.debtAmount, position.expiredWith, interestThreshold) =
            abi.decode(data, (uint256, uint256, Epoch, int256));

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

        if (swapParams.inSubstitute == position.collateralToken) {
            _swap(position.collateralToken, position.debtToken, swapParams.amount, swapParams.data);
        } else if (swapParams.inSubstitute == position.debtToken) {
            _swap(position.debtToken, position.collateralToken, swapParams.amount, swapParams.data);
        }

        _executeCouponTrade(
            user,
            position.debtToken,
            couponsToMint,
            couponsToBurn,
            debtDelta < 0 ? uint256(-debtDelta) : 0,
            interestThreshold
        );

        if (collateralDelta > 0) {
            ISubstitute(position.collateralToken).ensureBalance(user, uint256(collateralDelta));
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
        uint256 debtAmount,
        int256 maxPayInterest,
        Epoch expiredWith,
        SwapParams calldata swapParams,
        ERC20PermitParams calldata collateralPermitParams
    ) external payable nonReentrant wrapAndRefundETH returns (uint256 positionId) {
        collateralPermitParams.tryPermit(_getUnderlyingToken(collateralToken), msg.sender, address(this));

        bytes memory lockData = abi.encode(collateralAmount, debtAmount, expiredWith, maxPayInterest);
        lockData = abi.encode(0, msg.sender, swapParams, abi.encode(collateralToken, debtToken, lockData));
        bytes memory result = _loanPositionManager.lock(lockData);
        positionId = abi.decode(result, (uint256));

        ISubstitute(collateralToken).burnAll(msg.sender);
        ISubstitute(debtToken).burnAll(msg.sender);
        _loanPositionManager.transferFrom(address(this), msg.sender, positionId);
    }

    function adjust(
        uint256 positionId,
        uint256 collateralAmount,
        uint256 debtAmount,
        int256 interestThreshold,
        Epoch expiredWith,
        SwapParams calldata swapParams,
        PermitSignature calldata positionPermitParams,
        ERC20PermitParams calldata collateralPermitParams,
        ERC20PermitParams calldata debtPermitParams
    ) external payable nonReentrant wrapAndRefundETH onlyPositionOwner(positionId) {
        positionPermitParams.tryPermit(_loanPositionManager, positionId, address(this));
        LoanPosition memory position = _loanPositionManager.getPosition(positionId);
        collateralPermitParams.tryPermit(_getUnderlyingToken(position.collateralToken), msg.sender, address(this));
        debtPermitParams.tryPermit(_getUnderlyingToken(position.debtToken), msg.sender, address(this));

        position.collateralAmount = collateralAmount;
        position.debtAmount = debtAmount;
        position.expiredWith = expiredWith;

        _loanPositionManager.lock(_encodeAdjustData(positionId, position, interestThreshold, swapParams));

        ISubstitute(position.collateralToken).burnAll(msg.sender);
        ISubstitute(position.debtToken).burnAll(msg.sender);
    }

    function _swap(address inSubstitute, address outSubstitute, uint256 inAmount, bytes memory swapParams)
        internal
        returns (uint256 outAmount)
    {
        address inToken = ISubstitute(inSubstitute).underlyingToken();
        address outToken = ISubstitute(outSubstitute).underlyingToken();

        ISubstitute(inSubstitute).burn(inAmount, address(this));
        if (inToken == address(_weth)) _weth.deposit{value: inAmount}();
        IERC20(inToken).approve(_router, inAmount);
        (bool success, bytes memory result) = _router.call(swapParams);
        if (!success) revert CollateralSwapFailed(string(result));
        IERC20(inToken).approve(_router, 0);

        outAmount = IERC20(outToken).balanceOf(address(this));

        IERC20(outToken).approve(outSubstitute, outAmount);
        ISubstitute(outSubstitute).mint(outAmount, address(this));
    }

    function _encodeAdjustData(
        uint256 id,
        LoanPosition memory p,
        int256 interestThreshold,
        SwapParams memory swapParams
    ) internal view returns (bytes memory) {
        bytes memory data = abi.encode(p.collateralAmount, p.debtAmount, p.expiredWith, interestThreshold);
        return abi.encode(id, msg.sender, swapParams, data);
    }
}

