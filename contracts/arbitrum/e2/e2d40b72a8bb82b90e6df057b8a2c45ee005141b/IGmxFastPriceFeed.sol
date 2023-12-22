// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IGmxFastPriceFeed {
    function setLastUpdatedAt(uint256 _lastUpdatedAt) external;

    function gov() external view returns (address);

    function tokens(uint index) external view returns (address);

    function prices(address token) external view returns (uint256);

    function setUpdater(address _account, bool _isActive) external;

    function setPrices(
        address[] memory _tokens,
        uint256[] memory _prices,
        uint256 _timestamp
    ) external;

    function setTokenManager(address _tokenManager) external;

    function tokenManager() external view returns (address);

    function setMaxDeviationBasisPoints(
        uint256 _maxDeviationBasisPoints
    ) external;

    function maxDeviationBasisPoints() external view returns (uint256);

    function getPrice(
        address _token,
        uint256 _refPrice,
        bool _maximise
    ) external view returns (uint256);

    function favorFastPrice(address _token) external view returns (bool);

    function setMaxCumulativeDeltaDiffs(
        address[] memory _tokens,
        uint256[] memory _maxCumulativeDeltaDiffs
    ) external;
}

