// SPDX-License-Identifier: MIT



pragma solidity >=0.8.0;

interface IGmxVault {
    function whitelistedTokens(address token) external view returns (bool);

    function stableTokens(address token) external view returns (bool);

    function shortableTokens(address token) external view returns (bool);

    function getMaxPrice(address indexToken) external view returns (uint256);

    function getMinPrice(address indexToken) external view returns (uint256);

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

    function getPositionDelta(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (bool, uint256);

    function isLeverageEnabled() external view returns (bool);

    function guaranteedUsd(address _token) external view returns (uint256);

    function globalShortSizes(address _token) external view returns (uint256);
}

