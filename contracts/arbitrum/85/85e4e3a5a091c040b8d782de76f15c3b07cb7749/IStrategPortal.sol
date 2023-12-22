// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IStrategPortal {

    enum SwapIntegration {
        LIFI
    }

    error NotWhitelistedAddress();

    event LiFiExecutionResult(bool success, bytes returnData);
    event LiFiSetDiamond(bool whitelisted, address addr);
    event ParaswapSetAugustus(address augustus);
    event ParaswapExecutionResult(bool success, bytes returnData);
    event OneInchSetAugustus(address router);
    event OneInchExecutionResult(bool success, bytes returnData);
    
    event OracleWhitelistChanged(bool whitelisted, address addr);
    event OracleRateChanged(address from, address to, uint256 rate);

    function SOPT() external view returns (address);
    function setSOPT(address _SOPT) external view;

    function whitelistOracle(bool _enable, address _addr) external;

    function getOracleRates(
        address[] memory _froms, 
        address[] memory _to,
        uint256[] memory _amount
    ) external view returns (uint256[] memory);

    function getOraclePrices(
        address[] memory _assets
    ) external view returns (uint256[] memory);

    function updateOraclePrice(
        address[] memory _addresses, 
        uint256[] memory _prices
    ) external;

    function enableOraclePrice(
        address _asset, 
        uint8 _assetDecimals
    ) external;
    
    function disableOraclePrice(
        address _asset
    ) external;


    function swap(
        bool sourceIsVault,
        bool targetIsVault,
        SwapIntegration _route,
        address _sourceAsset,
        address _approvalAddress,
        address _targetAsset,
        uint256 _amount,
        bytes memory _permitParams, 
        bytes calldata _data
    ) external payable;

    function swapAndBridge(
        bool sourceIsVault,
        bool targetIsVault,
        SwapIntegration _route,
        address _approvalAddress,
        address _sourceAsset,
        address _targetAsset,
        uint256 _amount,
        uint256 _targetChain,
        bytes memory _permitParams, 
        bytes calldata _data
    ) external payable;

    function swapForSOPT(
        bool sourceIsVault,
        bool _nativeDeposit,
        SwapIntegration _route,
        address _receiver,
        address _approvalAddress,
        address _sourceAsset,
        uint256 _amount,
        bytes memory _permitParams,
        bytes calldata _data
    ) external payable;

    function lifiDiamond() external view returns (address);
    function setLiFiDiamond(address _diamond) external;
    function paraswapAugustus() external view returns (address);
    function setParaswapAugustus(address _augustus) external;
    function oneInchRouter() external view returns (address);
    function setOneInchRouter(address _router) external ;

    function lifiBridgeReceiver(
        address _tokenReceived,
        address _sender,
        address _toVault
    ) external;

    function lifiBridgeReceiverForSOPT(
        address _tokenReceived,
        address _sender
    ) external payable;
}
