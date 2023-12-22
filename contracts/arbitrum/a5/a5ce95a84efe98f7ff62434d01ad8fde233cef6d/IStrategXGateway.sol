// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStrategXGateway {
    
    function migrateToXChainVault(
        address _fromAsset,
        uint256 _fromAmount,
        address _vaultTargeted,
        address _gatewayTargeted,
        bytes calldata _xGatewayParams
    ) external payable;

}

