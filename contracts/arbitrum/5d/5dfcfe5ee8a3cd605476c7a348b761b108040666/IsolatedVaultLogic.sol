// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./TradeLogic.sol";

/*
 * Error Codes
 * I1: vault is not safe
 */
library IsolatedVaultLogic {
    struct CloseParams {
        uint256 lowerSqrtPrice;
        uint256 upperSqrtPrice;
        uint256 deadline;
    }

    event IsolatedVaultOpened(uint256 vaultId, uint256 isolatedVaultId, uint256 marginAmount);
    event IsolatedVaultClosed(uint256 vaultId, uint256 isolatedVaultId, uint256 marginAmount);

    function openIsolatedVault(
        DataType.AssetGroup storage _assetGroup,
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault storage _vault,
        DataType.Vault storage _isolatedVault,
        uint256 _depositAmount,
        uint256 _assetId,
        TradeLogic.TradeParams memory _tradeParams
    ) external returns (DataType.TradeResult memory tradeResult) {
        DataType.UserStatus storage perpUserStatus = VaultLib.getUserStatus(_assetGroup, _isolatedVault, _assetId);

        _vault.margin -= int256(_depositAmount);
        _isolatedVault.margin += int256(_depositAmount);

        PositionCalculator.isSafe(_assets, _vault, false);

        tradeResult = TradeLogic.execTrade(_assets, _isolatedVault, _assetId, perpUserStatus, _tradeParams);

        emit IsolatedVaultOpened(_vault.id, _isolatedVault.id, _depositAmount);
    }

    function closeIsolatedVault(
        DataType.AssetGroup storage _assetGroup,
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault storage _vault,
        DataType.Vault storage _isolatedVault,
        uint256 _assetId,
        CloseParams memory _closeParams
    ) external returns (DataType.TradeResult memory tradeResult) {
        DataType.UserStatus storage perpUserStatus = VaultLib.getUserStatus(_assetGroup, _isolatedVault, _assetId);

        tradeResult = closeVault(_assets, _isolatedVault, _assetId, perpUserStatus, _closeParams);

        // _isolatedVault.margin must be greater than 0

        int256 withdrawnMargin = _isolatedVault.margin;

        _vault.margin += _isolatedVault.margin;

        _isolatedVault.margin = 0;

        emit IsolatedVaultClosed(_vault.id, _isolatedVault.id, uint256(withdrawnMargin));
    }

    function closeVault(
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault storage _vault,
        uint256 _assetId,
        DataType.UserStatus storage _userStatus,
        CloseParams memory _closeParams
    ) internal returns (DataType.TradeResult memory tradeResult) {
        int256 tradeAmount = -_userStatus.perpTrade.perp.amount;
        int256 tradeAmountSqrt = -_userStatus.perpTrade.sqrtPerp.amount;

        return TradeLogic.execTrade(
            _assets,
            _vault,
            _assetId,
            _userStatus,
            TradeLogic.TradeParams(
                tradeAmount,
                tradeAmountSqrt,
                _closeParams.lowerSqrtPrice,
                _closeParams.upperSqrtPrice,
                _closeParams.deadline,
                false,
                ""
            )
        );
    }
}

