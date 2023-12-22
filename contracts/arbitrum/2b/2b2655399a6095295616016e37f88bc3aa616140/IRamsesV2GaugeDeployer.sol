// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title An interface for a contract that is capable of deploying Ramses V2 Gauges
/// @notice A contract that constructs a gauge must implement this to pass arguments to the gauge
/// @dev The store and retrieve method of supplying constructor arguments for CREATE2 isn't needed anymore
/// since we now use a beacon pattern
interface IRamsesV2GaugeDeployer {

}

