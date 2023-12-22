// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {     SafeERC20 } from "./SafeERC20.sol";
import {     IERC20Metadata,     IERC20 } from "./IERC20Metadata.sol";
import { Math } from "./Math.sol";

import {     ProxyReentrancyGuard } from "./ProxyReentrancyGuard.sol";
import { CegaStorage } from "./CegaStorage.sol";
import {     CegaGlobalStorage,     DepositQueue,     WithdrawalQueue,     Withdrawer,     Vault,     VaultStatus,     DCS_STRATEGY_ID } from "./Structs.sol";
import {     DCSOptionType,     DCSProductCreationParams,     DCSProduct,     DCSVault,     SettlementStatus } from "./DCSStructs.sol";
import { Transfers } from "./Transfers.sol";
import { VaultLogic } from "./VaultLogic.sol";
import { DCSLogic } from "./DCSLogic.sol";
import { IDCSProductEntry } from "./IDCSProductEntry.sol";
import { ICegaVault } from "./ICegaVault.sol";
import { ITreasury } from "./ITreasury.sol";
import { IAddressManager } from "./IAddressManager.sol";
import { IACLManager } from "./IACLManager.sol";
import { IOracleEntry } from "./IOracleEntry.sol";

contract DCSProductEntry is
    IDCSProductEntry,
    CegaStorage,
    ProxyReentrancyGuard
{
    using Transfers for address;

    // CONSTANTS

    uint256 private constant MAX_BPS = 1e4;

    IAddressManager private immutable addressManager;

    ITreasury private immutable treasury;

    // EVENTS

    event DepositQueued(
        uint32 productId,
        address sender,
        address receiver,
        uint128 amount
    );

    event DepositProcessed(
        address vaultAddress,
        address receiver,
        uint128 amount
    );

    event WithdrawalQueued(
        address vaultAddress,
        uint256 sharesAmount,
        address owner,
        uint32 nextProductId
    );

    event WithdrawalProcessed(
        address vaultAddress,
        uint256 sharesAmount,
        address owner,
        uint32 nextProductId
    );

    event VaultStatusUpdated(
        address indexed vaultAddress,
        VaultStatus vaultStatus
    );

    event SettlementStatusUpdated(
        address indexed vaultAddress,
        SettlementStatus settlementStatus
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

    modifier onlyCegaAdmin() {
        require(
            IACLManager(addressManager.getACLManager()).isCegaAdmin(msg.sender),
            "DCSPE:CA"
        );
        _;
    }

    // CONSTRUCTOR

    constructor(IAddressManager _addressManager, ITreasury _treasury) {
        addressManager = _addressManager;
        treasury = _treasury;
    }

    // VIEW FUNCTIONS

    function getDCSProduct(
        uint32 productId
    ) external view returns (DCSProduct memory) {
        CegaGlobalStorage storage cgs = getStorage();
        return cgs.dcsProducts[productId];
    }

    function getDCSLatestProductId() external view returns (uint32) {
        CegaGlobalStorage storage cps = getStorage();
        return cps.productIdCounter;
    }

    function getDCSProductDepositAsset(
        uint32 productId
    ) external view returns (address) {
        return
            DCSLogic.getDCSProductDepositAsset(
                getStorage().dcsProducts[productId]
            );
    }

    function getDCSDepositQueue(
        uint32 productId
    )
        external
        view
        returns (
            address[] memory depositors,
            uint128[] memory amounts,
            uint128 totalAmount
        )
    {
        DepositQueue storage queue = getStorage().dcsDepositQueues[productId];
        depositors = queue.depositors;
        amounts = new uint128[](depositors.length);
        for (uint256 i = 0; i < depositors.length; i++) {
            amounts[i] = queue.amounts[depositors[i]];
        }
        totalAmount = queue.queuedDepositsTotalAmount;
    }

    function getDCSWithdrawalQueue(
        address vaultAddress
    )
        external
        view
        returns (
            Withdrawer[] memory withdrawers,
            uint256[] memory amounts,
            uint256 totalAmount
        )
    {
        WithdrawalQueue storage queue = getStorage().dcsWithdrawalQueues[
            vaultAddress
        ];
        withdrawers = queue.withdrawers;
        amounts = new uint256[](withdrawers.length);
        for (uint256 i = 0; i < withdrawers.length; i++) {
            amounts[i] = queue.amounts[withdrawers[i].account][
                withdrawers[i].nextProductId
            ];
        }
        totalAmount = queue.queuedWithdrawalSharesAmount;
    }

    function isDCSWithdrawalPossible(
        address vaultAddress
    ) external view returns (bool) {
        CegaGlobalStorage storage cgs = getStorage();
        return VaultLogic.isWithdrawalPossible(cgs, vaultAddress);
    }

    function calculateDCSVaultFinalPayoff(
        address vaultAddress
    ) external view returns (uint256) {
        CegaGlobalStorage storage cgs = getStorage();
        return
            DCSLogic.calculateVaultFinalPayoff(
                cgs,
                addressManager,
                vaultAddress
            );
    }

    // MUTATIVE FUNCTIONS

    function createDCSProduct(
        DCSProductCreationParams calldata creationParams
    ) external onlyTraderAdmin returns (uint32) {
        CegaGlobalStorage storage cgs = getStorage();
        require(
            creationParams.quoteAssetAddress != creationParams.baseAssetAddress,
            "QBS"
        );
        require(creationParams.minDepositAmount > 0, "MDNZ");
        require(creationParams.minWithdrawalAmount > 0, "MWNZ");
        if (creationParams.dcsOptionType == DCSOptionType.BuyLow) {
            require(creationParams.strikeBarrierBps <= MAX_BPS, "IBLS");
        } else {
            require(creationParams.strikeBarrierBps >= MAX_BPS, "ISHS");
        }
        require(creationParams.tenorInSeconds > 0, "TNZ");

        address[] memory vaultAddresses;
        uint32 newId = ++cgs.productIdCounter;

        cgs.dcsProducts[newId] = DCSProduct({
            id: newId,
            dcsOptionType: creationParams.dcsOptionType,
            isDepositQueueOpen: false,
            quoteAssetAddress: creationParams.quoteAssetAddress,
            baseAssetAddress: creationParams.baseAssetAddress,
            maxDepositAmountLimit: creationParams.maxDepositAmountLimit,
            minDepositAmount: creationParams.minDepositAmount,
            minWithdrawalAmount: creationParams.minWithdrawalAmount,
            sumVaultUnderlyingAmounts: 0,
            vaults: vaultAddresses,
            daysToStartLateFees: creationParams.daysToStartLateFees,
            daysToStartAuctionDefault: creationParams.daysToStartAuctionDefault,
            daysToStartSettlementDefault: creationParams
                .daysToStartSettlementDefault,
            lateFeeBps: creationParams.lateFeeBps,
            strikeBarrierBps: creationParams.strikeBarrierBps,
            tenorInSeconds: creationParams.tenorInSeconds,
            disputePeriodInHours: creationParams.disputePeriodInHours
        });
        cgs.strategyOfProduct[newId] = DCS_STRATEGY_ID;

        return newId;
    }

    function addToDCSDepositQueue(
        uint32 productId,
        uint128 amount,
        address receiver
    ) external payable {
        CegaGlobalStorage storage cgs = getStorage();
        DCSProduct storage dcsProduct = cgs.dcsProducts[productId];
        require(dcsProduct.isDepositQueueOpen, "400:DQC");
        require(amount >= dcsProduct.minDepositAmount, "400:ATS");

        DepositQueue storage depositQueue = cgs.dcsDepositQueues[productId];

        uint128 _queuedDepositsTotalAmount = depositQueue
            .queuedDepositsTotalAmount + amount;
        depositQueue.queuedDepositsTotalAmount = _queuedDepositsTotalAmount;
        require(
            dcsProduct.sumVaultUnderlyingAmounts + _queuedDepositsTotalAmount <=
                dcsProduct.maxDepositAmountLimit,
            "400:ODL"
        );

        address depositAsset = DCSLogic.getDCSProductDepositAsset(dcsProduct);
        depositAsset.receiveTo(address(treasury), amount);

        uint128 currentQueuedAmount = depositQueue.amounts[receiver];
        if (currentQueuedAmount == 0) {
            depositQueue.depositors.push(receiver);
        }
        depositQueue.amounts[receiver] = currentQueuedAmount + amount;

        emit DepositQueued(productId, msg.sender, receiver, amount);
    }

    function processDCSDepositQueue(
        address vaultAddress,
        uint256 maxProcessCount
    ) external onlyTraderAdmin nonReentrant {
        CegaGlobalStorage storage cgs = getStorage();
        DCSLogic.processDepositQueue(cgs, vaultAddress, maxProcessCount);
    }

    function addToDCSWithdrawalQueue(
        address vaultAddress,
        uint256 sharesAmount,
        uint32 nextProductId
    ) external nonReentrant {
        CegaGlobalStorage storage cgs = getStorage();
        Vault storage vaultData = cgs.vaults[vaultAddress];
        DCSProduct storage dcsProduct = cgs.dcsProducts[vaultData.productId];
        require(sharesAmount >= dcsProduct.minWithdrawalAmount, "400:TS");

        ICegaVault(vaultAddress).transferFrom(
            msg.sender,
            vaultAddress,
            sharesAmount
        );

        WithdrawalQueue storage queue = cgs.dcsWithdrawalQueues[vaultAddress];
        uint256 currentQueuedAmount = queue.amounts[msg.sender][nextProductId];
        if (currentQueuedAmount == 0) {
            queue.withdrawers.push(
                Withdrawer({
                    account: msg.sender,
                    nextProductId: nextProductId
                })
            );
        }
        queue.amounts[msg.sender][nextProductId] =
            currentQueuedAmount +
            sharesAmount;

        queue.queuedWithdrawalSharesAmount += sharesAmount;

        emit WithdrawalQueued(
            vaultAddress,
            sharesAmount,
            msg.sender,
            nextProductId
        );
    }

    function processDCSWithdrawalQueue(
        address vaultAddress,
        uint256 maxProcessCount
    ) external onlyTraderAdmin nonReentrant {
        CegaGlobalStorage storage cgs = getStorage();
        DCSLogic.processWithdrawalQueue(
            cgs,
            treasury,
            addressManager,
            vaultAddress,
            maxProcessCount
        );
    }

    function checkDCSTradeExpiry(address vaultAddress) external nonReentrant {
        CegaGlobalStorage storage cgs = getStorage();
        DCSLogic.checkTradeExpiry(cgs, addressManager, vaultAddress);
    }

    function checkDCSSettlementDefault(
        address vaultAddress
    ) external nonReentrant {
        CegaGlobalStorage storage cgs = getStorage();
        DCSLogic.checkSettlementDefault(cgs, vaultAddress);
    }

    function collectDCSVaultFees(
        address vaultAddress
    ) external onlyTraderAdmin {
        CegaGlobalStorage storage cgs = getStorage();

        DCSLogic.collectVaultFees(cgs, treasury, addressManager, vaultAddress);
    }

    function submitDispute(address vaultAddress) external {
        CegaGlobalStorage storage cgs = getStorage();

        VaultLogic.disputeVault(
            cgs,
            vaultAddress,
            addressManager.getTradeWinnerNFT()
        );
    }

    function processTradeDispute(
        address vaultAddress,
        uint256 newPrice
    ) external onlyTraderAdmin {
        CegaGlobalStorage storage cgs = getStorage();

        VaultLogic.processDispute(cgs, vaultAddress, newPrice);
    }

    function overrideOraclePrice(
        address vaultAddress,
        uint64 timestamp,
        uint256 newPrice
    ) external onlyCegaAdmin {
        CegaGlobalStorage storage cgs = getStorage();
        require(newPrice != 0, "NP0");
        require(timestamp != 0, "TS0");

        VaultLogic.overrideOraclePrice(cgs, vaultAddress, timestamp, newPrice);
    }

    function getOraclePriceOverride(
        address vaultAddress,
        uint64 timestamp
    ) external view returns (uint256) {
        CegaGlobalStorage storage cgs = getStorage();

        return cgs.oraclePriceOverride[vaultAddress][timestamp];
    }
}

