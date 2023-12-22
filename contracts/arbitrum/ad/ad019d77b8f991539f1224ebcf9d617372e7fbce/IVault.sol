// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

interface IVault {
    struct Position {
        uint256 size;
        uint256 collateral;
        uint256 averagePrice;
        uint256 entryFundingRate;
        uint256 reserveAmount;
        int256 realisedPnl;
        uint256 lastIncreasedTime;
    }

    function getFeeBasisPoints(
        address _token,
        uint256 _usdgDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) external view returns (uint256);

    function usdg() external view returns (address);

    function usdgAmounts(address _token) external view returns (uint256);

    function maxUsdgAmounts(address _token) external view returns (uint256);

    function whitelistedTokens(address _token) external view returns (bool);

    function stableTokens(address _token) external view returns (bool);

    function shortableTokens(address _token) external view returns (bool);

    function getMinPrice(address _token) external view returns (uint256);

    function getMaxPrice(address _token) external view returns (uint256);

    function getPositionDelta(address _account, address _collateralToken, address _indexToken, bool _isLong)
        external
        view
        returns (bool, uint256);

    function getPosition(address _account, address _collateralToken, address _indexToken, bool _isLong)
        external
        view
        returns (
            uint256 size,
            uint256 collateral,
            uint256 averagePrice,
            uint256 entryFundingRate,
            uint256 reserveAmount,
            uint256 realisedPnl,
            bool isProfit,
            uint256 lastIncreasedTime
        );

    function poolAmounts(address _token) external view returns (uint256);

    function reservedAmounts(address _token) external view returns (uint256);

    function guaranteedUsd(address _token) external view returns (uint256);

    function globalShortSizes(address _token) external view returns (uint256);

    function positions(bytes32 _key)
        external
        view
        returns (
            uint256 _size,
            uint256 _collateral,
            uint256 _averagePrice,
            uint256 _entryFundingRate,
            uint256 _reserveAmount,
            int256 _realisedPnl,
            uint256 _lastIncreasedTime
        );

    function swap(address _tokenIn, address _tokenOut, address _receiver) external returns (uint256);

    function getPositionFee(uint256 _sizeDelta) external view returns (uint256);

    function getFundingFee(address _token, uint256 _size, uint256 _entryFundinRate) external view returns (uint256);

    function cumulativeFundingRates(address _token) external view returns (uint256);

    function getNextFundingRate(address _token) external view returns (uint256);

    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _lastIncreasedTime
    ) external view returns (bool, uint256);

    function allWhitelistedTokensLength() external view returns (uint256);

    function allWhitelistedTokens(uint256) external view returns (address);

    function tokenDecimals(address) external view returns (uint256);

    function taxBasisPoints() external view returns (uint256);

    function stableTaxBasisPoints() external view returns (uint256);

    function mintBurnFeeBasisPoints() external view returns (uint256);

    function globalShortAveragePrices(address) external view returns (uint256);
}

