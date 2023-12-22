// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;
import { IAccountBalance } from "./IAccountBalance.sol";
import { IBaseToken } from "./IBaseToken.sol";
import { IIndexPrice } from "./IIndexPrice.sol";
import { IClearingHouse } from "./IClearingHouse.sol";
import { IClearingHouseConfig } from "./IClearingHouseConfig.sol";
import { IVPool } from "./IVPool.sol";
import { IVault } from "./IVault.sol";
import { IMarketRegistry } from "./IMarketRegistry.sol";
import { IInsuranceFund } from "./IInsuranceFund.sol";
import { FullMath } from "./FullMath.sol";
import { PerpSafeCast } from "./PerpSafeCast.sol";
import { PerpMath } from "./PerpMath.sol";
import { SafeMathUpgradeable } from "./SafeMathUpgradeable.sol";
import { SignedSafeMathUpgradeable } from "./SignedSafeMathUpgradeable.sol";
import { DataTypes } from "./DataTypes.sol";
import { UniswapV3Broker } from "./UniswapV3Broker.sol";

library GenericLogic {
    using SafeMathUpgradeable for uint256;
    using SignedSafeMathUpgradeable for int256;
    using PerpSafeCast for uint256;
    using PerpSafeCast for uint128;
    using PerpSafeCast for int256;
    using PerpMath for uint256;
    using PerpMath for uint160;
    using PerpMath for uint128;
    using PerpMath for int256;

    uint256 internal constant _FULLY_CLOSED_RATIO = 1e18;

    //internal struct
    struct InternalCheckSlippageParams {
        bool isBaseToQuote;
        bool isExactInput;
        uint256 base;
        uint256 quote;
        uint256 oppositeAmountBound;
    }

    struct InternalUpdateInfoMultiplierVars {
        bool isBaseToQuote;
        int256 deltaBase;
        uint256 newDeltaBase;
        uint256 newDeltaQuote;
        uint256 newLongPositionSizeRate;
        uint256 newShortPositionSizeRate;
        int256 costDeltaQuote;
        bool isEnoughFund;
    }

    //event

    event FundingPaymentSettled(address indexed trader, address indexed baseToken, int256 fundingPayment);

    event MultiplierCostSpend(address indexed baseToken, int256 cost);

    /// @notice Emitted when taker's position is being changed
    /// @param trader Trader address
    /// @param baseToken The address of virtual base token(ETH, BTC, etc...)
    /// @param exchangedPositionSize The actual amount swap to uniswapV3 pool
    /// @param exchangedPositionNotional The cost of position, include fee
    /// @param fee The fee of open/close position
    /// @param openNotional The cost of open/close position, < 0: long, > 0: short
    /// @param realizedPnl The realized Pnl after open/close position
    /// @param sqrtPriceAfterX96 The sqrt price after swap, in X96
    event PositionChanged(
        address indexed trader,
        address indexed baseToken,
        int256 exchangedPositionSize,
        int256 exchangedPositionNotional,
        uint256 fee,
        int256 openNotional,
        int256 realizedPnl,
        uint256 sqrtPriceAfterX96
    );

    //event
    event PositionLiquidated(
        address indexed trader,
        address indexed baseToken,
        uint256 positionSize,
        uint256 positionNotional,
        uint256 liquidationPenaltyFee,
        address liquidator,
        uint256 liquidatorFee
    );

    /// @notice Emitted when maker's liquidity of a order changed
    /// @param baseToken The address of virtual base token(ETH, BTC, etc...)
    /// @param quoteToken The address of virtual USD token
    /// @param base The amount of base token added (> 0) / removed (< 0) as liquidity; fees not included
    /// @param quote The amount of quote token added ... (same as the above)
    /// @param liquidity The amount of liquidity unit added (> 0) / removed (< 0)
    event LiquidityChanged(
        address indexed baseToken,
        address indexed quoteToken,
        int256 base,
        int256 quote,
        int128 liquidity
    );

    /// @notice Emitted when open position with non-zero referral code
    /// @param referralCode The referral code by partners
    event ReferredPositionChanged(bytes32 indexed referralCode);

    //====================== END Event

    function requireNotMaker(address chAddress, address maker) internal view {
        // not Maker
        require(maker != IClearingHouse(chAddress).getMaker(), "CHD_NM");
    }

    function isLiquidatable(address chAddress, address trader) internal view returns (bool) {
        return
            getAccountValue(chAddress, trader) <
            IAccountBalance(IClearingHouse(chAddress).getAccountBalance()).getMarginRequirementForLiquidation(trader);
    }

    function checkMarketOpen(address baseToken) public view {
        // CH_MNO: Market not opened
        require(IBaseToken(baseToken).isOpen(), "CH_MNO");
    }

    function registerBaseToken(address chAddress, address trader, address baseToken) public {
        IAccountBalance(IClearingHouse(chAddress).getAccountBalance()).registerBaseToken(trader, baseToken);
    }

    function settleFundingGlobal(
        address chAddress,
        address baseToken
    ) public returns (DataTypes.Growth memory fundingGrowthGlobal) {
        (fundingGrowthGlobal) = IVPool(IClearingHouse(chAddress).getVPool()).settleFundingGlobal(baseToken);
        return fundingGrowthGlobal;
    }

    function settleFunding(
        address chAddress,
        address trader,
        address baseToken
    ) public returns (DataTypes.Growth memory fundingGrowthGlobal, int256 fundingPayment) {
        (fundingPayment, fundingGrowthGlobal) = IVPool(IClearingHouse(chAddress).getVPool()).settleFunding(
            trader,
            baseToken
        );
        if (fundingPayment != 0) {
            IAccountBalance(IClearingHouse(chAddress).getAccountBalance()).modifyOwedRealizedPnl(
                trader,
                fundingPayment.neg256()
            );
            emit FundingPaymentSettled(trader, baseToken, fundingPayment);
        }

        IAccountBalance(IClearingHouse(chAddress).getAccountBalance()).updateTwPremiumGrowthGlobal(
            trader,
            baseToken,
            fundingGrowthGlobal.twLongPremiumX96,
            fundingGrowthGlobal.twShortPremiumX96
        );
        return (fundingGrowthGlobal, fundingPayment);
    }

    function getFreeCollateralByRatio(address chAddress, address trader, uint24 ratio) public view returns (int256) {
        return IVault(IClearingHouse(chAddress).getVault()).getFreeCollateralByRatio(trader, ratio);
    }

    function checkSlippageAfterLiquidityChange(
        uint256 base,
        uint256 minBase,
        uint256 quote,
        uint256 minQuote
    ) public pure {
        // CH_PSCF: price slippage check fails
        require(base >= minBase && quote >= minQuote, "CH_PSCF");
    }

    function getSqrtMarkX96(address chAddress, address baseToken) public view returns (uint160) {
        return IVPool(IClearingHouse(chAddress).getVPool()).getSqrtMarkTwapX96(baseToken, 0);
    }

    function requireEnoughFreeCollateral(address chAddress, address trader) public view {
        if (trader == IClearingHouse(chAddress).getMaker()) return;
        // CH_NEFCI: not enough free collateral by imRatio
        require(
            getFreeCollateralByRatio(
                chAddress,
                trader,
                IClearingHouseConfig(IClearingHouse(chAddress).getClearingHouseConfig()).getImRatio()
            ) >= 0,
            "CH_NEFCI"
        );
    }

    function requireEnoughFreeCollateralForClose(address chAddress, address trader) public view {
        if (trader == IClearingHouse(chAddress).getMaker()) return;
        // CH_NEFCM: not enough free collateral by mmRatio
        require(
            getFreeCollateralByRatio(
                chAddress,
                trader,
                IClearingHouseConfig(IClearingHouse(chAddress).getClearingHouseConfig()).getMmRatio()
            ) >= 0,
            "CH_NEFCM"
        );
    }

    function getTakerOpenNotional(address chAddress, address trader, address baseToken) public view returns (int256) {
        return IAccountBalance(IClearingHouse(chAddress).getAccountBalance()).getTakerOpenNotional(trader, baseToken);
    }

    function getAccountValue(address chAddress, address trader) public view returns (int256) {
        return
            IVault(IClearingHouse(chAddress).getVault()).getAccountValue(trader).parseSettlementToken(
                IVault(IClearingHouse(chAddress).getVault()).decimals()
            );
    }

    function checkSlippage(InternalCheckSlippageParams memory params) public pure {
        // skip when params.oppositeAmountBound is zero
        if (params.oppositeAmountBound == 0) {
            return;
        }

        // B2Q + exact input, want more output quote as possible, so we set a lower bound of output quote
        // B2Q + exact output, want less input base as possible, so we set a upper bound of input base
        // Q2B + exact input, want more output base as possible, so we set a lower bound of output base
        // Q2B + exact output, want less input quote as possible, so we set a upper bound of input quote
        if (params.isBaseToQuote) {
            if (params.isExactInput) {
                // too little received when short
                require(params.quote >= params.oppositeAmountBound, "CH_TLRS");
            } else {
                // too much requested when short
                require(params.base <= params.oppositeAmountBound, "CH_TMRS");
            }
        } else {
            if (params.isExactInput) {
                // too little received when long
                require(params.base >= params.oppositeAmountBound, "CH_TLRL");
            } else {
                // too much requested when long
                require(params.quote <= params.oppositeAmountBound, "CH_TMRL");
            }
        }
    }

    function getTakerPositionSafe(address chAddress, address trader, address baseToken) public view returns (int256) {
        int256 takerPositionSize = IAccountBalance(IClearingHouse(chAddress).getAccountBalance()).getTakerPositionSize(
            trader,
            baseToken
        );
        // CH_PSZ: position size is zero
        require(takerPositionSize != 0, "CH_PSZ");
        return takerPositionSize;
    }

    function getOppositeAmount(
        address chAddress,
        uint256 oppositeAmountBound,
        bool isPartialClose
    ) internal view returns (uint256) {
        return
            isPartialClose
                ? oppositeAmountBound.mulRatio(
                    IClearingHouseConfig(IClearingHouse(chAddress).getClearingHouseConfig()).getPartialCloseRatio()
                )
                : oppositeAmountBound;
    }

    function getLiquidationPenaltyRatio(address chAddress) internal view returns (uint24) {
        return IClearingHouseConfig(IClearingHouse(chAddress).getClearingHouseConfig()).getLiquidationPenaltyRatio();
    }

    function getIndexPrice(address chAddress, address baseToken) internal view returns (uint256) {
        return
            IIndexPrice(baseToken).getIndexPrice(
                IClearingHouseConfig(IClearingHouse(chAddress).getClearingHouseConfig()).getTwapInterval()
            );
    }

    function getInsuranceFundFeeRatio(
        address exchange,
        address marketRegistry,
        address baseToken,
        bool isBaseToQuote
    ) public view returns (uint256) {
        (, uint256 markTwap, uint256 indexTwap) = IVPool(exchange).getFundingGrowthGlobalAndTwaps(baseToken);
        int256 deltaTwapRatio = (markTwap.toInt256().sub(indexTwap.toInt256())).mulDiv(1e6, indexTwap);
        IMarketRegistry.MarketInfo memory marketInfo = IMarketRegistry(marketRegistry).getMarketInfo(baseToken);
        // delta <= 2.5%
        if (deltaTwapRatio.abs() <= marketInfo.optimalDeltaTwapRatio) {
            return marketInfo.insuranceFundFeeRatio;
        }
        if ((isBaseToQuote && deltaTwapRatio > 0) || (!isBaseToQuote && deltaTwapRatio < 0)) {
            return 0;
        }
        // 2.5% < delta <= 5%
        if (
            marketInfo.optimalDeltaTwapRatio < deltaTwapRatio.abs() &&
            deltaTwapRatio.abs() <= marketInfo.unhealthyDeltaTwapRatio
        ) {
            return deltaTwapRatio.abs().mul(marketInfo.optimalFundingRatio).div(1e6);
        }
        // 5% < delta
        return
            PerpMath.min(
                deltaTwapRatio.abs(),
                uint256(IClearingHouseConfig(IVPool(exchange).getClearingHouseConfig()).getMaxFundingRate())
            );
    }

    function getNewPositionSizeForMultiplierRate(
        uint256 longPositionSize,
        uint256 shortPositionSize,
        uint256 oldMarkPrice,
        uint256 newMarkPrice,
        uint256 newDeltaPositionSize
    ) internal pure returns (uint256 newLongPositionSizeRate, uint256 newShortPositionSizeRate) {
        (uint256 newLongPositionSize, uint256 newShortPositionSize) = getNewPositionSizeForMultiplier(
            longPositionSize,
            shortPositionSize,
            oldMarkPrice,
            newMarkPrice,
            newDeltaPositionSize
        );
        newLongPositionSizeRate = longPositionSize != 0 ? newLongPositionSize.divMultiplier(longPositionSize) : 0;
        newShortPositionSizeRate = shortPositionSize != 0 ? newShortPositionSize.divMultiplier(shortPositionSize) : 0;
    }

    function getNewPositionSizeForMultiplier(
        uint256 longPositionSize,
        uint256 shortPositionSize,
        uint256 oldMarkPrice,
        uint256 newMarkPrice,
        uint256 newDeltaPositionSize
    ) internal pure returns (uint256 newLongPositionSize, uint256 newShortPositionSize) {
        newLongPositionSize = longPositionSize;
        newShortPositionSize = shortPositionSize;

        if ((longPositionSize + shortPositionSize) == 0) {
            return (newLongPositionSize, newShortPositionSize);
        }

        if (longPositionSize == shortPositionSize && oldMarkPrice == newMarkPrice) {
            return (newLongPositionSize, newShortPositionSize);
        }

        if (oldMarkPrice != newMarkPrice) {
            // GL_IP: Invalid Price
            require(oldMarkPrice > 0 && newMarkPrice > 0, "GL_IP");
            newLongPositionSize = FullMath.mulDiv(newLongPositionSize, oldMarkPrice, newMarkPrice);
            newShortPositionSize = FullMath.mulDiv(newShortPositionSize, oldMarkPrice, newMarkPrice);
        }

        // ajust to new delta base if newDeltaPositionSize > 0
        if (newDeltaPositionSize > 0) {
            uint256 oldDetalPositionSize = newLongPositionSize.toInt256().sub(newShortPositionSize.toInt256()).abs();
            int256 diffDetalPositionSize = newDeltaPositionSize.toInt256().sub(oldDetalPositionSize.toInt256());
            uint256 newTotalPositionSize = newLongPositionSize.add(newShortPositionSize);

            if (
                (diffDetalPositionSize > 0 && newLongPositionSize > newShortPositionSize) ||
                (diffDetalPositionSize < 0 && newLongPositionSize < newShortPositionSize)
            ) {
                newLongPositionSize = FullMath.mulDiv(
                    newLongPositionSize,
                    (1e18 + FullMath.mulDiv(diffDetalPositionSize.abs(), 1e18, newTotalPositionSize)),
                    1e18
                );
                newShortPositionSize = FullMath.mulDiv(
                    newShortPositionSize,
                    (1e18 - FullMath.mulDiv(diffDetalPositionSize.abs(), 1e18, newTotalPositionSize)),
                    1e18
                );
            } else if (
                (diffDetalPositionSize > 0 && newLongPositionSize < newShortPositionSize) ||
                (diffDetalPositionSize < 0 && newLongPositionSize > newShortPositionSize)
            ) {
                newLongPositionSize = FullMath.mulDiv(
                    newLongPositionSize,
                    (1e18 - FullMath.mulDiv(diffDetalPositionSize.abs(), 1e18, newTotalPositionSize)),
                    1e18
                );
                newShortPositionSize = FullMath.mulDiv(
                    newShortPositionSize,
                    (1e18 + FullMath.mulDiv(diffDetalPositionSize.abs(), 1e18, newTotalPositionSize)),
                    1e18
                );
            }
        }

        return (newLongPositionSize, newShortPositionSize);
    }

    function getInfoMultiplier(
        address chAddress,
        address baseToken
    ) internal view returns (uint256 oldLongPositionSize, uint256 oldShortPositionSize, uint256 deltaQuote) {
        (oldLongPositionSize, oldShortPositionSize) = IAccountBalance(IClearingHouse(chAddress).getAccountBalance())
            .getMarketPositionSize(baseToken);
        int256 oldDeltaBase = oldLongPositionSize.toInt256().sub(oldShortPositionSize.toInt256());
        if (oldDeltaBase != 0) {
            bool isBaseToQuote = oldDeltaBase > 0 ? true : false;
            UniswapV3Broker.ReplaySwapResponse memory estimate = IVPool(IClearingHouse(chAddress).getVPool())
                .estimateSwap(
                    DataTypes.OpenPositionParams({
                        baseToken: baseToken,
                        isBaseToQuote: isBaseToQuote,
                        isExactInput: isBaseToQuote,
                        oppositeAmountBound: 0,
                        amount: uint256(oldDeltaBase.abs()),
                        sqrtPriceLimitX96: 0,
                        deadline: block.timestamp + 60,
                        referralCode: ""
                    })
                );
            deltaQuote = isBaseToQuote ? estimate.amountOut : estimate.amountIn;
        }
    }

    function updateInfoMultiplier(
        address chAddress,
        address baseToken,
        uint256 longPositionSize,
        uint256 shortPositionSize,
        uint256 oldDeltaQuote,
        uint256 oldMarkPrice,
        uint256 newMarkPrice,
        bool isFixedPositionSize
    ) internal {
        InternalUpdateInfoMultiplierVars memory vars;

        vars.deltaBase = longPositionSize.toInt256().sub(shortPositionSize.toInt256());
        vars.isBaseToQuote = vars.deltaBase > 0 ? true : false;

        // update new size by price
        {
            (vars.newLongPositionSizeRate, vars.newShortPositionSizeRate) = GenericLogic
                .getNewPositionSizeForMultiplierRate(
                    longPositionSize,
                    shortPositionSize,
                    oldMarkPrice,
                    newMarkPrice,
                    0
                );
            IAccountBalance(IClearingHouse(chAddress).getAccountBalance()).modifyMarketMultiplier(
                baseToken,
                vars.newLongPositionSizeRate,
                vars.newShortPositionSizeRate
            );
        }

        (longPositionSize, shortPositionSize) = IAccountBalance(IClearingHouse(chAddress).getAccountBalance())
            .getMarketPositionSize(baseToken);

        vars.deltaBase = longPositionSize.toInt256().sub(shortPositionSize.toInt256());
        if (vars.deltaBase != 0) {
            UniswapV3Broker.ReplaySwapResponse memory estimate = IVPool(IClearingHouse(chAddress).getVPool())
                .estimateSwap(
                    DataTypes.OpenPositionParams({
                        baseToken: baseToken,
                        isBaseToQuote: vars.isBaseToQuote,
                        isExactInput: vars.isBaseToQuote,
                        oppositeAmountBound: 0,
                        amount: vars.deltaBase.abs(),
                        sqrtPriceLimitX96: 0,
                        deadline: block.timestamp + 60,
                        referralCode: ""
                    })
                );
            vars.newDeltaQuote = vars.isBaseToQuote ? estimate.amountOut : estimate.amountIn;
            vars.costDeltaQuote = (
                vars.isBaseToQuote
                    ? vars.newDeltaQuote.toInt256().sub(oldDeltaQuote.toInt256())
                    : oldDeltaQuote.toInt256().sub(vars.newDeltaQuote.toInt256())
            );
        }

        if (!isFixedPositionSize) {
            // for repeg price
            // estimate for check cost and fund
            vars.isEnoughFund = false;
            if (vars.costDeltaQuote > 0) {
                int256 remainDistributedFund = IInsuranceFund(IClearingHouse(chAddress).getInsuranceFund())
                    .getRepegAccumulatedFund()
                    .sub(IInsuranceFund(IClearingHouse(chAddress).getInsuranceFund()).getRepegDistributedFund());
                int256 freeCollateral = IVault(IClearingHouse(chAddress).getVault())
                    .getFreeCollateralByToken(
                        IClearingHouse(chAddress).getInsuranceFund(),
                        IInsuranceFund(IClearingHouse(chAddress).getInsuranceFund()).getToken()
                    )
                    .toInt256();
                if (remainDistributedFund >= vars.costDeltaQuote) {
                    if (freeCollateral >= vars.costDeltaQuote) {
                        vars.isEnoughFund = true;
                    }
                }
                if (!vars.isEnoughFund) {
                    // using cost with owedRealizedPnl from insuranceFund
                    vars.costDeltaQuote = PerpMath.min(
                        vars.costDeltaQuote,
                        PerpMath.min(
                            remainDistributedFund > 0 ? remainDistributedFund : 0,
                            freeCollateral > 0 ? freeCollateral : 0
                        )
                    );
                }
            } else {
                vars.isEnoughFund = true;
            }
            if (!vars.isEnoughFund) {
                // estimate cost to base
                UniswapV3Broker.ReplaySwapResponse memory estimate = IVPool(IClearingHouse(chAddress).getVPool())
                    .estimateSwap(
                        DataTypes.OpenPositionParams({
                            baseToken: baseToken,
                            isBaseToQuote: vars.isBaseToQuote,
                            isExactInput: !vars.isBaseToQuote,
                            oppositeAmountBound: 0,
                            amount: (
                                vars.isBaseToQuote
                                    ? oldDeltaQuote.add(vars.costDeltaQuote.abs())
                                    : oldDeltaQuote.sub(vars.costDeltaQuote.abs())
                            ),
                            sqrtPriceLimitX96: 0,
                            deadline: block.timestamp + 60,
                            referralCode: ""
                        })
                    );
                vars.newDeltaBase = vars.isBaseToQuote ? estimate.amountIn : estimate.amountOut;
                (vars.newLongPositionSizeRate, vars.newShortPositionSizeRate) = GenericLogic
                    .getNewPositionSizeForMultiplierRate(
                        longPositionSize,
                        shortPositionSize,
                        newMarkPrice,
                        newMarkPrice,
                        vars.newDeltaBase
                    );
                IAccountBalance(IClearingHouse(chAddress).getAccountBalance()).modifyMarketMultiplier(
                    baseToken,
                    vars.newLongPositionSizeRate,
                    vars.newShortPositionSizeRate
                );
            }
        }
        if (vars.costDeltaQuote != 0) {
            // update repeg fund
            IInsuranceFund(IClearingHouse(chAddress).getInsuranceFund()).repegFund(vars.costDeltaQuote);
            // update RealizedPnl for InsuranceFund
            IAccountBalance(IClearingHouse(chAddress).getAccountBalance()).modifyOwedRealizedPnl(
                IClearingHouse(chAddress).getInsuranceFund(),
                vars.costDeltaQuote.neg256()
            );
            // check RealizedPnl for InsuranceFund after repeg
            int256 freeCollateral = IVault(IClearingHouse(chAddress).getVault())
                .getFreeCollateralByToken(
                    IClearingHouse(chAddress).getInsuranceFund(),
                    IInsuranceFund(IClearingHouse(chAddress).getInsuranceFund()).getToken()
                )
                .toInt256();
            // GL_INE: InsuranceFund not fee fund
            require(freeCollateral >= 0, "GL_INFF");
            // emit event
            emit MultiplierCostSpend(baseToken, vars.costDeltaQuote);
        }
    }

    function addLiquidity(
        address chAddress,
        DataTypes.AddLiquidityParams calldata params
    )
        public
        returns (
            // check onlyLiquidityAdmin
            DataTypes.AddLiquidityResponse memory
        )
    {
        // input requirement checks:
        //   baseToken: in Exchange.settleFunding()
        //   base & quote: in LiquidityAmounts.getLiquidityForAmounts() -> FullMath.mulDiv()
        //   lowerTick & upperTick: in UniswapV3Pool._modifyPosition()
        //   minBase, minQuote & deadline: here

        checkMarketOpen(params.baseToken);

        // This condition is to prevent the intentional bad debt attack through price manipulation.
        // CH_OMPS: Over the maximum price spread
        // require(!IVPool(IClearingHouse(chAddress).getVPool()).isOverPriceSpread(params.baseToken), "CH_OMPS");

        settleFundingGlobal(chAddress, params.baseToken);

        // for multiplier
        (uint256 oldLongPositionSize, uint256 oldShortPositionSize, uint256 oldDeltaQuote) = GenericLogic
            .getInfoMultiplier(chAddress, params.baseToken);
        // for multiplier

        // note that we no longer check available tokens here because CH will always auto-mint in UniswapV3MintCallback
        UniswapV3Broker.AddLiquidityResponse memory response = UniswapV3Broker.addLiquidity(
            IMarketRegistry(IClearingHouse(chAddress).getMarketRegistry()).getPool(params.baseToken),
            UniswapV3Broker.AddLiquidityParams({ baseToken: params.baseToken, liquidity: params.liquidity })
        );

        // for multiplier
        updateInfoMultiplier(
            chAddress,
            params.baseToken,
            oldLongPositionSize,
            oldShortPositionSize,
            oldDeltaQuote,
            0,
            0,
            true
        );
        // for multiplier

        emit LiquidityChanged(
            params.baseToken,
            IClearingHouse(chAddress).getQuoteToken(),
            response.base.toInt256(),
            response.quote.toInt256(),
            response.liquidity.toInt128()
        );

        return
            DataTypes.AddLiquidityResponse({
                base: response.base,
                quote: response.quote,
                liquidity: response.liquidity
            });
    }

    function removeLiquidity(
        address chAddress,
        DataTypes.RemoveLiquidityParams memory params
    ) public returns (DataTypes.RemoveLiquidityResponse memory) {
        // input requirement checks:
        //   baseToken: in Exchange.settleFunding()
        //   lowerTick & upperTick: in UniswapV3Pool._modifyPosition()
        //   liquidity: in LiquidityMath.addDelta()
        //   minBase, minQuote & deadline: here

        // CH_MP: Market paused
        require(!IBaseToken(params.baseToken).isPaused(), "CH_MP");

        settleFundingGlobal(chAddress, params.baseToken);

        // for multiplier
        (uint256 oldLongPositionSize, uint256 oldShortPositionSize, uint256 oldDeltaQuote) = GenericLogic
            .getInfoMultiplier(chAddress, params.baseToken);
        // for multiplier

        // must settle funding first

        UniswapV3Broker.RemoveLiquidityResponse memory response = UniswapV3Broker.removeLiquidity(
            IMarketRegistry(IClearingHouse(chAddress).getMarketRegistry()).getPool(params.baseToken),
            chAddress,
            UniswapV3Broker.RemoveLiquidityParams({ baseToken: params.baseToken, liquidity: params.liquidity })
        );

        // for multiplier
        updateInfoMultiplier(
            chAddress,
            params.baseToken,
            oldLongPositionSize,
            oldShortPositionSize,
            oldDeltaQuote,
            0,
            0,
            true
        );
        // for multiplier

        emit LiquidityChanged(
            params.baseToken,
            IClearingHouse(chAddress).getQuoteToken(),
            response.base.neg256(),
            response.quote.neg256(),
            params.liquidity.neg128()
        );

        return DataTypes.RemoveLiquidityResponse({ quote: response.quote, base: response.base });
    }
}

