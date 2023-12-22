/*
 * SPDX-License-Identifier: Apache-2.0
 */
pragma solidity >=0.8;

import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./ICrossChainVerifier.sol";

abstract contract FeeTracker {
    using SafeMathUpgradeable for uint256;

    enum CollectFeeMethod {
        // Token does not required fee.
        NONE,
        // Token requires fee by default flat amount.
        FLAT,
        // Token requires fee by default percentage.
        PERCENTAGE,
        // Deduct token amount with RFI percentage then collect fee by default flat amount.
        RFI_N_FLAT,
        // Deduct token amount with RFI percentage then collect fee by default percentage.
        RFI_N_PERCENTAGE
    }

    function tokenCollectFeeMethod(
        address _token
    ) public view virtual returns (CollectFeeMethod);

    function feePercentage(
        address _token
    ) public view virtual returns (uint256);

    function flatFeeAmount(
        address _token
    ) public view virtual returns (uint256);

    function maxFeeAmount(address _token) public view virtual returns (uint256);

    function _collectFee(
        address _token,
        uint256 _amount
    ) internal returns (uint256 amountAfterFee, uint256 feeAmount) {
        CollectFeeMethod method = tokenCollectFeeMethod(_token);

        if (
            method == CollectFeeMethod.RFI_N_FLAT ||
            method == CollectFeeMethod.RFI_N_PERCENTAGE
        ) {
            _amount = _amountAfterRFI(_amount);
        }

        if (
            method == CollectFeeMethod.FLAT ||
            method == CollectFeeMethod.RFI_N_FLAT
        ) {
            feeAmount = flatFeeAmount(_token);
        }

        if (
            method == CollectFeeMethod.PERCENTAGE ||
            method == CollectFeeMethod.RFI_N_PERCENTAGE
        ) {
            uint256 percent = feePercentage(_token);
            feeAmount = _amount.mul(percent).div(1000);
        }

        uint256 maxFee = maxFeeAmount(_token);
        if (feeAmount > maxFee) {
            feeAmount = maxFee;
        }

        amountAfterFee = _amount.sub(feeAmount);
        _increaseFeeReserves(_token, feeAmount);

        return (amountAfterFee, feeAmount);
    }

    function _amountAfterRFI(uint256 _amount) private pure returns (uint256) {
        return _amount.mul(99).div(100);
    }

    function _increaseFeeReserves(
        address _token,
        uint256 _amount
    ) internal virtual;
}

