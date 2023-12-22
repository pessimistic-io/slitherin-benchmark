// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0 <0.9.0;


import "./UpdateStateStorage.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IVault.sol";

contract ForcedAction is UpdateStateStorage{

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    uint256 constant public UONE = 1E18;
    int256 constant public  ONE = 1E18;
    int256 constant public  FUNDING_PRECISION = 1E8;

    IVault immutable public vault;

    event LogBalanceChange(
        address account,
        address asset,
        int256 balanceDiff
    );

    event LogPositionChange(
        address account,
        bytes32 symbolId,
        int64 volume,
        int64 lastCumulativeFundingPerVolume,
        int128 entryCost
    );

    constructor(address _vault) {
        vault = IVault(_vault);
    }

    function forcedWithdraw(address asset) _reentryLock_ external
    {
        require(isFreezed, "forced: only at freezed");
        address account = msg.sender;
        require(holdPositions[account] == 0, "forced: exist active positions");
        int256 balance = balances[account][asset];
        require(balance>0, "forced: not enough balance");

        balances[account][asset] = 0;
        emit LogBalanceChange(account, asset, -balance);

        if (asset == address(0)) {
            vault.transferOut(account, asset, balance.itou());
        } else {
            vault.transferOut(account, asset, balance.itou().rescale(18, IERC20(asset).decimals()));
        }
    }

    function _updatePnlAndFunding(address account, AccountPosition memory pos, SymbolInfo memory symbolInfo, SymbolStats memory symbolStats, int32 tradeVolume) internal {
        int256 pricePrecision = symbolInfo.pricePrecision.utoi();
        int256 volumePrecision = symbolInfo.volumePrecision.utoi();
        int256 balanceDiff;
        {
            int256 funding = -int256(symbolStats.cumulativeFundingPerVolume - pos.lastCumulativeFundingPerVolume) * ONE / pricePrecision / volumePrecision / FUNDING_PRECISION * int256(pos.volume) * ONE / volumePrecision / ONE;
            int256 pnl = - (int256(pos.entryCost) * ONE * int256(tradeVolume).abs() / int256(pos.volume).abs() / pricePrecision / volumePrecision +
                 int256(tradeVolume) * ONE / volumePrecision * int256(symbolStats.indexPrice) * ONE / pricePrecision / ONE);
            balanceDiff = funding + pnl;
        }
        int256 entryCostAfter = int256(pos.entryCost) - int256(pos.entryCost) * int256(tradeVolume).abs() / int256(pos.volume).abs();

        address asset = symbolInfo.marginAsset;
        bytes32 symbolId = symbolInfo.symbolId;
        balances[account][asset] += balanceDiff;
        emit LogBalanceChange(account, asset, balanceDiff);

        accountPositions[account][symbolId] = AccountPosition({
                    volume: int64(pos.volume + tradeVolume),
                    lastCumulativeFundingPerVolume: symbolStats.cumulativeFundingPerVolume,
                    entryCost: int128(entryCostAfter)
                });
        emit LogPositionChange(account, symbolId, int64(pos.volume + tradeVolume), symbolStats.cumulativeFundingPerVolume, int128(entryCostAfter));
    }

    function forceTrade(address target, bytes32 symbolId, int32 tradeVolume) external _reentryLock_ {
        require(isFreezed, "forced: only at freezed");

        address account = msg.sender;
        AccountPosition memory pos = accountPositions[account][symbolId];
        AccountPosition memory targetPos = accountPositions[target][symbolId];

        require(pos.volume != 0 && targetPos.volume != 0, "forced: no position");
        require((pos.volume > 0 && tradeVolume < 0 && int256(pos.volume).abs() >= int256(tradeVolume).abs()) ||
            (pos.volume < 0 && tradeVolume > 0 && int256(pos.volume).abs() <= int256(tradeVolume).abs()), "forced: only close position");

        SymbolInfo memory symbolInfo = symbols[symbolId];
        SymbolStats memory symbolStats = symbolStats[symbolId];
        require(int256(tradeVolume) % symbolInfo.minVolume.utoi() == 0, "forced: invalid trade volume");

        if (pos.volume == -tradeVolume) {
                holdPositions[account] -= 1;
        }
        if (targetPos.volume == tradeVolume) {
                holdPositions[target] -= 1;
        }

        _updatePnlAndFunding(account, pos, symbolInfo, symbolStats, tradeVolume);
        _updatePnlAndFunding(target, targetPos, symbolInfo, symbolStats, -tradeVolume);
    }

}
