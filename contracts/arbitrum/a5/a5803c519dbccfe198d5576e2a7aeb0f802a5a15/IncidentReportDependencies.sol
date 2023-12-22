// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import "./IPriorityPoolFactory.sol";

interface ISimplePriorityPool {
    function activeCovered() external view returns (uint256);
}

abstract contract IncidentReportDependencies {
    IPriorityPoolFactory public priorityPoolFactory;

    address public executor;
}

