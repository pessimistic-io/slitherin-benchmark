/**
 * Types for the Automation facet
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

struct ScheduledAutomation {
    uint256 interval;
    uint256 lastExecutedTimestamp;
}

