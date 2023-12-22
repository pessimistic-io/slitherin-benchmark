// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./IPredyTradeCallback.sol";
import "./DataType.sol";
import "./Perp.sol";
import "./PositionCalculator.sol";
import "./Trade.sol";
import "./VaultLib.sol";
import "./PairLib.sol";
import "./ApplyInterestLib.sol";
import "./UpdateMarginLogic.sol";
import "./TradeLogic.sol";

/*
 * Error Codes
 * T1: tx too old
 * T2: too much slippage
 * T3: margin must be positive
 */
library TradePerpLogic {
    using VaultLib for DataType.Vault;

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
        uint256 vaultId, uint256 pairId, int256 tradeAmount, int256 tradeSqrtAmount, Perp.Payoff payoff, int256 fee
    );

    function execTrade(
        DataType.GlobalData storage _globalData,
        uint256 _vaultId,
        uint64 _pairId,
        TradeParams memory _tradeParams
    ) external returns (DataType.TradeResult memory tradeResult) {
        // Checks pairId exists
        PairLib.validatePairId(_globalData, _pairId);

        // Checks vaultId exists
        VaultLib.validateVaultId(_globalData, _vaultId);

        DataType.Vault storage vault = _globalData.vaults[_vaultId];
        DataType.PairGroup memory pairGroup = _globalData.pairGroups[vault.pairGroupId];

        // Checks vault owner is caller
        VaultLib.checkVault(vault, msg.sender);

        // Checks pair and vault belong to same pairGroup
        PairLib.checkPairBelongsToPairGroup(_globalData.pairs[_pairId], vault.pairGroupId);

        Perp.UserStatus storage openPosition = VaultLib.createOrGetOpenPosition(_globalData.pairs, vault, _pairId);

        // Updates interest rate related to the vault
        // New trade pairId is already included in openPositions.
        ApplyInterestLib.applyInterestForVault(vault, _globalData.pairs);

        // Validates trade params
        return execTradeAndValidate(pairGroup, _globalData, vault, _pairId, openPosition, _tradeParams);
    }

    function execTradeAndValidate(
        DataType.PairGroup memory _pairGroup,
        DataType.GlobalData storage _globalData,
        DataType.Vault storage _vault,
        uint256 _pairId,
        Perp.UserStatus storage _openPosition,
        TradeParams memory _tradeParams
    ) public returns (DataType.TradeResult memory tradeResult) {
        DataType.PairStatus storage pairStatus = _globalData.pairs[_pairId];

        checkDeadline(_tradeParams.deadline);

        tradeResult = TradeLogic.trade(
            _pairGroup,
            pairStatus,
            _globalData.rebalanceFeeGrowthCache,
            _openPosition,
            _tradeParams.tradeAmount,
            _tradeParams.tradeAmountSqrt
        );

        _vault.margin += tradeResult.fee + tradeResult.payoff.perpPayoff + tradeResult.payoff.sqrtPayoff;

        checkPrice(
            pairStatus.sqrtAssetStatus.uniswapPool,
            _tradeParams.lowerSqrtPrice,
            _tradeParams.upperSqrtPrice,
            pairStatus.isMarginZero
        );

        if (_tradeParams.enableCallback) {
            // Calls callback function
            int256 marginAmount = IPredyTradeCallback(msg.sender).predyTradeCallback(tradeResult, _tradeParams.data);

            require(marginAmount > 0, "T3");

            _vault.margin += marginAmount;

            UpdateMarginLogic.execMarginTransfer(_vault, pairStatus.stablePool.token, marginAmount);

            UpdateMarginLogic.emitEvent(_vault, marginAmount);
        }

        tradeResult.minDeposit =
            PositionCalculator.checkSafe(_globalData.pairs, _globalData.rebalanceFeeGrowthCache, _vault);

        emit PositionUpdated(
            _vault.id,
            pairStatus.id,
            _tradeParams.tradeAmount,
            _tradeParams.tradeAmountSqrt,
            tradeResult.payoff,
            tradeResult.fee
        );
    }

    function checkDeadline(uint256 _deadline) internal view {
        require(block.timestamp <= _deadline, "T1");
    }

    function checkPrice(address _uniswapPool, uint256 _lowerSqrtPrice, uint256 _upperSqrtPrice, bool _isMarginZero)
        internal
        view
    {
        uint256 sqrtPrice = UniHelper.convertSqrtPrice(UniHelper.getSqrtPrice(_uniswapPool), _isMarginZero);

        require(_lowerSqrtPrice <= sqrtPrice && sqrtPrice <= _upperSqrtPrice, "T2");
    }
}

