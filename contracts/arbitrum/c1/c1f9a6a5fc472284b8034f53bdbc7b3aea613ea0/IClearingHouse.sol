// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { IERC20 } from "./IERC20.sol";
import { Decimal } from "./Decimal.sol";
import { SignedDecimal } from "./SignedDecimal.sol";
import { IAmm } from "./IAmm.sol";
import { IDelegateApproval } from "./IDelegateApproval.sol";

interface IClearingHouse {
    /// @notice BUY = LONG, SELL = SHORT
    enum Side {
        BUY,
        SELL
    }

    /**
     * @title Position
     * @notice This struct records position information
     * @param size denominated in amm.baseAsset
     * @param margin isolated margin (collateral amt)
     * @param openNotional the quoteAsset value of the position. the cost of the position
     * @param lastUpdatedCumulativePremiumFraction for calculating funding payment, recorded at position update
     * @param blockNumber recorded at every position update
     */
    struct Position {
        SignedDecimal.signedDecimal size;
        Decimal.decimal margin;
        Decimal.decimal openNotional;
        SignedDecimal.signedDecimal lastUpdatedCumulativePremiumFractionLong;
        SignedDecimal.signedDecimal lastUpdatedCumulativePremiumFractionShort;
        uint256 blockNumber;
    }

    enum PnlCalcOption {
        SPOT_PRICE,
        ORACLE
    }

    //
    // EVENTS
    //

    /**
     * @notice This event is emitted when position is changed
     * @param trader - trader
     * @param amm - amm
     * @param margin - updated margin
     * @param exchangedPositionNotional - the position notional exchanged in the trade
     * @param exchangedPositionSize - the position size exchanged in the trade
     * @param fee - trade fee
     * @param positionSizeAfter - updated position size
     * @param realizedPnl - realized pnl on the trade
     * @param unrealizedPnlAfter - unrealized pnl remaining after the trade
     * @param badDebt - margin cleared by insurance fund (optimally 0)
     * @param liquidationPenalty - liquidation fee
     * @param markPrice - updated mark price
     * @param fundingPayment - funding payment (+: paid, -: received)
     */
    event PositionChanged(
        address indexed trader,
        address indexed amm,
        uint256 margin,
        uint256 exchangedPositionNotional,
        int256 exchangedPositionSize,
        uint256 fee,
        int256 positionSizeAfter,
        int256 realizedPnl,
        int256 unrealizedPnlAfter,
        uint256 badDebt,
        uint256 liquidationPenalty,
        uint256 markPrice,
        int256 fundingPayment
    );

    /**
     * @notice This event is emitted when position is liquidated
     * @param trader - trader
     * @param amm - amm
     * @param liquidator - liquidator
     * @param liquidatedPositionNotional - liquidated position notional
     * @param liquidatedPositionSize - liquidated position size
     * @param liquidationReward - liquidation reward to the liquidator
     * @param insuranceFundProfit - insurance fund profit on liquidation
     * @param badDebt - liquidation fee cleared by insurance fund (optimally 0)
     */
    event PositionLiquidated(
        address indexed trader,
        address indexed amm,
        address indexed liquidator,
        uint256 liquidatedPositionNotional,
        uint256 liquidatedPositionSize,
        uint256 liquidationReward,
        uint256 insuranceFundProfit,
        uint256 badDebt
    );

    /**
     * @notice emitted on funding payments
     * @param amm - amm
     * @param markPrice - mark price on funding
     * @param indexPrice - index price on funding
     * @param premiumFractionLong - total premium longs pay (when +ve), receive (when -ve)
     * @param premiumFractionShort - total premium shorts receive (when +ve), pay (when -ve)
     * @param insuranceFundPnl - insurance fund pnl from funding
     */
    event FundingPayment(
        address indexed amm,
        uint256 markPrice,
        uint256 indexPrice,
        int256 premiumFractionLong,
        int256 premiumFractionShort,
        int256 insuranceFundPnl
    );

    /**
     * @notice emitted on adding or removing margin
     * @param trader - trader address
     * @param amm - amm address
     * @param amount - amount changed
     * @param fundingPayment - funding payment
     */
    event MarginChanged(
        address indexed trader,
        address indexed amm,
        int256 amount,
        int256 fundingPayment
    );

    /**
     * @notice emitted on repeg (convergence event)
     * @param amm - amm address
     * @param quoteAssetReserveBefore - quote reserve before repeg
     * @param baseAssetReserveBefore - base reserve before repeg
     * @param quoteAssetReserveAfter - quote reserve after repeg
     * @param baseAssetReserveAfter - base reserve after repeg
     * @param repegPnl - effective pnl incurred on vault positions after repeg
     * @param repegDebt - amount borrowed from insurance fund
     */
    event Repeg(
        address indexed amm,
        uint256 quoteAssetReserveBefore,
        uint256 baseAssetReserveBefore,
        uint256 quoteAssetReserveAfter,
        uint256 baseAssetReserveAfter,
        int256 repegPnl,
        uint256 repegDebt
    );

    /// @notice emitted on setting repeg bots
    event RepegBotSet(address indexed amm, address indexed bot);

