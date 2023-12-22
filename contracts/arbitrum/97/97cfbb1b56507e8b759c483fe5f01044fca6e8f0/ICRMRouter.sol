// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface ICRMRouter {
    function getRiskPremium(
        address loanAsset,
        uint256 loanAssetChainId
    ) external view returns (uint256, uint256);

    function getLoanMarketPremium(
        address loanAsset,
        uint256 loanAssetChainId,
        address loanMarketUnderlying,
        uint256 loanMarketUnderlyingChainId
    ) external view returns (uint256 ratio, uint8 decimals);

    function getMaintenanceCollateralFactor(
        uint256 chainId,
        address asset
    ) external view returns (uint256 ratio, uint8 decimals);

    function getCollateralFactor(
        uint256 chainId,
        address asset
    ) external view returns (uint256 ratio, uint8 decimals);
}
