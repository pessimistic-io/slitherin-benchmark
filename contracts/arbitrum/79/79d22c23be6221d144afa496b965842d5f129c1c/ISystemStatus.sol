// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

interface ISystemStatus {
    function requireFuturesMarketActive(bytes32 marketKey) external view;
}

