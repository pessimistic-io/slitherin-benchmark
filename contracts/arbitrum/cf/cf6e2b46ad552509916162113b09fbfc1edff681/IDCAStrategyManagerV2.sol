// SPDX-License-Identifier: UNLICENSED
// © Copyright AutoDCA. All Rights Reserved

pragma solidity 0.8.9;

import "./DCATypes.sol";

interface IDCAStrategyManagerV2 {
    function getStrategy(
        uint256 strategyId
    ) external view returns (DCATypes.StrategyDataV2 memory);

    function getUserStrategy(
        address user,
        uint256 strategyId
    ) external view returns (DCATypes.UserStrategyData memory);

    function getStrategyParticipantsLength(
        uint256 strategyId
    ) external view returns (uint256);
}

