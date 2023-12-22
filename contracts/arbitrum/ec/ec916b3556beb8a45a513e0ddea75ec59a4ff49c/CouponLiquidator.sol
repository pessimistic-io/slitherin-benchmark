// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {LoanPosition} from "./LoanPosition.sol";
import {IWETH9} from "./IWETH9.sol";
import {ISubstitute} from "./ISubstitute.sol";
import {ILoanPositionManager} from "./ILoanPositionManager.sol";
import {IPositionLocker} from "./IPositionLocker.sol";
import {ICouponLiquidator} from "./ICouponLiquidator.sol";

contract CouponLiquidator is ICouponLiquidator, IPositionLocker {
    using SafeERC20 for IERC20;

    ILoanPositionManager private immutable _loanPositionManager;
    address private immutable _router;
    IWETH9 internal immutable _weth;

    constructor(address loanPositionManager, address router, address weth) {
        _loanPositionManager = ILoanPositionManager(loanPositionManager);
        _router = router;
        _weth = IWETH9(weth);
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory) {
        (uint256 positionId, uint256 swapAmount, bytes memory swapData) = abi.decode(data, (uint256, uint256, bytes));

        LoanPosition memory position = _loanPositionManager.getPosition(positionId);
        address inToken = ISubstitute(position.collateralToken).underlyingToken();
        address outToken = ISubstitute(position.debtToken).underlyingToken();
        _loanPositionManager.withdrawToken(position.collateralToken, address(this), swapAmount);
        _burnAllSubstitute(position.collateralToken, address(this));
        if (inToken == address(_weth)) {
            _weth.deposit{value: swapAmount}();
        }
        _swap(inToken, swapAmount, swapData);

        (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) =
            _loanPositionManager.liquidate(positionId, IERC20(outToken).balanceOf(address(this)));

        uint256 collateralAmount = liquidationAmount - protocolFeeAmount - swapAmount;

        if (collateralAmount > 0) {
            _loanPositionManager.withdrawToken(position.collateralToken, address(this), collateralAmount);
            _burnAllSubstitute(position.collateralToken, address(this));
            if (inToken == address(_weth)) {
                _weth.deposit{value: collateralAmount}();
            }
        }

        IERC20(outToken).approve(position.debtToken, repayAmount);
        ISubstitute(position.debtToken).mint(repayAmount, address(this));
        IERC20(position.debtToken).approve(address(_loanPositionManager), repayAmount);
        _loanPositionManager.depositToken(position.debtToken, repayAmount);

        return abi.encode(inToken, outToken);
    }

    function liquidate(uint256 positionId, uint256 swapAmount, bytes memory swapData, address feeRecipient) external {
        bytes memory lockData = abi.encode(positionId, swapAmount, swapData);
        (address collateralToken, address debtToken) =
            abi.decode(_loanPositionManager.lock(lockData), (address, address));

        uint256 collateralAmount = IERC20(collateralToken).balanceOf(address(this));
        if (collateralAmount > 0) {
            IERC20(collateralToken).safeTransfer(feeRecipient, collateralAmount);
        }

        uint256 debtAmount = IERC20(debtToken).balanceOf(address(this));
        if (debtAmount > 0) {
            IERC20(debtToken).safeTransfer(feeRecipient, debtAmount);
        }
    }

    function _swap(address inToken, uint256 inAmount, bytes memory swapData) internal {
        IERC20(inToken).approve(_router, inAmount);
        (bool success, bytes memory result) = _router.call(swapData);
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

