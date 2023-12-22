// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IDCSConfigurationEntry {
    // FUNCTIONS

    function setDCSMinDepositAmount(
        uint128 minDepositAmount,
        uint32 productId
    ) external;

    function setDCSMinWithdrawalAmount(
        uint128 minWithdrawalAmount,
        uint32 productId
    ) external;

    function setDCSIsDepositQueueOpen(
        bool isDepositQueueOpen,
        uint32 productId
    ) external;

    function setDaysToStartLateFees(
        uint32 productId,
        uint8 daysToStartLateFees
    ) external;

    function setDaysToStartAuctionDefault(
        uint32 productId,
        uint8 daysToStartAuctionDefault
    ) external;

    function setDaysToStartSettlementDefault(
        uint32 productId,
        uint8 daysToStartSettlementDefault
    ) external;

    function setDCSMaxDepositAmountLimit(
        uint128 maxDepositAmountLimit,
        uint32 productId
    ) external;

    function setDCSManagementFee(address vaultAddress, uint256 value) external;

    function setDCSYieldFee(address vaultAddress, uint256 value) external;

    function setDipsutePeriodInHours(
        uint32 productId,
        uint8 disputePeriodInHours
    ) external;
}

