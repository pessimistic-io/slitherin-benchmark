// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IPool.sol";

interface IActivePool is IPool {
    // --- Events ---

    event ActivePoolDebtUpdated(address _asset, uint256 _debtTokenAmount);
    event ActivePoolAssetBalanceUpdated(address _asset, uint256 _balance);
    event AssetVaultUpdated(address _asset, address _vault);
    event CollateralDepositedIntoSmartVault(
        address _asset,
        uint256 _balance,
        address _assetVault
    );

    // --- Functions ---

    function sendAsset(
        address _asset,
        address _account,
        uint256 _amount
    ) external;
}

