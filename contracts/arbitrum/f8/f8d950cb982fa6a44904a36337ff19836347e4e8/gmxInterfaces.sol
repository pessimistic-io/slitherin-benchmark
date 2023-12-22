// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

interface ICopyTraderIndex {
    function MIN_COLLATERAL_USD() external view returns (uint256);

    function COPY_TRADER_FEE() external view returns (uint256);

    function CT_EXECUTE_FEE() external view returns (uint256);

    function TREASURY() external view returns (address);

    function BACKEND() external view returns (address);
}

interface IVault {
    function getMaxPrice(address _token) external view returns (uint256);

    function getMinPrice(address _token) external view returns (uint256);

    function getPosition(address _account, address _collateralToken, address _indexToken, bool _isLong) external view returns (uint256, uint256, uint256, uint256, uint256, uint256, bool, uint256);
}

interface IRouter {
    function approvePlugin(address) external;
}

interface IPositionRouter {
    function minExecutionFee() external view returns (uint256);

    function createIncreasePositionETH(address[] memory _path, address _indexToken, uint256 _minOut, uint256 _sizeDelta, bool _isLong, uint256 _acceptablePrice, uint256 _executionFee, bytes32 _referralCode, address _callbackTarget) external payable returns (bytes32);

    function createDecreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH,
        address _callbackTarget
    ) external payable returns (bytes32);
}

interface ICopyTraderAccount {
    function createIncreasePositionETH(address indexToken, uint256 amountInEth, uint256 sizeDeltaUsd, bool isLong) external returns (bytes32);

    function createDecreasePosition(address indexToken, uint256 collateralDeltaUsd, uint256 sizeDeltaUsd, bool isLong, bool _isClose) external returns (bytes32);
}

