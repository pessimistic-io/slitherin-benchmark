// SPDX-License-Identifier: Unlicense
pragma solidity ^0.7.3;

interface IComptroller {
    function addMarket(address _market) external;

    function setLiquidityPool(address _liquidityPool) external;

    function borrowingCapacity(address _borrower) external view returns (uint256 capacity);

    function addBorrowerMarket(address _borrower, address _market) external;

    function removeBorrowerMarket(address _borrower, address _market) external;

    function getHealthRatio(address _borrower) external view returns (uint256);

    function sendCollateralToLiquidator(
        address _liquidator,
        address _borrower,
        uint256 _amount
    ) external;

    function sendCollateralToLiquidatorWithPreference(
        address _liquidator,
        address _borrower,
        uint256 _amount,
        address[] memory _markets
    ) external;
}

