// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {TransferHelper} from "./TransferHelper.sol";
import "./DataType.sol";
import "./PositionCalculator.sol";
import "./ScaledAsset.sol";
import "./VaultLib.sol";
import "./SettleUserFeeLogic.sol";

library UpdateMarginLogic {
    event MarginUpdated(uint256 vaultId, int256 marginAmount);

    function updateMargin(
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault storage _vault,
        int256 _marginAmount
    ) external {
        VaultLib.checkVault(_vault, msg.sender);
        // settle user fee and balance
        if (_marginAmount < 0) {
            SettleUserFeeLogic.settleUserFee(_assets, _vault);
        }

        _vault.margin += _marginAmount;

        PositionCalculator.isSafe(_assets, _vault, false);

        execMarginTransfer(_vault, getStableToken(_assets), _marginAmount);

        emitEvent(_vault, _marginAmount);
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

    function getStableToken(mapping(uint256 => DataType.AssetStatus) storage _assets) internal view returns (address) {
        return _assets[Constants.STABLE_ASSET_ID].token;
    }
}

