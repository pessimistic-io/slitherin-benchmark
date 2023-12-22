// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {CompletionSchedule} from "./CompletionSchedule.sol";
import {ITerm, IAgreementManager} from "./ITerm.sol";

/// @notice Agreement Term applying constraints according to a fixed schedule.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/IVesting.sol)
interface IVesting is ITerm {
    error Vesting__TimeOutOfBounds();

    function getSchedule(IAgreementManager manager, uint256 tokenId)
        external
        view
        returns (CompletionSchedule.Schedule memory);
}

