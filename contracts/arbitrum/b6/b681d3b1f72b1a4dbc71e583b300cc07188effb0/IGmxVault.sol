// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

struct Position {
    uint256 size;
    uint256 collateral;
    uint256 averagePrice;
    uint256 entryFundingRate;
    uint256 reserveAmount;
    int256 realisedPnl;
    uint256 lastIncreasedTime;
}

interface IGmxVault {

    function getPositionLeverage(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (uint256);

    function getPosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (
        uint256 size,
        uint256 collateral,
        uint256 averagePrice,
        uint256 entryFundingRate,
        uint256 reserveAmount,
        uint256 realisedPnl,
        bool realisedPnlOverZero,
        uint256 lastIncreaseTime
    );

    function globalShortSizes(address _token) external view returns (uint256);

    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _lastIncreasedTime
    ) external view returns (bool hasProfit, uint256 delta);

    function getPositionKey(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (bytes32);

    function getPositionFee(uint256 _size) external view returns (uint256);

    function getFundingFee(
        address _token,
        uint256 _size,
        uint256 _entryFundingRate
    ) external view returns (uint256);

    function positions(bytes32 key) external view returns (Position memory position);

    function reservedAmounts(address token) external view returns (uint256);

    function poolAmounts(address token) external view returns (uint256);

    function usdToTokenMax(address _token, uint256 _amount) external view returns (uint256);

    function usdToTokenMin(address _token, uint256 _amount) external view returns (uint256);

    function tokenToUsdMin(address _token, uint256 _amount) external view returns (uint256);

    function getMaxPrice(address _token) external view returns (uint256);

    function getMinPrice(address _token) external view returns (uint256);
}
