// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";

import "./IGambitTradingStorageV1.sol";
import "./IGambitPairInfosV1.sol";
import "./IGambitReferralsV1.sol";
import "./IGambitStakingV1.sol";

import "./IStableCoinDecimals.sol";

import "./GambitErrorsV1.sol";

import "./GambitTradingCallbacksV1StorageLayout.sol";

/**
 * @dev GambitTradingCallbacksV1Base implements events and modifiers and common functions
 */
abstract contract GambitTradingCallbacksV1Base is
    GambitTradingCallbacksV1StorageLayout
{
    // Custom data types
    struct AggregatorAnswer {
        uint orderId;
        uint price;
        uint conf;
        uint confMultiplierP;
    }

    // Useful to avoid stack too deep errors
    struct Values {
        uint posUsdc; // 1e6 (USDC) or 1e18 (DAI)
        uint levPosUsdc; // 1e6 (USDC) or 1e18 (DAI)
        uint tokenPriceUsdc; // 1e10
        int profitP; // 1e10
        uint price; // 1e10
        uint liqPrice; // 1e10
        uint usdcSentToTrader; // 1e6 (USDC) or 1e18 (DAI)
        uint reward1; // tmp value
        uint reward2; // tmp value
        uint reward3; // tmp value
    }

    // Events
    event MarketExecuted(
        uint indexed orderId,
        IGambitTradingStorageV1.Trade t,
        bool open,
        uint price,
        uint priceImpactP,
        uint positionSizeUsdc,
        int percentProfit,
        uint usdcSentToTrader
    );

    event LimitExecuted(
        uint indexed orderId,
        uint limitIndex,
        IGambitTradingStorageV1.Trade t,
        address indexed nftHolder,
        IGambitTradingStorageV1.LimitOrder orderType,
        uint price,
        uint priceImpactP,
        uint positionSizeUsdc,
        int percentProfit,
        uint usdcSentToTrader
    );

    event MarketOpenCanceled(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex
    );
    event MarketCloseCanceled(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        uint index
    );

    event SlUpdated(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint newSl
    );
    event SlCanceled(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        uint index
    );

    event CollateralRemoved(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint amount, // removed collateral amount with fee deducted
        uint newLeverage // updated leverage
    );

    event CollateralRemoveCanceled(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        uint index
    );

    event Pause(bool paused);
    event Done(bool done);

    event ClosingFeeSharesPUpdated(uint usdcVaultFeeP, uint sssFeeP);

    event DevGovFeeCharged(address indexed trader, uint valueUsdc);
    event OracleFeeCharged(address indexed trader, uint valueUsdc);
    event ReferralFeeCharged(address indexed trader, uint valueUsdc);
    event UsdcVaultFeeCharged(address indexed trader, uint valueUsdc);
    event SssFeeCharged(address indexed trader, uint valueUsdc);

    // Modifiers
    modifier onlyGov() {
        if (msg.sender != storageT.gov()) revert GambitErrorsV1.NotGov();
        _;
    }
    modifier onlyPriceAggregator() {
        if (msg.sender != address(storageT.priceAggregator()))
            revert GambitErrorsV1.NotAggregator();
        _;
    }
    modifier notDone() {
        if (isDone) revert GambitErrorsV1.Done();
        _;
    }

    // Manage params
    function setClosingFeeSharesP(
        uint _usdcVaultFeeP,
        uint _sssFeeP
    ) external onlyGov {
        if (_usdcVaultFeeP + _sssFeeP != 100)
            revert GambitErrorsV1.WrongParams();

        usdcVaultFeeP = _usdcVaultFeeP;
        sssFeeP = _sssFeeP;

        emit ClosingFeeSharesPUpdated(_usdcVaultFeeP, _sssFeeP);
    }

    // Manage state
    function pause() external onlyGov {
        isPaused = !isPaused;

        emit Pause(isPaused);
    }

    function done() external onlyGov {
        isDone = !isDone;

        emit Done(isDone);
    }

    // internal helpers

    // Shared code between market & limit callbacks
    function registerTrade(
        IGambitTradingStorageV1.Trade memory trade,
        uint nftId,
        uint limitIndex
    ) internal returns (IGambitTradingStorageV1.Trade memory, uint) {
        AggregatorInterfaceV6_2 aggregator = storageT.priceAggregator();
        IGambitPairsStorageV1 pairsStored = aggregator.pairsStorage();

        Values memory v;

        v.levPosUsdc = (trade.positionSizeUsdc * trade.leverage) / 1e18;
        v.tokenPriceUsdc = aggregator.tokenPriceUsdc();

        // 1. Charge referral fee (if applicable) and send USDC amount to vault
        if (referrals.getTraderReferrer(trade.trader) != address(0)) {
            // Use this variable to store lev pos usdc for dev/gov fees after referral fees
            // and before volumeReferredUsdc increases
            v.posUsdc =
                (v.levPosUsdc *
                    (100 *
                        PRECISION -
                        referrals.getPercentOfOpenFeeP(trade.trader))) /
                100 /
                PRECISION;

            (uint reward, bool enabledUsdcReward) = referrals
                .distributePotentialReward(
                    trade.trader,
                    v.levPosUsdc,
                    pairsStored.pairOpenFeeP(trade.pairIndex),
                    v.tokenPriceUsdc
                );
            // referal fee in USDC
            v.reward1 = reward;

            if (enabledUsdcReward) {
                // Transfer USDC to Referrals contract if referral is rewarded in USDC
                storageT.transferUsdc(
                    address(storageT),
                    address(referrals),
                    v.reward1
                );
            } else {
                // Convert referal fee from USDC to token value
                v.reward2 =
                    (v.reward1 * (10 ** (18 - usdcDecimals())) * PRECISION) /
                    v.tokenPriceUsdc;
                storageT.handleTokens(address(referrals), v.reward2, true);
            }
            trade.positionSizeUsdc -= v.reward1;

            emit ReferralFeeCharged(trade.trader, v.reward1);
        }

        // 2.1. Charge opening fee - referral fee (if applicable)
        v.reward2 = storageT.handleDevGovFees(
            trade.pairIndex, // _pairIndex
            (v.posUsdc > 0 ? v.posUsdc : v.levPosUsdc), // _leveragedPositionSize
            true // _fullFee
        );

        trade.positionSizeUsdc -= v.reward2;

        emit DevGovFeeCharged(trade.trader, v.reward2);

        // NOTE: we don't charge oracle fee when open trade now, but it will be chaged in the future.
        // // 2.2. Charge oracle fee
        // uint oracleFee = pairsStored.pairOracleFee(trade.pairIndex);
        // storageT.handleGovFee(oracleFee);

        // trade.positionSizeUsdc -= oracleFee;

        // emit OracleFeeCharged(trade.trader, oracleFee);

        // 3. Set trade final details
        trade.index = storageT.firstEmptyTradeIndex(
            trade.trader,
            trade.pairIndex
        );
        trade.initialPosToken =
            (trade.positionSizeUsdc *
                (10 ** (18 - usdcDecimals())) *
                PRECISION) /
            v.tokenPriceUsdc;

        trade.tp = correctTp(
            trade.openPrice,
            trade.leverage,
            trade.tp,
            trade.buy
        );
        trade.sl = correctSl(
            trade.openPrice,
            trade.leverage,
            trade.sl,
            trade.buy
        );

        // 4. Call other contracts
        pairInfos.storeTradeInitialAccFees(
            trade.trader,
            trade.pairIndex,
            trade.index,
            trade.buy
        );
        pairsStored.updateGroupCollateral(
            trade.pairIndex,
            trade.positionSizeUsdc,
            trade.buy,
            true
        );

        // 5. Store final trade in storage contract
        storageT.storeTrade(
            trade,
            IGambitTradingStorageV1.TradeInfo({
                tokenId: 0,
                tokenPriceUsdc: v.tokenPriceUsdc,
                openInterestUsdc: (trade.positionSizeUsdc * trade.leverage) /
                    1e18,
                tpLastUpdated: 0,
                slLastUpdated: 0,
                beingMarketClosed: false
            })
        );

        return (trade, v.tokenPriceUsdc);
    }

    //
    function unregisterTrade(
        IGambitTradingStorageV1.Trade memory trade,
        bool marketOrder,
        int percentProfit, // PRECISION // = currentPercentProfit
        uint currentUsdcPos, // 1e6 (USDC) or 1e18 (DAI) // = v.levPosUsdc / t.leverage
        uint initialUsdcPos, // 1e6 (USDC) or 1e18 (DAI) // = i.openInterestUsdc / t.leverage
        uint closingFeeUsdc, // 1e6 (USDC) or 1e18 (DAI) // = pairsStorage.pairCloseFeeP()
        uint tokenPriceUsdc // PRECISION
    ) internal returns (uint usdcSentToTrader) {
        // 1. Calculate net PnL (after all closing fees)
        // 1e6 (USDC) or 1e18 (DAI)
        usdcSentToTrader = pairInfos.getTradeValue(
            trade.trader,
            trade.pairIndex,
            trade.index,
            trade.buy,
            currentUsdcPos,
            trade.leverage,
            percentProfit,
            closingFeeUsdc
        );

        Values memory v;

        // 2.1 Vault reward
        v.reward2 = (closingFeeUsdc * usdcVaultFeeP) / 100;
        storageT.transferUsdc(address(storageT), address(this), v.reward2);
        storageT.vault().distributeReward(v.reward2);

        emit UsdcVaultFeeCharged(trade.trader, v.reward2);

        // 2.2 SSS reward
        v.reward3 = (closingFeeUsdc * sssFeeP) / 100;
        distributeStakingReward(trade.trader, v.reward3);

        // 2.3 Calculate remaining collateral (after close fee)
        uint usdcLeftInStorage = currentUsdcPos - v.reward2 - v.reward3;

        // 2.4 Take USDC from vault if winning trade
        // or send USDC to vault if losing trade
        if (usdcSentToTrader > usdcLeftInStorage) {
            storageT.vault().sendAssets(
                usdcSentToTrader - usdcLeftInStorage,
                trade.trader
            );
            storageT.transferUsdc(
                address(storageT),
                trade.trader,
                usdcLeftInStorage
            );
        } else {
            sendToVault(usdcLeftInStorage - usdcSentToTrader, trade.trader);
            storageT.transferUsdc(
                address(storageT),
                trade.trader,
                usdcSentToTrader
            );
        }

        // 3. Calls to other contracts
        storageT.priceAggregator().pairsStorage().updateGroupCollateral(
            trade.pairIndex,
            initialUsdcPos,
            trade.buy,
            false
        );

        // 4. Unregister trade
        storageT.unregisterTrade(trade.trader, trade.pairIndex, trade.index);
    }

    // Utils
    function currentPercentProfit(
        uint openPrice,
        uint currentPrice,
        bool buy,
        uint leverage
    ) internal pure returns (int p) {
        int maxPnlP = int(MAX_GAIN_P) * int(PRECISION); // 최대 수익 제한

        p =
            ((
                buy
                    ? int(currentPrice) - int(openPrice)
                    : int(openPrice) - int(currentPrice)
            ) *
                100 *
                int(PRECISION) *
                int(leverage)) /
            int(openPrice) /
            1e18;

        p = p > maxPnlP ? maxPnlP : p;
    }

    function correctTp(
        uint openPrice,
        uint leverage,
        uint tp,
        bool buy
    ) internal pure returns (uint) {
        if (
            tp == 0 ||
            currentPercentProfit(openPrice, tp, buy, leverage) ==
            int(MAX_GAIN_P) * int(PRECISION)
        ) {
            uint tpDiff = ((openPrice * MAX_GAIN_P) * 1e18) / leverage / 100;

            return
                buy ? openPrice + tpDiff : tpDiff <= openPrice
                    ? openPrice - tpDiff
                    : 0;
        }

        return tp;
    }

    function correctSl(
        uint openPrice,
        uint leverage,
        uint sl,
        bool buy
    ) internal pure returns (uint) {
        if (
            sl > 0 &&
            currentPercentProfit(openPrice, sl, buy, leverage) <
            int(MAX_SL_P) * int(PRECISION) * -1
        ) {
            uint slDiff = ((openPrice * MAX_SL_P) * 1e18) / leverage / 100;

            return buy ? openPrice - slDiff : openPrice + slDiff;
        }

        return sl;
    }

    function marketExecutionPrice(
        uint price,
        uint conf,
        uint confMultiplierP,
        uint spreadReductionP,
        bool long
    ) internal pure returns (uint) {
        uint priceDiff = (conf *
            (confMultiplierP - (confMultiplierP * spreadReductionP) / 100)) /
            100 /
            PRECISION;

        return long ? price + priceDiff : price - priceDiff;
    }

    function distributeStakingReward(address trader, uint amountUsdc) internal {
        storageT.transferUsdc(address(storageT), address(this), amountUsdc);
        staking.distributeRewardUsdc(amountUsdc);
        emit SssFeeCharged(trader, amountUsdc);
    }

    function sendToVault(uint amountUsdc, address trader) internal {
        storageT.transferUsdc(address(storageT), address(this), amountUsdc);
        storageT.vault().receiveAssets(amountUsdc, trader);
    }

    function usdcDecimals() public pure virtual returns (uint8);
}