    //
    // EXTERNAL
    //

    function delegateApproval() external view returns(IDelegateApproval);

    /**
     * @notice open a position
     * @param _amm amm address
     * @param _side enum Side; BUY for long and SELL for short
     * @param _quoteAssetAmount quote asset amount in 18 digits. Can Not be 0
     * @param _leverage leverage in 18 digits. Can Not be 0
     * @param _baseAssetAmountLimit base asset amount limit in 18 digits (slippage). 0 for any slippage
     */
    function openPosition(
        IAmm _amm,
        Side _side,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _leverage,
        Decimal.decimal memory _baseAssetAmountLimit
    ) external;

    function openPositionFor(
        IAmm _amm,
        Side _side,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _leverage,
        Decimal.decimal memory _baseAssetAmountLimit,
        address _trader
    ) external;

    /**
     * @notice close position
     * @param _amm amm address
     * @param _quoteAssetAmountLimit quote asset amount limit in 18 digits (slippage). 0 for any slippage
     */
    function closePosition(IAmm _amm, Decimal.decimal memory _quoteAssetAmountLimit)
        external;

    function closePositionFor(IAmm _amm, Decimal.decimal memory _quoteAssetAmountLimit, address _trader)
        external;


    /**
     * @notice partially close position
     * @param _amm amm address
     * @param _partialCloseRatio % to close
     * @param _quoteAssetAmountLimit quote asset amount limit in 18 digits (slippage). 0 for any slippage
     */
    function partialClose(
        IAmm _amm,
        Decimal.decimal memory _partialCloseRatio,
        Decimal.decimal memory _quoteAssetAmountLimit
    ) external;

    function partialCloseFor(
        IAmm _amm,
        Decimal.decimal memory _partialCloseRatio,
        Decimal.decimal memory _quoteAssetAmountLimit,
        address _trader
    ) external;

    /**
     * @notice add margin to increase margin ratio
     * @param _amm amm address
     * @param _addedMargin added margin in 18 digits
     */
    function addMargin(IAmm _amm, Decimal.decimal calldata _addedMargin)
        external;
    
    function addMarginFor(IAmm _amm, Decimal.decimal calldata _addedMargin, address _trader)
        external;
       
    /**
     * @notice remove margin to decrease margin ratio
     * @param _amm amm address
     * @param _removedMargin removed margin in 18 digits
     */
    function removeMargin(IAmm _amm, Decimal.decimal calldata _removedMargin)
        external;

    function removeMarginFor(IAmm _amm, Decimal.decimal calldata _removedMargin, address _trader)
        external;
        
    /**
     * @notice liquidate trader's underwater position. Require trader's margin ratio less than maintenance margin ratio
     * @param _amm amm address
     * @param _trader trader address
     */
    function liquidate(IAmm _amm, address _trader) external;

    /**
     * @notice settle funding payment
     * @dev dynamic funding mechanism refer (https://nftperp.notion.site/Technical-Stuff-8e4cb30f08b94aa2a576097a5008df24)
     * @param _amm amm address
     */
    function settleFunding(IAmm _amm) external;

  
    //
    // PUBLIC
    //

    /**
     * @notice get personal position information
     * @param _amm IAmm address
     * @param _trader trader address
     * @return struct Position
     */
    function getPosition(IAmm _amm, address _trader) external view returns (Position memory);

    /**
     * @notice get margin ratio, marginRatio = (margin + funding payment + unrealized Pnl) / positionNotional
     * @param _amm amm address
     * @param _trader trader address
     * @return margin ratio in 18 digits
     */
    function getMarginRatio(IAmm _amm, address _trader)
        external
        view
        returns (SignedDecimal.signedDecimal memory);

    /**
     * @notice get position notional and unrealized Pnl without fee expense and funding payment
     * @param _amm amm address
     * @param _trader trader address
     * @param _pnlCalcOption enum PnlCalcOption, SPOT_PRICE for spot price and ORACLE for oracle price
     * @return positionNotional position notional
     * @return unrealizedPnl unrealized Pnl
     */
    // unrealizedPnlForLongPosition = positionNotional - openNotional
    // unrealizedPnlForShortPosition = positionNotionalWhenBorrowed - positionNotionalWhenReturned =
    // openNotional - positionNotional = unrealizedPnlForLongPosition * -1
    function getPositionNotionalAndUnrealizedPnl(
        IAmm _amm,
        address _trader,
        PnlCalcOption _pnlCalcOption
    )
        external
        view
        returns (
            Decimal.decimal memory positionNotional,
            SignedDecimal.signedDecimal memory unrealizedPnl
        );

    /**
     * @notice get latest cumulative premium fraction.
     * @param _amm IAmm address
     * @return latestCumulativePremiumFractionLong cumulative premium fraction long
     * @return latestCumulativePremiumFractionShort cumulative premium fraction short
     */
    function getLatestCumulativePremiumFraction(IAmm _amm)
        external
        view
        returns (
            SignedDecimal.signedDecimal memory latestCumulativePremiumFractionLong,
            SignedDecimal.signedDecimal memory latestCumulativePremiumFractionShort
        );
}
