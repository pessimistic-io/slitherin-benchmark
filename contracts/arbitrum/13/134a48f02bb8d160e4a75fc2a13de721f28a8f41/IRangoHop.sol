// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./RangoHopModels.sol";

/// @title An interface to RangoHop.sol contract to improve type hinting
/// @author Uchiha Sasuke
interface IRangoHop {
    /// @notice Executes a Hop bridge call
    /// @param _request The request object containing required field by hop bridge
    /// @param _amount The amount to be bridged
    function hopBridge(
        RangoHopModels.HopRequest memory _request,
        address fromToken,
        uint _amount
    ) external payable;
}
