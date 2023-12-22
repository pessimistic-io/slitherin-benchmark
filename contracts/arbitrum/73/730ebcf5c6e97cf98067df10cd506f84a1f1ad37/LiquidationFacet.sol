// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { AppStorage, Position, Fill } from "./LibAppStorage.sol";
import { SchnorrSign } from "./IMuonV03.sol";
import { LibOracle, PositionPrice } from "./LibOracle.sol";
import { LibMaster } from "./LibMaster.sol";
import { LibHedgers } from "./LibHedgers.sol";
import { Decimal } from "./LibDecimal.sol";
import { LibDiamond } from "./LibDiamond.sol";
import { C } from "./C.sol";
import "./LibEnums.sol";

contract LiquidationFacet {
    using Decimal for Decimal.D256;

    AppStorage internal s;

    /**
     * @dev Unlike a cross liquidation, we don't check for deficits here.
     *      Counterparties should put limit sell orders at the liquidation price
     *      of the user, in order to mitigate the deficit. Failure to do so
     *      would result in the counterParty paying for the deficit.
     */
    function liquidatePositionIsolated(
        uint256 positionId,
        uint256 bidPrice,
        uint256 askPrice,
        bytes calldata reqId,
        uint256 timestamp_,
        SchnorrSign[] calldata sigs
    ) external {
        // Verify oracle signatures
        LibOracle.verifyPositionPriceOrThrow(positionId, bidPrice, askPrice, reqId, timestamp_, sigs);

        // Check if the position should be liquidated
        (bool shouldBeLiquidated, int256 pnlA, ) = LibMaster.positionShouldBeLiquidatedIsolated(
            positionId,
            bidPrice,
            askPrice
        );
        require(shouldBeLiquidated, "Not liquidatable");

        Position memory position = s.ma._allPositionsMap[positionId];
        require(position.positionType == PositionType.ISOLATED, "Position is not isolated");
        require(position.state != PositionState.LIQUIDATED, "Position already liquidated");

        uint256 amount = (position.lockedMargin * 2) + (position.cva * 2) + position.liquidationFee;

        // If partyA is in a loss, then that means he's the one who needs to be liquidated
        if (pnlA < 0) {
            s.ma._marginBalances[position.partyB] += amount;
        } else {
            s.ma._marginBalances[position.partyA] += amount;
        }

        // Reward the liquidator
        s.ma._marginBalances[msg.sender] += position.liquidationFee;

        // Update mappings
        _updatePositionDataIsolated(positionId, LibOracle.createPositionPrice(positionId, bidPrice, askPrice));
    }

    // solhint-disable-next-line code-complexity
    function liquidatePartyCross(
        address party,
        uint256[] calldata positionIds,
        uint256[] calldata bidPrices,
        uint256[] calldata askPrices,
        bytes calldata reqId,
        uint256 timestamp_,
        SchnorrSign[] calldata sigs
    ) external {
        // Verify oracle signatures
        LibOracle.verifyPositionPricesOrThrow(positionIds, bidPrices, askPrices, reqId, timestamp_, sigs);

        // Check if all positionIds are provided by length
        require(positionIds.length == s.ma._openPositionsCrossLength[party], "Invalid positionIds length");

        // Create structs for positionIds and prices
        PositionPrice[] memory positionPrices = LibOracle.createPositionPrices(positionIds, bidPrices, askPrices);

        /**
         * The below checks whether the party should be liquidated. We can do that based
         * on malicious inputs. If malicious then the next `for` loop will revert it.
         */
        (int256 uPnLCross, ) = LibMaster.calculateUPnLCross(positionPrices, party);
        bool shouldBeLiquidated = LibMaster.partyShouldBeLiquidatedCross(party, uPnLCross);
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
        uint256 received = 0;
        uint256 owed = 0;
        int256 lastPnL = 0;
        uint256 totalSingleLiquidationFees = 0;
        uint256 totalSingleCVA = 0;

        for (uint256 i = 0; i < positionPrices.length; i++) {
            (
                int256 pnl,
                uint256 r,
                uint256 o,
                uint256 singleLiquidationFee,
                uint256 singleCVA
            ) = _calculateRealizedDistribution(party, positionPrices[i]);
            received += r;
            owed += o;

            if (i != 0) {
                require(pnl <= lastPnL, "PNL must be in descending order");
            }
            lastPnL = pnl;
            totalSingleLiquidationFees += singleLiquidationFee;
            totalSingleCVA += singleCVA;
        }

        require(owed >= received, "Invalid realized distribution");
        uint256 deficit = owed - received;

        if (deficit < totalSingleLiquidationFees) {
            /// @dev See _distributePnLDeficitOne.
            Decimal.D256 memory liquidationFeeRatio = Decimal.ratio(
                totalSingleLiquidationFees - deficit,
                totalSingleLiquidationFees
            );
            for (uint256 i = 0; i < positionPrices.length; i++) {
                _distributePnLDeficitOne(party, positionPrices[i], liquidationFeeRatio, msg.sender);
                _updatePositionDataCross(positionPrices[i].positionId, positionPrices[i]);
            }
        } else if (deficit < totalSingleLiquidationFees + totalSingleCVA) {
            /// @dev See _distributePnLDeficitTwo.
            Decimal.D256 memory cvaRatio = Decimal.ratio(
                totalSingleLiquidationFees + totalSingleCVA - deficit,
                totalSingleCVA
            );
            for (uint256 i = 0; i < positionPrices.length; i++) {
                _distributePnLDeficitTwo(party, positionPrices[i], cvaRatio);
                _updatePositionDataCross(positionPrices[i].positionId, positionPrices[i]);
            }
        } else if (deficit < totalSingleLiquidationFees + totalSingleCVA * 2) {
            /// @dev See _distributePnLDeficitThree.
            Decimal.D256 memory cvaRatio = Decimal.ratio(
                totalSingleLiquidationFees + (totalSingleCVA * 2) - deficit,
                totalSingleCVA
            );
            for (uint256 i = 0; i < positionPrices.length; i++) {
                _distributePnLDeficitThree(party, positionPrices[i], cvaRatio);
                _updatePositionDataCross(positionPrices[i].positionId, positionPrices[i]);
            }
        } else if (deficit < totalSingleLiquidationFees * 2 + totalSingleCVA * 2) {
            /// @dev See _distributePnLDeficitFour.
            Decimal.D256 memory liquidationFeeRatio = Decimal.ratio(
                (totalSingleLiquidationFees * 2) + (totalSingleCVA * 2) - deficit,
                totalSingleLiquidationFees
            );
            for (uint256 i = 0; i < positionPrices.length; i++) {
                _distributePnLDeficitFour(party, positionPrices[i], liquidationFeeRatio);
                _updatePositionDataCross(positionPrices[i].positionId, positionPrices[i]);
            }
        } else {
            /// @dev See _distributePnLDeficitFive.
            // The deficit is too high, winning counterparties will receive a reduced PNL.
            uint256 pendingDeficit = deficit - (totalSingleLiquidationFees * 2) + (totalSingleCVA * 2);
            Decimal.D256 memory pnlRatio = pendingDeficit >= received
                ? Decimal.ratio(0, 1) // Nobody gets ANY pnl.
                : Decimal.ratio(received - pendingDeficit, received);

            for (uint256 i = 0; i < positionPrices.length; i++) {
                _distributePnLDeficitFive(party, positionPrices[i], pnlRatio);
                _updatePositionDataCross(positionPrices[i].positionId, positionPrices[i]);
            }
        }

        // Ultimately, reset the liquidated party his lockedMargin.
        s.ma._lockedMargin[party] = 0;
    }

    function _calculateRealizedDistribution(address party, PositionPrice memory positionPrice)
        private
        view
        returns (
            int256 pnl,
            uint256 received,
            uint256 owed,
            uint256 singleLiquidationFee,
            uint256 singleCVA
        )
    {
        Position storage position = s.ma._allPositionsMap[positionPrice.positionId];

        require(position.state != PositionState.LIQUIDATED, "Position already liquidated");
        require(position.partyA == party || position.partyB == party, "Invalid party");
        require(position.positionType == PositionType.CROSS, "Invalid position type");

        // Calculate the PnL of both parties.
        (int256 pnlA, int256 pnlB) = LibMaster.calculateUPnLIsolated(
            position.positionId,
            positionPrice.bidPrice,
            positionPrice.askPrice
        );

        // Extract our party's PNL
        pnl = position.partyA == party ? pnlA : pnlB;

        if (pnl <= 0) {
            received = 0;
            owed = uint256(-pnl);
        } else {
            uint256 amount = uint256(pnl);
            // Counterparty is isolated
            received = amount > position.lockedMargin ? position.lockedMargin : amount;
            owed = 0;
        }

        singleLiquidationFee = position.liquidationFee;
        singleCVA = position.cva;
    }

    function _updatePositionDataIsolated(uint256 positionId, PositionPrice memory positionPrice) private {
        Position memory position = s.ma._allPositionsMap[positionId];

        _updatePositionDataBase(positionId, positionPrice);
        s.ma._openPositionsIsolatedLength[position.partyA]--;
        s.ma._openPositionsIsolatedLength[position.partyB]--;
    }

    function _updatePositionDataCross(uint256 positionId, PositionPrice memory positionPrice) private {
        Position memory position = s.ma._allPositionsMap[positionId];

        _updatePositionDataBase(positionId, positionPrice);
        s.ma._openPositionsCrossLength[position.partyA]--;
        s.ma._openPositionsIsolatedLength[position.partyB]--;
    }

    function _updatePositionDataBase(uint256 positionId, PositionPrice memory positionPrice) private {
        Position storage position = s.ma._allPositionsMap[positionId];

        // Add the Fill
        LibMaster.createFill(
            position.positionId,
            position.side == Side.BUY ? Side.SELL : Side.BUY,
            position.currentBalanceUnits,
            position.side == Side.BUY ? positionPrice.bidPrice : positionPrice.askPrice
        );

        // Update the position state
        position.state = PositionState.LIQUIDATED;
        position.currentBalanceUnits = 0;
        position.mutableTimestamp = block.timestamp;
    }

    /**
     * @notice Deficit < liquidationFeeLiquidatedParty
     *
     * - Deficit is covered by the liquidator, he earns the remainder.
     * - CounterParty gets his CVA back.
     * - CounterParty gets the CVA of the liquidated party.
     * - CounterParty gets his liquidationFee back.
     *
     * If PnLLiquidatedParty <= 0:
     * - counterParty gets the entire PnL.
     * - counterParty gets his lockedMargin back.
     *
     * If PnLLiquidatedParty > 0:
     * - counterParty gets (lockedMargin - PnLLiquidatedParty) back.
     */
    function _distributePnLDeficitOne(
        address party,
        PositionPrice memory positionPrice,
        Decimal.D256 memory liquidationFeeRatio,
        address liquidator
    ) private {
        Position storage position = s.ma._allPositionsMap[positionPrice.positionId];

        require(position.state != PositionState.LIQUIDATED, "Position already liquidated");
        require(position.partyA == party || position.partyB == party, "Invalid party");

        // Calculate the PnL of both parties.
        (int256 pnlA, int256 pnlB) = LibMaster.calculateUPnLIsolated(
            position.positionId,
            positionPrice.bidPrice,
            positionPrice.askPrice
        );

        // Extract our party's PNL
        int256 pnl = position.partyA == party ? pnlA : pnlB;

        address counterParty = position.partyA == party ? position.partyB : position.partyA;
        uint256 baseReturnAmount = (position.cva * 2) + position.liquidationFee;

        if (pnl <= 0) {
            uint256 amount = baseReturnAmount + uint256(-pnl) + position.lockedMargin;
            s.ma._marginBalances[counterParty] += amount;
        } else {
            uint256 marginReturned = uint256(pnl) >= position.lockedMargin ? 0 : position.lockedMargin - uint256(pnl);
            uint256 amount = baseReturnAmount + marginReturned;
            s.ma._marginBalances[counterParty] += amount;
        }

        // Reward the liquidator + protocol
        uint256 liquidationFee = Decimal.mul(liquidationFeeRatio, position.liquidationFee).asUint256();
        uint256 protocolShare = Decimal.mul(C.getProtocolLiquidationShare(), liquidationFee).asUint256();
        s.ma._accountBalances[liquidator] += (liquidationFee - protocolShare);
        s.ma._accountBalances[LibDiamond.contractOwner()] += protocolShare;
    }

    /**
     * @notice Deficit < liquidationFeeLiquidatedParty + CVALiquidatedParty
     *
     * - Deficit is not sufficiently covered by the liquidationFee, liquidator earns nothing.
     * - Deficit is covered by the liquidatedParty's CVA, the counterParty receives the remainder.
     * - CounterParty gets his CVA back.
     * - CounterParty gets his liquidationFee back.
     *
     * If PnLLiquidatedParty <= 0:
     * - counterParty gets the entire PnL.
     * - counterParty gets his lockedMargin back.
     *
     * If PnLLiquidatedParty > 0:
     * - counterParty gets (lockedMargin - PnLLiquidatedParty) back.
     */
    function _distributePnLDeficitTwo(
        address party,
        PositionPrice memory positionPrice,
        Decimal.D256 memory cvaRatio
    ) private {
        Position storage position = s.ma._allPositionsMap[positionPrice.positionId];

        require(position.state != PositionState.LIQUIDATED, "Position already liquidated");
        require(position.partyA == party || position.partyB == party, "Invalid party");

        // Calculate the PnL of both parties.
        (int256 pnlA, int256 pnlB) = LibMaster.calculateUPnLIsolated(
            position.positionId,
            positionPrice.bidPrice,
            positionPrice.askPrice
        );

        // Extract our party's PNL
        int256 pnl = position.partyA == party ? pnlA : pnlB;

        address counterParty = position.partyA == party ? position.partyB : position.partyA;
        uint256 baseReturnAmount = position.cva +
            Decimal.mul(cvaRatio, position.cva).asUint256() +
            position.liquidationFee;

        if (pnl <= 0) {
            uint256 amount = baseReturnAmount + uint256(-pnl) + position.lockedMargin;
            s.ma._marginBalances[counterParty] += amount;
        } else {
            uint256 marginReturned = uint256(pnl) >= position.lockedMargin ? 0 : position.lockedMargin - uint256(pnl);
            uint256 amount = baseReturnAmount + marginReturned;
            s.ma._marginBalances[counterParty] += amount;
        }
    }

    /**
     * @notice Deficit < liquidationFeeLiquidatedParty + CVALiquidatedParty + CVACounterParty
     *
     * - Deficit is not sufficiently covered by the liquidationFee, liquidator earns nothing.
     * - Deficit is not sufficiently covered by the liquidatedParty's CVA.
     * - Deficit is covered by the counterParty's CVA, he receives the remainder.
     * - CounterParty gets his liquidationFee back.
     *
     * If PnLLiquidatedParty <= 0:
     * - counterParty gets the entire PnL.
     * - counterParty gets his lockedMargin back.
     *
     * If PnLLiquidatedParty > 0:
     * - counterParty gets (lockedMargin - PnLLiquidatedParty) back.
     */
    function _distributePnLDeficitThree(
        address party,
        PositionPrice memory positionPrice,
        Decimal.D256 memory cvaRatio
    ) private {
        Position storage position = s.ma._allPositionsMap[positionPrice.positionId];

        require(position.state != PositionState.LIQUIDATED, "Position already liquidated");
        require(position.partyA == party || position.partyB == party, "Invalid party");

        // Calculate the PnL of both parties.
        (int256 pnlA, int256 pnlB) = LibMaster.calculateUPnLIsolated(
            position.positionId,
            positionPrice.bidPrice,
            positionPrice.askPrice
        );

        // Extract our party's PNL
        int256 pnl = position.partyA == party ? pnlA : pnlB;

        address counterParty = position.partyA == party ? position.partyB : position.partyA;
        uint256 baseReturnAmount = Decimal.mul(cvaRatio, position.cva).asUint256() + position.liquidationFee;

        if (pnl <= 0) {
            uint256 amount = baseReturnAmount + uint256(-pnl) + position.lockedMargin;
            s.ma._marginBalances[counterParty] += amount;
        } else {
            uint256 marginReturned = uint256(pnl) >= position.lockedMargin ? 0 : position.lockedMargin - uint256(pnl);
            uint256 amount = baseReturnAmount + marginReturned;
            s.ma._marginBalances[counterParty] += amount;
        }
    }

    /**
     * @notice Deficit < liquidationFeeLiquidatedParty + liquidationFeeCounterParty + CVALiquidatedParty + CVACounterParty
     *
     * - Deficit is not sufficiently covered by the liquidationFee, liquidator earns nothing.
     * - Deficit is not sufficiently covered by the liquidatedParty's CVA.
     * - Deficit is not sufficiently covered by the counterParty's CVA.
     * - Deficit is covered by the counterParty's liquidationFee, he receives the remainder.
     *
     * If PnLLiquidatedParty <= 0:
     * - counterParty gets the entire PnL.
     * - counterParty gets his lockedMargin back.
     *
     * If PnLLiquidatedParty > 0:
     * - counterParty gets (lockedMargin - PnLLiquidatedParty) back.
     */
    function _distributePnLDeficitFour(
        address party,
        PositionPrice memory positionPrice,
        Decimal.D256 memory liquidationFeeRatio
    ) private {
        Position storage position = s.ma._allPositionsMap[positionPrice.positionId];

        require(position.state != PositionState.LIQUIDATED, "Position already liquidated");
        require(position.partyA == party || position.partyB == party, "Invalid party");

        // Calculate the PnL of both parties.
        (int256 pnlA, int256 pnlB) = LibMaster.calculateUPnLIsolated(
            position.positionId,
            positionPrice.bidPrice,
            positionPrice.askPrice
        );

        // Extract our party's PNL
        int256 pnl = position.partyA == party ? pnlA : pnlB;

        address counterParty = position.partyA == party ? position.partyB : position.partyA;
        uint256 baseReturnAmount = Decimal.mul(liquidationFeeRatio, position.liquidationFee).asUint256();

        if (pnl <= 0) {
            uint256 amount = baseReturnAmount + uint256(-pnl) + position.lockedMargin;
            s.ma._marginBalances[counterParty] += amount;
        } else {
            uint256 marginReturned = uint256(pnl) >= position.lockedMargin ? 0 : position.lockedMargin - uint256(pnl);
            uint256 amount = baseReturnAmount + marginReturned;
            s.ma._marginBalances[counterParty] += amount;
        }
    }

    /**
     * @notice Deficit > liquidationFeeLiquidatedParty + liquidationFeeCounterParty + CVALiquidatedParty + CVACounterParty
     *
     * - Deficit is not sufficiently covered by the liquidationFee, liquidator earns nothing.
     * - Deficit is not sufficiently covered by the liquidatedParty's CVA.
     * - Deficit is not sufficiently covered by the counterParty's CVA.
     * - Deficit is not sufficiently covered by the counterParty's liquidationFee.
     * - Deficit is covered by the counterParty's PNL.
     *
     * If PnLLiquidatedParty <= 0:
     * - counterParty gets a reduced amount of the PNL back.
     * - counterParty gets his lockedMargin back.
     *
     * If PnLLiquidatedParty > 0:
     * - counterParty gets (lockedMargin - PnLLiquidatedParty) back.
     */
    function _distributePnLDeficitFive(
        address party,
        PositionPrice memory positionPrice,
        Decimal.D256 memory pnlRatio
    ) private {
        Position storage position = s.ma._allPositionsMap[positionPrice.positionId];

        require(position.state != PositionState.LIQUIDATED, "Position already liquidated");
        require(position.partyA == party || position.partyB == party, "Invalid party");

        // Calculate the PnL of both parties.
        (int256 pnlA, int256 pnlB) = LibMaster.calculateUPnLIsolated(
            position.positionId,
            positionPrice.bidPrice,
            positionPrice.askPrice
        );

        // Extract our party's PNL
        int256 pnl = position.partyA == party ? pnlA : pnlB;

        address counterParty = position.partyA == party ? position.partyB : position.partyA;
        uint256 baseReturnAmount = Decimal.mul(pnlRatio, uint256(pnl)).asUint256();

        if (pnl <= 0) {
            uint256 amount = baseReturnAmount + position.lockedMargin;
            s.ma._marginBalances[counterParty] += amount;
        } else {
            uint256 amount = uint256(pnl) >= position.lockedMargin ? 0 : position.lockedMargin - uint256(pnl);
            s.ma._marginBalances[counterParty] += amount;
        }
    }
}

