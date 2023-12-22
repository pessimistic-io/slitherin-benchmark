// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {TransferHelper} from "./TransferHelper.sol";
import "./ApplyInterestLib.sol";
import "./DataType.sol";
import "./PairGroupLib.sol";
import "./PositionCalculator.sol";
import "./ScaledAsset.sol";
import "./VaultLib.sol";

library UpdateMarginLogic {
    event MarginUpdated(uint256 vaultId, int256 marginAmount);

    function updateMargin(DataType.GlobalData storage _globalData, uint64 _pairGroupId, int256 _marginAmount)
        external
        returns (uint256 vaultId)
    {
        // Checks margin is not 0
        require(_marginAmount != 0, "AZ");

        // Checks pairGroupId exists
        PairGroupLib.validatePairGroupId(_globalData, _pairGroupId);

        vaultId = _globalData.ownVaultsMap[msg.sender][_pairGroupId].mainVaultId;

        // Checks main vault belongs to pairGroup, or main vault does not exist
        vaultId = VaultLib.createVaultIfNeeded(_globalData, vaultId, msg.sender, _pairGroupId, true);

        DataType.Vault storage vault = _globalData.vaults[vaultId];

        vault.margin += _marginAmount;

        if (_marginAmount < 0) {
            ApplyInterestLib.applyInterestForVault(vault, _globalData.pairs);

            PositionCalculator.checkSafe(_globalData.pairs, _globalData.rebalanceFeeGrowthCache, vault);
        }

        execMarginTransfer(vault, _globalData.pairGroups[_pairGroupId].stableTokenAddress, _marginAmount);

        emitEvent(vault, _marginAmount);
    }

    function updateMarginOfIsolated(
        DataType.GlobalData storage _globalData,
        uint256 _pairGroupId,
        uint256 _isolatedVaultId,
        int256 _updateMarginAmount,
        bool _moveFromMainVault
    ) external returns (uint256 isolatedVaultId) {
        int256 updateMarginAmount = _updateMarginAmount;

        if (_isolatedVaultId > 0) {
            DataType.Vault memory isolatedVault = _globalData.vaults[_isolatedVaultId];

            if (
                _moveFromMainVault && !isolatedVault.autoTransferDisabled && _updateMarginAmount == 0
                    && isolatedVault.margin > 0
            ) {
                bool hasPosition = PositionCalculator.getHasPosition(isolatedVault);

                if (!hasPosition) {
                    updateMarginAmount = -isolatedVault.margin;
                }
            }
        }

        isolatedVaultId =
            _updateMarginOfIsolated(_globalData, _pairGroupId, _isolatedVaultId, updateMarginAmount, _moveFromMainVault);
    }

    function _updateMarginOfIsolated(
        DataType.GlobalData storage _globalData,
        uint256 _pairGroupId,
        uint256 _isolatedVaultId,
        int256 _updateMarginAmount,
        bool _moveFromMainVault
    ) internal returns (uint256 isolatedVaultId) {
        // Checks margin is not 0
        require(_updateMarginAmount != 0, "AZ");

        // Checks pairGroupId exists
        PairGroupLib.validatePairGroupId(_globalData, _pairGroupId);

        // Checks main vault belongs to pairGroup, or main vault does not exist
        isolatedVaultId = VaultLib.createVaultIfNeeded(_globalData, _isolatedVaultId, msg.sender, _pairGroupId, false);

        DataType.Vault storage isolatedVault = _globalData.vaults[isolatedVaultId];

        isolatedVault.margin += _updateMarginAmount;

        if (_updateMarginAmount < 0) {
            // Update interest rate related to main vault
            ApplyInterestLib.applyInterestForVault(isolatedVault, _globalData.pairs);

            PositionCalculator.checkSafe(_globalData.pairs, _globalData.rebalanceFeeGrowthCache, isolatedVault);
        }

        if (_moveFromMainVault) {
            DataType.OwnVaults storage ownVaults = _globalData.ownVaultsMap[msg.sender][_pairGroupId];

            DataType.Vault storage mainVault = _globalData.vaults[ownVaults.mainVaultId];

            mainVault.margin -= _updateMarginAmount;

            VaultLib.validateVaultId(_globalData, ownVaults.mainVaultId);

            // Checks account has mainVault
            VaultLib.checkVault(mainVault, msg.sender);

            // Checks pair and main vault belong to same pairGroup
            VaultLib.checkVaultBelongsToPairGroup(mainVault, _pairGroupId);

            if (_updateMarginAmount > 0) {
                // Update interest rate related to main vault
                ApplyInterestLib.applyInterestForVault(mainVault, _globalData.pairs);

                PositionCalculator.checkSafe(_globalData.pairs, _globalData.rebalanceFeeGrowthCache, mainVault);
            }

            emitEvent(mainVault, -_updateMarginAmount);
        } else {
            execMarginTransfer(
                isolatedVault, _globalData.pairGroups[_pairGroupId].stableTokenAddress, _updateMarginAmount
            );
        }

        emitEvent(isolatedVault, _updateMarginAmount);
    }

    function execMarginTransfer(DataType.Vault memory _vault, address _stable, int256 _marginAmount) public {
        if (_marginAmount > 0) {
            TransferHelper.safeTransferFrom(_stable, msg.sender, address(this), uint256(_marginAmount));
        } else if (_marginAmount < 0) {
            TransferHelper.safeTransfer(_stable, _vault.owner, uint256(-_marginAmount));
        }
    }

    function emitEvent(DataType.Vault memory _vault, int256 _marginAmount) internal {
        emit MarginUpdated(_vault.id, _marginAmount);
    }
}

