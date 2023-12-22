// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface IStrategPortal {

    enum SwapIntegration {
        LIFI
    }

    event LiFiExecutionResult(bool success, bytes returnData);

    function swap(
        bool sourceIsVault,
        bool targetIsVault,
        SwapIntegration _route,
        address _sourceAsset,
        address _targetAsset,
        uint256 _amount,
        bytes memory _permitParams, 
        bytes calldata _data
    ) external;

    function swapAndBridge(
        bool sourceIsVault,
        bool targetIsVault,
        SwapIntegration _route,
        address _sourceAsset,
        address _targetAsset,
        uint256 _amount,
        uint256 _targetChain,
        bytes memory _permitParams, 
        bytes calldata _data
    ) external;

    function setLiFiDiamond(address _diamond) external;

    function lifiBridgeReceiver(
        address _tokenReceived,
        address _sender,
        address _toVault
    ) external;
}
