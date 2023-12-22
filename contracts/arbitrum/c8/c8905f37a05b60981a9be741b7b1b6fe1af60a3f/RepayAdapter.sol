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
import {IRepayAdapter} from "./IRepayAdapter.sol";
import {Epoch, EpochLibrary} from "./Epoch.sol";

contract RepayAdapter is IRepayAdapter, Controller, IPositionLocker {
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

    function positionLockAcquired(bytes memory data) external returns (bytes memory) {
        if (msg.sender != address(_loanPositionManager)) revert InvalidAccess();

        (uint256 positionId, address user, uint256 sellCollateralAmount, uint256 minRepayAmount, bytes memory swapData)
        = abi.decode(data, (uint256, address, uint256, uint256, bytes));
        LoanPosition memory position = _loanPositionManager.getPosition(positionId);
        uint256 maxDebtAmount = position.debtAmount - minRepayAmount;

        _loanPositionManager.withdrawToken(position.collateralToken, address(this), sellCollateralAmount);
        (uint256 leftCollateralAmount, uint256 repayDebtAmount) =
            _swapCollateral(position.collateralToken, position.debtToken, sellCollateralAmount, swapData);
        IERC20(position.collateralToken).approve(address(_loanPositionManager), leftCollateralAmount);
        _loanPositionManager.depositToken(position.collateralToken, leftCollateralAmount);
        position.collateralAmount = position.collateralAmount + leftCollateralAmount - sellCollateralAmount;

        Epoch lastExpiredEpoch = EpochLibrary.lastExpiredEpoch();
        Coupon[] memory couponsToMint;
        Coupon[] memory couponsToBurn;
        unchecked {
            if (position.debtAmount < repayDebtAmount) {
                repayDebtAmount = position.debtAmount;
            }

            uint256 remainingDebtAmount = position.debtAmount - repayDebtAmount;
            uint256 minDebtAmount = _getMinDebtAmount(position.debtToken);
            if (0 < remainingDebtAmount && remainingDebtAmount < minDebtAmount) remainingDebtAmount = minDebtAmount;

            (couponsToMint, couponsToBurn,,) = _loanPositionManager.adjustPosition(
                positionId,
                position.collateralAmount,
                remainingDebtAmount,
                remainingDebtAmount == 0 ? lastExpiredEpoch : position.expiredWith
            );

            if (couponsToMint.length > 0) {
                _loanPositionManager.mintCoupons(couponsToMint, address(this), "");
                _wrapCoupons(couponsToMint);
            }

            _executeCouponTrade(
                user, position.debtToken, couponsToMint, couponsToBurn, repayDebtAmount, type(uint256).max, 0
            );

            uint256 depositDebtTokenAmount = IERC20(position.debtToken).balanceOf(address(this));

            if (position.debtAmount <= depositDebtTokenAmount) {
                remainingDebtAmount = 0;
                depositDebtTokenAmount = position.debtAmount;
            } else {
                remainingDebtAmount = position.debtAmount - depositDebtTokenAmount;
            }

            if (remainingDebtAmount > 0 && remainingDebtAmount < minDebtAmount) remainingDebtAmount = minDebtAmount;
            if (maxDebtAmount < remainingDebtAmount) revert ControllerSlippage();

            uint256 depositAmount = position.debtAmount - remainingDebtAmount;
            IERC20(position.debtToken).approve(address(_loanPositionManager), depositAmount);
            _loanPositionManager.depositToken(position.debtToken, depositAmount);
            position.debtAmount = remainingDebtAmount;
        }

        (couponsToMint,,,) = _loanPositionManager.adjustPosition(
            positionId,
            position.collateralAmount,
            position.debtAmount,
            position.debtAmount == 0 ? lastExpiredEpoch : position.expiredWith
        );
        _loanPositionManager.mintCoupons(couponsToMint, user, "");
        if (couponsToBurn.length > 0) {
            _unwrapCoupons(couponsToBurn);
            _loanPositionManager.burnCoupons(couponsToBurn);
        }

        _burnAllSubstitute(position.debtToken, user);
        _loanPositionManager.settlePosition(positionId);

        return "";
    }

    function repayWithCollateral(
        uint256 positionId,
        uint256 sellCollateralAmount,
        uint256 minRepayAmount,
        bytes memory swapData,
        PermitSignature calldata positionPermitParams
    ) external nonReentrant onlyPositionOwner(positionId) {
        _permitERC721(_loanPositionManager, positionId, positionPermitParams);
        _loanPositionManager.lock(abi.encode(positionId, msg.sender, sellCollateralAmount, minRepayAmount, swapData));
    }

    function _swapCollateral(address collateral, address debt, uint256 inAmount, bytes memory swapData)
        internal
        returns (uint256 leftInAmount, uint256 outAmount)
    {
        address inToken = ISubstitute(collateral).underlyingToken();
        address outToken = ISubstitute(debt).underlyingToken();

        ISubstitute(collateral).burn(inAmount, address(this));
        if (inToken == address(_weth)) _weth.deposit{value: inAmount}();
        IERC20(inToken).approve(_router, inAmount);
        (bool success, bytes memory result) = _router.call(swapData);
        if (!success) revert CollateralSwapFailed(string(result));
        IERC20(inToken).approve(_router, 0);

        outAmount = IERC20(outToken).balanceOf(address(this));
        leftInAmount = IERC20(inToken).balanceOf(address(this));

        if (leftInAmount > 0) {
            IERC20(inToken).approve(collateral, leftInAmount);
            ISubstitute(collateral).mint(leftInAmount, address(this));
        }

        IERC20(outToken).approve(debt, outAmount);
        ISubstitute(debt).mint(outAmount, address(this));
    }

    function _getMinDebtAmount(address debtToken) internal view returns (uint256 minDebtAmount) {
        unchecked {
            address[] memory assets = new address[](2);
            assets[0] = debtToken;
            assets[1] = address(0);

            uint256 debtDecimal = IERC20Metadata(debtToken).decimals();

            uint256[] memory prices = ICouponOracle(_loanPositionManager.oracle()).getAssetsPrices(assets);
            minDebtAmount = _loanPositionManager.minDebtValueInEth() * prices[1];
            if (debtDecimal > 18) {
                minDebtAmount *= 10 ** (debtDecimal - 18);
            } else {
                minDebtAmount /= 10 ** (18 - debtDecimal);
            }
            minDebtAmount /= prices[0];
        }
    }
}

