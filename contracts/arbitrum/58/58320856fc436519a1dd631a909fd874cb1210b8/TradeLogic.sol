// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./IPredyTradeCallback.sol";
import "./DataType.sol";
import "./Perp.sol";
import "./PositionCalculator.sol";
import "./Trade.sol";
import "./VaultLib.sol";
import "./AssetLib.sol";
import "./UpdateMarginLogic.sol";

/*
 * Error Codes
 * T1: tx too old
 * T2: too much slippage
 * T3: margin must be positive
 */
library TradeLogic {
    struct TradeParams {
        int256 tradeAmount;
        int256 tradeAmountSqrt;
        uint256 lowerSqrtPrice;
        uint256 upperSqrtPrice;
        uint256 deadline;
        bool enableCallback;
        bytes data;
    }

    event PositionUpdated(
        uint256 vaultId, uint256 assetId, int256 tradeAmount, int256 tradeSqrtAmount, Perp.Payoff payoff, int256 fee
    );

    function execTrade(
        mapping(uint256 => DataType.AssetStatus) storage _assets,
        DataType.Vault storage _vault,
        uint256 _assetId,
        DataType.UserStatus storage _userStatus,
        TradeParams memory _tradeParams
    ) public returns (DataType.TradeResult memory tradeResult) {
        DataType.AssetStatus storage underlyingAssetStatus = _assets[_assetId];
        DataType.AssetStatus storage stableAssetStatus = _assets[Constants.STABLE_ASSET_ID];

        AssetLib.checkUnderlyingAsset(_assetId, underlyingAssetStatus);

        checkDeadline(_tradeParams.deadline);

        tradeResult = trade(
            underlyingAssetStatus,
            stableAssetStatus,
            _userStatus.perpTrade,
            _tradeParams.tradeAmount,
            _tradeParams.tradeAmountSqrt
        );

        _vault.margin += tradeResult.fee + tradeResult.payoff.perpPayoff + tradeResult.payoff.sqrtPayoff;

        checkPrice(
            underlyingAssetStatus.sqrtAssetStatus.uniswapPool, _tradeParams.lowerSqrtPrice, _tradeParams.upperSqrtPrice
        );

        if (_tradeParams.enableCallback) {
            // Calls callback function
            int256 marginAmount = IPredyTradeCallback(msg.sender).predyTradeCallback(tradeResult, _tradeParams.data);

            require(marginAmount > 0, "T3");

            _vault.margin += marginAmount;

            UpdateMarginLogic.execMarginTransfer(_vault, stableAssetStatus.token, marginAmount);

            UpdateMarginLogic.emitEvent(_vault, marginAmount);
        }

        tradeResult.minDeposit = PositionCalculator.isSafe(_assets, _vault, false);

        emit PositionUpdated(
            _vault.id,
            underlyingAssetStatus.id,
            _tradeParams.tradeAmount,
            _tradeParams.tradeAmountSqrt,
            tradeResult.payoff,
            tradeResult.fee
        );
    }

    function trade(
        DataType.AssetStatus storage _underlyingAssetStatus,
        DataType.AssetStatus storage _stableAssetStatus,
        Perp.UserStatus storage _perpUserStatus,
        int256 _tradeAmount,
        int256 _tradeAmountSqrt
    ) public returns (DataType.TradeResult memory) {
        return Trade.trade(_underlyingAssetStatus, _stableAssetStatus, _perpUserStatus, _tradeAmount, _tradeAmountSqrt);
    }

    function checkDeadline(uint256 _deadline) internal view {
        require(block.timestamp <= _deadline, "T1");
    }

    function checkPrice(address _uniswapPool, uint256 _lowerSqrtPrice, uint256 _upperSqrtPrice) internal view {
        uint256 sqrtPrice = UniHelper.getSqrtPrice(_uniswapPool);

        require(_lowerSqrtPrice <= sqrtPrice && sqrtPrice <= _upperSqrtPrice, "T2");
    }
}

