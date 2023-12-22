// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {Vesting, CompletionSchedule, IAgreementManager} from "./Vesting.sol";

/// @notice Agreement Term extends vesting allowing issuer to improve vesting terms.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/terms/VestingWithAcceleration.sol)
contract VestingWithAcceleration is Vesting {
    using CompletionSchedule for CompletionSchedule.Schedule;

    error VestingWithAcceleration__UnfavorableChange();

    event VestingAccelerated(
        IAgreementManager indexed manager,
        uint256 indexed tokenId,
        CompletionSchedule.Schedule schedule
    );

    function accelerateVesting(
        IAgreementManager manager,
        uint256 tokenId,
        CompletionSchedule.Schedule calldata schedule
    ) public virtual {
        if (msg.sender != manager.issuer(tokenId)) revert Term__NotIssuer(msg.sender);
        CompletionSchedule.verifySchedule(schedule);
        CompletionSchedule.Schedule memory existingSchedule = vestingData[manager][tokenId];
        for (uint i = 0; i < schedule.times.length; i++) {
            if (schedule.percentages[i] < existingSchedule.percentageAt(schedule.times[i]))
                revert VestingWithAcceleration__UnfavorableChange();
        }
        for (uint i = 0; i < existingSchedule.times.length; i++) {
            if (existingSchedule.percentages[i] > schedule.percentageAt(existingSchedule.times[i]))
                revert VestingWithAcceleration__UnfavorableChange();
        }

        vestingData[manager][tokenId] = schedule;

        emit VestingAccelerated(manager, tokenId, schedule);
    }
}

