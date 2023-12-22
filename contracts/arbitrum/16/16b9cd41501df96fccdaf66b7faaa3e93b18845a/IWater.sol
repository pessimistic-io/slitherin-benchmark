// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWater {
    function lend(uint256 _amount, address _receiver) external returns (bool);

    function repayDebt(uint256 leverage, uint256 debtValue) external returns (bool);

    function getTotalDebt() external view returns (uint256);

    function updateTotalDebt(uint256 profit) external returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function balanceOfAsset() external view returns (uint256);
    function getUtilizationRate() external view returns (uint256);

    function asset() external view returns (address);
    function increaseTotalUSDC(uint256 amount) external;
}

