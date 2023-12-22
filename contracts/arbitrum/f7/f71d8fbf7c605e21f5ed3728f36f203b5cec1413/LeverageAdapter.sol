// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";

import {ISubstitute} from "./ISubstitute.sol";
import {ICouponOracle} from "./ICouponOracle.sol";
import {ILoanPositionManager} from "./ILoanPositionManager.sol";
import {LoanPosition} from "./LoanPosition.sol";
import {Coupon} from "./Coupon.sol";
import {Controller} from "./Controller.sol";
import {IPositionLocker} from "./IPositionLocker.sol";
import {ILeverageAdapter} from "./ILeverageAdapter.sol";
import {Epoch, EpochLibrary} from "./Epoch.sol";

contract LeverageAdapter is ILeverageAdapter, Controller, IPositionLocker {
    using EpochLibrary for Epoch;

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
        bytes memory swapData;
        (positionId, user, data, swapData) = abi.decode(data, (uint256, address, bytes, bytes));
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
        if (debtDelta > 0) {
            _loanPositionManager.withdrawToken(position.debtToken, address(this), uint256(debtDelta));
        }
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

        if (swapData.length > 0) {
            _swap(position.debtToken, position.collateralToken, swapData);
        }

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

    function leverage(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxPayInterest,
        uint16 loanEpochs,
        bytes memory swapData,
        ERC20PermitParams calldata collateralPermitParams
    ) external payable nonReentrant wrapETH {
        _permitERC20(collateralToken, collateralPermitParams);

        bytes memory lockData =
            abi.encode(collateralAmount, borrowAmount, EpochLibrary.current().add(loanEpochs - 1), maxPayInterest, 0);
        lockData = abi.encode(0, msg.sender, abi.encode(collateralToken, debtToken, lockData), swapData);
        bytes memory result = _loanPositionManager.lock(lockData);
        uint256 positionId = abi.decode(result, (uint256));

        _burnAllSubstitute(collateralToken, msg.sender);
        _burnAllSubstitute(debtToken, msg.sender);
        _loanPositionManager.transferFrom(address(this), msg.sender, positionId);
    }

    function leverageMore(
        uint256 positionId,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 maxPayInterest,
        bytes memory swapData,
        PermitSignature calldata positionPermitParams,
        ERC20PermitParams calldata collateralPermitParams
    ) external payable nonReentrant wrapETH onlyPositionOwner(positionId) {
        LoanPosition memory position = _loanPositionManager.getPosition(positionId);

        _permitERC20(position.collateralToken, collateralPermitParams);
        _permitERC721(_loanPositionManager, positionId, positionPermitParams);

        position.collateralAmount += collateralAmount;
        position.debtAmount += debtAmount;

        bytes memory data =
            abi.encode(position.collateralAmount, position.debtAmount, position.expiredWith, maxPayInterest, 0);

        _loanPositionManager.lock(abi.encode(positionId, msg.sender, data, swapData));

        _burnAllSubstitute(position.collateralToken, msg.sender);
        _burnAllSubstitute(position.debtToken, msg.sender);
    }

    function _swap(address inSubstitute, address outSubstitute, bytes memory swapData)
        internal
        returns (uint256 leftInAmount, uint256 outAmount)
    {
        uint256 inAmount = IERC20(inSubstitute).balanceOf(address(this));

        address inToken = ISubstitute(inSubstitute).underlyingToken();
        address outToken = ISubstitute(outSubstitute).underlyingToken();

        ISubstitute(inSubstitute).burn(inAmount, address(this));
        if (inToken == address(_weth)) _weth.deposit{value: inAmount}();
        IERC20(inToken).approve(_router, inAmount);
        (bool success, bytes memory result) = _router.call(swapData);
        if (!success) revert CollateralSwapFailed(string(result));
        IERC20(inToken).approve(_router, 0);

        outAmount = IERC20(outToken).balanceOf(address(this));
        leftInAmount = IERC20(inToken).balanceOf(address(this));

        if (leftInAmount > 0) {
            IERC20(inToken).approve(inSubstitute, leftInAmount);
            ISubstitute(inSubstitute).mint(leftInAmount, address(this));
        }

        IERC20(outToken).approve(outSubstitute, outAmount);
        ISubstitute(outSubstitute).mint(outAmount, address(this));
    }
}

