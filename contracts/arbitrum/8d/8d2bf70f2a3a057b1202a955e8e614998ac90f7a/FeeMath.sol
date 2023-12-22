// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./ConstantsLib.sol";

library FeeMath {
    /**
     * @notice Calculate the processing fee for the given percentage based on the total amount due.
     *
     * @dev baseFee_ and totalPayable_ need to be denominated in the same token.
     *
     * @param baseFee_ the base or 'fixed' fee, denominated in a ERC-20 token.
     * @param feePercentage_ the percentage fee to take. Must be 6 decimal precision.
     * @param totalPayable_ the amount to calculate the fee on, denominated in a ERC-20 token.
     *
     * @return processingFee - the processing fee amount.
     */
    function calculateProcessingFee(
        uint256 baseFee_,
        uint256 feePercentage_,
        uint256 totalPayable_
    ) internal pure returns (uint256 processingFee) {
        processingFee =
            baseFee_ +
            ((totalPayable_ * feePercentage_) / ConstantsLib.FEE_PRECISION);
    }
}

