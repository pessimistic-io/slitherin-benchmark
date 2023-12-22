// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { Withdrawer, VaultStatus } from "./Structs.sol";
import {     DCSProductCreationParams,     DCSProduct,     SettlementStatus } from "./DCSStructs.sol";
import {     IOracleEntry } from "./IOracleEntry.sol";

interface IDCSProductEntry {
    // FUNCTIONS

    function getDCSProduct(
        uint32 productId
    ) external view returns (DCSProduct memory);

    function getDCSLatestProductId() external view returns (uint32);

    function getDCSProductDepositAsset(
        uint32 productId
    ) external view returns (address);

    function getDCSDepositQueue(
        uint32 productId
    )
        external
        view
        returns (
            address[] memory depositors,
            uint128[] memory amounts,
            uint128 totalAmount
        );

    function getDCSWithdrawalQueue(
        address vaultAddress
    )
        external
        view
        returns (
            Withdrawer[] memory withdrawers,
            uint256[] memory amounts,
            uint256 totalAmount
        );

    function isDCSWithdrawalPossible(
        address vaultAddress
    ) external view returns (bool);

    function calculateDCSVaultFinalPayoff(
        address vaultAddress
    ) external view returns (uint256);

    function createDCSProduct(
        DCSProductCreationParams calldata creationParams
    ) external returns (uint32);

    function addToDCSDepositQueue(
        uint32 productId,
        uint128 amount,
        address receiver
    ) external payable;

    function processDCSDepositQueue(
        address vault,
        uint256 maxProcessCount
    ) external;

    function addToDCSWithdrawalQueue(
        address vault,
        uint256 sharesAmount,
        uint32 nextProductId
    ) external;

    function processDCSWithdrawalQueue(
        address vault,
        uint256 maxProcessCount
    ) external;

    function checkDCSTradeExpiry(address vaultAddress) external;

    function checkDCSSettlementDefault(address vaultAddress) external;

    function collectDCSVaultFees(address vaultAddress) external;

    function submitDispute(address vaultAddress) external;

    function processTradeDispute(
        address vaultAddress,
        uint256 newPrice
    ) external;

    function overrideOraclePrice(
        address vaultAddress,
        uint64 timestamp,
        uint256 newPrice
    ) external;

    function getOraclePriceOverride(
        address vaultAddress,
        uint64 timestamp
    ) external view returns (uint256);
}

