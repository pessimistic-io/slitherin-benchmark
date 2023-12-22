// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVaultUtils {
    function maxLeverage() external view returns (uint256);
    function maxLeverages(address _token) external view returns (uint256);
    function isTradable(address _token) external view returns (bool);
    function setMaxLeverage(uint256 _maxLeverage) external;
    function setMaxLeverages(address _token, uint256 _maxLeverage) external;
    function setIsTradable(address _token, bool _isTradable) external;
    function isTradableBatch(address[] memory _tokens) external view returns (bool[] memory);
    function validateTradablePair(address _token1, address _token2) external view;
    function fundingInterval() external view returns (uint256);
    function fundingRateFactor() external view returns (uint256);
    function stableFundingRateFactor() external view returns (uint256);

    function setFundingRate(uint256 _fundingInterval, uint256 _fundingRateFactor, uint256 _stableFundingRateFactor) external;
    function cumulativeFundingRates(address _token) external view returns (uint256);
    function lastFundingTimes(address _token) external view returns (uint256);
    function getNextFundingRate(address _token) external view returns (uint256);
    function updateCumulativeFundingRate(address _collateralToken, address _indexToken) external;
    
    function validateSwap(address _tokenIn, address _tokenOut) external view;
    function validateIncreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) external view;
    function validateDecreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver) external view;
    function validateLiquidation(address _account, address _collateralToken, address _indexToken, bool _isLong, bool _raise) external view returns (uint256, uint256);
    function getEntryFundingRate(address _collateralToken, address _indexToken, bool _isLong) external view returns (uint256);
    function getPositionFee(address _account, address _collateralToken, address _indexToken, bool _isLong, uint256 _sizeDelta) external view returns (uint256);
    function getFundingFee(address _account, address _collateralToken, address _indexToken, bool _isLong, uint256 _size, uint256 _entryFundingRate) external view returns (uint256);
    function getBuyUsdgFeeBasisPoints(address _token, uint256 _usdgAmount) external view returns (uint256);
    function getSellUsdgFeeBasisPoints(address _token, uint256 _usdgAmount) external view returns (uint256);
    function getSwapFeeBasisPoints(address _tokenIn, address _tokenOut, uint256 _usdgAmount) external view returns (uint256);
    function getFeeBasisPoints(address _token, uint256 _usdgDelta, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) external view returns (uint256);

    function getSyntheticGlobalLongSize(address _indexToken) external view returns (uint256);
    function getNextAveragePrice(address _indexToken, uint256 _size, uint256 _averagePrice, bool _isLong, uint256 _nextPrice, uint256 _sizeDelta, uint256 _lastIncreasedTime) external view returns (uint256);
    function getGlobalShortDelta(address _token) external view returns (bool, uint256);
    function getNextGlobalShortAveragePrice(address _indexToken, uint256 _nextPrice, uint256 _sizeDelta) external view returns (uint256);
    function getDeltaV2(address _indexToken, uint256 _size, uint256 _averagePrice, bool _isLong, uint256 _lastIncreasedTime, uint256 price) external view returns (bool, uint256);
    
    function getTargetUsdgAmount(address _token) external view returns (uint256);

    function tokenToUsdMin(address _token, uint256 _tokenAmount) external view returns (uint256);
    function usdToToken(address _token, uint256 _usdAmount, uint256 _price) external view returns (uint256);
    function getRedemptionCollateral(address _token) external view returns (uint256);
    function getRedemptionCollateralUsd(address _token) external view returns (uint256);

    function setErrorController(address _errorController) external;
    function setError(uint256 _errorCode, string calldata _error) external;
    function validateTokens(address _collateralToken, address _indexToken, bool _isLong) external view;
}

