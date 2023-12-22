// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IProduct } from "./IProduct.sol";
import { Deposit, LeverageMetadata } from "./Structs.sol";

interface ILOVProduct is IProduct {
    // View functions
    function depositQueues(uint256 leverage, uint256 index) external view returns (Deposit memory);

    function getDepositQueueCount(uint256 leverage) external view returns (uint256);

    function getVaultAddresses(uint256 leverage) external view returns (address[] memory);

    function leverages(uint256 leverage) external view returns (LeverageMetadata memory);

    // External functions
    function addToDepositQueue(uint256 leverage, address receiver) external;

    function createVault(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _vaultStart,
        uint256 _leverage
    ) external returns (address vaultAddress);

    function updateAllowedLeverage(uint256 _leverage, bool _isAllowed) external;
}

