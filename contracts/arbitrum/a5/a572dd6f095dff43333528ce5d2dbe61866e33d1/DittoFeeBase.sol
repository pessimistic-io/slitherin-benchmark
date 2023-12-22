// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IProtocolFees} from "./IProtocolFees.sol";
import {TransferHelper} from "./TransferHelper.sol";

/// @title DittoFeeBase
contract DittoFeeBase {
    // =========================
    // Constructor
    // =========================

    IProtocolFees internal immutable _protocolFees;

    uint256 internal constant E18 = 1e18;

    /// @notice Sets the addresses of the `automate` and `gelato` upon deployment.
    /// @param protocolFees:
    constructor(IProtocolFees protocolFees) {
        _protocolFees = protocolFees;
    }

    // =========================
    // Events
    // =========================

    /// @notice Emits when ditto fee is transferred.
    /// @param dittoFee The amount of Ditto fee transferred.
    event DittoFeeTransfer(uint256 dittoFee);

    // =========================
    // Helpers
    // =========================

    /// @dev Transfers the specified `dittoFee` amount to the `treasury`.
    /// @param dittoFee Amount of value to transfer.
    /// @param rollupFee Amount of roll up fee.
    /// @param isInstant Bool to indicate if the fee to be paid for instant action:
    function _transferDittoFee(
        uint256 dittoFee,
        uint256 rollupFee,
        bool isInstant
    ) internal {
        address treasury;
        uint256 feeGasBps;
        uint256 feeFix;

        if (isInstant) {
            (treasury, feeGasBps, feeFix) = _protocolFees
                .getInstantFeesAndTreasury();
        } else {
            (treasury, feeGasBps, feeFix) = _protocolFees
                .getAutomationFeesAndTreasury();
        }

        // if treasury is setted
        if (treasury != address(0)) {
            unchecked {
                // take percent of gasUsed + fixed fee
                dittoFee =
                    (((dittoFee + rollupFee) * feeGasBps) / E18) +
                    feeFix;
            }

            if (dittoFee > 0) {
                TransferHelper.safeTransferNative(treasury, dittoFee);

                emit DittoFeeTransfer(dittoFee);
            }
        }
    }
}

