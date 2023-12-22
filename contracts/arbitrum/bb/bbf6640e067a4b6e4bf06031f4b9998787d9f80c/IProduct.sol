// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { Deposit, FCNVaultMetadata, OptionBarrierType, OptionBarrier, VaultStatus, Withdrawal } from "./Structs.sol";

interface IProduct {
    // View functions
    function asset() external view returns (address);

    function cegaState() external view returns (address);

    function getVaultMetadata(address vaultAddress) external view returns (FCNVaultMetadata memory);

    function managementFeeBps() external view returns (uint256);

    function minDepositAmount() external view returns (uint256);

    function minWithdrawalAmount() external view returns (uint256);

    function name() external view returns (string memory);

    function vaults(
        address vaultAddress
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            address,
            VaultStatus,
            bool
        );

    function withdrawalQueues(address vaultAddress, uint256 index) external view returns (Withdrawal memory);

    function yieldFeeBps() external view returns (uint256);

    // External functions

    function addOptionBarrier(address vaultAddress, OptionBarrier calldata optionBarrier) external;

    function addToWithdrawalQueue(address vaultAddress, uint256 amountShares, address receiver) external;

    function calculateCurrentYield(address vaultAddress) external;

    function calculateVaultFinalPayoff(address vaultAddress) external returns (uint256 vaultFinalPayoff);

    function checkBarriers(address vaultAddress) external;

    function collectFees(address vaultAddress) external;

    function openVaultDeposits(address vaultAddress) external;

    function processDepositQueue(address vaultAddress, uint256 maxProcessCount) external;

    function processWithdrawalQueue(address vaultAddress, uint256 maxProcessCount) external;

    function receiveAssetsFromCegaState(address vaultAddress, uint256 amount) external;

    function removeOptionBarrier(address vaultAddress, uint256 index, string calldata _asset) external;

    function removeVault(uint256 index) external;

    function rolloverVault(address vaultAddress) external;

    function sendAssetsToTrade(address vaultAddress, address receiver, uint256 amount) external;

    function setIsDepositQueueOpen(bool _isDepositQueueOpen) external;

    function setKnockInStatus(address vaultAddress, bool newState) external;

    function setManagementFeeBps(uint256 _managementFeeBps) external;

    function setMaxDepositAmountLimit(uint256 _maxDepositAmountLimit) external;

    function setMinDepositAmount(uint256 _minDepositAmount) external;

    function setMinWithdrawalAmount(uint256 _minWithdrawalAmount) external;

    function setTradeData(
        address vaultAddress,
        uint256 _tradeDate,
        uint256 _tradeExpiry,
        uint256 _aprBps,
        uint256 _tenorInDays
    ) external;

    function setVaultMetadata(address vaultAddress, FCNVaultMetadata calldata metadata) external;

    function setVaultStatus(address vaultAddress, VaultStatus _vaultStatus) external;

    function setYieldFeeBps(uint256 _yieldFeeBps) external;

    function updateOptionBarrier(
        address vaultAddress,
        uint256 index,
        string calldata _asset,
        uint256 _strikeAbsoluteValue,
        uint256 _barrierAbsoluteValue
    ) external;

    function updateOptionBarrierOracle(
        address vaultAddress,
        uint256 index,
        string calldata _asset,
        string memory newOracleName
    ) external;
}

