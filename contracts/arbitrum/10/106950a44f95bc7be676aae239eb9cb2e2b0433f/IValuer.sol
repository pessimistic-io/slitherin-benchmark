// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IValuer {
    function getVaultValue(
        address vault,
        address asset,
        int256 unitPrice
    ) external view returns (uint256 minValue, uint256 maxValue);

    function getAssetValue(
        uint amount,
        address asset,
        int256 unitPrice
    ) external view returns (uint256 minValue, uint256 maxValue);
}

