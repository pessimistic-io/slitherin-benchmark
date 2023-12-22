// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { Decimal } from "./LibDecimal.sol";
import { PositionType, Side } from "./LibEnums.sol";
import { SchnorrSign, PositionPrice } from "./OracleStorage.sol";
import { OracleInternal } from "./OracleInternal.sol";
import { ConstantsInternal } from "./ConstantsInternal.sol";
import { MasterStorage, Position, PositionState } from "./MasterStorage.sol";
import { MasterCalculators } from "./MasterCalculators.sol";
import { LiquidationsInternal } from "./LiquidationsInternal.sol";
import { ILiquidationsEvents } from "./ILiquidationsEvents.sol";

contract Liquidations is ILiquidationsEvents {
    using MasterStorage for MasterStorage.Layout;
    using Decimal for Decimal.D256;

    /* ========== PUBLIC VIEWS ========== */

    function positionShouldBeLiquidatedIsolated(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice
    ) external view returns (bool shouldBeLiquidated, int256 uPnLA, int256 uPnLB) {
        return LiquidationsInternal.positionShouldBeLiquidatedIsolated(positionId, bidPrice, askPrice);
    }

    function partyShouldBeLiquidatedCross(address party, int256 uPnLCross) external view returns (bool) {
        return LiquidationsInternal.partyShouldBeLiquidatedCross(party, uPnLCross);
    }

    /* ========== PUBLIC WRITES ========== */

    /**
     * @dev Unlike a cross liquidation, we don't check for major deficits here.
     *      Counterparties should put limit sell orders at the liquidation price
     *      of the user, in order to mitigate the deficit. Failure to do so
     *      would result in the counterParty paying for the deficit.
     * @dev The above describes 'major' deficits. There's always a deficit,
     *      however the CVA aims to cover that.
     * @dev Cross positions are ALLOWED in order to liquidate partyB.
     */
    function liquidatePositionIsolated(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice,
        bytes calldata reqId,
        SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) external {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position memory position = s.allPositionsMap[positionId];

        // Verify oracle signatures
        OracleInternal.verifyPositionPriceOrThrow(positionId, bidPrice, askPrice, reqId, sign, gatewaySignature);

        // Check if the position should be liquidated
        (bool shouldBeLiquidated, int256 uPnLA, ) = LiquidationsInternal.positionShouldBeLiquidatedIsolated(
            positionId,
            bidPrice,
            askPrice
        );
        require(shouldBeLiquidated, "Not liquidatable");
        require(
            position.state != PositionState.LIQUIDATED && position.state != PositionState.CLOSED,
            "Position already closed"
        );

        /**
         * -PnL = position.lockedMargin(AorB) + a deficit
         *
         * Note: we're NOT dealing with PnL here for distribution, because
         * the PnL implies that a deficit is possible. However, since this
         * is an isolated liquidation, the (hidden) deficit is covered by
         * the CVA where its remainder (although not calculated) goes to
         * the counterParty.
         *
         * The liquidation takes form through not returning any funds to
         * to the counterParty because it's all strictly Isolated.
         **/
        address targetParty;
        if (position.positionType == PositionType.ISOLATED) {
            // We are liquidating either PartyA or PartyB, both are Isolated.
            uint256 amount = position.lockedMarginA +
                position.lockedMarginB +
                (position.cva * 2) +
                position.liquidationFee;

            if (uPnLA >= 0) {
                // PartyA is in profit, thus we're liquidating PartyB.
                s.marginBalances[position.partyA] += amount;
                targetParty = position.partyB;
            } else {
                // PartyB is in profit, thus we're liquidating PartyA.
                s.marginBalances[position.partyB] += amount;
                targetParty = position.partyA;
            }
        } else {
            // We are liquidating PartyB as Isolated, despite PartyA being Cross.
            targetParty = position.partyB;
            require(uPnLA >= 0, "PartyA should be profitable");
            // Amount excludes lockedMarginA, because he already has a claim to that.
            uint256 amount = position.lockedMarginB + (position.cva * 2) + position.liquidationFee;
            // PartyA receives money as CrossLockedMargin, thus improving his health.
            s.crossLockedMargin[position.partyA] += amount;
        }

        // Reward the liquidator + protocol
        uint256 protocolShare = Decimal
            .mul(ConstantsInternal.getProtocolLiquidationShare(), position.liquidationFee)
            .asUint256();
        s.accountBalances[msg.sender] += (position.liquidationFee - protocolShare);
        s.accountBalances[address(this)] += protocolShare;

        // Update mappings
        _updatePositionStateIsolated(position);

        // Emit the liquidation event
        emit Liquidate(
            positionId,
            position.partyA,
            position.partyB,
            targetParty,
            position.currentBalanceUnits,
            position.side == Side.BUY ? bidPrice : askPrice
        );
    }

    function liquidatePartyCross(
        address partyA,
        uint256[] calldata positionIds,
        uint256[] calldata bidPrices,
        uint256[] calldata askPrices,
        bytes calldata reqId,
        SchnorrSign calldata sign,
        bytes calldata gatewaySignature
    ) external {
        MasterStorage.Layout storage s = MasterStorage.layout();

        // Verify oracle signatures
        OracleInternal.verifyPositionPricesOrThrow(positionIds, bidPrices, askPrices, reqId, sign, gatewaySignature);

        // Check if all positionIds are provided by length
        require(positionIds.length == s.openPositionsCrossLength[partyA], "Invalid positionIds length");

        // Create structs for positionIds and prices
        PositionPrice[] memory positionPrices = OracleInternal.createPositionPrices(positionIds, bidPrices, askPrices);

        /**
         * The below checks whether the party should be liquidated. We can do that based
         * on malicious inputs. If malicious then the next `for` loop will revert it regardless.
         */
        int256 uPnLCross = MasterCalculators.calculateUPnLCross(positionPrices, partyA);
        bool shouldBeLiquidated = LiquidationsInternal.partyShouldBeLiquidatedCross(partyA, uPnLCross);
        require(shouldBeLiquidated, "Not liquidatable");

        /**
         * At this point the positionIds can still be malicious in nature. They can be:
         * - tied to a different party
         * - arbitrary positionIds
         * - no longer be valid (e.g. Muon is n-blocks behind)
         *
         * They can NOT:
         * - have a different length than the open positions list, see earlier `require`
         *
         * _calculateRealizedDistribution will catch & revert on any of the above issues.
         */
        uint256 debit = 0;
        uint256 credit = 0;
        int256 lastPnL = 0;
        uint256 totalSingleLiquidationFees = 0;
        uint256 totalDoubleCVA = 0;

        for (uint256 i = 0; i < positionPrices.length; i++) {
            (
                int256 pnl,
                uint256 _debit,
                uint256 _credit,
                uint256 singleLiquidationFee,
                uint256 doubleCVA
            ) = _calculateRealizedDistribution(partyA, positionPrices[i]);
            debit += _debit;
            credit += _credit;

            if (i != 0) {
                require(pnl <= lastPnL, "PNL must be in descending order");
            }
            lastPnL = pnl;
            totalSingleLiquidationFees += singleLiquidationFee;
            totalDoubleCVA += doubleCVA;
        }

        require(credit >= (debit + s.crossLockedMargin[partyA]), "PartyA should have more credit");
        uint256 deficit = credit - debit - s.crossLockedMargin[partyA];

        /**
         * We have a deficit that needs to be covered:
         * 1) Covered by the total CVA of all parties involved.
         * 2) Option 1 isn't sufficient. Covered by the PNL of all profitable PartyB's.
         */
        if (deficit < totalDoubleCVA) {
            Decimal.D256 memory doubleCVARatio = Decimal.ratio(totalDoubleCVA - deficit, totalDoubleCVA);
            for (uint256 i = 0; i < positionPrices.length; i++) {
                _distributePnLDeficitThroughCVA(positionPrices[i], doubleCVARatio);
                _updatePositionStateCross(positionPrices[i].positionId, positionPrices[i]);
            }
        } else {
            // The deficit is too high, profitable PartyB's will receive a reduced PNL.
            uint256 pendingDeficit = deficit - totalDoubleCVA;
            Decimal.D256 memory creditRatio = pendingDeficit >= credit
                ? Decimal.ratio(0, 1) // Nobody gets ANY pnl, extremely unlikely.
                : Decimal.ratio(credit - pendingDeficit, credit);

            for (uint256 i = 0; i < positionPrices.length; i++) {
                _distributePnLDeficitThroughCredit(positionPrices[i], creditRatio);
                _updatePositionStateCross(positionPrices[i].positionId, positionPrices[i]);
            }
        }

        // Ultimately, reset the liquidated party his lockedMargin.
        s.crossLockedMargin[partyA] = 0;

        // Reward the liquidator + protocol
        uint256 protocolShare = Decimal
            .mul(ConstantsInternal.getProtocolLiquidationShare(), totalSingleLiquidationFees)
            .asUint256();
        s.accountBalances[msg.sender] += (totalSingleLiquidationFees - protocolShare);
        s.accountBalances[address(this)] += protocolShare;
    }

    /* ========== PRIVATE WRITES ========== */

    function _distributePnLDeficitThroughCVA(
        PositionPrice memory positionPrice,
        Decimal.D256 memory doubleCVARatio
    ) private {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position memory position = s.allPositionsMap[positionPrice.positionId];

        // Calculate the PnL of PartyA.
        (int256 uPnLA, ) = MasterCalculators.calculateUPnLIsolated(
            position.positionId,
            positionPrice.bidPrice,
            positionPrice.askPrice
        );

        uint256 bonusAmount = Decimal.mul(doubleCVARatio, position.cva * 2).asUint256() + position.liquidationFee;

        if (uPnLA >= 0) {
            uint256 pnl = uint256(uPnLA);
            // PartyB gets his lockedMargin back minus the PnL that PartyA has earned.
            uint256 marginAmount = pnl >= position.lockedMarginB
                ? 0 // PartyB should've been liquidated here already.
                : position.lockedMarginB - pnl;
            s.marginBalances[position.partyB] += marginAmount + bonusAmount;
        } else {
            uint256 amount = bonusAmount + uint256(-uPnLA) + position.lockedMarginB;
            s.marginBalances[position.partyB] += amount;
        }
    }

    function _distributePnLDeficitThroughCredit(
        PositionPrice memory positionPrice,
        Decimal.D256 memory creditRatio
    ) private {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position memory position = s.allPositionsMap[positionPrice.positionId];

        // Calculate the PnL of PartyA.
        (int256 uPnLA, ) = MasterCalculators.calculateUPnLIsolated(
            position.positionId,
            positionPrice.bidPrice,
            positionPrice.askPrice
        );

        if (uPnLA >= 0) {
            uint256 pnl = uint256(uPnLA);
            uint256 marginAmount = pnl >= position.lockedMarginB
                ? 0 // PartyB should've been liquidated here already.
                : position.lockedMarginB - pnl;
            s.marginBalances[position.partyB] += marginAmount + position.liquidationFee;
        } else {
            // PartyB gets a reduced PNL, where -uPnLA == credit.
            uint256 amount = position.lockedMarginB +
                Decimal.mul(creditRatio, uint256(-uPnLA)).asUint256() +
                position.liquidationFee;
            s.marginBalances[position.partyB] += amount;
        }
    }

    function _updatePositionStateIsolated(Position memory position) private {
        MasterStorage.Layout storage s = MasterStorage.layout();

        _updatePositionStateBase(position.positionId);
        s.openPositionsIsolatedLength[position.partyA]--;
        s.openPositionsIsolatedLength[position.partyB]--;
    }

    function _updatePositionStateCross(uint256 positionId, PositionPrice memory positionPrice) private {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position memory position = s.allPositionsMap[positionId];

        _updatePositionStateBase(positionId);
        s.openPositionsCrossLength[position.partyA]--;
        s.openPositionsIsolatedLength[position.partyB]--;

        // Emit the liquidation event
        emit Liquidate(
            positionId,
            position.partyA,
            position.partyB,
            position.partyA, // PartyA is always the targetParty in Cross
            position.currentBalanceUnits,
            position.side == Side.BUY ? positionPrice.bidPrice : positionPrice.askPrice
        );
    }

    function _updatePositionStateBase(uint256 positionId) private {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position storage position = s.allPositionsMap[positionId];

        // Update the position state
        position.state = PositionState.LIQUIDATED;
        position.currentBalanceUnits = 0;
        position.mutableTimestamp = block.timestamp;
    }

    /* ========== PRIVATE VIEWS ========== */

    /**
     * @dev Calculates the realized distribution for a single position to uncover deficits.
     * @dev Strictly limited to Cross positions.
     * @dev Strictly targetting partyA (the liquidated party).
     */
    function _calculateRealizedDistribution(
        address partyA,
        PositionPrice memory positionPrice
    )
        private
        view
        returns (int256 uPnLA, uint256 debit, uint256 credit, uint256 singleLiquidationFee, uint256 doubleCVA)
    {
        MasterStorage.Layout storage s = MasterStorage.layout();
        Position memory position = s.allPositionsMap[positionPrice.positionId];

        require(
            position.state != PositionState.LIQUIDATED && position.state != PositionState.CLOSED,
            "Position already closed"
        );
        require(position.partyA == partyA, "Invalid party");
        require(position.positionType == PositionType.CROSS, "Invalid position type");

        // Calculate the PnL of PartyA
        (uPnLA, ) = MasterCalculators.calculateUPnLIsolated(
            position.positionId,
            positionPrice.bidPrice,
            positionPrice.askPrice
        );

        /**
         * Note: 'single' implies the half that PartyA locked into
         * the position, which he will now lose.
         *
         * His half + the other half (together 'double') will be:
         * - used for the global deficit (CVA)
         * - used to reward the liquidator (LiquidationFee)
         * - returned to PartyB
         **/
        singleLiquidationFee = position.liquidationFee;
        doubleCVA = position.cva * 2;

        if (uPnLA >= 0) {
            // PartyA receives the PNL.
            uint256 amount = uint256(uPnLA);
            debit = amount >= position.lockedMarginB
                ? position.lockedMarginB // PartyB should've been liquidated here already.
                : amount;
            credit = 0;
        } else {
            // PartyA has to pay PartyB.
            debit = 0;
            credit = uint256(-uPnLA);
        }
    }
}

