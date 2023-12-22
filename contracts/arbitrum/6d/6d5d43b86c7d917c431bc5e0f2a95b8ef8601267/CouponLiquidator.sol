// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {IERC20Permit} from "./IERC20Permit.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Math} from "./Math.sol";

import {IWETH9} from "./IWETH9.sol";
import {ISubstitute} from "./ISubstitute.sol";
import {ILoanPositionManager} from "./ILoanPositionManager.sol";
import {IPositionLocker} from "./IPositionLocker.sol";
import {ICouponLiquidator} from "./ICouponLiquidator.sol";
import {LoanPosition} from "./LoanPosition.sol";
import {SubstituteLibrary} from "./Substitute.sol";

contract CouponLiquidator is ICouponLiquidator, IPositionLocker {
    using SafeERC20 for IERC20;
    using SubstituteLibrary for ISubstitute;

    ILoanPositionManager private immutable _loanPositionManager;
    address private immutable _router;
    IWETH9 internal immutable _weth;

    constructor(address loanPositionManager, address router, address weth) {
        _loanPositionManager = ILoanPositionManager(loanPositionManager);
        _router = router;
        _weth = IWETH9(weth);
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory) {
        (
            address payer,
            uint256 positionId,
            uint256 swapAmount,
            bytes memory swapData,
            uint256 allowedSupplementaryAmount,
            address recipient
        ) = abi.decode(data, (address, uint256, uint256, bytes, uint256, address));

        LoanPosition memory position = _loanPositionManager.getPosition(positionId);
        address inToken = ISubstitute(position.collateralToken).underlyingToken();
        address outToken = ISubstitute(position.debtToken).underlyingToken();
        _loanPositionManager.withdrawToken(position.collateralToken, address(this), swapAmount);
        _burnAllSubstitute(position.collateralToken, address(this));
        if (inToken == address(_weth)) {
            _weth.deposit{value: swapAmount}();
        }
        if (swapAmount > 0 && swapData.length > 0) {
            _swap(inToken, swapAmount, swapData);
        }

        uint256 maxRepayAmount = IERC20(outToken).balanceOf(address(this))
            + Math.min(
                allowedSupplementaryAmount,
                Math.min(IERC20(outToken).balanceOf(payer), IERC20(outToken).allowance(payer, address(this)))
            );

        (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) =
            _loanPositionManager.liquidate(positionId, maxRepayAmount);

        ISubstitute(position.debtToken).ensureBalance(payer, repayAmount);
        IERC20(position.debtToken).approve(address(_loanPositionManager), repayAmount);
        _loanPositionManager.depositToken(position.debtToken, repayAmount);

        uint256 debtAmount = IERC20(outToken).balanceOf(address(this));
        if (debtAmount > 0) {
            IERC20(outToken).safeTransfer(recipient, debtAmount);
        }

        uint256 collateralAmount = liquidationAmount - protocolFeeAmount - swapAmount;

        _loanPositionManager.withdrawToken(position.collateralToken, address(this), collateralAmount);
        _burnAllSubstitute(position.collateralToken, recipient);

        return "";
    }

    function liquidate(
        uint256 positionId,
        uint256 swapAmount,
        bytes calldata swapData,
        uint256 allowedSupplementaryAmount,
        address recipient
    ) external payable {
        if (msg.value > 0) {
            _weth.deposit{value: msg.value}();
        }
        _loanPositionManager.lock(
            abi.encode(msg.sender, positionId, swapAmount, swapData, allowedSupplementaryAmount, recipient)
        );
    }

    function _swap(address inToken, uint256 inAmount, bytes memory swapParams) internal {
        IERC20(inToken).approve(_router, inAmount);
        (bool success, bytes memory result) = _router.call(swapParams);
        if (!success) revert CollateralSwapFailed(string(result));
        IERC20(inToken).approve(_router, 0);
    }

    function _burnAllSubstitute(address substitute, address to) internal {
        uint256 leftAmount = IERC20(substitute).balanceOf(address(this));
        if (leftAmount == 0) return;
        ISubstitute(substitute).burn(leftAmount, to);
    }

    receive() external payable {}
}

