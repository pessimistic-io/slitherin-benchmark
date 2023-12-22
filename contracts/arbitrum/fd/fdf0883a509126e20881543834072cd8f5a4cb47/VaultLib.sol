// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./Constants.sol";
import "./DataType.sol";
import "./ScaledAsset.sol";

library VaultLib {
    uint256 internal constant MAX_ISOLATED_VAULTS = 100;

    event VaultCreated(uint256 vaultId, address owner, bool isMainVault, uint256 pairGroupId);

    function validateVaultId(DataType.GlobalData storage _globalData, uint256 _vaultId) internal view {
        require(0 < _vaultId && _vaultId < _globalData.vaultCount, "V1");
    }

    function checkVault(DataType.Vault memory _vault, address _caller) internal pure {
        require(_vault.owner == _caller, "V2");
    }

    function checkVaultBelongsToPairGroup(DataType.Vault memory _vault, uint256 _pairGroupId) internal pure {
        require(_vault.pairGroupId == _pairGroupId, "VAULT0");
    }

    function createVaultIfNeeded(
        DataType.GlobalData storage _globalData,
        uint256 _vaultId,
        address _caller,
        uint256 _pairGroupId,
        bool _isMainVault
    ) internal returns (uint256 vaultId) {
        if (_vaultId == 0) {
            vaultId = _globalData.vaultCount++;

            require(vaultId < Constants.MAX_VAULTS, "MAXV");

            require(_caller != address(0), "V5");

            _globalData.vaults[vaultId].id = vaultId;
            _globalData.vaults[vaultId].owner = _caller;
            _globalData.vaults[vaultId].pairGroupId = _pairGroupId;

            if (_isMainVault) {
                updateMainVaultId(_globalData.ownVaultsMap[_caller][_pairGroupId], vaultId);
            } else {
                addIsolatedVaultId(_globalData.ownVaultsMap[_caller][_pairGroupId], vaultId);
            }

            emit VaultCreated(vaultId, msg.sender, _isMainVault, _pairGroupId);

            return vaultId;
        } else {
            validateVaultId(_globalData, _vaultId);
            checkVault(_globalData.vaults[_vaultId], _caller);
            checkVaultBelongsToPairGroup(_globalData.vaults[_vaultId], _pairGroupId);

            if (!_isMainVault) {
                require(_globalData.ownVaultsMap[_caller][_pairGroupId].mainVaultId != _vaultId, "V6");
            }

            return _vaultId;
        }
    }

    function createOrGetOpenPosition(
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        DataType.Vault storage _vault,
        uint64 _pairId
    ) internal returns (Perp.UserStatus storage userStatus) {
        userStatus = createOrGetUserStatus(_pairs, _vault, _pairId);
    }

    function createOrGetUserStatus(
        mapping(uint256 => DataType.PairStatus) storage _pairs,
        DataType.Vault storage _vault,
        uint64 _pairId
    ) internal returns (Perp.UserStatus storage) {
        for (uint256 i = 0; i < _vault.openPositions.length; i++) {
            if (_vault.openPositions[i].pairId == _pairId) {
                return _vault.openPositions[i];
            }
        }

        if (_vault.openPositions.length >= 1) {
            // vault must not be isolated and _pairId must not be isolated
            require(
                !_pairs[_vault.openPositions[0].pairId].isIsolatedMode && !_pairs[_pairId].isIsolatedMode, "ISOLATED"
            );
        }

        _vault.openPositions.push(Perp.createPerpUserStatus(_pairId));

        return _vault.openPositions[_vault.openPositions.length - 1];
    }

    function cleanOpenPosition(DataType.Vault storage _vault) internal {
        uint256 length = _vault.openPositions.length;

        for (uint256 i = 0; i < length; i++) {
            uint256 index = length - i - 1;
            Perp.UserStatus memory userStatus = _vault.openPositions[index];

            if (userStatus.perp.amount == 0 && userStatus.sqrtPerp.amount == 0) {
                removeOpenPosition(_vault, index);
            }
        }
    }

    function removeOpenPosition(DataType.Vault storage _vault, uint256 _index) internal {
        _vault.openPositions[_index] = _vault.openPositions[_vault.openPositions.length - 1];
        _vault.openPositions.pop();
    }

    function updateMainVaultId(DataType.OwnVaults storage _ownVaults, uint256 _mainVaultId) internal {
        require(_ownVaults.mainVaultId == 0, "V4");

        _ownVaults.mainVaultId = _mainVaultId;
    }

    function addIsolatedVaultId(DataType.OwnVaults storage _ownVaults, uint256 _newIsolatedVaultId) internal {
        require(_newIsolatedVaultId > 0, "V1");

        _ownVaults.isolatedVaultIds.push(_newIsolatedVaultId);

        require(_ownVaults.isolatedVaultIds.length <= MAX_ISOLATED_VAULTS, "V3");
    }

    function removeIsolatedVaultId(DataType.OwnVaults storage _ownVaults, uint256 _vaultId) internal {
        require(_vaultId > 0, "V1");

        if (_ownVaults.mainVaultId == _vaultId) {
            return;
        }

        uint256 index = getIsolatedVaultIndex(_ownVaults, _vaultId);

        removeIsolatedVaultIdWithIndex(_ownVaults, index);
    }

    function removeIsolatedVaultIdWithIndex(DataType.OwnVaults storage _ownVaults, uint256 _index) internal {
        _ownVaults.isolatedVaultIds[_index] = _ownVaults.isolatedVaultIds[_ownVaults.isolatedVaultIds.length - 1];
        _ownVaults.isolatedVaultIds.pop();
    }

    function getIsolatedVaultIndex(DataType.OwnVaults memory _ownVaults, uint256 _vaultId)
        internal
        pure
        returns (uint256)
    {
        uint256 index = type(uint256).max;

        for (uint256 i = 0; i < _ownVaults.isolatedVaultIds.length; i++) {
            if (_ownVaults.isolatedVaultIds[i] == _vaultId) {
                index = i;
                break;
            }
        }

        require(index <= MAX_ISOLATED_VAULTS, "V3");

        return index;
    }

    function getDoesExistsPairId(
        DataType.GlobalData storage _globalData,
        DataType.OwnVaults memory _ownVaults,
        uint256 _pairId
    ) internal view returns (bool) {
        for (uint256 i = 0; i < _ownVaults.isolatedVaultIds.length; i++) {
            DataType.Vault memory vault = _globalData.vaults[_ownVaults.isolatedVaultIds[i]];

            for (uint256 j = 0; j < vault.openPositions.length; j++) {
                Perp.UserStatus memory openPosition = vault.openPositions[j];

                if (openPosition.pairId == _pairId) {
                    return true;
                }
            }
        }

        return false;
    }
}

