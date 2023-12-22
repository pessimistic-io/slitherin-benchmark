// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

abstract contract VaultFeeHandler {
    uint256 public constant TOTAL_BASIS_POINT = 1000000;

    /**
     * @dev Function to calculate fee according to the given fee basis point.
     * @param _txnAmount total amount of the transaction.
     * @param _fee percentage of fee in basis points.
     * @return fee amount to be transferred.
     */
    function _calculateTotalFee(
        uint256 _txnAmount,
        uint256 _fee
    ) internal pure returns (uint256 fee) {
        fee = (_txnAmount * _fee) / TOTAL_BASIS_POINT;
    }

    /**
     * @dev Function to calculates fee share.
     * @param _txnFeeAmount transaction fee amount.
     * @param _vaultCreatorReward fee share in basis point for vault creator.
     */
    function _calculateFeeDistribution(
        uint256 _txnFeeAmount,
        uint256 _vaultCreatorReward
    )
        internal
        pure
        returns (uint256 feeToTreasury, uint256 rewardToVaultCreator)
    {
        feeToTreasury = _txnFeeAmount;
        if (_vaultCreatorReward > 0) {
            rewardToVaultCreator =
                (_txnFeeAmount * _vaultCreatorReward) /
                TOTAL_BASIS_POINT;
            feeToTreasury = _txnFeeAmount - rewardToVaultCreator;
        }
    }
}

