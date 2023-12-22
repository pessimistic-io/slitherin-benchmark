// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./RangoSynapseModels.sol";


/// @title An interface to RangoSynapse.sol contract to improve type hinting
/// @author Rango DeXter
interface IRangoSynapse {

    /// @notice Executes a Synapse bridge call
    /// @param inputToken The address of bridging token
    /// @param inputAmount The amount of the token to be bridged
    /// @param request required data for bridge
    function synapseBridge(
        address inputToken,
        uint inputAmount,
        RangoSynapseModels.SynapseBridgeRequest memory request
    ) external payable;

}
