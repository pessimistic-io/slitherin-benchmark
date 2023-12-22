// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { VaultStatus, Vault } from "./Structs.sol";
import { SettlementStatus, DCSVault } from "./DCSStructs.sol";
import {     IOracleEntry } from "./IOracleEntry.sol";

interface IDCSVaultEntry {
    // FUNCTIONS

    function getVault(
        address vaultAddress
    ) external view returns (Vault memory);

    function getVaultProductId(address vault) external view returns (uint32);

    function getIsDefaulted(address vaultAddress) external view returns (bool);

    function getDaysLate(address vaultAddress) external view returns (uint256);

    function totalAssets(address vaultAddress) external view returns (uint256);

    function convertToAssets(
        address vaultAddress,
        uint256 shares
    ) external view returns (uint256);

    function convertToShares(
        address vaultAddress,
        uint256 assets
    ) external view returns (uint256);

    function getDCSVault(
        address vaultAddress
    ) external view returns (DCSVault memory);

    function calculateDCSLateFee(
        address vaultAddress
    ) external view returns (uint256);

    function getDCSCouponPayment(
        address vaultAddress
    ) external view returns (uint256);

    function openVaultDeposits(address vaultAddress) external;

    function setVaultStatus(
        address vaultAddress,
        VaultStatus _vaultStatus
    ) external;

    function createDCSVault(
        uint32 productId,
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _vaultStartDate
    ) external returns (address vaultAddress);

    function endDCSAuction(
        address vaultAddress,
        address _auctionWinner,
        uint40 _tradeStartDate,
        uint256 _aprBps,
        IOracleEntry.DataSource dataSource
    ) external;

    function startDCSTrade(address vaultAddress) external payable;

    function settleDCSVault(address vaultAddress) external payable;

    function rolloverDCSVault(address vaultAddress) external;

    function setDCSSettlementStatus(
        address vaultAddress,
        SettlementStatus _settlementStatus
    ) external;

    function setDCSIsPayoffInDepositAsset(
        address vaultAddress,
        bool newState
    ) external;

    function checkDCSAuctionDefault(address vaultAddress) external;
}

