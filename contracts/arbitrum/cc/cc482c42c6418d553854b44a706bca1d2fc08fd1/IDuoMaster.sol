// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IDuoMaster {
    function userShares(
        uint256 pidMonopoly,
        address user
    ) external view returns (uint256);

    function totalShares(uint256 pidMonopoly) external view returns (uint256);

    function actionFeeAddress() external view returns (address);

    function performanceFeeAddress() external view returns (address);

    function owner() external view returns (address);
}

