// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

    struct AssetInfo {
    uint8 offset;
    address asset;
    address priceFeed;
    uint64 scale;
    uint64 borrowCollateralFactor;
    uint64 liquidateCollateralFactor;
    uint64 liquidationFactor;
    uint128 supplyCap;
}
interface IComet {

function balanceOf(address account) external view returns (uint256);
function supply(address asset, uint amount) external;
function withdraw(address asset, uint amount) external;
function getAssetInfo(uint8 i) external view returns (AssetInfo memory);
function getAssetInfoByAddress(address asset) external view returns (AssetInfo memory);
function getPrice(address priceFeed) external view returns (uint256) ;
function allow(address manager, bool isAllowed_) external ;
function getBorrowRate(uint utilization) external view returns (uint64);
function getUtilization() external view returns (uint);
}
