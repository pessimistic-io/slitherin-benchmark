// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {     ProxyReentrancyGuard } from "./ProxyReentrancyGuard.sol";
import { CegaStorage } from "./CegaStorage.sol";
import { CegaGlobalStorage, DepositQueue } from "./Structs.sol";
import { DCSProduct } from "./DCSStructs.sol";
import { IAddressManager } from "./IAddressManager.sol";
import { IACLManager } from "./IACLManager.sol";
import {     IDCSConfigurationEntry } from "./IDCSConfigurationEntry.sol";

contract DCSConfigurationEntry is
    IDCSConfigurationEntry,
    CegaStorage,
    ProxyReentrancyGuard
{
    // CONSTANTS

    uint256 private constant MAX_BPS = 1e4;

    IAddressManager private immutable addressManager;

    // EVENTS

    event MinDepositAmountUpdated(uint32 productId, uint256 minDepositAmount);

    event MinWithdrawalAmountUpdated(
        uint32 productId,
        uint256 minWithdrawalAmount
    );

    event IsDepositQueueOpenUpdated(uint32 productId, bool isDepositQueueOpen);

    event MaxDepositAmountLimitUpdated(
        uint32 productId,
        uint256 maxDepositAmountLimit
    );

    event ManagementFeeUpdated(address vaultAddress, uint256 value);

    event YieldFeeUpdated(address vaultAddress, uint256 value);

    event DisputePeriodInHoursUpdated(
        uint32 productId,
        uint8 disputePeriodInHours
    );

    event DaysToStartLateFeesUpdated(
        uint32 productId,
        uint8 daysToStartLateFees
    );

    event DaysToStartAuctionDefaultUpdated(
        uint32 productId,
        uint8 daysToStartAuctionDefault
    );

    event DaysToStartSettlementDefaultUpdated(
        uint32 productId,
        uint8 daysToStartSettlementDefault
    );

    // MODIFIERS

    modifier onlyTraderAdmin() {
        require(
            IACLManager(addressManager.getACLManager()).isTraderAdmin(
                msg.sender
            ),
            "DCSPE:TA"
        );
        _;
    }

    // CONSTRUCTOR

    constructor(IAddressManager _addressManager) {
        addressManager = _addressManager;
    }

    /**
     * @notice Sets the min deposit amount for the product
     * @param minDepositAmount is the minimum units of underlying for a user to deposit
     */
    function setDCSMinDepositAmount(
        uint128 minDepositAmount,
        uint32 productId
    ) external onlyTraderAdmin {
        require(minDepositAmount > 0, "400:IU");
        DCSProduct storage dcsProduct = getStorage().dcsProducts[productId];
        dcsProduct.minDepositAmount = minDepositAmount;
        emit MinDepositAmountUpdated(productId, minDepositAmount);
    }

    /**
     * @notice Sets the min withdrawal amount for the product
     * @param minWithdrawalAmount is the minimum units of vault shares for a user to withdraw
     */
    function setDCSMinWithdrawalAmount(
        uint128 minWithdrawalAmount,
        uint32 productId
    ) external onlyTraderAdmin {
        require(minWithdrawalAmount > 0, "400:IU");
        DCSProduct storage dcsProduct = getStorage().dcsProducts[productId];
        dcsProduct.minWithdrawalAmount = minWithdrawalAmount;
        emit MinWithdrawalAmountUpdated(productId, minWithdrawalAmount);
    }

    /**
     * @notice Toggles whether the product is open or closed for deposits
     * @param isDepositQueueOpen is a boolean for whether the deposit queue is accepting deposits
     */
    function setDCSIsDepositQueueOpen(
        bool isDepositQueueOpen,
        uint32 productId
    ) external onlyTraderAdmin {
        CegaGlobalStorage storage cgs = getStorage();
        DCSProduct storage dcsProduct = cgs.dcsProducts[productId];
        dcsProduct.isDepositQueueOpen = isDepositQueueOpen;
        emit IsDepositQueueOpenUpdated(productId, isDepositQueueOpen);
    }

    function setDaysToStartLateFees(
        uint32 productId,
        uint8 daysToStartLateFees
    ) external onlyTraderAdmin {
        require(daysToStartLateFees > 0, "400:IU");

        DCSProduct storage dcsProduct = getStorage().dcsProducts[productId];
        dcsProduct.daysToStartLateFees = daysToStartLateFees;

        emit DaysToStartLateFeesUpdated(productId, daysToStartLateFees);
    }

    function setDaysToStartAuctionDefault(
        uint32 productId,
        uint8 daysToStartAuctionDefault
    ) external onlyTraderAdmin {
        require(daysToStartAuctionDefault > 0, "400:IU");

        DCSProduct storage dcsProduct = getStorage().dcsProducts[productId];
        dcsProduct.daysToStartAuctionDefault = daysToStartAuctionDefault;

        emit DaysToStartAuctionDefaultUpdated(
            productId,
            daysToStartAuctionDefault
        );
    }

    function setDaysToStartSettlementDefault(
        uint32 productId,
        uint8 daysToStartSettlementDefault
    ) external onlyTraderAdmin {
        require(daysToStartSettlementDefault > 0, "400:IU");

        DCSProduct storage dcsProduct = getStorage().dcsProducts[productId];
        dcsProduct.daysToStartSettlementDefault = daysToStartSettlementDefault;

        emit DaysToStartSettlementDefaultUpdated(
            productId,
            daysToStartSettlementDefault
        );
    }

    /**
     * @notice Sets the maximum deposit limit for the product
     * @param maxDepositAmountLimit is the deposit limit for the product
     */
    function setDCSMaxDepositAmountLimit(
        uint128 maxDepositAmountLimit,
        uint32 productId
    ) external onlyTraderAdmin {
        CegaGlobalStorage storage cgs = getStorage();
        DCSProduct storage dcsProduct = cgs.dcsProducts[productId];
        DepositQueue storage depositQueue = cgs.dcsDepositQueues[productId];
        require(
            depositQueue.queuedDepositsTotalAmount +
                dcsProduct.sumVaultUnderlyingAmounts <=
                maxDepositAmountLimit,
            "400:TooSmall"
        );
        dcsProduct.maxDepositAmountLimit = maxDepositAmountLimit;
        emit MaxDepositAmountLimitUpdated(productId, maxDepositAmountLimit);
    }

    function setDCSManagementFee(
        address vaultAddress,
        uint256 value
    ) external onlyTraderAdmin {
        require(value <= MAX_BPS, "400:IB");

        CegaGlobalStorage storage cgs = getStorage();
        cgs.vaults[vaultAddress].managementFeeBps = value;

        emit ManagementFeeUpdated(vaultAddress, value);
    }

    function setDCSYieldFee(
        address vaultAddress,
        uint256 value
    ) external onlyTraderAdmin {
        require(value <= MAX_BPS, "400:IB");

        CegaGlobalStorage storage cgs = getStorage();
        cgs.vaults[vaultAddress].yieldFeeBps = value;

        emit YieldFeeUpdated(vaultAddress, value);
    }

    function setDipsutePeriodInHours(
        uint32 productId,
        uint8 disputePeriodInHours
    ) external onlyTraderAdmin {
        require(disputePeriodInHours > 0, "400:IU");

        DCSProduct storage dcsProduct = getStorage().dcsProducts[productId];
        dcsProduct.disputePeriodInHours = disputePeriodInHours;

        emit DisputePeriodInHoursUpdated(productId, disputePeriodInHours);
    }
}

