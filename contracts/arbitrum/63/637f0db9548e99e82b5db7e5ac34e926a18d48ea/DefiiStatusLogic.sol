// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

enum DefiiStatus {
    NOT_ENTERED,
    ENTER_STARTED,
    ENTERED,
    EXIT_STARTED
}

uint256 constant MASK_SIZE = 2;
uint256 constant ONES_MASK = (1 << MASK_SIZE) - 1;

library DefiiStatusLogic {
    /*
    Library for gas efficient status updates.

    We have more than 2 statuses, so, we can't use simple bitmask. To solve
    this problem, we use MASK_SIZE bits for every status.

    For example:
        We have 4 statuses, so, we can use 2 bits for it
        positionStatus - big binary number, each 2 bits represents defii status
        0b10110100 -> 10, 11, 01, 00 -> 2, 3, 1, 0
        0. ENTERED
        1. EXIT_STARTED
        2. ENTER_STARTED
        3. NOT_ENTERED

    Some functions needs allDefiisEnteredMask parameter. You can get it once from
    calculateAllDefiisEnteredMask function and cache.
    */

    using DefiiStatusLogic for uint256;

    function validateNewStatus(
        DefiiStatus currentStatus,
        DefiiStatus newStatus
    ) internal pure returns (bool) {
        // Valid cases
        // Enter: NOT_ENTERED -> ENTER_STARTED -> ENTERED
        // Exit: ENTERED -> EXIT_STARTED -> NOT_ENTERED

        // So
        return
            // NOT_ENTERED -> ENTER_STARTED
            (currentStatus == DefiiStatus.NOT_ENTERED &&
                newStatus == DefiiStatus.ENTER_STARTED) ||
            // ENTER_STARTED -> ENTERED
            (currentStatus == DefiiStatus.ENTER_STARTED &&
                newStatus == DefiiStatus.ENTERED) ||
            // ENTERED -> ENTER_STARTED / EXIT_STARTED
            (currentStatus == DefiiStatus.ENTERED &&
                (newStatus == DefiiStatus.EXIT_STARTED)) ||
            // EXIT_STARTED -> NOT_ENTERED
            (currentStatus == DefiiStatus.EXIT_STARTED &&
                (newStatus == DefiiStatus.NOT_ENTERED));
    }

    function setStatus(
        uint256 statusMask,
        uint256 defiiIndex,
        DefiiStatus newStatus
    ) internal pure returns (uint256) {
        uint256 offset = MASK_SIZE * defiiIndex;
        uint256 cleanupMask = ~(ONES_MASK << offset);
        uint256 newStatusMask = uint256(newStatus) << offset;

        return (statusMask & cleanupMask) | newStatusMask;
    }

    function isPositionProcessing(
        uint256 statusMask,
        uint256 allDefiisEnteredMask
    ) internal pure returns (bool) {
        return statusMask != 0 && statusMask != allDefiisEnteredMask;
    }

    function calculateAllDefiisEnteredMask(
        uint256 numDefiis
    ) internal pure returns (uint256 mask) {
        for (uint256 i = 0; i < numDefiis; i++) {
            mask |= uint256(DefiiStatus.ENTERED) << (MASK_SIZE * i);
        }
    }

    function defiiStatus(
        uint256 statusMask,
        uint256 defiiIndex
    ) internal pure returns (DefiiStatus) {
        return
            DefiiStatus((statusMask >> (MASK_SIZE * defiiIndex)) & ONES_MASK);
    }
}

