// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./IERC4626.sol";

interface ILendingPool is IERC4626 {
    function totalBorrowed() external view returns (uint256);

    function userCollateralAmount(address account) external view returns (uint256);

    function lendingAssetPriceFeed() external view returns (address);

    function lendingAssetRefreshRate() external view returns (uint256);

    function addCollateral(uint256 amount, address receiver) external;

    function removeCollateral(uint256 amount, address receiver) external;

    function borrow(uint256 amount) external;

    function repay(uint256 amount, address borrower) external;

    function repayCost(uint256 amount, address borrower) external;

    function getAccountLiquidity(address account) external returns (uint256 collateralValue, uint256 borrowValue);

    function getAccountLiquiditySimulate(
        address account,
        uint256 moreBorrow,
        uint256 lessBorrow,
        uint256 moreCollateral,
        uint256 lessCollateral
    ) external view returns (uint256 collateralValue, uint256 borrowValue);

    function getAccountBalances(
        address account
    ) external view returns (uint256 collateralTokens, uint256 borrowedTokens);
}

