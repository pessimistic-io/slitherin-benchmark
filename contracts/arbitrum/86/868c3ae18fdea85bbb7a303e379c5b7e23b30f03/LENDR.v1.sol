// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "./Kernel.sol";

/// @title Olympus Lender
/// @notice Olympus Lender (Module) Contract
/// @dev    The Olympus Lender Module tracks the lending AMOs
///         that are approved to be used by the Olympus protocol. This allows for a single-soure
///         of truth for reporting purposes.
abstract contract LENDRv1 is Module {
    // ========= ERRORS ========= //

    error LENDR_AMOAlreadyInstalled(address amo);
    error LENDR_InvalidInterface(address amo);

    // ========= EVENTS ========= //

    event AMOAdded(address indexed amo);
    event AMORemoved(address indexed amo);

    // ========= STATE ========= //

    /// @notice Count of active AMOs
    /// @dev    This is a useless variable in contracts but useful for any frontends or
    ///         off-chain requests where the array is not easily accessible.
    uint256 public activeAMOCount;

    /// @notice Tracks all active AMOs
    address[] public activeAMOs;
    mapping(address => bool) public isAMOInstalled;

    // ========= CORE FUNCTIONS ========= //

    /// @notice         Adds an AMO to the registry
    /// @param amo_     The address of the AMO to add
    function addAMO(address amo_) external virtual;

    /// @notice         Removes an AMO from the registry
    /// @param amo_     The address of the AMO to remove
    function removeAMO(address amo_) external virtual;

    // ========= VIEW FUNCTIONS ========= //

    /// @notice         Gets amount of OHM deployed by an AMO
    /// @param amo_     The address of the AMO to get the deployed OHM for
    function getDeployedOhm(address amo_) external view virtual returns (uint256);

    /// @notice         Gets total amount of OHM deployed by all AMOs
    function getTotalDeployedOhm() external view virtual returns (uint256);

    /// @notice         Gets amount of OHM that has been borrowed from the amo_'s deployment into a lending market
    /// @param amo_     The address of the AMO to get the borrowed OHM for
    function getBorrowedOhm(address amo_) external view virtual returns (uint256);

    /// @notice         Gets total amount of OHM that has been borrowed from all AMOs
    function getTotalBorrowedOhm() external view virtual returns (uint256);

    // ========= INTERNAL FUNCTIONS ========= //

    /// @notice         Checks if an address complies with the AMO interface (to the extent the LENDR module relies on it)
    /// @param amo_     The address of the AMO to check
    function _isAMO(address amo_) internal view virtual returns (bool);
}

