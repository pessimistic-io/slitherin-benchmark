// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity 0.8.13;

interface IAavePoolV3{
    function supply(address asset,uint256 amount,address onBehalfOf,uint16 referralCode)external;
    function withdraw(bytes32 args)external;
    function borrow(address asset,uint256 amount,uint256 interestRateMode,uint16 referralCode,address onBehalfOf)external;
    function repay(bytes32 args)external;
    function setUserEMode(uint8 categoryId) external;
    function setUserUseReserveAsCollateral(address asset,bool useAsCollateral) external;

    function getUserEMode(address user) external view returns (uint256);
    function getUserAccountData(address account) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
    function getReservesList() external view returns (address[] memory);
}
