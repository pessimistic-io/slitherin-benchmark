// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ITerm, IAgreementManager} from "./ITerm.sol";

/// @notice Agreement Term controls cancellation with grace period.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/IDelayedCancellation.sol)
interface IDelayedCancellation is ITerm {
    error DelayedCancellation__CancelNotInitiated();
    error DelayedCancellation__GracePeriodActive();

    event CancelInitiated(IAgreementManager indexed manager, uint256 indexed tokenId);

    /// @dev Data structure for Cancellation term
    struct DelayedCancellationTerm {
        uint256 cancelInitiatedAt;
        uint256 gracePeriod;
    }

    /// @dev initiate agreement cancellation and start grace period
    function initiateCancellation(IAgreementManager manager, uint256 tokenId) external;
}

