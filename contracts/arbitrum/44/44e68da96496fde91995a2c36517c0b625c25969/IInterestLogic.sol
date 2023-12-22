// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0 <0.8.0;
pragma abicoder v2;


interface IInterestLogic {
    function getMarketBorrowIG(address _pool, uint256 usedAmount, uint256 totalAmount, uint256 reserveRate, uint256 lastUpdateTime, uint256 borrowInterestGrowthGlobal) external view returns (uint256 borrowRate, uint256 borrowIg);

    function getBorrowAmount(uint256 borrowShare, uint256 borrowIg) external view returns (uint256);

    function getBorrowShare(uint256 amount, uint256 borrowIg) external view returns (uint256);
}

