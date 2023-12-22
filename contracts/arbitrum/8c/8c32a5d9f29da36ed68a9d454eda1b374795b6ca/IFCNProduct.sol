// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IProduct } from "./IProduct.sol";
import { Deposit } from "./Structs.sol";

interface IFCNProduct is IProduct {
    // View functions
    function calculateFees(
        address vaultAddress
    ) external view returns (uint256 totalFee, uint256 managementFee, uint256 yieldFee);

    function calculateKnockInRatio(address vaultAddress) external view returns (uint256 knockInRatio);

    function depositQueue(uint256 index) external view returns (Deposit memory);

    function getVaultAddresses() external view returns (address[] memory);

    function isDepositQueueOpen() external view returns (bool);

    function maxDepositAmountLimit() external view returns (uint256);

    function queuedDepositsCount() external view returns (uint256);

    function queuedDepositsTotalAmount() external view returns (uint256);

    function sumVaultUnderlyingAmounts() external view returns (uint256);

    function vaultAddresses(uint256 index) external view returns (address);

    // External functions

    function addToDepositQueue(uint256 amount) external;

    function createVault(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _vaultStart
    ) external returns (address vaultAddress);
}

