// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

abstract contract VaultFeeHandler {
    uint256 public constant TOTAL_BASIS_POINT = 1000000;

    /**
     * Calculates and returns fee according to the given fee basis point
     * @param _txnAmount total amount of the transaction
     * @param _fee percentage of fee in basis points
     */
    function _calculateTotalFee(
        uint256 _txnAmount,
        uint256 _fee
    ) internal pure returns (uint256 fee) {
        fee = (_txnAmount * _fee) / TOTAL_BASIS_POINT;
    }

    /**
     * Calculates fee share
     * @param _txnFeeAmount transaction fee amount
     * @param _vaultCreatorFee fee share in basis point for vault creator
     */
    function _calculateFeeDistribution(
        uint256 _txnFeeAmount,
        uint256 _vaultCreatorFee
    ) internal pure returns (uint256 feeToTreasury, uint256 feeToVaultCreator) {
        feeToTreasury = _txnFeeAmount;
        if (_vaultCreatorFee > 0) {
            feeToVaultCreator =
                (_txnFeeAmount * _vaultCreatorFee) /
                TOTAL_BASIS_POINT;
            feeToTreasury = _txnFeeAmount - feeToVaultCreator;
        }
    }
}

