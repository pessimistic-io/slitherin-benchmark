//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IInsuredLongsUtils {
    function getLiquidationPrice(
        address _positionManager,
        address _indexToken
    ) external view returns (uint256 liquidationPrice);

    function getLiquidationPrice(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta
    ) external view returns (uint256);

    function getRequiredAmountOfOptionsForInsurance(
        address _atlanticPool,
        address _collateralToken,
        address _indexToken,
        uint256 _size,
        uint256 _collateral,
        uint256 _putStrike
    ) external view returns (uint256 optionsAmount);

    function getRequiredAmountOfOptionsForInsurance(
        uint256 _putStrike,
        address _positionManager,
        address _indexToken,
        address _quoteToken
    ) external view returns (uint256 optionsAmount);

    function getEligiblePutStrike(
        address _atlanticPool,
        uint256 _offset,
        uint256 _liquidationPrice
    ) external view returns (uint256 eligiblePutStrike);

    function getPositionKey(
        address _positionManager,
        bool isIncrease
    ) external view returns (bytes32 key);

    function getPositionLeverage(
        address _positionManager,
        address _indexToken
    ) external view returns (uint256);

    function getLiquidatablestate(
        address _positionManager,
        address _indexToken,
        address _collateralToken,
        address _atlanticPool,
        uint256 _purchaseId,
        bool _isIncreased
    ) external view returns (uint256 _usdOut, address _outToken);

    function getAtlanticUnwindCosts(
        address _atlanticPool,
        uint256 _purchaseId,
        bool
    ) external view returns (uint256);

    function get1TokenSwapPath(
        address _token
    ) external pure returns (address[] memory path);

    function get2TokenSwapPath(
        address _token1,
        address _token2
    ) external pure returns (address[] memory path);

    function getOptionsPurchase(
        address _atlanticPool,
        uint256 purchaseId
    ) external view returns (uint256, uint256);

    function getPrice(address _token) external view returns (uint256 _price);

    function getCollateralAccess(
        address atlanticPool,
        uint256 _purchaseId
    ) external view returns (uint256 _collateralAccess);

    function getFundingFee(
        address _indexToken,
        address _positionManager,
        address _convertTo
    ) external view returns (uint256 fundingFee);

    function getAmountIn(
        uint256 _amountOut,
        uint256 _slippage,
        address _tokenOut,
        address _tokenIn
    ) external view returns (uint256 _amountIn);

    function getPositionSize(
        address _positionManager,
        address _indexToken
    ) external view returns (uint256 size);

    function getPositionFee(
        uint256 _size
    ) external view returns (uint256 feeUsd);

    function getAmountReceivedOnExitPosition(
        address _positionManager,
        address _indexToken,
        address _outToken
    ) external view returns (uint256 amountOut);

    function getStrategyExitSwapPath(
        address _atlanticPool,
        uint256 _purchaseId
    ) external view returns (address[] memory path);

    function validateIncreaseExecution(
        uint256 _collateralSize,
        uint256 _size,
        address _collateralToken,
        address _indexToken
    ) external view returns (bool);

    function validateUnwind(
        address _positionManager,
        address _indexToken,
        address _atlanticPool,
        uint256 _purchaseId
    ) external view returns (bool);

    function getUsdOutForUnwindWithFee(
        address _positionManager,
        address _indexToken,
        address _atlanticPool,
        uint256 _purchaseId
    ) external view returns (uint256 _usdOut);

    function calculateCollateral(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralAmount,
        uint256 _size
    ) external view returns (uint256 collateral);

    function calculateLeverage(
        uint256 _size,
        uint256 _collateral,
        address _collateralToken
    ) external view returns (uint256 _leverage);

    function getMinUnwindablePrice(
        address _positionManager,
        address _atlanticPool,
        address _indexToken,
        uint256 _purchaseId,
        uint256 _offset
    ) external view returns (bool isLiquidatable);


   function validateDecreaseCollateralDelta(
        address _positionManager,
        address _indexToken,
        uint256 _collateralDelta
    ) external view returns (bool valid);

       function getMarginFees(
        address _positionManager,
        address _indexToken,
        address _convertTo
    ) external view returns (uint256 fees);
}

