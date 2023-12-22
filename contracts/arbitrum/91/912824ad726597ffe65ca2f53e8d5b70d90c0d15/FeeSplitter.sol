// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Controllable } from "./Controllable.sol";

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

import { Constants } from "./Constants.sol";

// Sends a small portion of vault fees to the team treasury and the reward pool
contract FeeSplitter is Controllable {
    using SafeERC20 for IERC20;

    struct FeeRecipient {
        address recipient;
        uint256 proportion;
    }

    uint256 public numFeeRecipients;
    mapping(uint256 => FeeRecipient) public feeRecipients;

    error lengthMismatch();
    error incorrectProportions(uint256 proportionTotal); // Proportions must sum to 1e20.

    constructor(address _controller) Controllable(_controller) {}

    function distributeFees(address _token) external {
        uint256 feeAmount = IERC20(_token).balanceOf(address(this));
        if (feeAmount == 0) return;

        uint256 _numFeeRecipients = numFeeRecipients;
        for (uint256 i; i < _numFeeRecipients; ++i) {
            FeeRecipient memory feeRecipient = feeRecipients[i];
            IERC20(_token).safeTransfer(
                feeRecipient.recipient,
                (feeAmount * feeRecipient.proportion) / Constants.PERCENT_PRECISION
            );
        }
    }

    /**
     * @dev set new recipients for protocol yield
     * Note that this does not transfer out existing fees, so if the contract contains fees earmarked for existing recipients, this function
     * will retroactively earmark them for the new recipients.
     */
    function setFeeRecipients(FeeRecipient[] calldata _feeRecipients) external onlyMultisig {
        uint256 arrayLength = _feeRecipients.length;

        // Set fee recipients. Also track total fee proportions to ensure they sum to 100%.
        uint256 proportionTotal;
        for (uint256 i; i < arrayLength; ++i) {
            proportionTotal += _feeRecipients[i].proportion;
            feeRecipients[i] = _feeRecipients[i];
        }

        // Check that proportions sum to 100%
        if (proportionTotal != Constants.PERCENT_PRECISION) {
            revert incorrectProportions(proportionTotal);
        }

        // Set new number of fee recipients
        numFeeRecipients = arrayLength;
    }
}

