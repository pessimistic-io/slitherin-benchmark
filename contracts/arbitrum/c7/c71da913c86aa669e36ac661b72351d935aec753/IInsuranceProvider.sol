//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IInsuranceProvider {
    function getVaults(uint256) external view returns (address[2] memory);

    function purchaseForNextEpoch(uint256, uint256, uint256) external;

    function isNextEpochPurchasable(uint256) external view returns (bool);

    function pendingPayouts(uint256) external view returns (uint256);

    function pendingEmissions(uint256) external view returns (uint256);

    function claimPayouts(uint256) external returns (uint256);

    function emissionsToken() external view returns (address);
}

