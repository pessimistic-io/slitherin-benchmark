// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// ==============================================================
//  _____                 _      _____ _                        |
// |  _  |_ _ ___ ___ ___| |_   |   __|_|___ ___ ___ ___ ___    |
// |   __| | | . | . | -_|  _|  |   __| |   | .'|   |  _| -_|   |
// |__|  |___|  _|  _|___|_|    |__|  |_|_|_|__,|_|_|___|___|   |
//           |_| |_|                                            |
// ==============================================================
// ======================== IRouteFactory =======================
// ==============================================================
// Puppet Finance: https://github.com/GMX-Blueberry-Club/puppet-contracts

// Primary Author
// johnnyonline: https://github.com/johnnyonline

// Reviewers
// itburnz: https://github.com/nissoh

// ==============================================================

interface IBaseRouteFactory {

    // ============================================================================================
    // External Functions
    // ============================================================================================

    /// @notice The ```registerRouteAccount``` is called on Orchestrator.registerRouteAccount
    /// @param _reader The address of the Reader
    /// @param _setter The Setter contract address
    /// @param _data The data to be passed to the Route
    /// @return _route The address of the new Route
    function registerRouteAccount(address _reader, address _setter, bytes memory _data) external returns (address _route);

    // ============================================================================================
    // Events
    // ============================================================================================

    event RegisterRouteAccount(address indexed caller, address route, address reader, address setter, bytes data);
}
