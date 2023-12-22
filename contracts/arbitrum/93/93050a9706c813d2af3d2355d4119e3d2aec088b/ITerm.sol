// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.18;

interface ITerm {
    function createTerm(
        uint totalParticipants,
        uint registrationPeriod,
        uint cycleTime,
        uint contributionAmount,
        uint contributionPeriod,
        address stableTokenAddress
    ) external returns (uint);

    function joinTerm(uint termId, bool optYield) external payable;

    function startTerm(uint termId) external;

    function expireTerm(uint termId) external;
}

