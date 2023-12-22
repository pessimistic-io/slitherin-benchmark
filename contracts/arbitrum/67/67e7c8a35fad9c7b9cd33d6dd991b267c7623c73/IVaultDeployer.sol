// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import { IDepositHandler } from "./IDepositHandler.sol";

interface IVaultDeployer is IDepositHandler {
    function createVestingVault(
        bool shouldMintKey,
        address beneficiary,
        uint256 unlockTimestamp,
        IDepositHandler.FungibleTokenDeposit[] memory fungibleTokenDeposits
    ) external returns (address);

    function createBatchVault(
        bool shouldMintKey,
        address beneficiary,
        uint256 unlockTimestamp,
        IDepositHandler.FungibleTokenDeposit[] memory fungibleTokenDeposits,
        IDepositHandler.NonFungibleTokenDeposit[] memory nonFungibleTokenDeposits,
        IDepositHandler.MultiTokenDeposit[] memory multiTokenDeposits
    ) external returns (address);
}

