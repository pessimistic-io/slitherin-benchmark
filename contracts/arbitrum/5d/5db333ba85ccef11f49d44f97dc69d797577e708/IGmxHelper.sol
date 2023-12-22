// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IGmxVault} from "./IGmxVault.sol";

interface IGmxHelper {
    function tokenDecimals(address) external returns (uint256);

    function getPosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool,
            uint256
        );

    function usdToTokenMin(address, uint256) external returns (uint256);

    function getPositionKey(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external returns (bytes32);

    function tokenToUsdMin(address, uint256) external returns (uint256);

    function getMaxPrice(address) external returns (uint256);

    function getMinPrice(address) external returns (uint256);

    function adjustForDecimals(
        uint256 _amount,
        address _tokenDiv,
        address _tokenMul
    ) external view returns (uint256);

    function getWethToken() external view returns (address);

    function getGmxDecimals() external view returns (uint256);

    function calculateCollateralDelta(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta
    ) external returns (uint256 collateral);

    function validateLongIncreaseExecution(
        uint256 collateralSize,
        uint256 positionSize,
        address collateralToken,
        address indexToken
    ) external view returns (bool);

    function validateShortIncreaseExecution(
        uint256 collateralSize,
        uint256 positionSize,
        address indexToken
    ) external view returns (bool);

    function gmxVault() external view returns (IGmxVault);
}

