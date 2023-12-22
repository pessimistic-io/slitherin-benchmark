// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Enums} from "./Enums.sol";
import {ConfigTypes} from "./ConfigTypes.sol";

interface IAutomatedVaultsFactory {
    function allVaultsLength() external view returns (uint256);

    function createVault(
        ConfigTypes.InitMultiAssetVaultFactoryParams
            memory initMultiAssetVaultFactoryParams,
        ConfigTypes.StrategyParams calldata strategyParams,
        uint256 depositBalance
    ) external payable returns (address newVaultAddress);

    function pairExistsForBuyAsset(
        address depositAsset,
        address buyAsset
    ) external view returns (bool);

    function getAllVaultsPerStrategyWorker(
        address strategyWorker
    ) external view returns (address[] memory);

    function getBatchVaults(
        uint256 limit,
        uint256 startAfter
    ) external view returns (address[] memory);

    function getUserVaults(
        address user
    ) external view returns (address[] memory);
}

