// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./TransferHelper.sol";
import "./OnlySelf.sol";
import "./IVault.sol";
import "./ITradingCore.sol";
import "./IPriceFacade.sol";
import "./IPairsManager.sol";
import "./ITradingPortal.sol";
import "./ISlippageManager.sol";
import "./LibTrading.sol";
import "./LibTradingCore.sol";
import "./LibAccessControlEnumerable.sol";
import {ITradingCoreError} from "./Errors.sol";
import "./SignedMath.sol";
import {ZERO, ONE, UC, uc, into} from "./UC.sol";

contract TradingCoreFacet is ITradingCore, ITradingCoreError, OnlySelf {

    using SignedMath for int256;
    using TransferHelper for address;

    function updatePairPositionInfo(
        address pairBase, uint userPrice, uint marketPrice, uint qty, bool isLong, bool isOpen
    ) external onlySelf override returns (int256 longAccFundingFeePerShare){
        LibTradingCore.TradingCoreStorage storage tcs = LibTradingCore.tradingCoreStorage();
        PairPositionInfo storage ppi = tcs.pairPositionInfos[pairBase];
        _updatePairPositionInfo(ppi, pairBase, marketPrice);

        longAccFundingFeePerShare = ppi.longAccFundingFeePerShare;
        _updatePairQtyAndAvgPrice(tcs, ppi, pairBase, qty, userPrice, isOpen, isLong);
        emit UpdatePairPositionInfo(
            pairBase, ppi.lastFundingFeeBlock, ppi.longQty, ppi.shortQty,
            longAccFundingFeePerShare, ppi.lpLongAvgPrice, ppi.lpShortAvgPrice
        );
        return longAccFundingFeePerShare;
    }

    function updatePairPositionInfo(address pairBase) external override {
        (uint256 marketPrice,) = IPriceFacade(address(this)).getPriceFromCacheOrOracle(pairBase);
        LibTradingCore.TradingCoreStorage storage tcs = LibTradingCore.tradingCoreStorage();
        PairPositionInfo storage ppi = tcs.pairPositionInfos[pairBase];
        _updatePairPositionInfo(ppi, pairBase, marketPrice);
        emit UpdatePairAccFundingFeePerShare(pairBase, ppi.lastFundingFeeBlock, ppi.longAccFundingFeePerShare, marketPrice);
    }

    function addMarginPoolBalance(address token, uint256 amount) external override payable {
        if (!IVault(address(this)).getTokenForTrading(token).switchOn) revert UnsupportedMarginToken(token);
        token.transferFrom(msg.sender, amount);
        LibTrading.increaseOpenTradeAmount(LibTrading.tradingStorage(), token, amount);
        emit AddMarginPoolBalance(msg.sender, token, amount);
    }

    function getPairQty(address pairBase) external view override returns (PairQty memory) {
        ITradingCore.PairPositionInfo memory ppi = LibTradingCore.tradingCoreStorage().pairPositionInfos[pairBase];
        return PairQty(ppi.longQty, ppi.shortQty);
    }

    function slippagePrice(address pairBase, uint256 marketPrice, uint256 qty, bool isLong) external view returns (uint256) {
        PairPositionInfo memory ppi = LibTradingCore.tradingCoreStorage().pairPositionInfos[pairBase];
        return slippagePrice(
            PairQty(ppi.longQty, ppi.shortQty), IPairsManager(address(this)).getPairSlippageConfig(pairBase), marketPrice, qty, isLong
        );
    }

    function slippagePrice(
        PairQty memory pairQty,
        ISlippageManager.SlippageConfig memory sc,
        uint256 marketPrice, uint256 qty, bool isLong
    ) public pure override returns (uint256) {
        if (isLong) {
            uint slippage = sc.slippageLongP;
            if (sc.slippageType == ISlippageManager.SlippageType.ONE_PERCENT_DEPTH) {
                // slippage = (longQty + qty) * price / depthAboveUsd
                slippage = (pairQty.longQty + qty) * marketPrice * 1e4 / sc.onePercentDepthAboveUsd + 1;
            } else if (sc.slippageType == ISlippageManager.SlippageType.NET_POSITION && pairQty.longQty + qty >= pairQty.shortQty) {
                // slippage = max((longQty + qty - shortQty) * price / depthAboveUsd + 1, slippageLongP)
                uint256 s = (pairQty.longQty + qty - pairQty.shortQty) * marketPrice * 1e4 / sc.onePercentDepthAboveUsd + 1;
                slippage = s > sc.slippageLongP ? s : sc.slippageLongP;
            }
            return marketPrice * (1e4 + slippage) / 1e4;
        } else {
            uint slippage = sc.slippageShortP;
            if (sc.slippageType == ISlippageManager.SlippageType.ONE_PERCENT_DEPTH) {
                // slippage = (shortQty + qty) * price / depthBelowUsd
                slippage = (pairQty.shortQty + qty) * marketPrice * 1e4 / sc.onePercentDepthBelowUsd + 1;
            } else if (sc.slippageType == ISlippageManager.SlippageType.NET_POSITION && pairQty.shortQty + qty >= pairQty.longQty) {
                // slippage = max((shortQty + qty - longQty) * price / depthAboveUsd + 1, slippageLongP)
                uint256 s = (pairQty.shortQty + qty - pairQty.longQty) * marketPrice * 1e4 / sc.onePercentDepthBelowUsd + 1;
                slippage = s > sc.slippageShortP ? s : sc.slippageShortP;
            }
            return marketPrice * (1e4 - slippage) / 1e4;
        }
    }

    function triggerPrice(address pairBase, uint256 limitPrice, uint256 qty, bool isLong) external view returns (uint256) {
        PairPositionInfo memory ppi = LibTradingCore.tradingCoreStorage().pairPositionInfos[pairBase];
        return triggerPrice(
            PairQty(ppi.longQty, ppi.shortQty), IPairsManager(address(this)).getPairSlippageConfig(pairBase), limitPrice, qty, isLong
        );
    }

    function triggerPrice(
        PairQty memory pairQty,
        ISlippageManager.SlippageConfig memory sc,
        uint256 limitPrice, uint256 qty, bool isLong
    ) public pure override returns (uint256) {
        if (isLong) {
            uint slippage = sc.slippageLongP;
            if (sc.slippageType == ISlippageManager.SlippageType.ONE_PERCENT_DEPTH) {
                // slippage = (longQty + qty) * price / depthAboveUsd
                slippage = (pairQty.longQty + qty) * limitPrice * 1e4 / sc.onePercentDepthAboveUsd + 1;
            } else if (sc.slippageType == ISlippageManager.SlippageType.NET_POSITION && pairQty.longQty + qty >= pairQty.shortQty) {
                // slippage = max((longQty + qty - shortQty) * price / depthAboveUsd + 1, slippageLongP)
                uint256 s = (pairQty.longQty + qty - pairQty.shortQty) * limitPrice * 1e4 / sc.onePercentDepthAboveUsd + 1;
                slippage = s > sc.slippageLongP ? s : sc.slippageLongP;
            }
            return limitPrice * (1e4 - slippage) / 1e4;
        } else {
            uint slippage = sc.slippageShortP;
            if (sc.slippageType == ISlippageManager.SlippageType.ONE_PERCENT_DEPTH) {
                // slippage = (shortQty + qty) * price / depthBelowUsd
                slippage = (pairQty.shortQty + qty) * limitPrice * 1e4 / sc.onePercentDepthBelowUsd + 1;
            } else if (sc.slippageType == ISlippageManager.SlippageType.NET_POSITION && pairQty.shortQty + qty >= pairQty.longQty) {
                // slippage = max((shortQty + qty - longQty) * price / depthAboveUsd + 1, slippageLongP)
                uint256 s = (pairQty.shortQty + qty - pairQty.longQty) * limitPrice * 1e4 / sc.onePercentDepthBelowUsd + 1;
                slippage = s > sc.slippageShortP ? s : sc.slippageShortP;
            }
            return limitPrice * (1e4 + slippage) / 1e4;
        }
    }

    function lastLongAccFundingFeePerShare(address pairBase) external view override returns (int256 longAccFundingFeePerShare) {
        PairPositionInfo memory ppi = LibTradingCore.tradingCoreStorage().pairPositionInfos[pairBase];
        longAccFundingFeePerShare = ppi.longAccFundingFeePerShare;
        if (Constants.arbSys.arbBlockNumber() > ppi.lastFundingFeeBlock) {
            int256 fundingFeeR = LibTradingCore.fundingFeeRate(ppi, pairBase);
            longAccFundingFeePerShare += fundingFeeR * (- 1) * int256(Constants.arbSys.arbBlockNumber() - ppi.lastFundingFeeBlock);
        }
        return longAccFundingFeePerShare;
    }

    function _updatePairPositionInfo(PairPositionInfo storage ppi, address pairBase, uint marketPrice) private {
        if (ppi.longQty > 0 || ppi.shortQty > 0) {
            uint256 lpReceiveFundingFeeUsd = _updateFundingFee(ppi, pairBase, marketPrice);
            if (lpReceiveFundingFeeUsd > 0) {
                ITradingPortal(address(this)).settleLpFundingFee(lpReceiveFundingFeeUsd);
            }
        } else {
            ppi.lastFundingFeeBlock = Constants.arbSys.arbBlockNumber();
        }
    }

    function _updateFundingFee(
        ITradingCore.PairPositionInfo storage ppi, address pairBase, uint256 marketPrice
    ) private returns (uint256 lpReceiveFundingFeeUsd){
        int256 oldLongAccFundingFeePerShare = ppi.longAccFundingFeePerShare;
        bool needTransfer = _updateAccFundingFeePerShare(ppi, pairBase);
        if (needTransfer) {
            int256 longReceiveFundingFeeUsd = int256(ppi.longQty * marketPrice) * (ppi.longAccFundingFeePerShare - oldLongAccFundingFeePerShare) / 1e18;
            int256 shortReceiveFundingFeeUsd = int256(ppi.shortQty * marketPrice) * (ppi.longAccFundingFeePerShare - oldLongAccFundingFeePerShare) * (- 1) / 1e18;
            if (ppi.longQty > ppi.shortQty) {
                require(
                    (shortReceiveFundingFeeUsd == 0 && longReceiveFundingFeeUsd == 0) ||
                    longReceiveFundingFeeUsd < 0 && shortReceiveFundingFeeUsd >= 0 && longReceiveFundingFeeUsd.abs() > shortReceiveFundingFeeUsd.abs(),
                    "TradingCoreFacet: Funding fee calculation error. [LONG]"
                );
                lpReceiveFundingFeeUsd = (longReceiveFundingFeeUsd + shortReceiveFundingFeeUsd).abs();
            } else {
                require(
                    (shortReceiveFundingFeeUsd == 0 && longReceiveFundingFeeUsd == 0) ||
                    (shortReceiveFundingFeeUsd < 0 && longReceiveFundingFeeUsd >= 0 && shortReceiveFundingFeeUsd.abs() > longReceiveFundingFeeUsd.abs()),
                    "TradingCoreFacet: Funding fee calculation error. [SHORT]"
                );
                lpReceiveFundingFeeUsd = (shortReceiveFundingFeeUsd + longReceiveFundingFeeUsd).abs();
            }
        }
        return lpReceiveFundingFeeUsd;
    }

    function _updateAccFundingFeePerShare(
        ITradingCore.PairPositionInfo storage ppi, address pairBase
    ) private returns (bool){
        if (Constants.arbSys.arbBlockNumber() <= ppi.lastFundingFeeBlock) {
            return false;
        }
        int256 fundingFeeR = LibTradingCore.fundingFeeRate(ppi, pairBase);
        // (ppi.longQty > ppi.shortQty) & (fundingFeeRate > 0) & (Long - money <==> Short + money) & (longAcc < 0)
        // (ppi.longQty < ppi.shortQty) & (fundingFeeRate < 0) & (Long + money <==> Short - money) & (longAcc > 0)
        // (ppi.longQty == ppi.shortQty) & (fundingFeeRate == 0)
        ppi.longAccFundingFeePerShare += fundingFeeR * (- 1) * int256(Constants.arbSys.arbBlockNumber() - ppi.lastFundingFeeBlock);
        ppi.lastFundingFeeBlock = Constants.arbSys.arbBlockNumber();
        return true;
    }

    function _updatePairQtyAndAvgPrice(
        LibTradingCore.TradingCoreStorage storage tcs,
        ITradingCore.PairPositionInfo storage ppi,
        address pairBase, uint256 qty,
        uint256 userPrice, bool isOpen, bool isLong
    ) private {
        if (isOpen) {
            if (ppi.longQty == 0 && ppi.shortQty == 0) {
                ppi.pairBase = pairBase;
                ppi.pairIndex = uint16(tcs.hasPositionPairs.length);
                tcs.hasPositionPairs.push(pairBase);
            }
            if (isLong) {
                ppi.lpShortAvgPrice = uint64((ppi.lpShortAvgPrice * ppi.longQty + userPrice * qty) / (ppi.longQty + qty));
                // LP Reduce position, No change in average price
                ppi.longQty += qty;
            } else {
                ppi.lpLongAvgPrice = uint64((ppi.lpLongAvgPrice * ppi.shortQty + userPrice * qty) / (ppi.shortQty + qty));
                // LP Reduce position, No change in average price
                ppi.shortQty += qty;
            }
        } else {
            if (isLong) {
                if (ppi.longQty == qty) {
                    ppi.lpShortAvgPrice = 0;
                } else {
                    ppi.lpShortAvgPrice = uint64((ppi.lpShortAvgPrice * ppi.longQty - userPrice * qty) / (ppi.longQty - qty));
                }
                ppi.longQty -= qty;
            } else {
                if (ppi.shortQty == qty) {
                    ppi.lpLongAvgPrice = 0;
                } else {
                    ppi.lpLongAvgPrice = uint64((ppi.lpLongAvgPrice * ppi.shortQty - userPrice * qty) / (ppi.shortQty - qty));
                }
                ppi.shortQty -= qty;
            }
            if (ppi.longQty == 0 && ppi.shortQty == 0) {
                address[] storage pairs = tcs.hasPositionPairs;
                uint lastIndex = pairs.length - 1;
                uint removeIndex = ppi.pairIndex;
                if (lastIndex != removeIndex) {
                    address lastPair = pairs[lastIndex];
                    pairs[removeIndex] = lastPair;
                    tcs.pairPositionInfos[lastPair].pairIndex = uint16(removeIndex);
                }
                pairs.pop();
                delete tcs.pairPositionInfos[pairBase];
            }
        }
    }

    function lpUnrealizedPnlTotalUsd() public view returns (int256 totalUsd) {
        LibTradingCore.TradingCoreStorage storage tcs = LibTradingCore.tradingCoreStorage();
        address[] memory hasPositionPairs = tcs.hasPositionPairs;
        for (UC i = ZERO; i < uc(hasPositionPairs.length); i = i + ONE) {
            address pairBase = hasPositionPairs[i.into()];
            PairPositionInfo memory ppi = tcs.pairPositionInfos[pairBase];
            (uint256 price,) = IPriceFacade(address(this)).getPriceFromCacheOrOracle(pairBase);
            // LP Short Position
            if (ppi.longQty > 0) {
                totalUsd += int256(ppi.longQty) * (int256(uint256(ppi.lpShortAvgPrice)) - int256(price));
            }
            // LP Long position
            if (ppi.shortQty > 0) {
                totalUsd += int256(ppi.shortQty) * (int256(price) - int256(uint256(ppi.lpLongAvgPrice)));
            }
        }
        return totalUsd;
    }

    function lpUnrealizedPnlUsd() external view override returns (int256 totalUsd, LpMarginTokenUnPnl[] memory tokenUnPnlUsd) {
        totalUsd = lpUnrealizedPnlTotalUsd();
        MarginPct[] memory marginPct = _tokenMarginPct();
        tokenUnPnlUsd = new LpMarginTokenUnPnl[](marginPct.length);
        for (UC i = ZERO; i < uc(marginPct.length); i = i + ONE) {
            MarginPct memory mp = marginPct[i.into()];
            tokenUnPnlUsd[i.into()] = LpMarginTokenUnPnl(mp.token, totalUsd * int256(mp.pct) / int256(1e4));
        }
        return (totalUsd, tokenUnPnlUsd);
    }

    function lpUnrealizedPnlUsd(address targetToken) external view override returns (int256 totalUsd, int256 tokenUsd) {
        LibTrading.TradingStorage storage ts = LibTrading.tradingStorage();
        totalUsd = lpUnrealizedPnlTotalUsd();
        uint256 totalMarginUsd;
        uint256 tokenMarginUsd;
        if (ts.openTradeTokenIns.length == 0) {
            return (totalUsd, 0);
        }
        UC size = uc(ts.openTradeTokenIns.length);
        for (UC i = ZERO; i < size; i = i + ONE) {
            address token = ts.openTradeTokenIns[i.into()];
            if (ts.openTradeAmountIns[token] > 0) {
                IVault.MarginToken memory mt = IVault(address(this)).getTokenForTrading(token);
                uint marginUsd = mt.price * ts.openTradeAmountIns[token] * 1e10 / (10 ** mt.decimals);
                totalMarginUsd += marginUsd;
                if (token == targetToken) {
                    tokenMarginUsd = marginUsd;
                }
            }
        }
        return (totalUsd, totalUsd * int256(tokenMarginUsd) / int256(totalMarginUsd));
    }

    function _tokenMarginPct() private view returns (MarginPct[] memory marginPct) {
        LibTrading.TradingStorage storage ts = LibTrading.tradingStorage();

        ITrading.MarginBalance[] memory balances = new ITrading.MarginBalance[](ts.openTradeTokenIns.length);
        uint256 totalMarginUsd;
        UC index = ZERO;
        for (UC i = ZERO; i < uc(ts.openTradeTokenIns.length); i = i + ONE) {
            address token = ts.openTradeTokenIns[i.into()];
            if (ts.openTradeAmountIns[token] > 0) {
                IVault.MarginToken memory mt = IVault(address(this)).getTokenForTrading(token);
                uint marginUsd = mt.price * ts.openTradeAmountIns[token] * 1e10 / (10 ** mt.decimals);
                balances[index.into()] = ITrading.MarginBalance(token, mt.price, mt.decimals, marginUsd);
                totalMarginUsd += marginUsd;
                index = index + ONE;
            }
        }
        marginPct = new MarginPct[](index.into());
        uint256 points = 1e4;
        for (UC i = ONE; i < index; i = i + ONE) {
            // tokenMarginUsd * 1e4 / totalMarginUsd;
            ITrading.MarginBalance memory mb = balances[i.into()];
            uint256 share = mb.balanceUsd * 1e4 / totalMarginUsd;
            marginPct[i.into()] = MarginPct(mb.token, share);
            points -= share;
        }
        marginPct[0] = MarginPct(balances[0].token, points);
        return marginPct;
    }

    function lpNotionalUsd() external view override returns (uint256 notionalUsd) {
        LibTradingCore.TradingCoreStorage storage tcs = LibTradingCore.tradingCoreStorage();
        address[] memory hasPositionPairs = tcs.hasPositionPairs;
        for (UC i = ZERO; i < uc(hasPositionPairs.length); i = i + ONE) {
            address pairBase = hasPositionPairs[i.into()];
            PairPositionInfo memory ppi = tcs.pairPositionInfos[pairBase];
            (uint256 price,) = IPriceFacade(address(this)).getPriceFromCacheOrOracle(pairBase);
            if (ppi.longQty > ppi.shortQty) {
                notionalUsd += (ppi.longQty - ppi.shortQty) * price;
            } else {
                notionalUsd += (ppi.shortQty - ppi.longQty) * price;
            }
        }
        return notionalUsd;
    }
}

