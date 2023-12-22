// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IAaveProtocolDataProvider {
	function getReserveConfigurationData(address asset) external view returns (
    uint256 decimals,
    uint256 ltv,
    uint256 liquidationThreshold,
    uint256 liquidationBonus,
    uint256 reserveFactor,
    bool usageAsCollateralEnabled,
    bool borrowingEnabled,
    bool stableBorrowRateEnabled,
    bool isActive,
    bool isFrozen
	);
}


