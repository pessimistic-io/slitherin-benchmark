pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT



import "./LayerZeroBridge.sol";

/// @title A lz bridge mock
/// @author zk.link
contract LayerZeroBridgeMock is LayerZeroBridge {

    constructor(IZkLink _zklink, ILayerZeroEndpoint _endpoint) LayerZeroBridge(_zklink, _endpoint) {
    }

    function setEndpoint(ILayerZeroEndpoint newEndpoint) external onlyGovernor {
        endpoint = newEndpoint;
    }
}

